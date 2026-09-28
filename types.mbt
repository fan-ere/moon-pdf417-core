// Public types, shared constants and encoding errors.
//
// Everything in this module works on *codewords*: integers in the range
// 0..928, the alphabet PDF417 uses before the symbols are turned into bars
// and spaces.  The library deliberately stops at that boundary; start/stop
// patterns, row indicators and graphics belong to a renderer.

///|
/// Compaction (high level encoding) mode.
///
/// `Text` uses the packed Text Compaction sub-modes, `Numeric` the base 900
/// decimal compaction, `Byte` the raw byte compaction and `Auto` lets the
/// encoder pick a mode per segment.
pub(all) enum Compaction {
  Text
  Numeric
  Byte
  Auto
}

///|
pub impl Eq for Compaction with fn equal(self : Compaction, other : Compaction) -> Bool {
  match (self, other) {
    (Text, Text) => true
    (Numeric, Numeric) => true
    (Byte, Byte) => true
    (Auto, Auto) => true
    _ => false
  }
}

///|
/// Keep `Eq` usable by callers without promoting its methods.
pub extend Compaction with Eq::{not_equal, equal}

///|
/// Text Compaction sub-mode, as defined by ISO/IEC 15438 4.4.2.
pub(all) enum TextSubmode {
  Alpha
  Lower
  Mixed
  Punctuation
}

///|
pub impl Eq for TextSubmode with fn equal(
  self : TextSubmode,
  other : TextSubmode,
) -> Bool {
  match (self, other) {
    (Alpha, Alpha) => true
    (Lower, Lower) => true
    (Mixed, Mixed) => true
    (Punctuation, Punctuation) => true
    _ => false
  }
}

///|
pub extend TextSubmode with Eq::{not_equal, equal}

///|
/// Debug rendering of a text sub-mode, used by tests and diagnostics.
pub fn TextSubmode::name(self : TextSubmode) -> String {
  match self {
    Alpha => "Alpha"
    Lower => "Lower"
    Mixed => "Mixed"
    Punctuation => "Punctuation"
  }
}

///|
/// A complete PDF417 codeword sequence with the layout that produced it.
///
/// `codewords` is the *full* sequence that a low level encoder consumes:
/// the symbol length descriptor, the high level data codewords, the pad
/// codewords and finally the error correction codewords.
pub(all) struct Symbol {
  codewords : Array[Int]
  columns : Int
  rows : Int
  ec_level : Int
  data_count : Int
  pad_count : Int
}

///|
/// Everything that can go wrong while encoding.
///
/// `EncodeError` is a MoonBit error type, so it can be raised with `raise`
/// and caught with `catch`.  Every fallible entry point also has an `_opt`
/// companion that returns `Option` instead.
pub suberror EncodeError {
  /// The input contained no encodable character.
  EmptyInput
  /// A character cannot be represented in the requested compaction mode.
  UnrepresentableChar(Int)
  /// The data plus padding and error correction does not fit into 928
  /// codewords.
  TooManyCodewords(Int)
  /// The error correction level was outside 0..8.
  InvalidErrorCorrectionLevel(Int)
  /// The requested number of columns was outside 1..30.
  InvalidColumnCount(Int)
  /// No row count in 3..90 can hold the requested codewords for this
  /// column count.
  LayoutImpossible(Int, Int)
  /// The caller asked for more corrections than Reed-Solomon can guarantee
  /// for this codeword count.
  TooManyErasures(Int, Int)
} derive(Debug)

///|
/// Keep the derived `Debug` implementation available through `to_repr`
/// without promoting it to a regular method (which the compiler deprecates).
pub extend EncodeError with @debug.Debug::{to_repr}

///|
pub let max_codewords : Int = 928

///|
pub let max_columns : Int = 30

///|
pub let min_columns : Int = 1

///|
pub let min_rows : Int = 3

///|
pub let max_rows : Int = 90

///|
pub let max_error_correction_level : Int = 8

///|
/// Number of Reed-Solomon parity codewords for an error correction level.
/// ISO/IEC 15438 defines this as `2^(level + 1)`.
pub fn error_correction_codeword_count(level : Int) -> Int {
  1 << (level + 1)
}

///|
/// Mode latch to Text Compaction.
pub let latch_text : Int = 900

///|
/// Mode latch to Byte Compaction with an explicit length count.
pub let latch_byte_padded : Int = 901

///|
/// Mode latch to Numeric Compaction.
pub let latch_numeric : Int = 902

///|
/// Mode shift to Byte Compaction for a single byte.
pub let shift_byte : Int = 913

///|
/// Mode latch to Byte Compaction for multiples of six bytes.
pub let latch_byte : Int = 924

///|
/// Pad codeword used to fill a symbol up to `rows * columns`.
pub let pad_codeword : Int = 900

///|
/// Highest byte value that byte compaction can carry.
pub let max_byte_value : Int = 255
