# Sources and compliance notes

`moon-pdf417-core` is an original MoonBit implementation written from public
specifications. The repository does not copy source code, pattern tables or
test fixtures from another barcode library.

## Specifications

- ISO/IEC 15438 (PDF417): chapter 4.4 for the three compactions, annex P for
  the automatic mode selection, chapter 4.10 and annex F for the error
  correction generator polynomials, annex Q for the row and column rules and
  the start/stop pattern geometry, annex E for the recommended error
  correction level, chapter 4.9.2 for pad codewords.
- The mixed and punctuation character tables of Text Compaction are the ones
  the standard defines; `scripts/gen_text_tables.py` regenerates them from the
  character lists so a transcription slip cannot survive review.

## References used for verification

- [ZXing](https://github.com/zxing/zxing) (Apache-2.0) was used as a
  *behavioural* reference and as a source of published test vectors:
  - the small Text Compaction vectors ("AB", "ABCD", "HELLO"),
  - the high level mode selection rules of its PDF417 encoder,
  - the level 0 and level 2 parity vectors for the input `[3, 1, 2]`,
  - the generator polynomial constants of annex F and the start/stop pattern
    bit values,
  - the row indicator formulas in annex Q.

  No ZXing source file is included in this repository and the 928 by 3 codeword
  pattern table of annex A was **not** transcribed; the project intentionally
  stops before bar/space patterns. Where the reference implementation's
  behaviour was used as an oracle, the commit that introduced the vector says
  so.

## Independent decisions

- The decoder is an independent part of this project, not a port: it recovers
  the Berlekamp-Massey iteration degree directly instead of following the
  register-length heuristic of the reference encoder, and it re-checks all
  syndromes after a repair rather than trusting the solve.
- The symbol structure layer expresses the geometry as computation
  (`symbol_modules`, `left_row_indicator`, `right_row_indicator`). Its start and
  stop patterns and the annex A symbol character tables were checked against
  the reference values, including the structural rules the standard imposes
  (17 modules per character, every bar or space 1..6 modules wide, alternating
  and starting with a bar), which `scripts/gen_pattern_tables.py` re-runs with
  `--check`.

## Symbol character tables

`patterns.mbt` is the ISO/IEC 15438 annex A symbol character table: 929
characters per bar-space cluster, stored as 17 bit integers. It is specification
data rather than program logic.

`scripts/gen_pattern_tables.py` normalises the table and refuses to emit it
unless every one of the 2787 entries satisfies the structural rules above and
the start and stop patterns decode to their documented widths.
`scripts/audit_pattern_tables.py` re-checks the committed file on its own and
can compare it against a reference copy with `--reference`; run against the
reference implementation's table it reports the storage forms as identical, so
no value was altered while normalising.

Two findings worth recording:

* the three clusters are told apart by a *sequence* of adjacent element widths,
  not by any single element. No element is constant inside a cluster, so a
  decoder has to compare a pattern; the audit prints the per-element ranges to
  make that visible. The library never needs to guess a cluster: the row index
  already says which one applies.
* the library depends on the tables only through `cluster_pattern`, so a
  caller that does not render anything never pays attention to them.


## Test data

All test inputs are short synthetic examples ("HELLO WORLD", digit runs,
`[3, 1, 2]`, deliberately corrupted codewords). No private data, commercial
fixture or closed test vector is included.
