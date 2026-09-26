// Numeric Compaction (ISO/IEC 15438 4.4.4).
//
// The numeric string is split into chunks of at most 44 digits.  Each chunk
// is prefixed with a literal "1" and then converted to base 900 by repeated
// division; that prefix is what removes the ambiguity caused by leading
// zeros, so "0001234" and "1234" get different codeword sequences.
//
// The conversion uses plain decimal long division, so no big integer library
// is needed.

///|
/// Number of decimal digits converted per numeric codeword block.
pub let numeric_chunk_size : Int = 44

///|
/// Divide a base 10 digit array by 900, returning the quotient digits and the
/// remainder.  Input and output are normal order (most significant first).
fn divide_by_900(digits : Array[Int]) -> (Array[Int], Int) {
  let quotient : Array[Int] = []
  let mut remainder = 0
  for digit in digits {
    let value = remainder * 10 + digit
    let next = value / 900
    remainder = value % 900
    if !quotient.is_empty() || next != 0 {
      quotient.push(next)
    }
  }
  (quotient, remainder)
}

///|
/// Convert one digit chunk to base 900 digits: the chunk gets a leading "1"
/// and is then repeatedly divided by 900.
pub fn decimal_chunk_to_base900(digits : Array[Int]) -> Array[Int] {
  let mut decimal : Array[Int] = [1]
  for digit in digits {
    decimal.push(digit)
  }
  let reverse : Array[Int] = []
  while !decimal.is_empty() {
    let (quotient, remainder) = divide_by_900(decimal)
    reverse.push(remainder)
    decimal = quotient
  }
  let result : Array[Int] = []
  let mut index = reverse.length()
  while index > 0 {
    index -= 1
    result.push(reverse[index])
  }
  result
}

///|
/// Convert base 900 digits back to decimal digits.  `base900` is most
/// significant first; the result has no leading zeros except for the value 0.
pub fn base900_to_decimal(base900 : Array[Int]) -> Array[Int] {
  let mut decimal : Array[Int] = [0]
  for word in base900 {
    // decimal = decimal * 900 + word, computed least significant first.
    let next : Array[Int] = []
    let mut add = word
    let mut index = decimal.length()
    while index > 0 {
      index -= 1
      let value = decimal[index] * 900 + add
      next.push(value % 10)
      add = value / 10
    }
    while add > 0 {
      next.push(add % 10)
      add = add / 10
    }
    let ordered : Array[Int] = []
    let mut position = next.length()
    while position > 0 {
      position -= 1
      ordered.push(next[position])
    }
    decimal = ordered
  }
  let trimmed : Array[Int] = []
  let mut started = false
  for digit in decimal {
    if digit != 0 || started {
      started = true
      trimmed.push(digit)
    }
  }
  if trimmed.is_empty() {
    trimmed.push(0)
  }
  trimmed
}

///|
/// Encode decimal digits with Numeric Compaction.  The latch codeword is not
/// included; `encode_high_level` adds it.
///
/// `input` must be non-empty and contain only ASCII digits.
pub fn encode_numeric(input : Array[Int]) -> Array[Int] raise EncodeError {
  encode_numeric_segment(input, 0, input.length())
}

///|
/// Encode `input[start..start+count)` with Numeric Compaction.
pub fn encode_numeric_segment(
  input : Array[Int],
  start : Int,
  count : Int,
) -> Array[Int] raise EncodeError {
  if count <= 0 {
    raise EmptyInput
  }
  let digits : Array[Int] = []
  let mut index = 0
  while index < count {
    let code = input[start + index]
    if !is_digit(code) {
      raise UnrepresentableChar(code)
    }
    digits.push(code - 48)
    index += 1
  }
  let result : Array[Int] = []
  let mut offset = 0
  while offset < digits.length() {
    let end = if offset + numeric_chunk_size < digits.length() {
      offset + numeric_chunk_size
    } else {
      digits.length()
    }
    let chunk : Array[Int] = []
    while offset < end {
      chunk.push(digits[offset])
      offset += 1
    }
    for word in decimal_chunk_to_base900(chunk) {
      result.push(word)
    }
  }
  result
}

///|
/// Decode Numeric Compaction codewords back to decimal digits.
///
/// The caller passes exactly the codewords that belong to the numeric
/// segment, without the latch codeword.
pub fn decode_numeric(words : Array[Int]) -> Array[Int] raise EncodeError {
  if words.is_empty() {
    raise EmptyInput
  }
  let digits : Array[Int] = []
  let mut offset = 0
  while offset < words.length() {
    let end = if offset + numeric_chunk_size < words.length() {
      offset + numeric_chunk_size
    } else {
      words.length()
    }
    let chunk : Array[Int] = []
    while offset < end {
      chunk.push(words[offset])
      offset += 1
    }
    let decimal = base900_to_decimal(chunk)
    // The leading "1" prefix is not part of the original digits.
    let mut index = 0
    let mut skipped = false
    while index < decimal.length() {
      if !skipped && decimal[index] == 1 {
        skipped = true
      } else {
        digits.push(decimal[index] + 48)
      }
      index += 1
    }
    if !skipped {
      raise UnrepresentableChar(-1)
    }
  }
  digits
}

///|
/// Numeric encoding without error handling: returns `None` on failure.
pub fn encode_numeric_opt(input : Array[Int]) -> Array[Int]? {
  try encode_numeric(input) catch {
    _ => None
  } noraise {
    words => Some(words)
  }
}
