// Byte Compaction (ISO/IEC 15438 4.4.3).
//
// Bytes are processed in groups of six.  Each group is read as a big endian
// 48 bit integer and written back as five base 900 codewords; any remaining
// one to five bytes are emitted literally.

///|
/// Number of bytes compressed into five codewords per group.
pub let byte_group_size : Int = 6

///|
/// Number of codewords a full byte group produces.
pub let byte_group_codewords : Int = 5

///|
/// `true` if `count` bytes form complete six byte groups, which is the
/// condition for the 924 latch instead of the 901 latch.
pub fn is_byte_group_multiple(count : Int) -> Bool {
  count > 0 && count % byte_group_size == 0
}

///|
/// Number of base 900 codewords needed to describe a byte run of `count`
/// bytes, including the length count that 901 mode carries.
pub fn byte_capacity(count : Int) -> Int {
  if count <= 0 {
    return 0
  }
  let groups = count / byte_group_size
  let rest = count % byte_group_size
  groups * byte_group_codewords + rest
}

///|
/// Number of codewords needed for an explicit byte length count: one
/// codeword while the count is below 900, otherwise two.
pub fn byte_count_codewords(count : Int) -> Int {
  if count <= 0 {
    0
  } else if count < 900 {
    1
  } else {
    2
  }
}

///|
/// Convert six bytes to five base 900 codewords.
pub fn bytes_to_base900(bytes : Array[Int]) -> Array[Int] raise EncodeError {
  if bytes.length() != byte_group_size {
    raise UnrepresentableChar(bytes.length())
  }
  let mut value : Int64 = 0L
  for byte in bytes {
    if byte < 0 || byte > max_byte_value {
      raise UnrepresentableChar(byte)
    }
    value = value * 256L + byte.to_int64()
  }
  let group : Array[Int] = [0, 0, 0, 0, 0]
  let mut position = byte_group_codewords
  while position > 0 {
    position -= 1
    group[position] = (value % 900L).to_int()
    value = value / 900L
  }
  group
}

///|
/// Convert five base 900 codewords back to six bytes.
pub fn base900_to_bytes(words : Array[Int]) -> Array[Int] raise EncodeError {
  if words.length() != byte_group_codewords {
    raise UnrepresentableChar(words.length())
  }
  let mut value : Int64 = 0L
  for word in words {
    if word < 0 || word > 899 {
      raise UnrepresentableChar(word)
    }
    value = value * 900L + word.to_int64()
  }
  let bytes : Array[Int] = [0, 0, 0, 0, 0, 0]
  let mut position = byte_group_size
  while position > 0 {
    position -= 1
    bytes[position] = (value % 256L).to_int()
    value = value / 256L
  }
  bytes
}

///|
/// Encode a byte run with Byte Compaction.  Neither the 901/924 latch nor the
/// length count is included; `encode_high_level` adds those.
pub fn encode_byte(input : Array[Int]) -> Array[Int] raise EncodeError {
  encode_byte_segment(input, 0, input.length())
}

///|
/// Encode `input[start..start+count)` as six byte groups plus a literal tail.
pub fn encode_byte_segment(
  input : Array[Int],
  start : Int,
  count : Int,
) -> Array[Int] raise EncodeError {
  if count <= 0 {
    raise EmptyInput
  }
  let result : Array[Int] = []
  let mut index = 0
  while index + byte_group_size <= count {
    let group : Array[Int] = []
    let mut offset = 0
    while offset < byte_group_size {
      group.push(input[start + index + offset])
      offset += 1
    }
    for word in bytes_to_base900(group) {
      result.push(word)
    }
    index += byte_group_size
  }
  while index < count {
    let byte = input[start + index]
    if byte < 0 || byte > max_byte_value {
      raise UnrepresentableChar(byte)
    }
    result.push(byte)
    index += 1
  }
  result
}

///|
/// Decode Byte Compaction codewords (without latch and length count) back to
/// bytes.  Trailing incomplete groups are returned literally.
pub fn decode_byte(words : Array[Int]) -> Array[Int] raise EncodeError {
  if words.is_empty() {
    raise EmptyInput
  }
  let bytes : Array[Int] = []
  let mut index = 0
  while index + byte_group_codewords <= words.length() {
    let group : Array[Int] = []
    let mut offset = 0
    while offset < byte_group_codewords {
      group.push(words[index + offset])
      offset += 1
    }
    for byte in base900_to_bytes(group) {
      bytes.push(byte)
    }
    index += byte_group_codewords
  }
  while index < words.length() {
    bytes.push(words[index])
    index += 1
  }
  bytes
}
