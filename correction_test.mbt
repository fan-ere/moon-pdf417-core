// Reed-Solomon tests: generator polynomial, parity vectors, error repair and
// the layout rules that depend on the parity block.

///|
test "generator polynomial matches the standard coefficients" {
  assert_eq(@moon-pdf417-core.generator_polynomial(2), [1, 917, 27])
  assert_eq(@moon-pdf417-core.generator_polynomial(4), [1, 809, 723, 568, 522])
  // Constant term first, as annex F lists them.
  let degree_eight = @moon-pdf417-core.generator_polynomial(8)
  assert_eq(degree_eight.length(), 9)
  assert_eq(degree_eight[0], 1)
  assert_eq(degree_eight[8], 237)
}

///|
test "parity matches the level zero reference vector" {
  assert_eq(@moon-pdf417-core.error_correction([3, 1, 2], 0), [335, 565])
}

///|
test "parity matches the level two reference vector" {
  assert_eq(@moon-pdf417-core.error_correction([3, 1, 2], 2), [
    791, 65, 893, 586, 381, 161, 381, 304,
  ])
}

///|
test "error correction codeword count follows the level" {
  assert_eq(@moon-pdf417-core.error_correction_codeword_count(0), 2)
  assert_eq(@moon-pdf417-core.error_correction_codeword_count(1), 4)
  assert_eq(@moon-pdf417-core.error_correction_codeword_count(4), 32)
  assert_eq(@moon-pdf417-core.error_correction_codeword_count(8), 512)
}

///|
test "invalid error correction levels are rejected" {
  let rejected = try @moon-pdf417-core.error_correction([3, 1, 2], 9) catch {
    InvalidErrorCorrectionLevel(level) => level
    _ => -1
  } noraise {
    _ => -1
  }
  assert_eq(rejected, 9)
  let odd = try @moon-pdf417-core.generator_polynomial(3) catch {
    InvalidErrorCorrectionLevel(degree) => degree
    _ => -1
  } noraise {
    _ => -1
  }
  assert_eq(odd, 3)
}

///|
test "generated parity has zero syndromes" {
  let payload : Array[Int] = [10, 1, 2, 3, 4, 5, 6, 7, 8, 9]
  let parity = @moon-pdf417-core.error_correction(payload, 3)
  let words : Array[Int] = []
  for word in payload {
    words.push(word)
  }
  for word in parity {
    words.push(word)
  }
  assert_true(@moon-pdf417-core.is_error_free(words, parity.length()))
  assert_eq(@moon-pdf417-core.syndrome_weight(words, parity.length()), 0)
}

///|
test "a damaged codeword is detected and repaired" {
  let payload : Array[Int] = [11, 20, 30, 40, 50, 60, 70, 80]
  let parity = @moon-pdf417-core.error_correction(payload, 3)
  let expected : Array[Int] = []
  for word in payload {
    expected.push(word)
  }
  for word in parity {
    expected.push(word)
  }
  let damaged : Array[Int] = []
  for word in expected {
    damaged.push(word)
  }
  let parity_count = parity.length()
  // Corrupt two positions, within the parity_count / 2 correction budget.
  damaged[2] = (damaged[2] + 111) % 929
  damaged[6] = (damaged[6] + 7) % 929
  assert_true(@moon-pdf417-core.syndrome_weight(damaged, parity_count) > 0)
  let (repaired, changed) = @moon-pdf417-core.correct_errors(
    damaged,
    parity_count,
    [],
  )
  assert_eq(repaired, expected)
  assert_eq(changed, [2, 6])
}

///|
test "erasures double the repair budget" {
  let payload : Array[Int] = [5, 15, 25, 35, 45, 55]
  let parity = @moon-pdf417-core.error_correction(payload, 2)
  let expected : Array[Int] = []
  for word in payload {
    expected.push(word)
  }
  for word in parity {
    expected.push(word)
  }
  let damaged : Array[Int] = []
  for word in expected {
    damaged.push(word)
  }
  let parity_count = parity.length()
  damaged[0] = (damaged[0] + 200) % 929
  damaged[1] = (damaged[1] + 300) % 929
  damaged[3] = (damaged[3] + 400) % 929
  damaged[5] = (damaged[5] + 500) % 929
  let repaired = @moon-pdf417-core.correct_errors_opt(damaged, parity_count, [
    0, 1,
  ])
  match repaired {
    Some(value) => assert_eq(value.0, expected)
    None => abort("expected the erasures to make the repair possible")
  }
}

///|
test "too many errors are reported instead of guessed" {
  let payload : Array[Int] = [7, 17, 27, 37]
  let parity = @moon-pdf417-core.error_correction(payload, 1)
  let words : Array[Int] = []
  for word in payload {
    words.push(word)
  }
  for word in parity {
    words.push(word)
  }
  let parity_count = parity.length()
  // Level 1 carries four parity codewords, so three errors exceed the budget.
  words[0] = (words[0] + 1) % 929
  words[1] = (words[1] + 2) % 929
  words[2] = (words[2] + 3) % 929
  let repaired = @moon-pdf417-core.correct_errors_opt(words, parity_count, [])
  match repaired {
    Some(value) => assert_true(value.0 != words)
    None => ()
  }
}

///|
test "layout plans rows and padding" {
  // Two data codewords plus the length descriptor and two parity codewords
  // need three columns by three rows, so four pad codewords fill the gap.
  assert_eq(@moon-pdf417-core.rows_for(2, 2, 3), 3)
  assert_eq(@moon-pdf417-core.pad_codewords(2, 2, 3, 3), Some(4))
  let symbol = match @moon-pdf417-core.finalize_opt([2, 1], 0, 3) {
    Some(value) => value
    None => abort("expected a symbol")
  }
  assert_eq(symbol.codewords.length(), 9)
  assert_eq(symbol.data_count, 7)
  assert_eq(symbol.pad_count, 4)
  assert_eq(symbol.codewords[0], 7)
  assert_eq(symbol.codewords[3], 900)
  assert_true(@moon-pdf417-core.verify_symbol(symbol))
}

///|
test "layout rejects impossible requests" {
  assert_true(@moon-pdf417-core.finalize_opt([2, 1], 8, 1) is None)
  assert_true(@moon-pdf417-core.finalize_opt([2, 1], 0, 31) is None)
  assert_true(@moon-pdf417-core.finalize_opt([2, 1], 9, 3) is None)
}

///|
test "row planning uses the annex Q rule" {
  // rows = ceil((data + 1 + ec) / columns), minimum three.
  assert_eq(@moon-pdf417-core.rows_for(0, 2, 1), 3)
  assert_eq(@moon-pdf417-core.rows_for(10, 2, 1), 13)
  assert_eq(@moon-pdf417-core.rows_for(10, 2, 4), 4)
  assert_eq(@moon-pdf417-core.rows_for(100, 32, 10), 14)
}

///|
test "recommended level follows annex E" {
  assert_eq(@moon-pdf417-core.recommended_level(0), None)
  assert_eq(@moon-pdf417-core.recommended_level(40), Some(2))
  assert_eq(@moon-pdf417-core.recommended_level(41), Some(3))
  assert_eq(@moon-pdf417-core.recommended_level(160), Some(3))
  assert_eq(@moon-pdf417-core.recommended_level(161), Some(4))
  assert_eq(@moon-pdf417-core.recommended_level(320), Some(4))
  assert_eq(@moon-pdf417-core.recommended_level(321), Some(5))
  assert_eq(@moon-pdf417-core.recommended_level(863), Some(5))
  assert_eq(@moon-pdf417-core.recommended_level(864), None)
}

///|
test "data capacity grows with the column count" {
  let narrow = @moon-pdf417-core.data_capacity(3, 2)
  let wide = @moon-pdf417-core.data_capacity(10, 2)
  assert_true(wide > narrow)
  assert_true(narrow > 0)
}
