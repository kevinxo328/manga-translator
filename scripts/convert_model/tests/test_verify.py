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
    PrefillStageRecord,
    PrefillVisionLayerSubstepRecord,
    Sample,
    TensorSummary,
    TopToken,
    clamp_crop_box,
    compute_cer,
    expand_detector_crop_box,
    expand_crop_box,
    filter_samples_by_ids,
    format_report_block,
    load_detector_samples,
    load_crop_samples,
    load_single_image_sample,
    load_samples_from_args,
    list_page_images,
    normalize_text,
    parse_crop_box_arg,
    percentile,
    prepare_samples,
    remove_ngram_loops,
    summarize_tensor,
    summarize_records,
    write_prefill_stage_report_json,
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

    def test_list_page_images_skips_dot_and_underscore_directories(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            base = Path(temp_dir)
            visible = base / "visible"
            hidden = base / ".hidden"
            private = base / "_private"
            nested = visible / "__nested"
            visible.mkdir()
            hidden.mkdir()
            private.mkdir()
            nested.mkdir()

            Image.new("RGB", (20, 20), "white").save(visible / "keep.png")
            Image.new("RGB", (20, 20), "white").save(hidden / "skip.png")
            Image.new("RGB", (20, 20), "white").save(private / "skip.jpg")
            Image.new("RGB", (20, 20), "white").save(nested / "skip.jpeg")

            images = list_page_images(base)

            self.assertEqual([path.name for path in images], ["keep.png"])

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
                image=None,
                crop=None,
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
                image=None,
                crop=None,
                crop_manifest=manifest_path.resolve(),
                test_images=None,
                keep_detector_json=False,
                detector_json_output=None,
            )
            dataset = load_samples_from_args(args)

            self.assertEqual(dataset.mode, "crop_manifest")
            self.assertEqual(len(dataset.samples), 1)
            self.assertEqual(dataset.samples[0].mode, "crop")

    def test_parse_crop_box_arg_parses_four_floats(self):
        self.assertEqual(
            parse_crop_box_arg("1,2,3,4"),
            CropBox(x=1.0, y=2.0, width=3.0, height=4.0),
        )

    def test_parse_crop_box_arg_rejects_invalid_input(self):
        with self.assertRaises(argparse.ArgumentTypeError):
            parse_crop_box_arg("1,2,3")

    def test_load_single_image_sample_supports_absolute_path_without_crop(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            image_path = Path(temp_dir) / "page.png"
            Image.new("RGB", (40, 30), "white").save(image_path)

            dataset = load_single_image_sample(image_path.resolve(), crop_box=None)

            self.assertEqual(dataset.mode, "single_image")
            self.assertEqual(len(dataset.samples), 1)
            self.assertEqual(dataset.samples[0].sample_id, "page")
            self.assertEqual(dataset.samples[0].crop_box, CropBox(x=0.0, y=0.0, width=40.0, height=30.0))

    def test_load_single_image_sample_supports_absolute_path_with_crop(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            image_path = Path(temp_dir) / "page.png"
            Image.new("RGB", (40, 30), "white").save(image_path)

            dataset = load_single_image_sample(
                image_path.resolve(),
                crop_box=CropBox(x=5.0, y=6.0, width=7.0, height=8.0),
            )

            self.assertEqual(dataset.samples[0].crop_box, CropBox(x=5.0, y=6.0, width=7.0, height=8.0))
            self.assertEqual(dataset.samples[0].mode, "single_image_crop")

    def test_load_samples_from_args_prefers_single_image_mode(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            image_path = Path(temp_dir) / "panel.jpg"
            Image.new("RGB", (20, 10), "white").save(image_path)

            args = argparse.Namespace(
                image=image_path.resolve(),
                crop=CropBox(x=1.0, y=2.0, width=3.0, height=4.0),
                crop_manifest=None,
                test_images=None,
                keep_detector_json=False,
                detector_json_output=None,
            )

            dataset = load_samples_from_args(args)

            self.assertEqual(dataset.mode, "single_image")
            self.assertEqual(dataset.samples[0].sample_id, "panel")
            self.assertEqual(dataset.samples[0].crop_box, CropBox(x=1.0, y=2.0, width=3.0, height=4.0))

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

    def test_filter_samples_by_ids_keeps_requested_samples(self):
        samples = [
            Sample(sample_id="a", image_path=Path("/tmp/a.png"), mode="crop"),
            Sample(sample_id="b", image_path=Path("/tmp/b.png"), mode="crop"),
        ]
        dataset = LoadedDataset(mode="crop_manifest", samples=samples, metadata={"page_count": 2})

        filtered = filter_samples_by_ids(dataset, ["b"])

        self.assertEqual([sample.sample_id for sample in filtered.samples], ["b"])
        self.assertEqual(filtered.mode, dataset.mode)
        self.assertEqual(filtered.metadata, dataset.metadata)

    def test_filter_samples_by_ids_raises_for_missing_id(self):
        dataset = LoadedDataset(
            mode="crop_manifest",
            samples=[Sample(sample_id="a", image_path=Path("/tmp/a.png"), mode="crop")],
        )

        with self.assertRaisesRegex(ValueError, "missing requested sample ids"):
            filter_samples_by_ids(dataset, ["missing"])

    def test_summarize_tensor_reports_shape_and_statistics(self):
        summary = summarize_tensor([[1.0, -1.0], [3.0, 5.0]])

        self.assertEqual(summary.dtype, "float32")
        self.assertEqual(summary.shape, [2, 2])
        self.assertEqual(summary.prefix[:4], [1.0, -1.0, 3.0, 5.0])
        self.assertAlmostEqual(summary.mean, 2.0)
        self.assertAlmostEqual(summary.min, -1.0)
        self.assertAlmostEqual(summary.max, 5.0)
        self.assertAlmostEqual(summary.l2, (36.0) ** 0.5)
        self.assertGreater(summary.std, 0.0)

    def test_write_prefill_stage_report_json_preserves_layer_outputs(self):
        args = argparse.Namespace(
            quantized_model=Path("/tmp/model"),
            max_pixels=1024,
            prompt="OCR",
            max_tokens=16,
            temperature=0.0,
            crop_padding=0.0,
            sample_id=["sample-1"],
        )
        summary = TensorSummary(
            dtype="bfloat16",
            shape=[1, 2],
            mean=1.0,
            std=0.5,
            min=0.0,
            max=2.0,
            l2=2.2360679,
            prefix=[0.0, 2.0],
            token_row_prefixes=[[0.0, 2.0]],
        )
        record = PrefillStageRecord(
            sample_id="sample-1",
            prepared_image_path="/tmp/prepared.png",
            source_image_path="/tmp/source.png",
            crop_box=[1.0, 2.0, 3.0, 4.0],
            crop_padding=0.18,
            input_ids_count=3,
            input_ids_prefix=[11, 12, 13],
            target_width=392,
            target_height=392,
            generated_text="……",
            generated_tokens=[2703, 2],
            termination_token=2,
            first_step_top_tokens=[TopToken(token_id=2703, logit=21.25)],
            pixel_values=summary,
            vision_patch_embeddings=summary,
            vision_position_embeddings=summary,
            vision_input_embeddings=summary,
            vision_first_layer_output=summary,
            vision_layer_outputs=[summary, summary],
            vision_target_layer_substeps=[
                PrefillVisionLayerSubstepRecord(
                    layer_index=6,
                    input_hidden_states=summary,
                    post_layer_norm1=summary,
                    pre_rotary_queries=summary,
                    pre_rotary_keys=summary,
                    post_rotary_queries=summary,
                    post_rotary_keys=summary,
                    values=summary,
                    attention_output=summary,
                    post_attention_residual=summary,
                    post_layer_norm2=summary,
                    fc1_output=summary,
                    gelu_output=summary,
                    mlp_output=summary,
                    output_hidden_states=summary,
                )
            ],
            encoded_vision_features=summary,
            projected_image_features=summary,
            merged_embeddings=summary,
            first_step_logits=summary,
        )

        with tempfile.TemporaryDirectory() as temp_dir:
            output_path = Path(temp_dir) / "prefill.json"
            write_prefill_stage_report_json(
                output_path=output_path,
                args=args,
                dataset_metadata={"page_count": 1},
                records=[record],
            )
            payload = json.loads(output_path.read_text())

        self.assertEqual(payload["records"][0]["vision_layer_outputs"][0]["dtype"], "bfloat16")
        self.assertEqual(payload["records"][0]["vision_layer_outputs"][0]["token_row_prefixes"], [[0.0, 2.0]])
        self.assertEqual(len(payload["records"][0]["vision_layer_outputs"]), 2)
        self.assertEqual(payload["records"][0]["vision_target_layer_substeps"][0]["layer_index"], 6)


if __name__ == "__main__":
    unittest.main()
