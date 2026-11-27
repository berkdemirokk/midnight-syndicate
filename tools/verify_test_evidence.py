"""Fail CI for missing, malformed, incomplete or failing Godot test evidence."""
import argparse
import json
from pathlib import Path

def verify(data, minimum):
    if not isinstance(data, dict) or not isinstance(data.get("_meta"), dict):
        raise ValueError("Missing test metadata")
    count = 0
    for filename, cases in data.items():
        if filename == "_meta":
            continue
        if not filename.startswith("test_") or not filename.endswith(".gd"):
            raise ValueError(f"Unexpected test file: {filename}")
        if not isinstance(cases, dict) or not cases or "error" in cases:
            raise ValueError(f"Invalid test file evidence: {filename}")
        for case, result in cases.items():
            if not case.startswith("test_") or not isinstance(result, dict):
                raise ValueError(f"Malformed case: {filename}::{case}")
            if result.get("pass") is not True or result.get("failures") != []:
                raise ValueError(f"Failed/incomplete case: {filename}::{case}")
            count += 1
    if count < minimum:
        raise ValueError(f"Only {count} cases, expected at least {minimum}")
    return count

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("path", type=Path)
    parser.add_argument("--minimum", type=int, default=335)
    args = parser.parse_args()
    try:
        count = verify(json.loads(args.path.read_text(encoding="utf-8")), args.minimum)
    except (OSError, ValueError, TypeError) as exc:
        parser.exit(1, f"Test evidence rejected: {exc}\n")
    print(f"Verified {count} passing test cases.")

if __name__ == "__main__":
    main()
