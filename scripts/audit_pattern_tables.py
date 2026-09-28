"""Independent audit of the generated pattern table and the Rust/Java reference.

Checks, from the committed `patterns.mbt` alone:

1. every cluster holds 929 entries;
2. every entry decodes to 8 elements covering exactly 17 modules;
3. every element is 1..6 modules wide and the entry starts with a bar;
4. all 929 entries inside a cluster are distinct (unique symbol characters);
5. patterns are unique across clusters, so (cluster, pattern) identifies an
   entry;
6. the committed values equal the values in the reference table.

Point 6 is run only when a reference file is supplied.
"""

from __future__ import annotations

import argparse
import pathlib
import re
import sys


def widths(pattern: int, size: int = 17) -> list[int]:
    runs: list[int] = []
    last = (pattern >> (size - 1)) & 1
    run = 0
    for position in range(size - 1, -1, -1):
        bit = (pattern >> position) & 1
        if bit == last:
            run += 1
        else:
            runs.append(run)
            last, run = bit, 1
    runs.append(run)
    return runs


def read_moonbit(path: pathlib.Path) -> list[list[int]]:
    text = path.read_text(encoding="utf-8")
    clusters = []
    for cluster in range(3):
        match = re.search(
            rf"cluster{cluster}_patterns : Array\[Int\] = \[(.*?)\n\]", text, re.S
        )
        if match is None:
            raise SystemExit(f"cluster {cluster} not found in {path.name}")
        clusters.append(
            [int(item, 16) for item in re.findall(r"0x([0-9a-fA-F]+)", match.group(1))]
        )
    return clusters


def read_reference(path: pathlib.Path) -> list[list[int]]:
    text = path.read_text(encoding="utf-8", errors="replace")
    body = text.split("CODEWORD_TABLE", 1)[1].split("};", 1)[0]
    clusters = []
    for chunk in re.split(r"\}\s*,\s*\{", body):
        values = [int(item, 16) for item in re.findall(r"0x([0-9a-fA-F]+)", chunk)]
        if values:
            clusters.append(values)
    return clusters


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--table", type=pathlib.Path, default=pathlib.Path("patterns.mbt")
    )
    parser.add_argument("--reference", type=pathlib.Path)
    args = parser.parse_args()

    failures: list[str] = []
    clusters = read_moonbit(args.table)

    def report(name: str, ok: bool, detail: str = "") -> None:
        print(f"  [{'ok ' if ok else 'FAIL'}] {name}{(' — ' + detail) if detail else ''}")
        if not ok:
            failures.append(name)

    print("1. 每簇条数")
    report("929 entries per cluster", [len(c) for c in clusters] == [929] * 3,
           str([len(c) for c in clusters]))

    print("2. 结构规则 (17 模块 / 8 元素 / 宽度 1..6 / 起始于条)")
    bad = []
    for ci, cluster in enumerate(clusters):
        for idx, pattern in enumerate(cluster):
            runs = widths(pattern)
            if (len(runs) != 8 or sum(runs) != 17
                    or any(r < 1 or r > 6 for r in runs)
                    or ((pattern >> 16) & 1) != 1):
                bad.append((ci, idx, runs))
    report("all 2787 entries structurally valid", not bad, f"{len(bad)} bad")

    print("3. 簇内唯一")
    dupes = []
    for ci, cluster in enumerate(clusters):
        if len(set(cluster)) != len(cluster):
            dupes.append(ci)
    report("no duplicate pattern inside a cluster", not dupes, str(dupes))

    print("4. 跨簇唯一")
    all_patterns = [p for c in clusters for p in c]
    report("patterns unique across clusters", len(set(all_patterns)) == len(all_patterns),
           f"{len(all_patterns) - len(set(all_patterns))} collisions")

    print("5. 判别位（信息性，不作断言）")
    # PDF417 distinguishes the clusters by a sequence of adjacent element
    # widths, not by a single position: no element is constant inside a
    # cluster.  Report the ranges so the finding is visible.
    for element in range(8):
        ranges = [
            sorted({widths(p)[element] for p in clusters[c]}) for c in range(3)
        ]
        print(f"  element {element}: {ranges}")

    if args.reference is not None:
        print("6. 与参考实现逐字节比对")
        reference = read_reference(args.reference)
        same = reference == clusters
        report("committed table equals the reference table", same)
        if not same:
            for c in range(3):
                diff = [i for i in range(929) if reference[c][i] != clusters[c][i]]
                if diff:
                    print(f"      cluster {c}: {len(diff)} differences, first {diff[:5]}")

    print()
    if failures:
        print(f"FAILED: {len(failures)} check(s): {', '.join(failures)}")
        return 1
    print("ALL CHECKS PASSED")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
