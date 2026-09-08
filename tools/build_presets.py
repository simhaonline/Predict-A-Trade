#!/usr/bin/env python3
"""
build_presets.py — self-contained preset generator for Predict-A-Trade-Ultra.mq5

Parses the authoritative parameter profile (prompt.md Phase 1 + Phase 3.5) and the
EA's own input declarations, then emits every .set preset in presets/ with:

  - EVERY input the EA declares (no missing rows -> no "unknown parameter" errors),
  - enum inputs serialized as integers (MT5 .set format),
  - per-preset overrides (SR off / advisory / prop-firm),
  - a verification pass that re-reads each written file and checks name parity
    with the EA source.

No external dependencies: Python 3 standard library only. Run from the repo root:

    python3 tools/build_presets.py

The script is the single source of truth for preset regeneration: change prompt.md
(Phase 1 values) or EA inputs, re-run, commit. Never hand-edit a .set file.
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
EA = os.path.join(ROOT, "Predict-A-Trade-Ultra.mq5")
PROMPT = os.path.join(ROOT, "prompt.md")
OUT = os.path.join(ROOT, "presets")

# MT5 .set serialization for non-trivial types
TIMEFRAMES = {
    "PERIOD_M1": "1", "PERIOD_M2": "2", "PERIOD_M3": "3", "PERIOD_M4": "4",
    "PERIOD_M5": "5", "PERIOD_M6": "6", "PERIOD_M10": "10", "PERIOD_M12": "12",
    "PERIOD_M15": "15", "PERIOD_M20": "20", "PERIOD_M30": "30",
    "PERIOD_H1": "16385", "PERIOD_H2": "16386", "PERIOD_H3": "16387",
    "PERIOD_H4": "16388", "PERIOD_H6": "16390", "PERIOD_H8": "16392",
    "PERIOD_H12": "16396", "PERIOD_D1": "16408", "PERIOD_W1": "32769",
    "PERIOD_MN1": "49153",
}


def load_source():
    with open(EA, encoding="utf-8") as fh:
        return fh.read()


def source_inputs(src):
    """Ordered list of (name, type, default_literal) for every declared input."""
    out = []
    for m in re.finditer(
        r"input\s+\w+\s+(Inp\w+)\s*=\s*([^;]+);", src
    ):
        name = m.group(1)
        default = m.group(2).strip()
        tm = re.search(
            r"input\s+([\w<>]+)\s+" + re.escape(name) + r"\s*=", src
        )
        out.append((name, tm.group(1) if tm else "double", default))
    return out


def parse_profile(prompt):
    """Phase 1 values: the first `InpX = value` table between PHASE 1 and PHASE 2."""
    lines = prompt.replace("\r\n", "\n").split("\n")
    p1 = next(i for i, l in enumerate(lines) if "PHASE 1" in l)
    p2 = next(i for i, l in enumerate(lines) if "PHASE 2" in l and i > p1)
    vals = {}
    for line in lines[p1:p2]:
        m = re.match(r"^(Inp\w+)\s*=\s*(.+?)\s*$", line)
        if m:
            vals.setdefault(m.group(1), m.group(2).strip())
    return vals


def parse_sr_defaults(prompt):
    """Phase 3.5 SR defaults: `InpX = value` pairs between PHASE 3 and PHASE 4."""
    lines = prompt.replace("\r\n", "\n").split("\n")
    p3 = next(i for i, l in enumerate(lines) if "PHASE 3" in l)
    p4 = next(i for i, l in enumerate(lines) if "PHASE 4" in l and i > p3)
    section = "\n".join(lines[p3:p4])
    vals = {}
    # single pair per line
    for line in section.split("\n"):
        m = re.match(r"^\s*(Inp\w+)\s*=\s*(.+?)\s*$", line)
        if m:
            vals.setdefault(m.group(1), m.group(2).strip())
    # multiple pairs per line (table rows like "InpSR_TF1 = PERIOD_M15  InpSR_BarsTF1 = 300")
    for m in re.finditer(
        r"(Inp\w+)\s*=\s*([A-Za-z0-9_.\-]+)(?=\s{2,}Inp\w+\s*=|$)", section
    ):
        vals.setdefault(m.group(1), m.group(2).strip())
    return vals


def enum_tables(src):
    tables = {}
    for m in re.finditer(r"enum\s+(\w+)\s*\{(.*?)\};", src, re.S):
        body = m.group(2)
        table, nxt = {}, 0
        for item in re.finditer(r"(\w+)(?:\s*=\s*(-?\d+))?\s*[,}]", body):
            name, val = item.group(1), item.group(2)
            if val is not None:
                nxt = int(val)
            table.setdefault(name, str(nxt))
            nxt += 1
        tables[m.group(1)] = table
    return tables


def serialize(name, itype, value, enums):
    if itype in enums:
        return enums[itype].get(value, value)
    if itype == "ENUM_TIMEFRAMES":
        return TIMEFRAMES.get(value, value)
    if itype == "string":
        return value if value.startswith('"') else '"' + value + '"'
    return value  # bool / int / double / color keep the literal


def build_rows(src, prompt):
    inputs = source_inputs(src)
    enums = enum_tables(src)
    profile = parse_profile(prompt)
    sr = parse_sr_defaults(prompt)
    rows, applied = [], {}
    for name, itype, default in inputs:
        if name in profile:
            val = profile[name]
        elif name in sr:
            val = sr[name]
        else:
            val = default  # Phase 2/4 additions keep their source default
        rows.append(f"{name}={serialize(name, itype, val, enums)}")
        applied[name] = val
    return rows, applied


def write_set(path, rows):
    with open(path, "w", encoding="utf-8") as fh:
        fh.write("\n".join(rows) + "\n")


def verify(path, src):
    """Re-read a written .set and check name parity with the EA source."""
    declared = {name for name, _, _ in source_inputs(src)}
    with open(path, encoding="utf-8") as fh:
        rows = [l.strip() for l in fh if l.strip()]
    names = [r.split("=")[0] for r in rows]
    assert len(names) == len(set(names)), f"{path}: duplicate input rows"
    assert set(names) == declared, (
        f"{path}: name mismatch — missing {sorted(declared - set(names))}, "
        f"extra {sorted(set(names) - declared)}"
    )
    return len(rows)


def main():
    src = load_source()
    prompt = ""
    for candidate in (PROMPT, os.path.join(ROOT, "prompt.md")):
        if os.path.exists(candidate):
            prompt = open(candidate, encoding="utf-8", errors="replace").read()
            break
    if not prompt:
        print("prompt.md not found — falling back to EA source defaults", file=sys.stderr)

    rows, applied = build_rows(src, prompt)
    os.makedirs(OUT, exist_ok=True)

    variants = {
        "XAUUSD_M1_UltraScalp.set": rows,                                   # production (SR_SOFT_FILTER)
        "XAUUSD_M1_UltraScalp_SR_Off.set": [r.replace("InpUseSRZones=true", "InpUseSRZones=false") for r in rows],
        "XAUUSD_M1_UltraScalp_Advisory.set": [r.replace("InpSRMode=1", "InpSRMode=0") for r in rows],
        "XAUUSD_M1_UltraScalp_PropFirm.set": [
            r.replace("InpPropFirmMode=false", "InpPropFirmMode=true")
             .replace("InpDailyLossPercent=2.5", "InpDailyLossPercent=2.0")
             .replace("InpPropMaxTrailingDDPct=5.0", "InpPropMaxTrailingDDPct=4.0")
             .replace("InpMaxTradesPerDay=25", "InpMaxTradesPerDay=15")
            for r in rows
        ],
    }
    for fname, content in variants.items():
        path = os.path.join(OUT, fname)
        write_set(path, content)
        n = verify(path, src)
        print(f"OK  {fname}  ({n} inputs, verified)")

    print("\nKey values applied:")
    for probe in ("InpSimpleScalpMode", "InpBreakerAction", "InpRiskPercent",
                  "InpSL_ATR_Multiplier", "InpSRMode", "InpPropFirmMode"):
        print(f"  {probe} = {applied.get(probe, '(source default)')}")


if __name__ == "__main__":
    main()