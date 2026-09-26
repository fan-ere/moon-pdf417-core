# Moon PDF417 Core

A dependency-free MoonBit library for the **codeword layer** of PDF417: the
part between "the user has a message" and "a renderer has codewords".

It implements high level encoding (Text, Byte and Numeric compaction plus the
automatic mode selector), GF(929) Reed-Solomon error correction, symbol layout
planning, row indicators, and the inverse decoders that make every generated
symbol verifiable.

```moonbit
let codes : Array[Int] = []
for character in "HELLO WORLD 1234567890123".iter() {
  codes.push(character.to_int())
}
let high = @pdf417.encode_high_level(codes)          // data codewords
let symbol = @pdf417.finalize(high.codewords, 2, 4)  // + descriptor, pad, parity
@pdf417.verify_symbol(symbol)                        // true
```

## What it does

| Area | API |
| --- | --- |
| Text Compaction | `encode_text`, `encode_text_segment`, `decode_text`, `text_automaton` |
| Numeric Compaction | `encode_numeric`, `decimal_chunk_to_base900`, `base900_to_decimal`, `decode_numeric` |
| Byte Compaction | `encode_byte`, `bytes_to_base900`, `base900_to_bytes`, `decode_byte` |
| Automatic mode selection | `encode_high_level`, `consecutive_digits`, `consecutive_text`, `consecutive_binary` |
| Error correction | `error_correction`, `generator_polynomial`, `syndromes`, `correct_errors` |
| Layout | `finalize`, `rows_for`, `pad_codewords`, `plan_columns`, `data_capacity` |
| Structure | `start_pattern`, `stop_pattern`, `left_row_indicator`, `right_row_indicator`, `symbol_rows`, `symbol_modules` |
| Verification | `verify_symbol`, `is_error_free`, `round_trip_matches`, `decode_high_level` |

### Scope

This is a **codeword layer** library. It does **not** contain the ISO/IEC
15438 annex A table of 928 bar/space patterns per cluster, so it does not draw
a scannable symbol by itself. A renderer supplies the pattern data and uses
`symbol_rows`, `symbol_modules` and the start/stop patterns from here to place
the codewords.

It also does **not** implement ECI, so input is interpreted as an array of code
units in `0..255`. `utf8_bytes` converts a MoonBit string to UTF-8 byte values
for callers that want non-Latin-1 payloads; pass the result to byte compaction
or to the automatic selector.

## Install and reproduce

Install the [MoonBit toolchain](https://www.moonbitlang.com/download/) and make
sure `moon version --all` works. Then, from the repository root:

```sh
moon check --deny-warn --target all
moon build --target wasm
moon test --deny-warn --target wasm
moon test --deny-warn --target wasm-gc
moon test --deny-warn --target js
moon run examples/quickstart --target wasm
```

`examples/quickstart` prints the data codewords, the padded and parity-corrected
codeword sequence and the verification result, so a successful run is the
shortest reproducibility check.

## Command line

```sh
moon run cmd/main --target native -- encode --data "HELLO WORLD 1234567890123" --level 2 --columns 4
moon run cmd/main --target native -- inspect --data "HELLO WORLD"
moon run cmd/main --target native -- capacity --level 2
moon run cmd/main --target native -- structure --columns 4 --rows 6 --level 2
```

`--codes 72,69,76,76,79` feeds raw code units instead of text. The CLI works on
every target; the examples above use `native` because it needs no runtime.

## Correctness evidence

* Text Compaction vectors: `"AB" -> [1]`, `"ABCD" -> [1, 63]`,
  `"HELLO" -> [214, 341, 449]`, `"]_" -> [876, 877]`.
* Numeric Compaction vector: `"1234" -> [12, 434]` with the leading `1` prefix
  kept, so leading zeros survive.
* Reed-Solomon reference vectors: level 0 over `[3, 1, 2]` gives
  `[335, 565]`; level 2 gives `[791, 65, 893, 586, 381, 161, 381, 304]`; the
  generator polynomials equal annex F.
* Error correction is tested end to end: two corrupted codewords in a level 3
  symbol are located with Berlekamp-Massey and repaired, and erasures double
  the repair budget.
* The suite then covers the three compactions, the mode selector, the decoder,
  the parity block, the layout rules and the row indicator formulas.

The tests show that the encoder and decoder agree with the reference vectors
above; they do not prove that a third party decoder or a scanner reads these
symbols, because the bar/space patterns are out of scope here. See
[docs/SOURCES.md](docs/SOURCES.md) for what was compared against which
reference.

## Documentation

* [申报书.md](申报书.md) — one page project proposal.
* [docs/SOURCES.md](docs/SOURCES.md) — specifications, references and licenses.
* [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md) — development log.
* [docs/OSC2026_SELF_REVIEW.md](docs/OSC2026_SELF_REVIEW.md) — local self review.
* [AGENTS.md](AGENTS.md) — conventions for agents and contributors.

## License

MIT, see [LICENSE](LICENSE).
