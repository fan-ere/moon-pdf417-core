// Low level encoding: codewords to modules.
//
// A PDF417 symbol is drawn row by row.  Every row is
//
//     start pattern
//     left row indicator codeword
//     one symbol character per data column
//     right row indicator codeword
//     stop pattern
//
// and every codeword is one symbol character: a 17 module pattern chosen from
// the cluster of the row, i.e. `row mod 3`.  The clusters are the tables in
// `patterns.mbt`.  A module value of 1 is a bar and 0 is a space.
//
// This module is the bridge from codewords to something a renderer can fill:
// `symbol_matrix` returns one row of modules per symbol row, and the helpers
// below turn that into ASCII or SVG.

///|
/// Modules of the start pattern.
pub let start_modules : Int = 17

///|
/// Modules of the stop pattern.
pub let stop_modules : Int = 18

///|
/// Symbol character for `codeword` in `cluster`, or `None` when the codeword
/// or the cluster is out of range.
pub fn cluster_pattern(cluster : Int, codeword : Int) -> Int? {
  if codeword < 0 || codeword > max_codewords {
    return None
  }
  match cluster {
    0 => Some(cluster0_patterns[codeword])
    1 => Some(cluster1_patterns[codeword])
    2 => Some(cluster2_patterns[codeword])
    _ => None
  }
}

///|
/// `true` when the module is a bar.  Bits below the pattern's most significant
/// bit do not exist and are always spaces.
pub fn module_is_bar(pattern : Int, modules : Int, index : Int) -> Bool {
  if index < 0 || index >= modules {
    return false
  }
  ((pattern >> (modules - 1 - index)) & 1) == 1
}

///|
/// Append the modules of `pattern` to `row`.
fn append_pattern(row : Array[Int], pattern : Int, modules : Int) -> Unit {
  for index in 0..<modules {
    row.push(if module_is_bar(pattern, modules, index) { 1 } else { 0 })
  }
}

///|
/// Append the modules of `codeword` in `cluster` to `row`, raising when the
/// codeword has no symbol character in that cluster.
fn append_codeword(
  row : Array[Int],
  cluster : Int,
  codeword : Int,
) -> Unit raise EncodeError {
  match cluster_pattern(cluster, codeword) {
    Some(pattern) => append_pattern(row, pattern, start_modules)
    None => raise UnrepresentableChar(codeword)
  }
}

///|
/// Module row of one symbol row, without a quiet zone.
///
/// `row` is zero based, `codewords` are the symbol codewords in storage order
/// (row major) and `ec_level` is the error correction level the indicators
/// report.  The row indicator codewords are computed from the layout, exactly
/// as `symbol_rows` does.
pub fn symbol_row_modules(
  codewords : Array[Int],
  row : Int,
  columns : Int,
  rows : Int,
  ec_level : Int,
) -> Array[Int] raise EncodeError {
  let modules : Array[Int] = []
  append_pattern(modules, start_pattern, start_modules)
  let cluster = row_cluster(row)
  append_codeword(
    modules,
    cluster,
    left_row_indicator(row, rows, columns, ec_level),
  )
  for column in 0..<columns {
    let index = row * columns + column
    let codeword = if index < codewords.length() { codewords[index] } else { 0 }
    append_codeword(modules, cluster, codeword)
  }
  append_codeword(
    modules,
    cluster,
    right_row_indicator(row, rows, columns, ec_level),
  )
  append_pattern(modules, stop_pattern, stop_modules)
  modules
}

///|
/// Every module of a symbol, one array per row, without a quiet zone.
pub fn symbol_matrix(symbol : Symbol) -> Array[Array[Int]] raise EncodeError {
  let matrix : Array[Array[Int]] = []
  for row in 0..<symbol.rows {
    matrix.push(
      symbol_row_modules(
        symbol.codewords,
        row,
        symbol.columns,
        symbol.rows,
        symbol.ec_level,
      ),
    )
  }
  matrix
}

///|
/// Module width of one row, i.e. `35 + 17 * columns`.
pub fn matrix_row_width(matrix : Array[Array[Int]]) -> Int {
  if matrix.length() == 0 {
    return 0
  }
  matrix[0].length()
}

///|
/// Check that a matrix is rectangular, that every row starts with the start
/// pattern and ends with the stop pattern, and that the width matches the
/// column count.
pub fn verify_matrix(matrix : Array[Array[Int]], columns : Int) -> Bool {
  if matrix.length() == 0 {
    return false
  }
  let width = symbol_modules(columns)
  for row in matrix {
    if row.length() != width {
      return false
    }
    for index in 0..<start_modules {
      if row[index] !=
        (if module_is_bar(start_pattern, start_modules, index) { 1 } else { 0 }) {
        return false
      }
    }
    let stop_offset = width - stop_modules
    for index in 0..<stop_modules {
      if row[stop_offset + index] !=
        (if module_is_bar(stop_pattern, stop_modules, index) { 1 } else { 0 }) {
        return false
      }
    }
    for value in row {
      if value != 0 && value != 1 {
        return false
      }
    }
  }
  true
}

///|
/// Bounding box of the 17 module block that holds column `column`, in user
/// units: `(left, top, width, height)` with the quiet zone included.
///
/// This is what a scanner samples for that column, and what a highlight or
/// annotation layer would draw around it.
pub fn column_box(
  column : Int,
  columns : Int,
  rows : Int,
  scale : Int,
  quiet : Int,
) -> (Int, Int, Int, Int) {
  let unit = if scale <= 0 { 1 } else { scale }
  let quiet_zone = if quiet < 0 { 0 } else { quiet }
  if columns <= 0 || column < 0 || column >= columns || rows <= 0 {
    return (0, 0, 0, 0)
  }
  let left = (quiet_zone + start_modules + column * 17) * unit
  (left, quiet_zone * unit, 17 * unit, rows * unit)
}

///|
/// Render a matrix as text: `X` per bar, space per space, scale repeats.  A
/// quiet zone of `quiet` modules is added on both sides so the result can be
/// eyeballed as a symbol.
pub fn matrix_to_ascii(
  matrix : Array[Array[Int]],
  scale : Int,
  quiet : Int,
) -> String {
  let rows : Array[String] = []
  for row in matrix {
    let line = StringBuilder()
    for _ in 0..<(quiet * scale) {
      line.write_char(' ')
    }
    for value in row {
      for _ in 0..<scale {
        if value == 1 {
          line.write_char('X')
        } else {
          line.write_char(' ')
        }
      }
    }
    for _ in 0..<(quiet * scale) {
      line.write_char(' ')
    }
    rows.push(line.to_string())
  }
  let result = StringBuilder()
  let mut index = 0
  while index < rows.length() {
    if index > 0 {
      result.write_char('\n')
    }
    result.write_string(rows[index])
    index += 1
  }
  result.to_string()
}

///|
/// Render a matrix as a black and white SVG document.
///
/// `scale` is the width of one module in user units and `quiet` the quiet zone
/// in modules.  The output uses one path per row, so the document stays small
/// even for a thirty column symbol.
pub fn matrix_to_svg(
  matrix : Array[Array[Int]],
  scale : Int,
  quiet : Int,
) -> String {
  let unit = if scale <= 0 { 1 } else { scale }
  let quiet_zone = if quiet < 0 { 0 } else { quiet }
  let width = matrix_row_width(matrix)
  let height = matrix.length()
  let total_width = (width + 2 * quiet_zone) * unit
  let total_height = (height + 2 * quiet_zone) * unit
  let svg = StringBuilder()
  svg.write_string("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n")
  svg.write_string("<svg xmlns=\"http://www.w3.org/2000/svg\" ")
  svg.write_string("width=\"" + total_width.to_string() + "\" ")
  svg.write_string("height=\"" + total_height.to_string() + "\" ")
  svg.write_string("viewBox=\"0 0 " + total_width.to_string() + " ")
  svg.write_string(total_height.to_string() + "\">\n")
  svg.write_string("<rect width=\"100%\" height=\"100%\" fill=\"#ffffff\"/>\n")
  svg.write_string("<path fill=\"#000000\" d=\"")
  for row_index in 0..<matrix.length() {
    let row = matrix[row_index]
    let top = (quiet_zone + row_index) * unit
    let mut index = 0
    while index < row.length() {
      if row[index] == 1 {
        let run_start = index
        while index < row.length() && row[index] == 1 {
          index += 1
        }
        let left = (quiet_zone + run_start) * unit
        let right = (quiet_zone + index) * unit
        svg.write_string("M" + left.to_string() + " " + top.to_string() + "h")
        svg.write_string((right - left).to_string())
        svg.write_string("v" + unit.to_string() + "h-")
        svg.write_string((right - left).to_string())
        svg.write_string("z")
      } else {
        index += 1
      }
    }
  }
  svg.write_string("\"/>\n")
  svg.write_string("</svg>\n")
  svg.to_string()
}
