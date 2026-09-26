// Low level *structure* of a symbol: row indicators, patterns and geometry.
//
// This module deliberately stops before bar and space widths.  It provides
// what a renderer needs to place codewords and what a renderer test needs to
// check geometry, with the start pattern, the stop pattern and the row
// indicator formulas of ISO/IEC 15438 annex Q expressed as computation
// instead of a 928 by 3 data table.

///|
/// Start pattern, 17 modules, most significant bit first (0 = space).
pub let start_pattern : Int = 0x1fea8

///|
/// Stop pattern, 18 modules, most significant bit first.
pub let stop_pattern : Int = 0x3fa29

///|
/// Width of the start pattern in modules.
pub let start_pattern_modules : Int = 17

///|
/// Width of the stop pattern in modules.
pub let stop_pattern_modules : Int = 18

///|
/// Number of data codewords in one row: one left indicator, `columns` data
/// codewords and one right indicator.
pub fn row_codeword_count(columns : Int) -> Int {
  columns + 2
}

///|
/// Total module width of a symbol with `columns` columns.
///
/// Following the geometry used by the reference implementation: the start
/// pattern (17 modules) and the stop pattern (18 modules) are joined by the
/// left indicator, `columns` data codewords and the right indicator, so the
/// width is `35 + 17 * columns`.
pub fn symbol_modules(columns : Int) -> Int {
  35 + 17 * columns
}

///|
/// Bar and space cluster of row `row`, i.e. `row mod 3`.
pub fn row_cluster(row : Int) -> Int {
  row % 3
}

///|
/// Left row indicator codeword for a row, from annex Q.
///
/// The three clusters carry different information: cluster 0 puts the row
/// count in the low position, cluster 1 the error correction level and the
/// row count modulo three, cluster 2 the column count.
pub fn left_row_indicator(
  row : Int,
  rows : Int,
  columns : Int,
  ec_level : Int,
) -> Int {
  match row_cluster(row) {
    0 => 30 * (row / 3) + (rows - 1) / 3
    1 => 30 * (row / 3) + ec_level * 3 + (rows - 1) % 3
    _ => 30 * (row / 3) + (columns - 1)
  }
}

///|
/// Right row indicator codeword for a row, from annex Q.
pub fn right_row_indicator(
  row : Int,
  rows : Int,
  columns : Int,
  ec_level : Int,
) -> Int {
  match row_cluster(row) {
    0 => 30 * (row / 3) + (columns - 1)
    1 => 30 * (row / 3) + (rows - 1) / 3
    _ => 30 * (row / 3) + ec_level * 3 + (rows - 1) % 3
  }
}

///|
/// Codewords of one row in stored order: left indicator, data codewords,
/// right indicator.
pub fn row_codewords(
  codewords : Array[Int],
  row : Int,
  columns : Int,
  rows : Int,
  ec_level : Int,
) -> Array[Int] {
  let result : Array[Int] = [left_row_indicator(row, rows, columns, ec_level)]
  let base = row * columns
  for offset in 0..<columns {
    let index = base + offset
    result.push(if index < codewords.length() { codewords[index] } else { 0 })
  }
  result.push(right_row_indicator(row, rows, columns, ec_level))
  result
}

///|
/// Split a symbol's codewords into rows.  Returns `None` when the symbol is
/// inconsistent with its layout.
pub fn symbol_rows(symbol : Symbol) -> Array[Array[Int]]? {
  if symbol.codewords.length() != symbol.columns * symbol.rows {
    return None
  }
  let rows : Array[Array[Int]] = []
  for row in 0..<symbol.rows {
    rows.push(
      row_codewords(
        symbol.codewords,
        row,
        symbol.columns,
        symbol.rows,
        symbol.ec_level,
      ),
    )
  }
  Some(rows)
}

///|
/// Expand a pattern into its bar widths, starting with a bar and alternating.
/// A pattern whose leading bit is 0 starts with a zero width bar, which is how
/// the caller detects the leading space.
pub fn pattern_widths(pattern : Int, modules : Int) -> Array[Int] {
  let widths : Array[Int] = []
  if modules <= 0 {
    return widths
  }
  let mut mask = 1 << (modules - 1)
  let mut last = (pattern & mask) != 0
  let mut width = 0
  for _ in 0..<modules {
    let bit = (pattern & mask) != 0
    if bit == last {
      width += 1
    } else {
      widths.push(width)
      last = bit
      width = 1
    }
    mask = mask >> 1
  }
  widths.push(width)
  widths
}

///|
/// `true` if a pattern describes exactly `modules` modules and alternates
/// between bars and spaces with every width in 1..8.  PDF417 patterns are 17
/// modules wide except the stop pattern, which is 18 modules and starts with
/// an eight module bar (the start pattern).
pub fn is_valid_pattern(pattern : Int, modules : Int) -> Bool {
  let widths = pattern_widths(pattern, modules)
  if widths.length() == 0 {
    return false
  }
  let mut total = 0
  for width in widths {
    if width < 1 || width > 8 {
      return false
    }
    total += width
  }
  total == modules
}

///|
/// Geometry of a symbol in modules.
pub(all) struct Geometry {
  width_modules : Int
  height_rows : Int
  data_columns : Int
  data_rows : Int
  ec_level : Int
}

///|
/// Geometry of a finalized symbol.
pub fn geometry_of(symbol : Symbol) -> Geometry {
  {
    width_modules: symbol_modules(symbol.columns),
    height_rows: symbol.rows,
    data_columns: symbol.columns,
    data_rows: symbol.rows,
    ec_level: symbol.ec_level,
  }
}

///|
/// Total codeword capacity of a `columns` by `rows` data area, including the
/// row indicators of every row.
pub fn symbol_codeword_capacity(columns : Int, rows : Int) -> Int {
  if columns < min_columns ||
    columns > max_columns ||
    rows < min_rows ||
    rows > max_rows {
    return 0
  }
  columns * rows
}

///|
/// Smallest legal symbol that holds `codewords` codewords, searching column
/// counts from one to thirty and preferring the geometry closest to the
/// standard's 3:1 ratio.
pub fn smallest_symbol(codewords : Int, ec_level : Int) -> (Int, Int)? {
  if codewords <= 0 {
    return None
  }
  if ec_level < 0 || ec_level > max_error_correction_level {
    return None
  }
  let ec_count = error_correction_codeword_count(ec_level)
  let mut best : (Int, Int)? = None
  let mut best_area = 0
  let mut columns = min_columns
  while columns <= max_columns {
    let rows = rows_for(codewords, ec_count, columns)
    if rows >= min_rows && rows <= max_rows {
      let area = columns * rows
      let take = match best {
        None => true
        Some(_) => area < best_area
      }
      if take {
        best = Some((columns, rows))
        best_area = area
      }
    }
    columns += 1
  }
  best
}
