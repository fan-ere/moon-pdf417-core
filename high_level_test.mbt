// High level encoding tests: the automatic mode selector and its boundaries.

///|
fn high_test_codes(text : String) -> Array[Int] {
  let result : Array[Int] = []
  for character in text.iter() {
    result.push(character.to_int())
  }
  result
}

///|
fn high(text : String) -> @moon-pdf417-core.HighLevel raise {
  try @moon-pdf417-core.encode_high_level(high_test_codes(text)) catch {
    error => fail("unexpected failure: " + repr(error))
  } noraise {
    level => level
  }
}

///|
fn high_words(text : String) -> Array[Int] raise {
  high(text).codewords
}

///|
test "short text input stays in text mode" {
  // B, C, D always fit text mode, so no latch codeword is emitted.
  assert_eq(high_words("ABCD"), [1, 63])
  assert_eq(high("ABCD").modes.length(), 1)
}

///|
test "thirteen or more digits latch into numeric mode" {
  let words = high_words("1234567890123")
  assert_eq(words[0], 902)
  assert_eq(words.length(), 6)
  let many = high_words("1234567890")
  // Ten digits are not worth a numeric latch, so they stay textual.
  assert_true(many[0] != 902)
}

///|
test "a single non-text byte uses the 913 shift" {
  // The shift is chosen only when the byte forms a binary run of exactly one
  // character, which here happens because a 13 digit run follows and cuts the
  // binary run short.
  let input : Array[Int] = [
    65, 66, 67, 68, 69, 70, 71, 72, 73, 74, 200, 49, 50, 51, 52, 53, 54, 55, 56,
    57, 48, 49, 50, 51, 88, 89, 90,
  ]
  let result = @moon-pdf417-core.encode_high_level(input)
  let mut shifts = 0
  for word in result.codewords {
    if word == 913 {
      shifts += 1
    }
  }
  assert_eq(shifts, 1)
}

///|
test "a longer non-text run uses the 901 latch" {
  let input : Array[Int] = [200, 201, 202, 203, 204, 205, 206]
  let result = @moon-pdf417-core.encode_high_level(input)
  assert_eq(result.codewords[0], 901)
  assert_eq(result.codewords[1], 7)
}

///|
test "a six byte multiple uses the 924 latch" {
  let input : Array[Int] = [1, 2, 3, 4, 5, 6]
  let result = @moon-pdf417-core.encode_high_level(input)
  assert_eq(result.codewords[0], 924)
  assert_eq(result.codewords.length(), 6)
}

///|
test "mode counters follow annex P" {
  let digits = high_test_codes("123456789012345")
  assert_eq(@moon-pdf417-core.consecutive_digits(digits, 0), 15)
  assert_eq(@moon-pdf417-core.consecutive_digits(digits, 14), 1)
  let text = high_test_codes("ABCDEFGH")
  assert_eq(@moon-pdf417-core.consecutive_text(text, 0), 8)
  // A run of 13 digits cuts the text run before the digits start.
  let mixed = high_test_codes("ABC1234567890123XYZ")
  assert_eq(@moon-pdf417-core.consecutive_text(mixed, 0), 3)
  assert_eq(@moon-pdf417-core.consecutive_binary(mixed, 0), 3)
}

///|
test "non text bytes cut the text run" {
  let input : Array[Int] = [65, 66, 67, 200, 68, 69, 70, 71]
  assert_eq(@moon-pdf417-core.consecutive_text(input, 0), 3)
  assert_eq(@moon-pdf417-core.consecutive_binary(input, 0), 8)
}

///|
test "high level encoding rejects empty and out of range input" {
  assert_true(@moon-pdf417-core.encode_high_level_opt([]) is None)
  assert_true(@moon-pdf417-core.encode_high_level_opt([300]) is None)
  assert_true(@moon-pdf417-core.encode_high_level_opt([65]) is Some(_))
}

///|
test "high level encoding round trips" {
  let samples : Array[String] = [
    "HELLO WORLD", "Hello World 1234", "1234567890", "1234567890123", "ABC1234567890123DEF",
    "PDF417 TEST", "a", "A", "MixedCase And Punctuation!",
  ]
  for sample in samples {
    let codes = high_test_codes(sample)
    let words = high(sample).codewords
    assert_true(
      @moon-pdf417-core.round_trip_matches(codes, words),
      msg="round trip failed for " + sample,
    )
  }
}

///|
test "explicit compaction entry points emit their latches" {
  assert_eq(@moon-pdf417-core.encode_numeric_only(high_test_codes("1234")), [
    902, 12, 434,
  ])
  assert_eq(@moon-pdf417-core.encode_bytes_only([1, 2, 3]), [901, 3, 1, 2, 3])
  assert_eq(@moon-pdf417-core.encode_bytes_only([1, 2, 3, 4, 5, 6]), [
    924, 1, 620, 89, 74, 846,
  ])
  assert_eq(@moon-pdf417-core.encode_text_only(high_test_codes("AB")), [1])
}
