import argparse
import json
import tempfile
import unittest
from unittest import mock
from pathlib import Path

from PIL import Image

from scripts.convert_model.verify import (
    CropBox,
    EvaluationRecord,
    LoadedDataset,
    Sample,
    clamp_crop_box,
    compute_cer,
    expand_detector_crop_box,
    expand_crop_box,
    format_report_block,
    load_detector_samples,
    load_crop_samples,
    load_samples_from_args,
    normalize_text,
    percentile,
    prepare_samples,
    remove_ngram_loops,
    summarize_records,
)


class VerifyHelpersTests(unittest.TestCase):
    def test_normalize_text_normalizes_punctuation_and_whitespace(self):
        self.assertEqual(normalize_text("a！\r\nb…  \n"), "a!\nb...")

    def test_compute_cer_handles_empty_reference(self):
        self.assertEqual(compute_cer("", ""), 0.0)
        self.assertEqual(compute_cer("", "abc"), 1.0)

    def test_remove_ngram_loops_trims_repeated_phrase(self):
        cleaned, detected = remove_ngram_loops("abcdefghi xyz abcdefghi xyz")
        self.assertTrue(detected)
        self.assertEqual(cleaned, "abcdefghi xyz")

    def test_percentile_interpolates_between_values(self):
        self.assertAlmostEqual(percentile([0.1, 0.2, 0.3, 0.4], 0.5), 0.25)
        self.assertAlmostEqual(percentile([0.1, 0.2, 0.3, 0.4], 0.9), 0.37)

    def test_expand_crop_box_applies_padding_then_clamps(self):
        box = CropBox(x=10, y=20, width=50, height=40)
        expanded = expand_crop_box(box, 0.1, image_width=100, image_height=80)
        self.assertEqual(expanded, CropBox(x=5, y=16, width=60, height=48))

        clamped = clamp_crop_box(CropBox(x=-10, y=-5, width=30, height=20), image_width=100, image_height=80)
        self.assertEqual(clamped, CropBox(x=0, y=0, width=20, height=15))

    def test_format_report_block_indents_multiline_output(self):
        self.assertEqual(format_report_block("a\nb"), "      a\n      b")
        self.assertEqual(format_report_block(""), "      [empty]")

    def test_load_crop_samples_resolves_relative_paths(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            base = Path(temp_dir)
            image_path = base / "page.png"
            Image.new("RGB", (20, 20), "white").save(image_path)

            manifest_path = base / "manifest.json"
            manifest_path.write_text(
                json.dumps(
                    {
                        "samples": [
                            {
                                "id": "sample-1",
                                "image": "page.png",
                                "crop": [1, 2, 3, 4],
                                "reference_text": "abc",
                            }
                        ]
                    }
                )
            )

            samples = load_crop_samples(manifest_path)
            self.assertEqual(len(samples), 1)
            self.assertEqual(samples[0].image_path, image_path.resolve())
            self.assertEqual(samples[0].crop_box, CropBox(x=1, y=2, width=3, height=4))
            self.assertEqual(samples[0].reference_text, "abc")

    def test_prepare_samples_crops_images_and_records_padding(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            base = Path(temp_dir)
            image_path = base / "page.png"
            Image.new("RGB", (100, 100), "white").save(image_path)

            sample = Sample(
                sample_id="crop-1",
                image_path=image_path,
                mode="crop",
                crop_box=CropBox(x=10, y=10, width=20, height=10),
            )

            prepared = prepare_samples([sample], crop_padding=0.1)
            self.assertEqual(len(prepared), 1)
            self.assertTrue(prepared[0].prepared_image_path.exists())
            self.assertEqual(prepared[0].sample.crop_box, CropBox(x=8, y=9, width=24, height=12))
            self.assertEqual(prepared[0].sample.metadata["crop_padding"], 0.1)

    def test_load_detector_samples_parses_regions_and_zero_region_pages(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            base = Path(temp_dir)
            test_dir = base / "book1"
            test_dir.mkdir()
            page1 = test_dir / "001.png"
            page2 = test_dir / "002.png"
            Image.new("RGB", (100, 50), "white").save(page1)
            Image.new("RGB", (120, 80), "white").save(page2)

            detector_json = base / "detector.json"
            detector_json.write_text(
                json.dumps(
                    {
                        "schemaVersion": 1,
                        "pages": [
                            {
                                "imagePath": str(page1.resolve()),
                                "pageWidth": 100,
                                "pageHeight": 50,
                                "regions": [
                                    {
                                        "x": 10,
                                        "y": 12,
                                        "width": 20,
                                        "height": 8,
                                        "confidence": 0.95,
                                        "classIndex": 0,
                                    }
                                ],
                            },
                            {
                                "imagePath": str(page2.resolve()),
                                "pageWidth": 120,
                                "pageHeight": 80,
                                "regions": [],
                            },
                        ],
                    }
                )
            )

            dataset = load_detector_samples(detector_json, test_dir)
            self.assertEqual(dataset.mode, "detector")
            self.assertEqual(len(dataset.samples), 1)
            self.assertEqual(dataset.samples[0].sample_id, "001#region-001")
            self.assertEqual(dataset.samples[0].mode, "detector_crop")
            self.assertEqual(dataset.samples[0].crop_box, CropBox(x=10.0, y=12.0, width=20.0, height=8.0))
            self.assertEqual(dataset.metadata["page_count"], 2)
            self.assertEqual(dataset.metadata["zero_region_pages"], ["002"])

    def test_expand_detector_crop_box_matches_paddleocr_rules(self):
        self.assertEqual(
            expand_detector_crop_box(CropBox(x=50, y=20, width=60, height=30), 200, 100),
            CropBox(x=34.0, y=14.0, width=92.0, height=42.0),
        )
        self.assertEqual(
            expand_detector_crop_box(CropBox(x=0, y=0, width=20, height=10), 100, 50),
            CropBox(x=0.0, y=0.0, width=32.0, height=16.0),
        )
        self.assertEqual(
            expand_detector_crop_box(CropBox(x=40, y=10, width=20, height=40), 100, 100),
            CropBox(x=30.0, y=0.0, width=40.0, height=61.0),
        )

    @mock.patch("scripts.convert_model.verify.run_detector_export_cli")
    def test_load_samples_from_args_uses_detector_crops_not_full_pages(self, mock_export):
        with tempfile.TemporaryDirectory() as temp_dir:
            base = Path(temp_dir)
            test_dir = base / "pages"
            test_dir.mkdir()
            page = test_dir / "001.png"
            Image.new("RGB", (100, 80), "white").save(page)

            def write_detector_json(page_images, output_path):
                self.assertEqual(page_images, [page.resolve()])
                output_path.write_text(
                    json.dumps(
                        {
                            "schemaVersion": 1,
                            "pages": [
                                {
                                    "imagePath": str(page.resolve()),
                                    "pageWidth": 100,
                                    "pageHeight": 80,
                                    "regions": [
                                        {
                                            "x": 10,
                                            "y": 10,
                                            "width": 20,
                                            "height": 10,
                                            "confidence": 0.9,
                                            "classIndex": 0,
                                        }
                                    ],
                                }
                            ],
                        }
                    )
                )

            mock_export.side_effect = write_detector_json
            args = argparse.Namespace(
                crop_manifest=None,
                test_images=test_dir.resolve(),
                keep_detector_json=False,
                detector_json_output=None,
            )

            dataset = load_samples_from_args(args)
            prepared = prepare_samples(dataset.samples, crop_padding=0.0)

            self.assertEqual(dataset.mode, "detector")
            self.assertEqual(len(prepared), 1)
            self.assertNotEqual(prepared[0].prepared_image_path, page.resolve())
            with Image.open(prepared[0].prepared_image_path) as cropped:
                self.assertEqual(cropped.size, (42, 22))

    def test_load_samples_from_args_preserves_crop_manifest_support(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            base = Path(temp_dir)
            image_path = base / "page.png"
            Image.new("RGB", (20, 20), "white").save(image_path)
            manifest_path = base / "manifest.json"
            manifest_path.write_text(
                json.dumps(
                    {
                        "samples": [
                            {
                                "id": "sample-1",
                                "image": "page.png",
                                "crop": [1, 2, 3, 4],
                            }
                        ]
                    }
                )
            )

            args = argparse.Namespace(
                crop_manifest=manifest_path.resolve(),
                test_images=None,
                keep_detector_json=False,
                detector_json_output=None,
            )
            dataset = load_samples_from_args(args)

            self.assertEqual(dataset.mode, "crop_manifest")
            self.assertEqual(len(dataset.samples), 1)
            self.assertEqual(dataset.samples[0].mode, "crop")

    def test_summarize_records_counts_failures(self):
        records = [
            EvaluationRecord(
                sample_id="a",
                mode="page",
                image_path="a.png",
                prepared_image_path="a.png",
                crop_box=None,
                crop_padding=0.0,
                original_text="abc",
                quantized_text="abc",
                cer_delta=0.01,
                quantized_loop_detected=False,
                empty_output=False,
            ),
            EvaluationRecord(
                sample_id="b",
                mode="page",
                image_path="b.png",
                prepared_image_path="b.png",
                crop_box=None,
                crop_padding=0.0,
                original_text="abc",
                quantized_text="",
                cer_delta=0.4,
                quantized_loop_detected=True,
                empty_output=True,
            ),
        ]

        summary = summarize_records(records, fail_threshold=0.05)
        self.assertEqual(summary["sample_count"], 2)
        self.assertEqual(summary["fail_count"], 1)
        self.assertEqual(summary["empty_output_count"], 1)
        self.assertEqual(summary["quantized_loop_count"], 1)


if __name__ == "__main__":
    unittest.main()
