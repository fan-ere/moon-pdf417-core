// Structure tests: row indicators, patterns and geometry.

///|
/// Build a symbol for a short data sequence, aborting the test on failure.
fn sample_symbol(level : Int, columns : Int) -> @moon-pdf417-core.Symbol {
  let data : Array[Int] = [1, 2, 3, 4, 5, 6, 7, 8]
  match @moon-pdf417-core.finalize_opt(data, level, columns) {
    Some(symbol) => symbol
    None => abort("expected a symbol")
  }
}

///|
test "row indicators follow annex Q" {
  // Cluster 0: the left indicator carries the row count group, the right one
  // the column count.
  assert_eq(@moon-pdf417-core.left_row_indicator(0, 9, 4, 2), 2)
  assert_eq(@moon-pdf417-core.right_row_indicator(0, 9, 4, 2), 3)
  // Cluster 1 adds the error correction level to the left indicator.
  assert_eq(@moon-pdf417-core.left_row_indicator(1, 9, 4, 2), 8)
  assert_eq(@moon-pdf417-core.right_row_indicator(1, 9, 4, 2), 2)
  // Cluster 2 swaps the column count over to the left indicator.
  assert_eq(@moon-pdf417-core.left_row_indicator(2, 9, 4, 2), 3)
  assert_eq(@moon-pdf417-core.right_row_indicator(2, 9, 4, 2), 8)
}

///|
test "row indicators stay inside the codeword alphabet" {
  for rows in [3, 9, 30, 90] {
    for columns in [1, 4, 30] {
      for level in [0, 4, 8] {
        for row in 0..<rows {
          let left = @moon-pdf417-core.left_row_indicator(
            row, rows, columns, level,
          )
          let right = @moon-pdf417-core.right_row_indicator(
            row, rows, columns, level,
          )
          assert_true(
            left >= 0 && left <= 928,
            msg="left indicator out of range",
          )
          assert_true(
            right >= 0 && right <= 928,
            msg="right indicator out of range",
          )
        }
      }
    }
  }
}

///|
test "row cluster cycles every three rows" {
  assert_eq(@moon-pdf417-core.row_cluster(0), 0)
  assert_eq(@moon-pdf417-core.row_cluster(1), 1)
  assert_eq(@moon-pdf417-core.row_cluster(2), 2)
  assert_eq(@moon-pdf417-core.row_cluster(3), 0)
}

///|
test "start and stop patterns are structurally valid" {
  assert_eq(
    @moon-pdf417-core.pattern_widths(@moon-pdf417-core.start_pattern, 17),
    [8, 1, 1, 1, 1, 1, 1, 3],
  )
  assert_eq(
    @moon-pdf417-core.pattern_widths(@moon-pdf417-core.stop_pattern, 18),
    [7, 1, 1, 3, 1, 1, 1, 2, 1],
  )
  assert_true(
    @moon-pdf417-core.is_valid_pattern(@moon-pdf417-core.start_pattern, 17),
  )
  assert_true(
    @moon-pdf417-core.is_valid_pattern(@moon-pdf417-core.stop_pattern, 18),
  )
}

///|
test "symbol modules follow the standard formula" {
  // 35 modules of start and stop pattern plus 17 modules per data column.
  assert_eq(@moon-pdf417-core.symbol_modules(1), 52)
  assert_eq(@moon-pdf417-core.symbol_modules(4), 103)
  assert_eq(@moon-pdf417-core.symbol_modules(30), 545)
}

///|
test "rows expose left and right indicators around the data" {
  let symbol = sample_symbol(2, 3)
  match @moon-pdf417-core.symbol_rows(symbol) {
    Some(rows) => {
      assert_eq(rows.length(), symbol.rows)
      for row in 0..<symbol.rows {
        let codewords = rows[row]
        assert_eq(codewords.length(), symbol.columns + 2)
        assert_eq(
          codewords[0],
          @moon-pdf417-core.left_row_indicator(
            row,
            symbol.rows,
            symbol.columns,
            symbol.ec_level,
          ),
        )
        assert_eq(
          codewords[codewords.length() - 1],
          @moon-pdf417-core.right_row_indicator(
            row,
            symbol.rows,
            symbol.columns,
            symbol.ec_level,
          ),
        )
      }
    }
    None => abort("expected rows")
  }
}

///|
test "geometry reports the module box" {
  let symbol = sample_symbol(1, 3)
  let geometry = @moon-pdf417-core.geometry_of(symbol)
  assert_eq(geometry.data_columns, 3)
  assert_eq(geometry.height_rows, symbol.rows)
  assert_eq(geometry.ec_level, 1)
  assert_eq(geometry.width_modules, @moon-pdf417-core.symbol_modules(3))
}

///|
test "smallest symbol picks a legal layout" {
  match @moon-pdf417-core.smallest_symbol(20, 2) {
    Some(layout) => {
      let (columns, rows) = layout
      assert_true(columns >= 1 && columns <= 30)
      assert_true(rows >= 3 && rows <= 90)
      assert_true(columns * rows >= 20 + 1 + 8)
    }
    None => abort("expected a layout")
  }
}

///|
test "planned columns respect the requested row window" {
  match @moon-pdf417-core.plan_columns(20, 8, 4, 4, 3, 10) {
    Some(layout) => {
      let (columns, rows) = layout
      assert_eq(columns, 4)
      assert_true(rows >= 3 && rows <= 10)
    }
    None => abort("expected a layout")
  }
  // A window that no row count can satisfy has no answer.
  assert_true(@moon-pdf417-core.plan_columns(400, 8, 1, 3, 3, 5) is None)
}

///|
test "planned columns sit close to the three to one ratio" {
  match @moon-pdf417-core.plan_columns(20, 8, 1, 30, 3, 90) {
    Some(layout) => {
      let (columns, rows) = layout
      // Reference geometry: (17 * columns + 69) * 0.357 mm wide, rows * 2 mm
      // tall, aimed at a 3:1 ratio.
      let width = (17.0 * columns.to_double() + 69.0) * 0.357
      let height = rows.to_double() * 2.0
      let ratio = width / height
      assert_true(ratio > 1.0 && ratio < 6.0, msg="ratio out of range")
    }
    None => abort("expected a layout")
  }
}
