// Decoding: the inverse of the compactions, used for round-trip verification.
//
// PDF417 puts great care into *encoding* and leaves a good deal of work to the
// decoder.  Text Compaction, for instance, has no explicit end-of-segment
// marker: padding of a trailing odd value is indistinguishable from a real
// punctuation shift, so a decoder has to fall back on plausibility checks.
// This module documents and implements those rules so that a generated symbol
// can be read back and compared with its input.

///|
/// Reverse the Text Compaction sub-mode automaton.  `values` is a sequence of
/// values 0..29 without the trailing pad heuristic applied.
pub fn decode_text_values(values : Array[Int]) -> Array[Int] raise EncodeError {
  let output : Array[Int] = []
  let mut index = 0
  let mut submode = Alpha
  while index < values.length() {
    let value = values[index]
    match submode {
      Alpha =>
        if value < 26 {
          output.push(value + 65)
        } else if value == 26 {
          output.push(32)
        } else if value == 27 {
          submode = Lower
        } else if value == 28 {
          submode = Mixed
        } else if index + 1 < values.length() {
          index += 1
          let character = punctuation_lookup(values[index])
          output.push(character)
        } else {
          raise UnrepresentableChar(value)
        }
      Lower =>
        if value < 26 {
          output.push(value + 97)
        } else if value == 26 {
          output.push(32)
        } else if value == 27 {
          submode = Alpha
        } else if value == 28 {
          submode = Mixed
        } else if index + 1 < values.length() {
          index += 1
          let character = punctuation_lookup(values[index])
          output.push(character)
        } else {
          raise UnrepresentableChar(value)
        }
      Mixed =>
        if value < 25 {
          output.push(mixed_lookup(value))
        } else if value == 25 {
          submode = Punctuation
        } else if value == 26 {
          output.push(32)
        } else if value == 27 {
          submode = Lower
        } else if value == 28 {
          submode = Alpha
        } else if index + 1 < values.length() {
          index += 1
          let character = punctuation_lookup(values[index])
          output.push(character)
        } else {
          raise UnrepresentableChar(value)
        }
      Punctuation =>
        if value < 30 {
          output.push(punctuation_lookup(value))
        } else {
          raise UnrepresentableChar(value)
        }
    }
    index += 1
  }
  output
}

///|
/// Character for a Punctuation sub-mode value.
fn punctuation_lookup(value : Int) -> Int raise EncodeError {
  if value < 0 || value >= punctuation_char.length() {
    raise UnrepresentableChar(value)
  }
  let character = punctuation_char[value]
  if character < 0 {
    raise UnrepresentableChar(value)
  }
  character
}

///|
/// Character for a Mixed sub-mode value.
fn mixed_lookup(value : Int) -> Int raise EncodeError {
  if value < 0 || value >= mixed_char.length() {
    raise UnrepresentableChar(value)
  }
  let character = mixed_char[value]
  if character < 0 {
    raise UnrepresentableChar(value)
  }
  character
}

///|
/// Unpack codewords into Text Compaction values, dropping a trailing
/// punctuation-shift pad when the resulting stream still decodes cleanly.
pub fn unpack_text_values(words : Array[Int]) -> Array[Int] {
  let values : Array[Int] = []
  for word in words {
    if word < 0 || word > 928 {
      return []
    }
    values.push(word / 30)
    values.push(word % 30)
  }
  if values.length() == 0 || values[values.length() - 1] != tc_text_pad {
    return values
  }
  // The stream ends in 29, which is either the pad for an odd number of
  // values or a genuine punctuation shift followed by a value.  Both readings
  // are usually decodable, so `padded_ok` (which for a real character
  // sequence consumes the last codeword as a pending shift) decides.
  let trimmed : Array[Int] = []
  for index in 0..<(values.length() - 1) {
    trimmed.push(values[index])
  }
  let padded_ok = text_values_decode(values)
  let trimmed_ok = text_values_decode(trimmed)
  if padded_ok {
    values
  } else if trimmed_ok {
    trimmed
  } else {
    values
  }
}

///|
/// `true` when `values` can be decoded without raising.
fn text_values_decode(values : Array[Int]) -> Bool {
  try decode_text_values(values) catch {
    _ => false
  } noraise {
    _ => true
  }
}

///|
/// Decode a Text Compaction codeword run back to characters.
pub fn decode_text(words : Array[Int]) -> Array[Int] raise EncodeError {
  if words.is_empty() {
    raise EmptyInput
  }
  decode_text_values(unpack_text_values(words))
}

///|
/// Decode a high level data codeword sequence (without the symbol length
/// descriptor) back to characters.
///
/// Text and byte segments are decoded exactly.  Numeric segments are decoded
/// greedily from the latch up to the next mode latch, which is how the
/// encoder emits them in the common single-segment case.
pub fn decode_high_level(words : Array[Int]) -> Array[Int] raise EncodeError {
  if words.is_empty() {
    raise EmptyInput
  }
  let output : Array[Int] = []
  let mut index = 0
  let mut mode = Text
  while index < words.length() {
    let word = words[index]
    if word == latch_text {
      mode = Text
      index += 1
      continue
    }
    if word == latch_numeric {
      mode = Numeric
      index += 1
      continue
    }
    if word == latch_byte || word == latch_byte_padded {
      mode = Byte
      index += 1
      let mut byte_count = 0
      if word == latch_byte_padded {
        byte_count = words[index]
        index += 1
        if byte_count >= 900 {
          byte_count = byte_count * 900 + words[index]
          index += 1
        }
      }
      if byte_count == 0 {
        // 924 mode: consume the rest of the sequence.
        let body : Array[Int] = []
        while index < words.length() {
          body.push(words[index])
          index += 1
        }
        for byte in decode_byte(body) {
          output.push(byte)
        }
      } else {
        let consumed = byte_capacity(byte_count)
        let body : Array[Int] = []
        let mut taken = 0
        while taken < consumed && index < words.length() {
          body.push(words[index])
          index += 1
          taken += 1
        }
        for byte in decode_byte(body) {
          output.push(byte)
        }
      }
      continue
    }
    if word == shift_byte {
      mode = Byte
      index += 1
      if index < words.length() {
        output.push(words[index])
        index += 1
      }
      mode = Text
      continue
    }
    if mode == Text {
      let body : Array[Int] = []
      while index < words.length() &&
            words[index] != latch_text &&
            words[index] != latch_numeric &&
            words[index] != latch_byte &&
            words[index] != latch_byte_padded {
        body.push(words[index])
        index += 1
      }
      for character in decode_text(body) {
        output.push(character)
      }
      continue
    }
    if mode == Numeric {
      let body : Array[Int] = []
      while index < words.length() &&
            words[index] != latch_text &&
            words[index] != latch_numeric &&
            words[index] != latch_byte &&
            words[index] != latch_byte_padded {
        body.push(words[index])
        index += 1
      }
      for digit in decode_numeric(body) {
        output.push(digit)
      }
      continue
    }
    raise UnrepresentableChar(word)
  }
  output
}

///|
/// Decoding without error handling.
pub fn decode_high_level_opt(words : Array[Int]) -> Array[Int]? {
  try decode_high_level(words) catch {
    _ => None
  } noraise {
    characters => Some(characters)
  }
}

///|
/// `true` when the high level decoding of `words` reproduces `input`.
pub fn round_trip_matches(input : Array[Int], words : Array[Int]) -> Bool {
  match decode_high_level_opt(words) {
    Some(decoded) => decoded == input
    None => false
  }
}

///|
/// Convert a string to its UTF-8 byte values.  Handy for callers that want
/// non-Latin-1 payloads, since the library itself works on 0..255 code units.
pub fn utf8_bytes(text : String) -> Array[Int] {
  let bytes : Array[Int] = []
  for character in text.iter() {
    let code = character.to_int()
    if code < 0x80 {
      bytes.push(code)
    } else if code < 0x800 {
      bytes.push(0xC0 | (code >> 6))
      bytes.push(0x80 | (code & 0x3F))
    } else if code < 0x10000 {
      bytes.push(0xE0 | (code >> 12))
      bytes.push(0x80 | ((code >> 6) & 0x3F))
      bytes.push(0x80 | (code & 0x3F))
    } else {
      bytes.push(0xF0 | (code >> 18))
      bytes.push(0x80 | ((code >> 12) & 0x3F))
      bytes.push(0x80 | ((code >> 6) & 0x3F))
      bytes.push(0x80 | (code & 0x3F))
    }
  }
  bytes
}
