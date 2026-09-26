#!/usr/bin/env python3
"""Regenerate the Text Compaction lookup tables of `text_tables.mbt`.

ISO/IEC 15438 defines Text Compaction as a mapping from characters to values
0..29 in four sub-modes.  Alpha and Lower are arithmetic, but Mixed and
Punctuation are tables.  Hand-transcribing them is error prone: an earlier
revision of this repository dropped one Punctuation entry, which shifted every
value from position 4 onward, so `]` encoded as 6 instead of 5.

This script takes the two character lists in table order, builds the inverted
"character code -> value" arrays that the encoder needs, and prints them in the
exact form used by `text_tables.mbt`.  The forward tables ("value -> character
code") are printed as well, so the two directions can be eyeballed together.

Usage:
    python scripts/gen_text_tables.py            # print the tables
    python scripts/gen_text_tables.py --check    # diff against text_tables.mbt
"""

from __future__ import annotations

import argparse
import pathlib
import re
import sys

# Value 0..29 -> character code, in the order the standard lists them.
# A zero means "no character assigned to this value".
MIXED_RAW = [
    48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 38, 13, 9, 44, 58, 35,
    45, 46, 36, 47, 43, 37, 42, 61, 94, 0, 32, 0, 0, 0,
]

PUNCTUATION_RAW = [
    59, 60, 62, 64, 91, 92, 93, 95, 96, 126, 33, 13, 9, 44, 58, 10,
    45, 46, 36, 47, 34, 124, 42, 40, 41, 63, 123, 125, 39, 0,
]

TABLE_PATH = pathlib.Path(__file__).resolve().parent.parent / "text_tables.mbt"


def invert(raw: list[int]) -> list[int]:
    """Build the `character code -> value` table, -1 where unassigned."""
    inverse = [-1] * 256
    for value, code in enumerate(raw):
        if code > 0:
            if inverse[code] != -1:
                raise ValueError(f"character {code} assigned twice")
            inverse[code] = value
    return inverse


def consistent(inverse: list[int], raw: list[int]) -> None:
    for code in range(256):
        value = inverse[code]
        if value >= 0 and raw[value] != code:
            raise ValueError(f"table is not an inverse at character {code}")


def format_array(name: str, values: list[int], rows: int = 16) -> str:
    lines = [f"pub let {name} : Array[Int] = ["]
    for start in range(0, len(values), rows):
        chunk = values[start : start + rows]
        body = ", ".join(str(value) for value in chunk)
        lines.append(f"  {body}, // {start}..{start + len(chunk) - 1}")
    lines.append("]")
    return "\n".join(lines)


def render() -> str:
    mixed_inverse = invert(MIXED_RAW)
    punctuation_inverse = invert(PUNCTUATION_RAW)
    consistent(mixed_inverse, MIXED_RAW)
    consistent(punctuation_inverse, PUNCTUATION_RAW)
    return "\n\n".join(
        [
            format_array("mixed_value", mixed_inverse),
            format_array("punctuation_value", punctuation_inverse),
            format_array("mixed_char", MIXED_RAW),
            format_array("punctuation_char", PUNCTUATION_RAW),
        ]
    )


def extract(source: str, name: str) -> list[int] | None:
    """Read a `pub let <name> : Array[Int]` literal out of the source file.

    Comments are stripped first so the trailing `// 0..15` markers cannot be
    mistaken for values, and the array body ends at the last `]` of the
    literal rather than at the first one.
    """
    without_comments = re.sub(r"//[^\n]*", "", source)
    match = re.search(
        rf"pub let {name} : Array\[Int\] = \[(.*?)\]\s*(?=pub let|\Z)",
        without_comments,
        re.S,
    )
    if match is None:
        return None
    return [int(item) for item in re.findall(r"-?\d+", match.group(1))]


def same_table(actual: list[int], expected: list[int]) -> bool:
    """Compare two value tables.

    The source file marks unused values with -1 and may omit trailing unused
    slots; the generator uses 0 to mean "no character assigned".  Both are
    normalised here so the comparison only looks at the assigned entries.
    """
    height = max(len(actual), len(expected))
    for index in range(height):
        left = actual[index] if index < len(actual) else -1
        right = expected[index] if index < len(expected) else -1
        if left <= 0 or right <= 0:
            if left > 0 or right > 0:
                return False
        elif left != right:
            return False
    return True


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--check",
        action="store_true",
        help="compare the generated tables with text_tables.mbt",
    )
    args = parser.parse_args()

    generated = {
        "mixed_value": invert(MIXED_RAW),
        "punctuation_value": invert(PUNCTUATION_RAW),
        "mixed_char": MIXED_RAW,
        "punctuation_char": PUNCTUATION_RAW,
    }

    if not args.check:
        print(render())
        return 0

    source = TABLE_PATH.read_text(encoding="utf-8")
    failures = []
    for name, expected in generated.items():
        actual = extract(source, name)
        if actual is None:
            failures.append(f"{name}: not found in {TABLE_PATH.name}")
        elif not same_table(actual, expected):
            failures.append(f"{name}: differs from the generated table")
    if failures:
        for failure in failures:
            print(f"error: {failure}", file=sys.stderr)
        return 1
    print(f"{TABLE_PATH.name} matches the generated tables")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
