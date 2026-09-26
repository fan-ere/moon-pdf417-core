# Development log

This is the development history of `moon-pdf417-core`, written from the
repository's own Git history. Each section names the commit range it covers and
the decisions that were made, including the ones that turned out to be wrong.

## 1. Scope: what layer is worth building

PDF417 in the MoonBit ecosystem sits between two problems. A *renderer* turns
codewords into bars; a *codeword layer* turns a message into codewords with the
right error correction. The renderer side needs a 928 by 3 table of bar/space
patterns and a lot of geometry, and it is where every existing implementation
already spends its lines. The codeword side is where the interesting,
checkable mathematics is: base 900 compaction, a finite field, and layout
rules that a test can prove.

So the project fixes its boundary before writing code: it owns everything up to
and including the padded, parity-corrected codeword sequence, plus the row
indicator formulas, and it deliberately does not embed the annex A pattern
table. That decision is recorded in the README, in the proposal and in
`symbol.mbt`, and it is the reason `verify_symbol` can exist without a renderer.

## 2. Metadata, module identity and tooling

The first commits set the module to `fan-ere/moon-pdf417-core`, pinned
`preferred_target = "wasm"`, added a dependency-free `moon.pkg`, the MIT
license and a `.gitattributes` that forces LF so a Windows checkout produces
the same bytes as CI.

Two toolchain facts shaped the code that follows. The local compiler is
`moonc v0.10.14` with `moon 0.1.20260920`, and in this version:

* `try?` is deprecated; the migration is `try expr catch { e => ... } noraise
  { ok => ... }`, which is why every fallible entry point has a matching `_opt`
  companion written in that form;
* `derive(Eq)` and `derive(Debug)` on a `suberror` produce an
  `implicit_impl_as_method` warning that `--deny-warn` turns into an error, so
  `EncodeError` derives `Debug` and carries an explicit
  `pub extend EncodeError with @debug.Debug::{to_repr}` declaration.

`moon.mod` also taught a smaller lesson: its value syntax does not accept
`\u{...}` escapes, so the human readable Chinese description lives in the
README and the module description stays English.

## 3. Text Compaction and a table bug worth remembering

Text Compaction maps characters to values 0..29 in four sub-modes and packs two
values into a codeword. Alpha and Lower are arithmetic; Mixed and Punctuation
are tables. The first version hand-transcribed both tables, and that was the
single most expensive mistake in the project: the Punctuation table was missing
one entry, which shifted every value from position 4 onward, so `]` encoded as
6 instead of 5. Round trip tests did not catch it because both directions used
the same wrong table; only the fixed vector `"]_" -> [876, 877]` did.

The fix was structural rather than a one line correction:
`scripts/gen_text_tables.py` now rebuilds both inverse tables from the character
lists and prints them for review. That is also why `text_tables.mbt` documents
itself as generated data with a checking script rather than as hand-written
constants.

The sub-mode automaton itself has one rule that is easy to get backwards: in
Alpha, code 27 shifts to Lower *for the same character*, so the shifted letter
must be emitted in the same step. The first implementation shifted and then
moved on, which inserted a spurious 26 (space) into every mixed case string.
The test `"AbD" -> [27, 33]` pins that down.

## 4. Numeric and Byte compaction

Numeric Compaction prefixes each chunk of up to 44 digits with a literal `1` so
leading zeros survive; without it `"0123"` and `"123"` would collide. The
implementation keeps that prefix and does the conversion with decimal long
division, which avoids pulling in a big integer package and keeps the library
free of dependencies.

Byte Compaction reads six bytes as a big endian 48 bit integer and writes five
base 900 codewords, so the arithmetic has to happen in `Int64`; the remaining
one to five bytes are emitted literally. The 901 versus 924 decision is
`count % 6 == 0`, and 901 mode carries an explicit byte count that needs one
codeword below 900 and two from 900 upward.

## 5. The mode selector, and a stall that hung the test runner

`encode_high_level` follows annex P: measure the consecutive digit run, the text
run and the binary run at the current position, then latch. Three rules matter
and all three were initially wrong:

1. The text branch is taken when `t >= 5` **or** when the rest of the input
   contains no digits at all (`n == len - p`). Implementing the second half as
   `digits == length - position` never fired; the correct expression is
   "the text run covers everything that is left".
2. A text run of length zero must never be selected. The first version accepted
   it, appended nothing, and did not advance the cursor: the test runner spun
   at 100% CPU until it was killed. The condition now requires
   `text_run > 0`, so the walk always makes progress.
3. The binary run counter must look *forward* for the next run of 13 or more
   digits instead of resetting the count at every character. With the reset
   version a non-text byte followed by plain text produced a binary run that
   swallowed the rest of the message, so the 913 shift was never used.

The shift itself was another correction: the first implementation hard-coded
`in_text_mode = false` after a byte run, even when a single byte had just been
carried by the 913 shift, which stays in text mode. `push_byte_run` now returns
the mode it leaves behind.

`high_level_test.mbt` covers each of these rules, and the specific input that
triggers the shift (a byte between a text run and a 13 digit run) is written
out in full with a comment explaining why the more obvious input does not reach
that branch.

## 6. Reed-Solomon: making the decoder actually repair

Parity generation was straightforward: build `(x-3)(x-3^2)...(x-3^degree)`,
take the remainder of `data(x) * x^degree`, store it most significant first, and
check it against the level 0 and level 2 vectors.

The decoder was where the real work was, and the first version was wrong twice:

* Berlekamp-Massey used the "register length" heuristic of a public reference
  encoder. For two errors it produced a degree four locator whose Chien search
  found the two correct positions *plus* two spurious ones, which then looked
  like "too many errors". Tracking the true register degree with
  `2 * degree <= index` and `degree = index + 1 - degree` gives the degree two
  locator with exactly two roots.
* Magnitude recovery assumed `S[j] = sum e_k * X_k^j`, but the syndrome
  evaluator computes `S[j] = sum e_k * X_k^(j+1)`. The solver was therefore
  solving the wrong system. It now uses matching powers.

Both bugs were invisible to the encoder tests and only appeared once a test
corrupted a codeword on purpose. After every repair the sequence is re-checked
by recomputing all syndromes, so a wrong answer surfaces as a failure instead
of as silently damaged data. Erasure positions are accepted and double the
repair budget.

## 7. Layout and structure

The layout rules are the ones a reviewer can check by hand:
`rows = ceil((data + 1 + ec) / columns)` with a three row minimum, pad codewords
of value 900, and the symbol length descriptor first. `finalize` composes them
with the parity block, and `verify_symbol` re-derives all three properties.

The structure layer adds the start and stop patterns, expands patterns into bar
widths, and implements the annex Q row indicator formulas. These are computed
rather than tabulated, and the tests check the formulas against hand derived
values for all three clusters plus the range `0..928` across every legal row,
column and level combination.

One small wrong assumption is worth recording: the total module width was first
written as "start plus stop plus codewords", which double counted the area
covered by start and stop. The corrected form is `35 + 17 * columns`, matching
the geometry the reference implementation uses.

## 8. Decoding as a verification tool

The decoder exists to make claims falsifiable. `decode_text_values` inverts the
sub-mode automaton, `decode_byte` and `decode_numeric` invert the other two
compactions, and `decode_high_level` walks the mode latches.

Text Compaction has no end-of-segment marker: the pad for an odd number of
values is 29, which is also the punctuation shift code. `unpack_text_values`
therefore documents the ambiguity and prefers the reading that decodes, rather
than silently truncating the last character. This is a real property of the
format, not a shortcut, and it is why the README says the round trip check is
evidence about *our* encoder and decoder rather than a third party guarantee.

## 9. Command line and examples

`cmd/main` exposes `encode`, `inspect`, `capacity` and `structure`, sharing the
library's public API and adding nothing that is not tested. The runner passes
the module path as `argv[0]`, which the parser strips when the first argument
looks like an artifact path. `examples/quickstart` is the shortest end to end
reproduction: it encodes a mixed message, lays out a level 2 symbol and prints
the verification result.

## 10. Remaining work

* The annex A pattern table and SVG/ASCII rendering, which would turn codewords
  into a scannable image; the boundary is documented in the README and in
  `symbol.mbt`.
* ECI and charset negotiation, so non-Latin-1 payloads do not need the caller
  to pre-encode with `utf8_bytes`.
* Macro PDF417 and structured append.

Publishing to mooncakes.io has not been done; the repository is the record of
what exists today.
