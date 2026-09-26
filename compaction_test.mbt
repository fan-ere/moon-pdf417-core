// Compaction tests for Byte and Numeric modes.

///|
test "numeric keeps the leading zero marker" {
  assert_eq(@moon-pdf417-core.encode_numeric_opt([48]), Some([10]))
  assert_eq(
    @moon-pdf417-core.encode_numeric_opt([49, 50, 51, 52]),
    Some([12, 434]),
  )
}

///|
test "numeric rejects non digits and empty input" {
  assert_eq(@moon-pdf417-core.encode_numeric_opt([49, 50, 65]), None)
  assert_eq(@moon-pdf417-core.encode_numeric_opt([]), None)
}

///|
test "numeric and decimal conversions round trip" {
  // Chunks are given as digit values (0..9), the form the codec works in.
  let chunks : Array[Array[Int]] = [
    [0],
    [9, 9],
    [1, 2, 3, 4, 5, 6, 7, 8, 9],
    [
      1, 2, 3, 4, 5, 6, 7, 8, 9, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9,
      0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 0, 1, 2, 3, 4,
    ],
  ]
  for chunk in chunks {
    let base = @moon-pdf417-core.decimal_chunk_to_base900(chunk)
    let decimal = @moon-pdf417-core.base900_to_decimal(base)
    // `decimal` carries the leading 1 prefix the encoder adds, so drop it.
    let trimmed : Array[Int] = []
    let mut index = 0
    let mut skipped = false
    while index < decimal.length() {
      if !skipped && decimal[index] == 1 {
        skipped = true
      } else {
        trimmed.push(decimal[index])
      }
      index += 1
    }
    assert_eq(trimmed, chunk)
  }
}

///|
test "numeric encoding round trips through the segment decoder" {
  let codes : Array[Int] = [48, 49, 50, 51, 52, 53, 54, 55, 56, 57]
  let words = @moon-pdf417-core.encode_numeric(codes)
  assert_eq(@moon-pdf417-core.decode_numeric(words), codes)
}

///|
test "numeric codeword count follows the chunk encoder" {
  let single = @moon-pdf417-core.encode_numeric_opt([53])
  assert_eq(single.map(words => words.length()), Some(1))
  let twelve : Array[Int] = [49, 50, 51, 52, 53, 54, 55, 56, 57, 48, 49, 50]
  let many = @moon-pdf417-core.encode_numeric_opt(twelve)
  assert_eq(many.map(words => words.length()), Some(5))
}

///|
test "byte groups follow the base 900 conversion" {
  assert_eq(
    @moon-pdf417-core.bytes_to_base900([1, 2, 3, 4, 5, 6]),
    [1, 620, 89, 74, 846],
  )
  assert_eq(
    @moon-pdf417-core.base900_to_bytes([1, 620, 89, 74, 846]),
    [1, 2, 3, 4, 5, 6],
  )
}

///|
test "byte compaction emits groups then a literal tail" {
  assert_eq(
    @moon-pdf417-core.encode_byte([1, 2, 3, 4, 5, 6]),
    [1, 620, 89, 74, 846],
  )
  assert_eq(@moon-pdf417-core.encode_byte([1, 2, 3]), [1, 2, 3])
  assert_eq(
    @moon-pdf417-core.encode_byte([1, 2, 3, 4, 5, 6, 255]),
    [1, 620, 89, 74, 846, 255],
  )
}

///|
test "byte decoding inverts compaction" {
  let samples : Array[Array[Int]] = [
    [0],
    [255],
    [0, 1, 2, 3, 4, 5],
    [1, 2, 3, 4, 5, 6, 255],
    [200, 128, 64, 32, 16, 8, 4, 2, 1],
    [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
  ]
  for sample in samples {
    let words = @moon-pdf417-core.encode_byte(sample)
    assert_eq(@moon-pdf417-core.decode_byte(words), sample)
  }
}

///|
test "latch selection distinguishes 901 from 924" {
  assert_true(@moon-pdf417-core.is_byte_group_multiple(6))
  assert_true(@moon-pdf417-core.is_byte_group_multiple(12))
  assert_false(@moon-pdf417-core.is_byte_group_multiple(7))
  assert_false(@moon-pdf417-core.is_byte_group_multiple(0))
}

///|
test "byte count uses two codewords from 900 bytes" {
  assert_eq(@moon-pdf417-core.byte_count_codewords(1), 1)
  assert_eq(@moon-pdf417-core.byte_count_codewords(899), 1)
  assert_eq(@moon-pdf417-core.byte_count_codewords(900), 2)
  assert_eq(@moon-pdf417-core.byte_count_codewords(0), 0)
}

///|
test "byte capacity matches the emitted codeword count" {
  assert_eq(@moon-pdf417-core.byte_capacity(1), 1)
  assert_eq(@moon-pdf417-core.byte_capacity(5), 5)
  assert_eq(@moon-pdf417-core.byte_capacity(6), 5)
  assert_eq(@moon-pdf417-core.byte_capacity(7), 6)
  assert_eq(@moon-pdf417-core.byte_capacity(12), 10)
}

///|
test "byte values outside 0..255 are rejected" {
  let rejected = try @moon-pdf417-core.encode_byte([256]) catch {
    UnrepresentableChar(value) => value
    _ => -1
  } noraise {
    _ => -1
  }
  assert_eq(rejected, 256)
}
