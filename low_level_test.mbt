// Low level tests: symbol characters, module rows, matrices and rendering.

///|
fn split_lines(text : String) -> Array[String] {
  let lines : Array[String] = []
  for part in text.split("\n") {
    lines.push(part.to_owned())
  }
  lines
}

///|
fn low_symbol(level : Int, columns : Int) -> @moon-pdf417-core.Symbol {
  let data : Array[Int] = [1, 2, 3, 4, 5, 6, 7, 8]
  match @moon-pdf417-core.finalize_opt(data, level, columns) {
    Some(symbol) => symbol
    None => abort("expected a symbol")
  }
}

///|
fn low_matrix(symbol : @moon-pdf417-core.Symbol) -> Array[Array[Int]] {
  try @moon-pdf417-core.symbol_matrix(symbol) catch {
    _ => abort("expected a matrix")
  } noraise {
    matrix => matrix
  }
}

///|
test "every cluster holds 929 structurally valid patterns" {
  let counts = [
    @moon-pdf417-core.cluster0_patterns.length(),
    @moon-pdf417-core.cluster1_patterns.length(),
    @moon-pdf417-core.cluster2_patterns.length(),
  ]
  assert_eq(counts, [929, 929, 929])
  for cluster in 0..<3 {
    for codeword in 0..<929 {
      let pattern = match @moon-pdf417-core.cluster_pattern(cluster, codeword) {
        Some(value) => value
        None => abort("missing pattern")
      }
      let widths = @moon-pdf417-core.pattern_widths(pattern, 17)
      let mut total = 0
      for width in widths {
        assert_true(width >= 1 && width <= 6, msg="illegal element width")
        total += width
      }
      assert_eq(total, 17)
    }
  }
}

///|
test "cluster lookup rejects out of range values" {
  assert_true(@moon-pdf417-core.cluster_pattern(3, 0) is None)
  assert_true(@moon-pdf417-core.cluster_pattern(0, 929) is None)
  assert_true(@moon-pdf417-core.cluster_pattern(0, -1) is None)
  assert_true(@moon-pdf417-core.cluster_pattern(2, 928) is Some(_))
}

///|
test "the first symbol character of each cluster is unique" {
  let firsts = [
    @moon-pdf417-core.cluster0_patterns[0],
    @moon-pdf417-core.cluster1_patterns[0],
    @moon-pdf417-core.cluster2_patterns[0],
  ]
  assert_eq(firsts[0], 0x1d5c0)
  assert_eq(firsts[1], 0x1f560)
  assert_eq(firsts[2], 0x1abe0)
  assert_true(firsts[0] != firsts[1] && firsts[1] != firsts[2])
}

///|
test "module lookup reads the pattern most significant bit first" {
  // 0b1000... starts with a bar, 0b0111... with a space.
  assert_true(@moon-pdf417-core.module_is_bar(0x10000, 17, 0))
  assert_false(@moon-pdf417-core.module_is_bar(0x10000, 17, 1))
  assert_false(@moon-pdf417-core.module_is_bar(0x08000, 17, 0))
  // Out of range indices are spaces rather than a panic.
  assert_false(@moon-pdf417-core.module_is_bar(0x1ffff, 17, -1))
  assert_false(@moon-pdf417-core.module_is_bar(0x1ffff, 17, 17))
  assert_false(@moon-pdf417-core.module_is_bar(0x1ffff, 17, 900))
}

///|
test "a module row has the width the geometry promises" {
  let symbol = low_symbol(2, 4)
  let row = try
    @moon-pdf417-core.symbol_row_modules(
      symbol.codewords,
      0,
      symbol.columns,
      symbol.rows,
      symbol.ec_level,
    )
  catch {
    _ => []
  } noraise {
    value => value
  }
  assert_eq(row.length(), @moon-pdf417-core.symbol_modules(4))
  assert_eq(row.length(), 137)
}

///|
test "the matrix is rectangular and framed by the start and stop patterns" {
  let symbol = low_symbol(2, 4)
  let matrix = low_matrix(symbol)
  assert_eq(matrix.length(), symbol.rows)
  assert_true(
    @moon-pdf417-core.verify_matrix(matrix, symbol.columns),
    msg="matrix failed verification",
  )
  assert_eq(@moon-pdf417-core.matrix_row_width(matrix), 137)
  // A wrong column count must be rejected.
  assert_false(@moon-pdf417-core.verify_matrix(matrix, 5))
}

///|
test "each row uses the cluster of its row index" {
  let symbol = low_symbol(1, 3)
  let matrix = low_matrix(symbol)
  for row in 0..<matrix.length() {
    let cluster = @moon-pdf417-core.row_cluster(row)
    let left = @moon-pdf417-core.left_row_indicator(
      row,
      symbol.rows,
      symbol.columns,
      symbol.ec_level,
    )
    let pattern = match @moon-pdf417-core.cluster_pattern(cluster, left) {
      Some(value) => value
      None => abort("missing pattern")
    }
    // The left indicator sits right after the start pattern.
    for index in 0..<17 {
      let expected = if @moon-pdf417-core.module_is_bar(pattern, 17, index) {
        1
      } else {
        0
      }
      assert_eq(matrix[row][17 + index], expected)
    }
  }
}

///|
test "column boxes sit inside the symbol and do not overlap" {
  let columns = 4
  let rows = 6
  let scale = 2
  let quiet = 2
  let mut previous_right = 0
  for column in 0..<columns {
    let (left, top, width, height) = @moon-pdf417-core.column_box(
      column, columns, rows, scale, quiet,
    )
    assert_eq(width, 17 * scale)
    assert_eq(height, rows * scale)
    assert_eq(top, quiet * scale)
    // The first column starts after the quiet zone and the start pattern.
    assert_true(
      left >= (quiet + 17) * scale,
      msg="column box overlaps the start pattern",
    )
    // Column blocks are adjacent, so the next one starts where the previous
    // one ends.
    assert_true(left >= previous_right, msg="column boxes overlap")
    previous_right = left + width
  }
  // Out of range requests produce an empty box instead of a panic.
  assert_eq(
    @moon-pdf417-core.column_box(-1, columns, rows, scale, quiet),
    (0, 0, 0, 0),
  )
  assert_eq(
    @moon-pdf417-core.column_box(columns, columns, rows, scale, quiet),
    (0, 0, 0, 0),
  )
}

///|
test "ASCII rendering repeats modules by the scale factor" {
  let symbol = low_symbol(0, 2)
  let matrix = low_matrix(symbol)
  let modules = @moon-pdf417-core.symbol_modules(symbol.columns)
  let text = @moon-pdf417-core.matrix_to_ascii(matrix, 1, 1)
  let lines = split_lines(text)
  assert_eq(lines.length(), symbol.rows)
  assert_eq(lines[0].length(), modules + 2)
  let wide = @moon-pdf417-core.matrix_to_ascii(matrix, 3, 0)
  assert_eq(split_lines(wide)[0].length(), modules * 3)
}

///|
test "SVG rendering declares the module box and draws the bars" {
  let symbol = low_symbol(1, 3)
  let matrix = low_matrix(symbol)
  let svg = @moon-pdf417-core.matrix_to_svg(matrix, 2, 2)
  assert_true(svg.has_prefix("<?xml"))
  assert_true(svg.has_suffix("</svg>\n"))
  // (symbol width + 2 * quiet) * scale each way.
  let modules = @moon-pdf417-core.symbol_modules(symbol.columns)
  let expected_width = (modules + 2 * 2) * 2
  let expected_height = (symbol.rows + 2 * 2) * 2
  assert_true(
    svg.contains("width=\"" + expected_width.to_string() + "\""),
    msg="unexpected width",
  )
  assert_true(
    svg.contains(
      "viewBox=\"0 0 " +
      expected_width.to_string() +
      " " +
      expected_height.to_string() +
      "\"",
    ),
    msg="unexpected viewBox",
  )
  assert_true(svg.contains("<path fill=\"#000000\""))
  // One subpath per bar run, and every row must contribute at least one.
  let mut runs = 0
  let mut index = 0
  let path_start = match svg.find("<path fill=\"#000000\"") {
    Some(value) => value
    None => abort("the drawing path is missing")
  }
  let body = svg[path_start:].to_owned()
  while index < body.length() {
    if body[index] == 'M' {
      runs += 1
    }
    index += 1
  }
  assert_true(runs >= symbol.rows, msg="too few bar runs")
}
