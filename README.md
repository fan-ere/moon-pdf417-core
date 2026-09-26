# Moon PDF417 Core

A pure MoonBit **codeword-layer** library for PDF417. It encodes uppercase text and spaces in Alpha submode, bytes in 901/924 mode, and decimal strings in numeric mode. It generates Reed-Solomon parity over GF(929), plans rows from a chosen column count, inserts padding and updates the length descriptor.

## Use

```moonbit
let text = encode_uppercase("HELLO WORLD")
let binary = encode_bytes([1, 2, 3, 4, 5, 6])
let digits = encode_numeric("123456789")
match text {
  Some(data) => {
    let full = finalize_codewords(data, 2, 4)
    // Pass `full` to a PDF417 row-pattern renderer.
  }
  None => ()
}
```

`encode_uppercase` rejects unsupported characters; `encode_numeric` requires digits. `finalize_codewords` rejects invalid levels (outside 0-8), columns (outside 1-30) and impossible capacities. Output contains data, padding and correction codewords. **It is not a scannable symbol:** row indicators, bar/space patterns, start/stop patterns and graphic rendering are outside this package. Mixed/punctuation text optimization is also not supported.

## Install and reproduce

Install the [MoonBit toolchain](https://www.moonbitlang.com/download/) and confirm that `moon version --all` works. Run these commands from this project's root directory:

```sh
moon check --deny-warn --target all
moon build --target wasm
moon test --deny-warn --target wasm
moon run --target wasm examples/demo
```

Tests include a numeric reference vector and level-zero parity vector, along with capacity and input boundaries. CI defines check, build, and test on Linux. See [PROJECT_PROPOSAL.md](PROJECT_PROPOSAL.md) for the September contest proposal.

## Scope and source

This package serves barcode renderers and codeword compatibility tools. GitHub searches `moonbit PDF417`, `moonbit barcode417` and Mooncakes search `pdf417` found no MoonBit equivalent on 2026-09-24; this is not a universal guarantee. Algorithms follow PDF417's public principles; the parity vector was compared with [ZXing](https://github.com/zxing/zxing) (Apache-2.0), without copying code or tables. MIT license.
