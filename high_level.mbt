// High level encoding: the automatic mode selector described in
// ISO/IEC 15438 annex P.
//
// The selector walks the input once.  At every position it measures how many
// characters can be carried by numeric compaction, text compaction and byte
// compaction, then latches into the mode that the standard recommends.  The
// result is the list of *data codewords*; the symbol length descriptor, pad
// codewords and error correction codewords are added by `finalize`.

///|
/// Result of a high level encoding pass.
pub(all) struct HighLevel {
  /// Data codewords, one entry per PDF417 codeword (0..928).
  codewords : Array[Int]
  /// The compaction modes that were used, in order.  Handy for tests and for
  /// the CLI `inspect` command.
  modes : Array[Compaction]
  /// For every codeword, the index into `modes` describing where it came
  /// from.  Latch and shift codewords belong to the segment that follows.
  segments : Array[Int]
}

///|
/// Pending result being built while the selector walks the input.
priv struct HighLevelBuilder {
  codewords : Array[Int]
  modes : Array[Compaction]
  segments : Array[Int]
}

///|
fn HighLevelBuilder::new() -> HighLevelBuilder {
  { codewords: [], modes: [], segments: [] }
}

///|
fn HighLevelBuilder::push_word(
  self : HighLevelBuilder,
  word : Int,
  segment : Int,
) -> Unit {
  self.codewords.push(word)
  self.segments.push(segment)
}

///|
fn HighLevelBuilder::push_words(
  self : HighLevelBuilder,
  words : Array[Int],
  segment : Int,
) -> Unit {
  for word in words {
    self.push_word(word, segment)
  }
}

///|
/// Index of the mode currently being emitted, or -1 when nothing has been
/// emitted yet.
fn HighLevelBuilder::current_segment(self : HighLevelBuilder) -> Int {
  self.modes.length() - 1
}

///|
/// `true` if `code` is a byte that Text Compaction can carry, following the
/// "printable ASCII plus tab, newline and carriage return" rule of annex P.
pub fn is_text_byte(code : Int) -> Bool {
  code == 9 || code == 10 || code == 13 || (code >= 32 && code <= 126)
}

///|
/// Number of consecutive digits starting at `start`.
pub fn consecutive_digits(input : Array[Int], start : Int) -> Int {
  let mut count = 0
  let mut index = start
  while index < input.length() && is_digit(input[index]) {
    count += 1
    index += 1
  }
  count
}

///|
/// Number of consecutive characters that Text Compaction can carry, stopping
/// when a run of 13 or more digits begins.
pub fn consecutive_text(input : Array[Int], start : Int) -> Int {
  let length = input.length()
  let mut index = start
  while index < length {
    let mut numeric = 0
    while numeric < 13 && index < length && is_digit(input[index]) {
      numeric += 1
      index += 1
    }
    if numeric >= 13 {
      return index - start - numeric
    }
    if numeric > 0 {
      continue
    }
    if !is_text_byte(input[index]) {
      break
    }
    index += 1
  }
  index - start
}

///|
/// Number of consecutive characters that should go through byte compaction
/// starting at `start`, following annex P: at most 13 digits may be absorbed
/// before the run is cut so the numeric mode can take over.
pub fn consecutive_binary(input : Array[Int], start : Int) -> Int {
  let length = input.length()
  let mut index = start
  while index < length {
    let mut numeric = 0
    let mut cursor = index
    while numeric < 13 && cursor < length && is_digit(input[cursor]) {
      numeric += 1
      cursor += 1
    }
    if numeric >= 13 {
      return index - start
    }
    index += 1
  }
  index - start
}

///|
/// Emit a byte run, choosing the 913 shift for a single byte inside text
/// mode, the 924 latch for multiples of six bytes and the 901 latch
/// otherwise.  The 901 latch is followed by an explicit byte count.
fn push_byte_run(
  builder : HighLevelBuilder,
  input : Array[Int],
  start : Int,
  count : Int,
  in_text_mode : Bool,
  segment : Int,
) -> Unit {
  if count <= 0 {
    return
  }
  if count == 1 && in_text_mode {
    builder.push_word(shift_byte, segment)
    builder.push_word(input[start], segment)
    return
  }
  if is_byte_group_multiple(count) {
    builder.push_word(latch_byte, segment)
  } else {
    builder.push_word(latch_byte_padded, segment)
    if count < 900 {
      builder.push_word(count, segment)
    } else {
      builder.push_word(count / 900, segment)
      builder.push_word(count % 900, segment)
    }
  }
  let body = encode_byte_segment(input, start, count) catch {
    _ => []
  }
  builder.push_words(body, segment)
}

///|
/// Run the automatic mode selector over `input`.
///
/// Throws `EmptyInput` for an empty input and `UnrepresentableChar` for a
/// code unit outside 0..255.
pub fn encode_high_level(input : Array[Int]) -> HighLevel raise EncodeError {
  if input.is_empty() {
    raise EmptyInput
  }
  for code in input {
    if code < 0 || code > max_byte_value {
      raise UnrepresentableChar(code)
    }
  }
  let builder = HighLevelBuilder::new()
  let length = input.length()
  let mut position = 0
  let mut in_text_mode = true
  let mut submode : TextSubmode = Alpha
  while position < length {
    let digits = consecutive_digits(input, position)
    if digits >= 13 {
      let segment = builder.modes.length()
      builder.modes.push(Numeric)
      builder.push_word(latch_numeric, segment)
      let body = encode_numeric_segment(input, position, digits) catch {
        _ => []
      }
      builder.push_words(body, segment)
      in_text_mode = false
      submode = Alpha
      position += digits
      continue
    }
    let text_run = consecutive_text(input, position)
    if text_run >= 5 || digits == length - position {
      let target = if in_text_mode && !builder.modes.is_empty() {
        builder.current_segment()
      } else {
        let index = builder.modes.length()
        builder.modes.push(Text)
        if !in_text_mode {
          builder.push_word(latch_text, index)
        }
        index
      }
      let (words, next_submode) = encode_text_segment(
        input,
        position,
        text_run,
        submode,
      ) catch {
        _ => ([], Alpha)
      }
      builder.push_words(words, target)
      submode = next_submode
      in_text_mode = true
      position += text_run
      continue
    }
    let mut binary_run = consecutive_binary(input, position)
    if binary_run == 0 {
      binary_run = 1
    }
    let segment = builder.modes.length()
    builder.modes.push(Byte)
    push_byte_run(builder, input, position, binary_run, in_text_mode, segment)
    in_text_mode = false
    submode = Alpha
    position += binary_run
  }
  { codewords: builder.codewords, modes: builder.modes, segments: builder.segments }
}

///|
/// High level encoding without error handling.
pub fn encode_high_level_opt(input : Array[Int]) -> HighLevel? {
  try encode_high_level(input) catch {
    _ => None
  } noraise {
    level => Some(level)
  }
}

///|
/// Encode text with the packed Text Compaction sub-modes only.  The latch
/// codeword is not emitted, matching a symbol whose first data codeword is
/// already in text mode.
pub fn encode_text_only(input : Array[Int]) -> Array[Int] raise EncodeError {
  encode_text(input)
}

///|
/// Encode bytes with Byte Compaction only, including the 901/924 latch and
/// the explicit length count.
pub fn encode_bytes_only(input : Array[Int]) -> Array[Int] raise EncodeError {
  if input.is_empty() {
    raise EmptyInput
  }
  let builder = HighLevelBuilder::new()
  builder.modes.push(Byte)
  push_byte_run(builder, input, 0, input.length(), false, 0)
  builder.codewords
}

///|
/// Encode digits with Numeric Compaction only, including the 902 latch.
pub fn encode_numeric_only(input : Array[Int]) -> Array[Int] raise EncodeError {
  if input.is_empty() {
    raise EmptyInput
  }
  let result : Array[Int] = [latch_numeric]
  for word in encode_numeric(input) {
    result.push(word)
  }
  result
}
