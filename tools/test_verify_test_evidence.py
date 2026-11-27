import unittest
from verify_test_evidence import verify

def evidence():
    return {"_meta": {}, "test_a.gd": {"test_a": {"pass": True, "failures": []}}}

class EvidenceTests(unittest.TestCase):
    def test_valid(self):
        self.assertEqual(verify(evidence(), 1), 1)

    def test_count_floor(self):
        with self.assertRaises(ValueError):
            verify(evidence(), 2)

    def test_failed_case(self):
        data = evidence()
        data["test_a.gd"]["test_a"]["pass"] = False
        with self.assertRaises(ValueError):
            verify(data, 1)

    def test_missing_cases(self):
        with self.assertRaises(ValueError):
            verify({"_meta": {}, "test_a.gd": {}}, 0)

    def test_failure_details_not_ignored(self):
        data = evidence()
        data["test_a.gd"]["test_a"]["failures"] = ["runtime error"]
        with self.assertRaises(ValueError):
            verify(data, 1)

if __name__ == "__main__":
    unittest.main()
