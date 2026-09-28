# Project Agents.md Guide

This is a [MoonBit](https://docs.moonbitlang.com) project.

## Project

`moon-pdf417-core` is a dependency-free MoonBit library for the codeword layer
of PDF417: high level encoding, GF(929) Reed-Solomon error correction, symbol
layout and the decoders used to verify all of it.

- The root package is the library. Keep it free of external dependencies so it
  compiles for `native`, `wasm`, `wasm-gc` and `js`.
- `cmd/main` is the command line front end and may import `moonbitlang/core/env`.
- `examples/quickstart` is the shortest end to end reproduction and must keep
  working on every target.

## Scope

The library stops at codewords. It does **not** carry the ISO/IEC 15438 annex A
bar/space pattern table and does not draw a scannable symbol. If you add
rendering, keep the current codeword API intact and record the licence of any
table you introduce.

## Project structure

- MoonBit packages live per directory, each with a `moon.pkg` listing its
  dependencies.
- Blackbox tests end in `_test.mbt` and import the package under test; whitebox
  tests end in `_wbtest.mbt` and see the package internals. Use a `_wbtest.mbt`
  only when a test must reach a private function.
- `moon.mod` holds the module metadata.

## Coding conventions

- MoonBit code is organised in blocks separated by `///|`.
- Fallible functions raise `EncodeError` (a `suberror` in `types.mbt`) and each
  one has an `_opt` companion returning `Option`, written as
  `try expr catch { _ => None } noraise { value => Some(value) }`.
  `try?` is deprecated in the current toolchain.
- Do not derive `Eq` or `Debug` on `EncodeError`: `--deny-warn` rejects the
  implicit method promotion. `EncodeError` derives `Debug` and carries an
  explicit `pub extend EncodeError with @debug.Debug::{to_repr}`.
- Keep generated data (the Text Compaction tables) in its own file with the
  script that regenerates it next to it in `scripts/`.

## Tooling

- `moon fmt` formats the code and `moon info` refreshes the generated `.mbti`
  interfaces. Run `moon fmt && moon info` before committing; `moon info` must
  leave no diff.
- `moon check --deny-warn --target all` must pass before a commit.
- `moon test --deny-warn --target wasm` must pass; run `wasm-gc` and `js` too
  when you touch arithmetic or string handling.
- `moon run examples/quickstart --target wasm` and the `cmd/main` smoke test:
  ```sh
  moon run cmd/main --target wasm -- encode --data "HELLO WORLD 1234567890123" --level 2 --columns 4
  moon run cmd/main --target wasm -- structure --columns 4 --rows 4 --level 2
  ```
- Prefer `assert_eq` for stable values (reference vectors, table lookups) and
  `assert_true` for properties such as the `0..928` range of row indicators.
- Use `moon coverage analyze > uncovered.log` when you want to see which
  branches of the mode selector or the decoder are still untested.
