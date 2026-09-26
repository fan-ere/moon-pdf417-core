// Text Compaction tests: known vectors, sub-mode transitions and round trips.

///|
/// Convert an ASCII string literal into code units so the tests read as text.
fn ascii_codes(text : String) -> Array[Int] {
  let result : Array[Int] = []
  for character in text.iter() {
    result.push(character.to_int())
  }
  result
}

///|
/// Run the Text Compaction encoder, failing the test on error.
fn expect_words(text : String) -> Array[Int] raise {
  try @moon-pdf417-core.encode_text(ascii_codes(text)) catch {
    error => fail("unexpected failure: " + repr(error))
  } noraise {
    words => words
  }
}

///|
fn expect_decode(words : Array[Int]) -> Array[Int] raise {
  try @moon-pdf417-core.decode_text(words) catch {
    error => fail("unexpected decode failure: " + repr(error))
  } noraise {
    text => text
  }
}

///|
test "alpha pairs pack into one codeword" {
  assert_eq(expect_words("AB"), [1])
  assert_eq(expect_words("ABCD"), [1, 63])
  // H=7, E=4, L=11, L=11, O=14 -> 7*30+4, 11*30+11, 14*30+29.
  assert_eq(expect_words("HELLO"), [214, 341, 449])
}

///|
test "a trailing odd value is padded with 29" {
  assert_eq(expect_words("A"), [29])
  assert_eq(expect_words("ABC"), [1, 89])
}

///|
test "space is 26 in alpha and lower sub-modes" {
  assert_eq(expect_words("  "), [806])
}

///|
test "one lower case letter shifts and stays in lower mode" {
  // 27 shifts to Lower and carries the letter in the same step, so values are
  // [27, 0] and the trailing 0 is padded to 32.
  assert_eq(expect_words("a"), [810])
}

///|
test "lower case letters after alpha pack through the shift" {
  // "A" -> 0, shift -> 27, "b" -> 1, "b" -> 1, so values are 0, 27, 1, 1.
  assert_eq(expect_words("Abb"), [27, 31])
}

///|
test "mixed sub-mode characters are reachable" {
  // "1" and "2" are Mixed values 1 and 2, reached with 28.
  assert_eq(expect_words("12"), [841, 89])
}

///|
test "punctuation uses a shift when isolated" {
  // "!" is Punctuation value 10, reached with 29.
  assert_eq(expect_words("!"), [880])
  assert_eq(expect_words("A!"), [29, 329])
}

///|
test "two punctuation characters use the punctuation latch" {
  // Both characters are outside Mixed, so the encoder shifts with 29 and
  // carries the Punctuation values 6 for "]" and 7 for "_".
  assert_eq(expect_words("]_"), [876, 877])
}

///|
test "text encodable code units follow annex P" {
  assert_true(@moon-pdf417-core.is_text_code(9))
  assert_true(@moon-pdf417-core.is_text_code(13))
  assert_true(@moon-pdf417-core.is_text_code(42))
  assert_false(@moon-pdf417-core.is_text_code(0))
  assert_false(@moon-pdf417-core.is_text_code(200))
  assert_false(@moon-pdf417-core.is_text_code(8364))
}

///|
test "unsupported characters are reported" {
  try @moon-pdf417-core.encode_text([200]) catch {
    UnrepresentableChar(code) => assert_eq(code, 200)
    _ => fail("expected UnrepresentableChar")
  } noraise {
    _ => fail("expected UnrepresentableChar")
  }
}

///|
test "empty input is reported" {
  try @moon-pdf417-core.encode_text([]) catch {
    EmptyInput => ()
    _ => fail("expected EmptyInput")
  } noraise {
    _ => fail("expected EmptyInput")
  }
}

///|
test "text decoding inverts encoding" {
  let samples : Array[String] = [
    "A", "AB", "HELLO WORLD", "Hello World", "a", "ab", "12", "!", "]_", "Hello, World!",
    "A1B2", "PDF417 TEST", "?;",
  ]
  for sample in samples {
    let words = expect_words(sample)
    assert_eq(expect_decode(words), ascii_codes(sample))
  }
}

///|
test "segment encoding reports the ending sub-mode" {
  let encoded = try
    @moon-pdf417-core.encode_text_segment(ascii_codes("abc"), 0, 3, Alpha)
  catch {
    error => fail("unexpected failure: " + repr(error))
  } noraise {
    value => value
  }
  let (words, submode) = encoded
  assert_eq(submode.name(), "Lower")
  assert_eq(words, [810, 32])
}
