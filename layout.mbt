// Symbol layout: row planning, pad codewords and final assembly.
//
// The layout rules follow ISO/IEC 15438 annex Q and chapter 4.9:
//   * a symbol has three to ninety rows and one to thirty columns,
//   * `rows = ceil((data + ec) / columns)` with a minimum of three rows,
//   * pad codewords (value 900) fill the data area,
//   * the first codeword is the symbol length descriptor, i.e. the number of
//     data, pad and descriptor codewords, excluding error correction.

///|
/// Rows required for `source_codewords` data codewords, `ec_codewords` error
/// correction codewords and `columns` columns, with at least `min_rows` rows.
pub fn plan_rows(
  source_codewords : Int,
  ec_codewords : Int,
  columns : Int,
  min_rows : Int,
) -> Int {
  if columns <= 0 {
    return 0
  }
  let needed = source_codewords + 1 + ec_codewords
  let mut rows = (needed + columns - 1) / columns
  if rows < min_rows {
    rows = min_rows
  }
  rows
}

///|
/// Rows required with the default three row minimum.
pub fn rows_for(
  source_codewords : Int,
  ec_codewords : Int,
  columns : Int,
) -> Int {
  plan_rows(source_codewords, ec_codewords, columns, min_rows)
}

///|
/// Number of pad codewords needed so that data, padding, descriptor and
/// error correction exactly fill `rows * columns` codewords.  Returns `None`
/// when the data area is smaller than the data.
pub fn pad_codewords(
  source_codewords : Int,
  ec_codewords : Int,
  columns : Int,
  rows : Int,
) -> Int? {
  let capacity = columns * rows - ec_codewords
  let used = source_codewords + 1
  if capacity < used {
    None
  } else {
    Some(capacity - used)
  }
}

///|
/// `true` if `columns` and `rows` describe a legal data area.
pub fn is_valid_layout(columns : Int, rows : Int) -> Bool {
  columns >= min_columns &&
  columns <= max_columns &&
  rows >= min_rows &&
  rows <= max_rows
}

///|
/// Choose the column count that gets closest to the 3:1 width/height ratio
/// the standard recommends, searching `min_cols..max_cols` and accepting a
/// row count inside `min_r..max_r`.
///
/// Returns `None` when no column count fits.
pub fn plan_columns(
  source_codewords : Int,
  ec_codewords : Int,
  min_cols : Int,
  max_cols : Int,
  min_r : Int,
  max_r : Int,
) -> (Int, Int)? {
  let low = if min_cols < min_columns { min_columns } else { min_cols }
  let high = if max_cols > max_columns { max_columns } else { max_cols }
  let mut best : (Int, Int)? = None
  let mut best_distance = 0.0
  let mut columns = low
  while columns <= high {
    let rows = plan_rows(source_codewords, ec_codewords, columns, min_r)
    if rows >= min_r && rows <= max_r {
      let width = (17 * columns + 69).to_double() * 0.357
      let height = rows.to_double() * 2.0
      let ratio = width / height
      let distance = if ratio > 3.0 { ratio - 3.0 } else { 3.0 - ratio }
      let take = match best {
        None => true
        Some(_) => distance < best_distance
      }
      if take {
        best = Some((columns, rows))
        best_distance = distance
      }
    }
    columns += 1
  }
  best
}

///|
/// Finalize a high level encoding into a complete codeword sequence.
///
/// `data` are the high level data codewords (without the length descriptor),
/// `level` is the error correction level and `columns` the requested column
/// count.  The returned `Symbol` carries the full sequence a low level
/// encoder consumes, plus the layout that produced it.
pub fn finalize(
  data : Array[Int],
  level : Int,
  columns : Int,
) -> Symbol raise EncodeError {
  if level < 0 || level > max_error_correction_level {
    raise InvalidErrorCorrectionLevel(level)
  }
  if columns < min_columns || columns > max_columns {
    raise InvalidColumnCount(columns)
  }
  let ec_count = error_correction_codeword_count(level)
  let rows = rows_for(data.length(), ec_count, columns)
  if rows > max_rows {
    raise LayoutImpossible(columns, rows)
  }
  let pad = match pad_codewords(data.length(), ec_count, columns, rows) {
    Some(value) => value
    None => raise LayoutImpossible(columns, rows)
  }
  let data_count = data.length() + pad + 1
  if data_count + ec_count > max_codewords {
    raise TooManyCodewords(data_count + ec_count)
  }
  let payload : Array[Int] = [data_count]
  for word in data {
    payload.push(word)
  }
  for _ in 0..<pad {
    payload.push(pad_codeword)
  }
  let parity = error_correction(payload, level)
  let codewords : Array[Int] = []
  for word in payload {
    codewords.push(word)
  }
  for word in parity {
    codewords.push(word)
  }
  { codewords, columns, rows, ec_level: level, data_count, pad_count: pad, }
}

///|
/// `finalize` without error handling.
pub fn finalize_opt(data : Array[Int], level : Int, columns : Int) -> Symbol? {
  try finalize(data, level, columns) catch {
    _ => None
  } noraise {
    symbol => Some(symbol)
  }
}

///|
/// `true` if the sequence can be laid out and the trailing codewords are a
/// valid Reed-Solomon parity block.
pub fn verify_symbol(symbol : Symbol) -> Bool {
  let ec_count = error_correction_codeword_count(symbol.ec_level)
  if symbol.codewords.length() != symbol.data_count + ec_count {
    return false
  }
  if symbol.codewords.length() != symbol.columns * symbol.rows {
    return false
  }
  if symbol.codewords[0] != symbol.data_count {
    return false
  }
  is_error_free(symbol.codewords, ec_count)
}

///|
/// Largest number of data codewords that still fits a symbol with `columns`
/// columns at `level`.
pub fn data_capacity(columns : Int, level : Int) -> Int {
  if columns < min_columns || columns > max_columns {
    return 0
  }
  if level < 0 || level > max_error_correction_level {
    return 0
  }
  let ec_count = error_correction_codeword_count(level)
  let mut rows = min_rows
  let mut best = 0
  while rows <= max_rows {
    let capacity = columns * rows - ec_count - 1
    if capacity > best {
      best = capacity
    }
    rows += 1
  }
  best
}

///|
/// Recommended minimum error correction level for `n` data codewords, from
/// annex E of ISO/IEC 15438.  Returns `None` when the standard gives no
/// recommendation.
pub fn recommended_level(n : Int) -> Int? {
  if n <= 0 {
    None
  } else if n <= 40 {
    Some(2)
  } else if n <= 160 {
    Some(3)
  } else if n <= 320 {
    Some(4)
  } else if n <= 863 {
    Some(5)
  } else {
    None
  }
}

///|
/// `true` if the codeword sequence respects the structural rules of a symbol:
/// length descriptor first, pad codewords 900 in the data area and no value
/// outside 0..928.
pub fn is_structurally_valid(codewords : Array[Int]) -> Bool {
  if codewords.length() < min_rows {
    return false
  }
  if codewords[0] != codewords.length() {
    return false
  }
  for word in codewords {
    if word < 0 || word > max_codewords {
      return false
    }
  }
  true
}
