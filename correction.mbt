// Reed-Solomon error correction over GF(929).
//
// PDF417 error correction is a systematic Reed-Solomon code over the prime
// field GF(929) with generator polynomial
//
//     g(x) = (x - 3^1)(x - 3^2) ... (x - 3^degree)
//
// where `degree = 2^(level + 1)`.  The parity codewords are the remainder of
// `data(x) * x^degree` divided by `g(x)`, stored most significant first.
//
// This module implements both directions: parity generation for the encoder
// and a Berlekamp-Massey / Chien / Gaussian magnitude decoder for
// verification.  The decoder is what lets tests prove that a generated symbol
// survives a corrupted codeword.

///|
fn modulo929(value : Int) -> Int {
  let remainder = value % 929
  if remainder < 0 {
    remainder + 929
  } else {
    remainder
  }
}

///|
/// `base^exponent mod 929`.
pub fn pow_mod929(base : Int, exponent : Int) -> Int {
  let mut result = 1
  let mut factor = modulo929(base)
  let mut power = exponent
  while power > 0 {
    if power % 2 == 1 {
      result = result * factor % 929
    }
    factor = factor * factor % 929
    power = power / 2
  }
  result
}

///|
/// Multiplicative inverse modulo 929; 929 is prime, so every non-zero value
/// has an inverse.
pub fn inverse929(value : Int) -> Int {
  pow_mod929(value, 927)
}

///|
/// Generator polynomial coefficients for `degree` parity codewords, most
/// significant first.  The leading coefficient is always 1.
pub fn generator_polynomial(degree : Int) -> Array[Int] raise EncodeError {
  if degree < 2 || degree > 512 || degree % 2 != 0 {
    raise InvalidErrorCorrectionLevel(degree)
  }
  let mut polynomial : Array[Int] = [1]
  let mut root = 1
  for _ in 0..<degree {
    root = root * 3 % 929
    let next : Array[Int] = Array::make(polynomial.length() + 1, 0)
    for index in 0..<polynomial.length() {
      next[index] = modulo929(next[index] + polynomial[index])
      next[index + 1] = modulo929(next[index + 1] - polynomial[index] * root)
    }
    polynomial = next
  }
  polynomial
}

///|
/// Compute the parity codewords for `data` at the given error correction
/// level.
///
/// `data` is the full data codeword sequence, including the symbol length
/// descriptor.  The result holds `2^(level + 1)` codewords in storage order.
pub fn error_correction(
  data : Array[Int],
  level : Int,
) -> Array[Int] raise EncodeError {
  if level < 0 || level > max_error_correction_level {
    raise InvalidErrorCorrectionLevel(level)
  }
  for word in data {
    if word < 0 || word > max_codewords {
      raise UnrepresentableChar(word)
    }
  }
  let degree = error_correction_codeword_count(level)
  if data.length() + degree > max_codewords {
    raise TooManyCodewords(data.length() + degree)
  }
  let polynomial = generator_polynomial(degree)
  let working : Array[Int] = []
  for word in data {
    working.push(word)
  }
  for _ in 0..<degree {
    working.push(0)
  }
  for index in 0..<data.length() {
    let leading = working[index]
    if leading != 0 {
      for offset in 0..<(degree + 1) {
        working[index + offset] = modulo929(
          working[index + offset] - leading * polynomial[offset],
        )
      }
    }
  }
  let parity : Array[Int] = []
  for index in data.length()..<working.length() {
    parity.push(modulo929(-working[index]))
  }
  parity
}

///|
/// Reed-Solomon syndromes of a complete codeword sequence.
///
/// `S[j]` is `c(3^(j+1))`.  A sequence without errors yields all-zero
/// syndromes.
pub fn syndromes(words : Array[Int], parity_count : Int) -> Array[Int] {
  let result : Array[Int] = []
  for index in 0..<parity_count {
    let root = pow_mod929(3, index + 1)
    let mut value = 0
    for word in words {
      value = modulo929(value * root + word)
    }
    result.push(value)
  }
  result
}

///|
/// `true` if every syndrome of `words` is zero.
pub fn is_error_free(words : Array[Int], parity_count : Int) -> Bool {
  for syndrome in syndromes(words, parity_count) {
    if syndrome != 0 {
      return false
    }
  }
  true
}

///|
/// Number of non-zero syndromes: a cheap measure of how damaged a sequence is.
pub fn syndrome_weight(words : Array[Int], parity_count : Int) -> Int {
  let mut weight = 0
  for syndrome in syndromes(words, parity_count) {
    if syndrome != 0 {
      weight += 1
    }
  }
  weight
}

///|
/// Field element attached to codeword `position` of a sequence of `length`
/// codewords: `X = 3^(length - 1 - position)`.
pub fn error_locator_of(position : Int, length : Int) -> Int {
  pow_mod929(3, length - 1 - position)
}

///|
/// Solve `matrix * solution = rhs` over GF(929).  Returns `None` for a
/// singular system.
fn solve_gf929(matrix : Array[Array[Int]], rhs : Array[Int]) -> Array[Int]? {
  let size = rhs.length()
  let rows : Array[Array[Int]] = []
  for index in 0..<size {
    let row : Array[Int] = []
    for column in 0..<size {
      row.push(modulo929(matrix[index][column]))
    }
    row.push(modulo929(rhs[index]))
    rows.push(row)
  }
  for pivot in 0..<size {
    let mut selected = -1
    for row in pivot..<size {
      if rows[row][pivot] != 0 {
        selected = row
        break
      }
    }
    if selected < 0 {
      return None
    }
    let swapped = rows[pivot]
    rows[pivot] = rows[selected]
    rows[selected] = swapped
    let inverse = inverse929(rows[pivot][pivot])
    for column in pivot..<(size + 1) {
      rows[pivot][column] = modulo929(rows[pivot][column] * inverse)
    }
    for row in 0..<size {
      if row != pivot && rows[row][pivot] != 0 {
        let factor = rows[row][pivot]
        for column in pivot..<(size + 1) {
          rows[row][column] = modulo929(
            rows[row][column] - factor * rows[pivot][column],
          )
        }
      }
    }
  }
  let solution : Array[Int] = []
  for index in 0..<size {
    solution.push(rows[index][size])
  }
  Some(solution)
}

///|
/// Berlekamp-Massey: shortest linear feedback shift register generating the
/// syndrome sequence.  Coefficients are returned constant term first, with a
/// leading 1.
pub fn berlekamp_massey(sequence : Array[Int]) -> Array[Int] {
  let mut locator : Array[Int] = [1]
  let mut previous : Array[Int] = [1]
  let mut shift = 1
  let mut last_discrepancy = 1
  let mut degree = 0
  for index in 0..<sequence.length() {
    let mut discrepancy = sequence[index]
    let mut offset = 1
    while offset <= degree {
      discrepancy = modulo929(
        discrepancy + locator[offset] * sequence[index - offset],
      )
      offset += 1
    }
    if discrepancy == 0 {
      shift += 1
      continue
    }
    if 2 * degree <= index {
      let snapshot = locator
      let factor = discrepancy * inverse929(last_discrepancy) % 929
      let next : Array[Int] = Array::make(previous.length() + shift, 0)
      for position in 0..<locator.length() {
        next[position] = locator[position]
      }
      for position in 0..<previous.length() {
        next[position + shift] = modulo929(
          next[position + shift] - factor * previous[position],
        )
      }
      locator = next
      previous = snapshot
      last_discrepancy = discrepancy
      degree = index + 1 - degree
      shift = 1
    } else {
      let factor = discrepancy * inverse929(last_discrepancy) % 929
      let next : Array[Int] = Array::make(locator.length(), 0)
      for position in 0..<locator.length() {
        next[position] = locator[position]
      }
      for position in 0..<previous.length() {
        if position + shift < next.length() {
          next[position + shift] = modulo929(
            next[position + shift] - factor * previous[position],
          )
        }
      }
      locator = next
      shift += 1
    }
  }
  locator
}

///|
/// Evaluate the locator polynomial (constant term first) at `value`.
fn eval_locator(locator : Array[Int], value : Int) -> Int {
  let mut result = 0
  let mut power = 1
  for coefficient in locator {
    result = modulo929(result + coefficient * power)
    power = power * value % 929
  }
  result
}

///|
/// Chien search: positions whose field element is a root of `locator`.
fn chien_search(
  locator : Array[Int],
  length : Int,
  erasures : Array[Int],
) -> Array[Int] {
  let positions : Array[Int] = []
  for position in 0..<length {
    if eval_locator(locator, inverse929(error_locator_of(position, length))) == 0 {
      positions.push(position)
    }
  }
  for position in erasures {
    let mut present = false
    for existing in positions {
      if existing == position {
        present = true
      }
    }
    if !present {
      positions.push(position)
    }
  }
  positions
}

///|
/// Forney style magnitude recovery: solve
/// `S[j] = sum_k magnitude_k * X_k^(j+1)` for the known error positions,
/// which is the linear system the syndrome evaluator produces.
fn solve_magnitudes(
  observed : Array[Int],
  positions : Array[Int],
  length : Int,
) -> Array[Int]? {
  let count = positions.length()
  if count == 0 {
    return Some([])
  }
  let matrix : Array[Array[Int]] = []
  let rhs : Array[Int] = []
  for row in 0..<count {
    let entries : Array[Int] = []
    for column in 0..<count {
      entries.push(
        pow_mod929(error_locator_of(positions[column], length), row + 1),
      )
    }
    matrix.push(entries)
    rhs.push(observed[row])
  }
  solve_gf929(matrix, rhs)
}

///|
/// Repair a codeword sequence.
///
/// `erasures` lists positions that are known to be damaged; the decoder can
/// then fix up to `parity_count - erasures.length()` further errors, and
/// `parity_count / 2` unknown errors when no erasures are supplied.
///
/// Returns the repaired sequence together with the positions that changed.
/// Raises `TooManyErasures` when the sequence cannot be repaired.
pub fn correct_errors(
  words : Array[Int],
  parity_count : Int,
  erasures : Array[Int],
) -> (Array[Int], Array[Int]) raise EncodeError {
  if parity_count < 2 || parity_count % 2 != 0 || parity_count > 512 {
    raise InvalidErrorCorrectionLevel(parity_count)
  }
  for position in erasures {
    if position < 0 || position >= words.length() {
      raise UnrepresentableChar(position)
    }
  }
  let observed = syndromes(words, parity_count)
  let mut damaged = false
  for value in observed {
    if value != 0 {
      damaged = true
    }
  }
  if !damaged {
    return (words, [])
  }
  if erasures.length() * 2 > parity_count {
    raise TooManyErasures(erasures.length(), parity_count)
  }
  let locator = berlekamp_massey(observed)
  let positions = chien_search(locator, words.length(), erasures)
  if positions.length() == 0 || positions.length() * 2 > parity_count {
    raise TooManyErasures(positions.length(), parity_count)
  }
  let magnitudes = match solve_magnitudes(observed, positions, words.length()) {
    Some(values) => values
    None => raise TooManyErasures(positions.length(), parity_count)
  }
  let repaired : Array[Int] = []
  for word in words {
    repaired.push(word)
  }
  let changed : Array[Int] = []
  for index in 0..<positions.length() {
    let position = positions[index]
    let magnitude = magnitudes[index]
    if magnitude != 0 {
      repaired[position] = modulo929(repaired[position] - magnitude)
      changed.push(position)
    }
  }
  // Confirm the repair by recomputing the syndromes.
  if !is_error_free(repaired, parity_count) {
    raise TooManyErasures(positions.length(), parity_count)
  }
  changed.sort()
  (repaired, changed)
}

///|
/// Repair without error handling: `None` when the sequence cannot be
/// repaired.
pub fn correct_errors_opt(
  words : Array[Int],
  parity_count : Int,
  erasures : Array[Int],
) -> (Array[Int], Array[Int])? {
  try correct_errors(words, parity_count, erasures) catch {
    _ => None
  } noraise {
    repaired => Some(repaired)
  }
}
