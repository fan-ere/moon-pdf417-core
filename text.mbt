// Text Compaction (ISO/IEC 15438 4.4.2).
//
// Characters are mapped to values 0..29 in one of four sub-modes, and two
// consecutive values are packed into a single codeword as
// `first * 30 + second`.  A trailing odd value is padded with 29, the
// punctuation shift code that the standard designates as the text pad.

///|
/// `true` if `code` is a capital letter or a space, i.e. the Alpha sub-mode.
pub fn is_alpha_upper(code : Int) -> Bool {
  code == 32 || (code >= 65 && code <= 90)
}

///|
/// `true` if `code` is a lower case letter or a space, i.e. the Lower
/// sub-mode.
pub fn is_alpha_lower(code : Int) -> Bool {
  code == 32 || (code >= 97 && code <= 122)
}

///|
/// `true` if the Mixed sub-mode can represent `code`.
pub fn is_mixed(code : Int) -> Bool {
  code >= 0 && code < 256 && mixed_value[code] >= 0
}

///|
/// `true` if the Punctuation sub-mode can represent `code`.
pub fn is_punctuation(code : Int) -> Bool {
  code >= 0 && code < 256 && punctuation_value[code] >= 0
}

///|
/// `true` if Text Compaction can represent `code` at all.
pub fn is_text_code(code : Int) -> Bool {
  is_alpha_upper(code) ||
  is_alpha_lower(code) ||
  is_mixed(code) ||
  is_punctuation(code)
}

///|
/// `true` if every code unit of `input` is text encodable.
pub fn is_text_input(input : Array[Int]) -> Bool {
  for code in input {
    if !is_text_code(code) {
      return false
    }
  }
  true
}

///|
/// `true` if `code` is an ASCII decimal digit.
pub fn is_digit(code : Int) -> Bool {
  code >= 48 && code <= 57
}

///|
/// `true` if every code unit of `input` is a decimal digit.
pub fn is_numeric_input(input : Array[Int]) -> Bool {
  for code in input {
    if !is_digit(code) {
      return false
    }
  }
  true
}

///|
/// Pack a run of Text Compaction values into codewords.  Returns `None` when
/// the run is empty: PDF417 has no representation for an empty text segment.
fn pack_text_values(values : Array[Int]) -> Array[Int]? {
  if values.is_empty() {
    return None
  }
  let result : Array[Int] = []
  let mut index = 0
  while index < values.length() {
    let first = values[index]
    let second = if index + 1 < values.length() {
      values[index + 1]
    } else {
      tc_text_pad
    }
    result.push(first * 30 + second)
    index += 2
  }
  Some(result)
}

///|
/// Run the Text Compaction sub-mode automaton over `input[start..start+count)`
/// starting in `initial`, and return the resulting values together with the
/// sub-mode the encoder ends in.
pub fn text_automaton(
  input : Array[Int],
  start : Int,
  count : Int,
  initial : TextSubmode,
) -> (Array[Int], TextSubmode) raise EncodeError {
  let values : Array[Int] = []
  let mut submode = initial
  let mut index = 0
  while index < count {
    let code = input[start + index]
    match submode {
      Alpha =>
        if is_alpha_upper(code) {
          values.push(if code == 32 { 26 } else { code - 65 })
          index += 1
        } else if is_alpha_lower(code) {
          // 27 shifts to Lower for the *same* character, so the value of the
          // current character is emitted here, not on the next iteration.
          submode = Lower
          values.push(tc_alpha_to_lower)
          values.push(if code == 32 { 26 } else { code - 97 })
          index += 1
        } else if is_mixed(code) {
          submode = Mixed
          values.push(tc_alpha_to_mixed)
        } else if is_punctuation(code) {
          values.push(tc_alpha_to_punct)
          values.push(punctuation_value[code])
          index += 1
        } else {
          raise UnrepresentableChar(code)
        }
      Lower =>
        if is_alpha_lower(code) {
          // In Lower sub-mode 27 shifts to Alpha instead of emitting 26, so a
          // space is encoded arithmetically here.
          values.push(if code == 32 { 26 } else { code - 97 })
          index += 1
        } else if is_mixed(code) {
          submode = Mixed
          values.push(tc_lower_to_mixed)
        } else if is_punctuation(code) {
          values.push(tc_lower_to_punct)
          values.push(punctuation_value[code])
          index += 1
        } else if is_alpha_upper(code) {
          // In Lower sub-mode 27 is the shift to Alpha, so lowercase "a".."z"
          // and the space are already covered above; only a genuine shift
          // lands here.
          submode = Alpha
          values.push(tc_lower_to_alpha)
        } else {
          raise UnrepresentableChar(code)
        }
      Mixed =>
        if is_mixed(code) {
          values.push(mixed_value[code])
          index += 1
        } else if is_alpha_upper(code) {
          submode = Alpha
          values.push(tc_mixed_to_alpha)
        } else if is_alpha_lower(code) {
          submode = Lower
          values.push(tc_mixed_to_lower)
        } else if is_punctuation(code) {
          if index + 1 < count && is_punctuation(input[start + index + 1]) {
            submode = Punctuation
            values.push(tc_mixed_to_punct_latch)
          } else {
            values.push(tc_mixed_to_punct_shift)
            values.push(punctuation_value[code])
            index += 1
          }
        } else {
          raise UnrepresentableChar(code)
        }
      Punctuation =>
        if is_punctuation(code) {
          values.push(punctuation_value[code])
          index += 1
        } else {
          submode = Alpha
          values.push(tc_punct_to_alpha)
        }
    }
  }
  (values, submode)
}

///|
/// Encode `input[start..start+count)` in Text Compaction and report both the
/// codewords and the sub-mode the encoder finished in.
pub fn encode_text_segment(
  input : Array[Int],
  start : Int,
  count : Int,
  initial : TextSubmode,
) -> (Array[Int], TextSubmode) raise EncodeError {
  if count <= 0 {
    raise EmptyInput
  }
  let (values, submode) = text_automaton(input, start, count, initial)
  match pack_text_values(values) {
    Some(words) => (words, submode)
    None => raise EmptyInput
  }
}

///|
/// Encode a whole input in Text Compaction, starting in the Alpha sub-mode.
///
/// Every code unit must be representable by one of the four sub-modes;
/// otherwise `UnrepresentableChar` is raised.
pub fn encode_text(input : Array[Int]) -> Array[Int] raise EncodeError {
  encode_text_from(input, Alpha)
}

///|
/// Like `encode_text`, but lets the caller choose the sub-mode the encoder
/// starts in.  Useful when several text segments are concatenated after a
/// single mode latch.
pub fn encode_text_from(
  input : Array[Int],
  initial : TextSubmode,
) -> Array[Int] raise EncodeError {
  if input.is_empty() {
    raise EmptyInput
  }
  let (words, _) = encode_text_segment(input, 0, input.length(), initial)
  words
}

///|
/// Encode text with no error handling: returns `None` instead of raising.
pub fn encode_text_opt(input : Array[Int]) -> Array[Int]? {
  try encode_text(input) catch {
    _ => None
  } noraise {
    words => Some(words)
  }
}
