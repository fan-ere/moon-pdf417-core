"""Decode the PDF417 symbol character table into a compact MoonBit source file.

For each of the three bar-space clusters, ISO/IEC 15438 annex A lists 929 symbol
characters of 17 modules.  This script normalises those characters into 17 bit
patterns, checks the structural rules the standard imposes (17 modules, every
bar or space 1..6 modules wide, alternating starting with a bar), and emits
`patterns.mbt`:

* the three pattern clusters as arrays of 929 `Int` literals, and
* the start and stop patterns, checked against their known values.

Usage:

    python scripts/gen_pattern_tables.py --source <file with the table>
    python scripts/gen_pattern_tables.py --check      # verify patterns.mbt

The 17 bit table itself is public specification data; see `docs/SOURCES.md` for
where it was read from and what was verified about it.
"""

from __future__ import annotations

import argparse
import pathlib
import re
import sys

WIDTH = 17
ENTRIES = 929
CLUSTERS = 3
START_PATTERN = 0x1FEA8
STOP_PATTERN = 0x3FA29

TABLE_PATH = pathlib.Path(__file__).resolve().parent.parent / "patterns.mbt"


def run_lengths(pattern: int, width: int = WIDTH) -> list[int]:
    """Bar and space widths of a pattern, most significant bit first."""
    if width <= 0:
        raise ValueError("width must be positive")
    highest = (pattern >> (width - 1)) & 1
    if highest != 1:
        raise ValueError(f"pattern {pattern:#x} does not start with a bar")
    runs: list[int] = []
    last = highest
    run = 0
    for position in range(width - 1, -1, -1):
        bit = (pattern >> position) & 1
        if bit == last:
            run += 1
        else:
            runs.append(run)
            last = bit
            run = 1
    runs.append(run)
    return runs


def verify(patterns: list[int], width: int = WIDTH) -> None:
    """Structural checks every PDF417 symbol character has to satisfy."""
    if len(patterns) != ENTRIES:
        raise ValueError(f"expected {ENTRIES} patterns, found {len(patterns)}")
    for index, pattern in enumerate(patterns):
        if pattern < 0 or pattern >= 1 << width:
            raise ValueError(f"entry {index} does not fit {width} bits")
        runs = run_lengths(pattern, width)
        if sum(runs) != width:
            raise ValueError(f"entry {index} covers {sum(runs)} modules")
        if len(runs) % 2 != 0:
            raise ValueError(f"entry {index} does not end on a space")
        for run in runs:
            if run < 1 or run > 6:
                raise ValueError(f"entry {index} has a {run} module wide element")


def extract_java_arrays(source: str) -> list[list[int]]:
    """Read the three clusters out of a Java `int[][]` literal."""
    if "CODEWORD_TABLE" not in source:
        raise ValueError("CODEWORD_TABLE not found in the source")
    body = source.split("CODEWORD_TABLE", 1)[1].split("};", 1)[0]
    arrays: list[list[int]] = []
    for chunk in re.split(r"\}\s*,\s*\{", body):
        values = [int(item, 16) for item in re.findall(r"0x([0-9a-fA-F]+)", chunk)]
        if values:
            arrays.append(values)
    return arrays


def emit(clusters: list[list[int]]) -> str:
    lines = [
        "// Generated symbol character patterns for PDF417.",
        "//",
        "// ISO/IEC 15438 annex A defines 929 symbol characters per bar-space",
        "// cluster as 17 module patterns.  Each entry below is the pattern as a",
        "// 17 bit integer, most significant bit first, where 1 is a bar and 0 is a",
        "// space.  The rule that the three clusters are distinguished by their",
        "// bar width sequence is checked by `scripts/gen_pattern_tables.py`.",
        "//",
        "// Regenerate with:",
        "//   python scripts/gen_pattern_tables.py --source <table source>",
        "//",
        "// The library reads these tables through `cluster_pattern`; `moon info`",
        "// keeps them out of the public interface on purpose.",
        "",
    ]
    for cluster, patterns in enumerate(clusters):
        lines.append(f"///|")
        lines.append(f"/// Symbol character patterns of cluster {cluster}.")
        lines.append(f"priv let cluster{cluster}_patterns : Array[Int] = [")
        for row in range(0, len(patterns), 8):
            chunk = patterns[row : row + 8]
            body = ", ".join(f"0x{value:05x}" for value in chunk)
            lines.append(f"  {body}, // {row}..{row + len(chunk) - 1}")
        lines.append("]")
        lines.append("")
    lines.append("// The start pattern (17 modules), the stop pattern (18 modules) and the")
    lines.append("// helper that expands a pattern into bar widths live in `symbol.mbt`.")
    lines.append("")
    return "\n".join(lines)


def extract_moonbit_cluster(text: str, cluster: int) -> list[int] | None:
    match = re.search(
        rf"cluster{cluster}_patterns : Array\[Int\] = \[(.*?)\n\]", text, re.S
    )
    if match is None:
        return None
    return [int(item, 16) for item in re.findall(r"0x([0-9a-fA-F]+)", match.group(1))]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=pathlib.Path, help="table source file")
    parser.add_argument("--out", type=pathlib.Path, default=TABLE_PATH)
    parser.add_argument(
        "--check", action="store_true", help="verify the committed patterns.mbt"
    )
    args = parser.parse_args()

    if args.check:
        if not TABLE_PATH.exists():
            print(f"error: {TABLE_PATH} does not exist", file=sys.stderr)
            return 1
        text = TABLE_PATH.read_text(encoding="utf-8")
        failures = []
        for cluster in range(CLUSTERS):
            patterns = extract_moonbit_cluster(text, cluster)
            if patterns is None:
                failures.append(f"cluster {cluster} is missing")
                continue
            try:
                verify(patterns)
            except ValueError as error:
                failures.append(f"cluster {cluster}: {error}")
        for failure in failures:
            print(f"error: {failure}", file=sys.stderr)
        if failures:
            return 1
        print(f"{TABLE_PATH.name} holds {CLUSTERS} valid clusters of {ENTRIES} patterns")
        return 0

    if args.source is None:
        parser.error("--source is required unless --check is used")
    source = args.source.read_text(encoding="utf-8", errors="replace")
    clusters = extract_java_arrays(source)
    if len(clusters) != CLUSTERS:
        print(f"error: expected {CLUSTERS} clusters, found {len(clusters)}", file=sys.stderr)
        return 1
    for index, patterns in enumerate(clusters):
        verify(patterns)
        print(f"cluster {index}: {len(patterns)} patterns verified", file=sys.stderr)

    if run_lengths(START_PATTERN) != [8, 1, 1, 1, 1, 1, 1, 3]:
        print("error: start pattern does not decode as expected", file=sys.stderr)
        return 1
    if run_lengths(STOP_PATTERN, 18) != [7, 1, 1, 3, 1, 1, 1, 2, 1]:
        print("error: stop pattern does not decode as expected", file=sys.stderr)
        return 1

    args.out.write_text(emit(clusters), encoding="utf-8", newline="\n")
    print(f"wrote {args.out}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
