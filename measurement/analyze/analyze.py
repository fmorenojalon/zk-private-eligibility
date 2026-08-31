#!/usr/bin/env python3
"""F1.3 measurement analysis (specs/phase-1/measurement-harness.md §5).

Ingests measurement/records/records.ndjson, groups by (circuit.name,
circuit.parameters), and writes mean/median/p95/stddev summary tables to
measurement/reports/ in both Markdown and CSV.
"""
import json
import statistics
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
RECORDS_FILE = ROOT / "records" / "records.ndjson"
REPORTS_DIR = ROOT / "reports"

METRIC_FIELDS = [
    "witness_gen_ms",
    "proving_ms",
    "verification_ms",
    "peak_memory_mb",
    "proof_size_bytes",
]


def load_records():
    if not RECORDS_FILE.exists():
        return []
    records = []
    for line in RECORDS_FILE.read_text().splitlines():
        line = line.strip()
        if not line:
            continue
        records.append(json.loads(line))
    return records


def group_key(record):
    params = record["circuit"].get("parameters", {})
    param_str = ",".join(f"{k}={v}" for k, v in sorted(params.items()))
    device = record["device"]
    device_str = "simulator" if device.get("is_simulator") else device.get("model", "unknown")
    return (record["circuit"]["name"], param_str, device_str)


def percentile(values, pct):
    if len(values) == 1:
        return values[0]
    sorted_vals = sorted(values)
    k = (len(sorted_vals) - 1) * (pct / 100)
    f = int(k)
    c = min(f + 1, len(sorted_vals) - 1)
    if f == c:
        return sorted_vals[f]
    return sorted_vals[f] + (sorted_vals[c] - sorted_vals[f]) * (k - f)


def summarize(records):
    groups = {}
    for rec in records:
        key = group_key(rec)
        groups.setdefault(key, []).append(rec)

    rows = []
    for (circuit, params, device), recs in sorted(groups.items()):
        row = {"circuit": circuit, "parameters": params, "device": device, "n": len(recs)}
        for field in METRIC_FIELDS:
            values = [r["metrics"][field] for r in recs if field in r["metrics"]]
            if not values:
                continue
            row[f"{field}_mean"] = round(statistics.mean(values), 1)
            row[f"{field}_median"] = round(statistics.median(values), 1)
            row[f"{field}_p95"] = round(percentile(values, 95), 1)
            row[f"{field}_stddev"] = round(statistics.stdev(values), 1) if len(values) > 1 else 0.0
        rows.append(row)
    return rows


def write_markdown(rows, out_path):
    if not rows:
        out_path.write_text("No records found.\n")
        return
    lines = ["# Measurement Summary", ""]
    for row in rows:
        lines.append(f"## {row['circuit']} ({row['parameters'] or 'no params'}) on {row['device']}")
        lines.append("")
        lines.append(f"n = {row['n']}")
        lines.append("")
        lines.append("| Metric | Mean | Median | p95 | Stddev |")
        lines.append("| --- | --- | --- | --- | --- |")
        for field in METRIC_FIELDS:
            if f"{field}_mean" not in row:
                continue
            lines.append(
                f"| {field} | {row[f'{field}_mean']} | {row[f'{field}_median']} | "
                f"{row[f'{field}_p95']} | {row[f'{field}_stddev']} |"
            )
        lines.append("")
    out_path.write_text("\n".join(lines))


def write_csv(rows, out_path):
    if not rows:
        out_path.write_text("")
        return
    fieldnames = sorted({k for row in rows for k in row.keys()})
    lines = [",".join(fieldnames)]
    for row in rows:
        lines.append(",".join(str(row.get(f, "")) for f in fieldnames))
    out_path.write_text("\n".join(lines) + "\n")


def main():
    records = load_records()
    rows = summarize(records)
    REPORTS_DIR.mkdir(parents=True, exist_ok=True)
    write_markdown(rows, REPORTS_DIR / "summary.md")
    write_csv(rows, REPORTS_DIR / "summary.csv")
    print(f"Ingested {len(records)} record(s) across {len(rows)} group(s).")
    print(f"Wrote {REPORTS_DIR / 'summary.md'} and {REPORTS_DIR / 'summary.csv'}")


if __name__ == "__main__":
    main()
