import unittest

from scripts.convert_model.sweep import parse_float_list, parse_int_list


class SweepHelpersTests(unittest.TestCase):
    def test_parse_int_list(self):
        self.assertEqual(parse_int_list("32, 64,128"), [32, 64, 128])

    def test_parse_float_list(self):
        self.assertEqual(parse_float_list("0, 0.05,0.1"), [0.0, 0.05, 0.1])


if __name__ == "__main__":
    unittest.main()
