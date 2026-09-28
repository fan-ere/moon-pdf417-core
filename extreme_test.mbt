///|
/// Exercise the extremes of the layout space end to end: one column, thirty
/// columns, the maximum error correction level and a payload large enough to
/// need many rows.  Catches index and pattern table mistakes that the small
/// fixtures cannot reach.
test "extreme layouts build a valid matrix" {
  let cases : Array[(Int, Int)] = [(0, 1), (0, 30), (8, 30), (4, 3), (2, 2)]
  for entry in cases {
    let (level, columns) = entry
    let data : Array[Int] = []
    for index in 0..<40 {
      data.push(index % 900)
    }
    match @moon-pdf417-core.finalize_opt(data, level, columns) {
      None => abort("layout was rejected")
      Some(symbol) => {
        assert_true(@moon-pdf417-core.verify_symbol(symbol))
        let matrix = try @moon-pdf417-core.symbol_matrix(symbol) catch {
          _ => abort("matrix failed")
        } noraise {
          value => value
        }
        assert_eq(matrix.length(), symbol.rows)
        assert_true(@moon-pdf417-core.verify_matrix(matrix, columns))
        for row in matrix {
          assert_eq(row.length(), @moon-pdf417-core.symbol_modules(columns))
        }
      }
    }
  }
}

///|
/// A level 8 symbol needs 512 error correction codewords, so one column cannot
/// hold it: the layout must report the failure rather than emit a symbol that
/// claims a level it does not carry.
test "a level that cannot fit the column count is rejected" {
  let data : Array[Int] = [1, 2, 3, 4, 5, 6, 7, 8]
  assert_true(@moon-pdf417-core.finalize_opt(data, 8, 1) is None)
  // The same level fits once the symbol is wide enough.
  assert_true(@moon-pdf417-core.finalize_opt(data, 8, 30) is Some(_))
}

///|
/// The smallest symbol the layout produces for one data codeword at level 0:
/// the descriptor plus the data plus two parity codewords need more than the
/// three row minimum, because one column holds a single codeword per row.
test "the smallest one column symbol has four rows" {
  let symbol = match @moon-pdf417-core.finalize_opt([100], 0, 1) {
    Some(value) => value
    None => abort("expected a symbol")
  }
  assert_eq(symbol.columns, 1)
  assert_eq(symbol.rows, 4)
  assert_eq(symbol.pad_count, 0)
  assert_eq(symbol.data_count, 2)
  assert_eq(symbol.codewords.length(), 4)
  let matrix = low_matrix(symbol)
  assert_eq(matrix.length(), 4)
  assert_eq(matrix[0].length(), @moon-pdf417-core.symbol_modules(1))
  assert_true(@moon-pdf417-core.verify_matrix(matrix, 1))
}

///|
/// The row indicator codewords must be addressable in the pattern table for
/// every legal row, column and level.
test "row indicators are addressable in every legal layout" {
  for rows in [3, 4, 30, 90] {
    for columns in [1, 2, 15, 30] {
      for level in [0, 4, 8] {
        for row in 0..<rows {
          let left = @moon-pdf417-core.left_row_indicator(
            row, rows, columns, level,
          )
          let right = @moon-pdf417-core.right_row_indicator(
            row, rows, columns, level,
          )
          let cluster = @moon-pdf417-core.row_cluster(row)
          assert_true(
            @moon-pdf417-core.cluster_pattern(cluster, left) is Some(_),
            msg="left indicator has no symbol character",
          )
          assert_true(
            @moon-pdf417-core.cluster_pattern(cluster, right) is Some(_),
            msg="right indicator has no symbol character",
          )
        }
      }
    }
  }
}
