import json
import tempfile
import unittest
from pathlib import Path

from PIL import Image

from scripts.convert_model.verify import (
    CropBox,
    EvaluationRecord,
    Sample,
    clamp_crop_box,
    compute_cer,
    detect_ordering_mismatch,
    expand_crop_box,
    load_crop_samples,
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

    def test_detect_ordering_mismatch_requires_same_line_multiset(self):
        self.assertTrue(detect_ordering_mismatch("a\nb", "b\na"))
        self.assertFalse(detect_ordering_mismatch("a\nb", "a\nc"))
        self.assertFalse(detect_ordering_mismatch("abc", "cba"))

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

    def test_summarize_records_counts_failures(self):
        records = [
            EvaluationRecord(
                sample_id="a",
                mode="page",
                image_path="a.png",
                prepared_image_path="a.png",
                crop_box=None,
                crop_padding=0.0,
                reference_source="bf16",
                original_text="abc",
                quantized_text="abc",
                cer_delta=0.01,
                original_loop_detected=False,
                quantized_loop_detected=False,
                empty_output=False,
                ordering_mismatch=False,
                catastrophic=False,
            ),
            EvaluationRecord(
                sample_id="b",
                mode="page",
                image_path="b.png",
                prepared_image_path="b.png",
                crop_box=None,
                crop_padding=0.0,
                reference_source="bf16",
                original_text="abc",
                quantized_text="",
                cer_delta=0.4,
                original_loop_detected=False,
                quantized_loop_detected=True,
                empty_output=True,
                ordering_mismatch=True,
                catastrophic=True,
            ),
        ]

        summary = summarize_records(records, fail_threshold=0.05)
        self.assertEqual(summary["sample_count"], 2)
        self.assertEqual(summary["fail_count"], 1)
        self.assertEqual(summary["catastrophic_count"], 1)
        self.assertEqual(summary["ordering_mismatch_count"], 1)
        self.assertEqual(summary["empty_output_count"], 1)


if __name__ == "__main__":
    unittest.main()
