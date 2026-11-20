#!/usr/bin/env python3
"""Checks the schemas the Swift tests wrote against JSON Schema draft 2020-12.

Each fixture holds a schema, values that must validate and values that must
not. The schema must be a valid 2020-12 schema, and it must reach the same
verdicts as
JSONSchema.contains(_:), including the "uuid" format. Run it after
`swift test` with JSON_SCHEMA_FIXTURES set to the same folder.
"""

import json
import pathlib
import sys

from jsonschema import Draft202012Validator

DIALECT = "https://json-schema.org/draft/2020-12/schema"


def main(folder: str) -> int:
    files = sorted(pathlib.Path(folder).glob("*.json"))
    if not files:
        print(f"No fixtures in {folder}. Did the tests run with JSON_SCHEMA_FIXTURES set?")
        return 1

    failures = []
    for path in files:
        fixture = json.loads(path.read_text())
        name, schema = fixture["name"], fixture["schema"]
        if schema.get("$schema") != DIALECT:
            failures.append(f"{name}: does not declare {DIALECT}")
        try:
            Draft202012Validator.check_schema(schema)
        except Exception as error:  # SchemaError, with the reason
            failures.append(f"{name}: not a valid 2020-12 schema: {error}")
        validator = Draft202012Validator(schema, format_checker=Draft202012Validator.FORMAT_CHECKER)
        for value in fixture["valid"]:
            if not validator.is_valid(value):
                failures.append(f"{name}: should accept {json.dumps(value)}")
        for value in fixture["invalid"]:
            if validator.is_valid(value):
                failures.append(f"{name}: should refuse {json.dumps(value)}")

    for failure in failures:
        print(failure)
    print(f"Checked {len(files)} fixtures, {len(failures)} failures.")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1]))
