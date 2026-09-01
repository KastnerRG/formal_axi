#!/usr/bin/env python3
"""Turn a Questa formal report into small, reviewable run artifacts."""

from __future__ import annotations

import argparse
import csv
import json
import re
from pathlib import Path


TARGET = re.compile(r"^Targets (.+?) \((\d+)\)$")
METRIC = re.compile(
    r"^(Elapsed Time|Total CPU Time|Total Peak Memory|Maximum Peak Memory|Peak Cores)\s+(.+?)\s*$"
)
VACUITY_RESULT = re.compile(r"Vacuity Check (Passed|Failed): (.+?) \(engine:")
VACUITY_PROGRESS = re.compile(r"Check Status: Vacuity (\d+)/(\d+)")


def parse_targets(lines: list[str]) -> list[dict[str, str]]:
    rows: list[dict[str, str]] = []
    status: str | None = None
    passed_rule = False
    for raw in lines:
        line = raw.strip()
        match = TARGET.match(line)
        if match:
            candidate = match.group(1).lower().replace(" with warnings", "")
            status = candidate.replace(" ", "_")
            passed_rule = False
            continue
        if status is None:
            continue
        if line and set(line) == {"-"}:
            if passed_rule:
                status = None
            else:
                passed_rule = True
            continue
        if passed_rule and line:
            rows.append({"property": line, "status": status})
    return rows


def parse_vacuity(lines: list[str]) -> tuple[list[dict[str, str]], int, int]:
    results: dict[str, str] = {}
    completed = total = 0
    for raw in lines:
        line = raw.strip()
        result = VACUITY_RESULT.search(line)
        if result:
            # Questa calls an assertion "Vacuity Check Failed" when no trace
            # reaches its trigger.  Use names that describe the evidence.
            results[result.group(2)] = (
                "nonvacuous" if result.group(1) == "Passed" else "unreachable"
            )
        progress = VACUITY_PROGRESS.search(line)
        if progress:
            completed, total = map(int, progress.groups())
    rows = [
        {"property": prop, "vacuity": status}
        for prop, status in sorted(results.items())
    ]
    return rows, completed, total


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("report", type=Path)
    parser.add_argument("--output-dir", type=Path)
    parser.add_argument("--verify-log", type=Path)
    args = parser.parse_args()

    outdir = args.output_dir or args.report.parent
    outdir.mkdir(parents=True, exist_ok=True)
    lines = args.report.read_text(errors="replace").splitlines()
    rows = parse_targets(lines)

    with (outdir / "property_status.csv").open("w", newline="") as stream:
        writer = csv.DictWriter(
            stream, fieldnames=["property", "status"], lineterminator="\n"
        )
        writer.writeheader()
        writer.writerows(rows)

    verify_log = args.verify_log or args.report.with_name("formal_verify.log")
    vacuity_rows: list[dict[str, str]] = []
    vacuity_completed = vacuity_total = 0
    if verify_log.is_file():
        verify_lines = verify_log.read_text(errors="replace").splitlines()
        vacuity_rows, vacuity_completed, vacuity_total = parse_vacuity(verify_lines)
        with (outdir / "vacuity_status.csv").open("w", newline="") as stream:
            writer = csv.DictWriter(
                stream, fieldnames=["property", "vacuity"], lineterminator="\n"
            )
            writer.writeheader()
            writer.writerows(vacuity_rows)

    counts: dict[str, int] = {}
    for row in rows:
        counts[row["status"]] = counts.get(row["status"], 0) + 1

    metrics: dict[str, str] = {}
    for line in lines:
        match = METRIC.match(line.strip())
        if match and match.group(1) not in metrics:
            metrics[match.group(1)] = match.group(2)

    vacuity_counts: dict[str, int] = {}
    for row in vacuity_rows:
        status = row["vacuity"]
        vacuity_counts[status] = vacuity_counts.get(status, 0) + 1

    summary = {
        "statuses": counts,
        "vacuity": {
            "statuses": vacuity_counts,
            "completed": vacuity_completed,
            "total": vacuity_total,
        },
        "metrics": metrics,
        "target_count": len(rows),
    }
    (outdir / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")

    bad = sum(
        counts.get(key, 0)
        for key in ("fired", "inconclusive", "unknown", "skipped")
    )
    if vacuity_total and (
        vacuity_completed != vacuity_total or len(vacuity_rows) != vacuity_total
    ):
        bad += 1
    print(json.dumps(summary, sort_keys=True))
    return 1 if bad else 0


if __name__ == "__main__":
    raise SystemExit(main())
