#!/usr/bin/env python3
"""Perform a non-GUI sanity inspection of exported counterexample VCDs."""

from __future__ import annotations

import argparse
import csv
from pathlib import Path


def inspect(path: Path) -> dict[str, str | int]:
    variables = 0
    timestamps = 0
    enddefs = False
    with path.open(errors="replace") as stream:
        for line in stream:
            if line.startswith("$var "):
                variables += 1
            elif line.startswith("$enddefinitions"):
                enddefs = True
            elif line.startswith("#"):
                timestamps += 1
    return {
        "file": str(path),
        "bytes": path.stat().st_size,
        "variables": variables,
        "timestamps": timestamps,
        "parse_status": "ok" if enddefs and variables and timestamps else "invalid",
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("directory", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    rows = [inspect(path) for path in sorted(args.directory.rglob("*.vcd"))]
    args.output.parent.mkdir(parents=True, exist_ok=True)
    fields = ["file", "bytes", "variables", "timestamps", "parse_status"]
    with args.output.open("w", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=fields, lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)
    invalid = sum(row["parse_status"] != "ok" for row in rows)
    print(f"inspected={len(rows)} invalid={invalid}")
    return 1 if invalid else 0


if __name__ == "__main__":
    raise SystemExit(main())
