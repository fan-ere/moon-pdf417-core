///|
/// Minimal end to end example: encode a message, lay out a symbol, build the
/// module matrix, verify it and draw it.
///
/// Run it with:
///   moon run examples/quickstart --target wasm
fn main {
  let message = "PDF417 HIGH LEVEL ENCODING 1234567890"
  let codes : Array[Int] = []
  for character in message.iter() {
    codes.push(character.to_int())
  }
  let high = @pdf417.encode_high_level(codes) catch {
    error => {
      println("high level encoding failed: " + repr(error))
      return
    }
  }
  println("input: " + message)
  println("data codewords: " + high.codewords.length().to_string())
  let symbol = @pdf417.finalize(high.codewords, 2, 4) catch {
    error => {
      println("layout failed: " + repr(error))
      return
    }
  }
  println(
    "symbol: " +
    symbol.rows.to_string() +
    " rows x " +
    symbol.columns.to_string() +
    " columns, " +
    symbol.codewords.length().to_string() +
    " codewords (" +
    symbol.data_count.to_string() +
    " data incl. descriptor, " +
    symbol.pad_count.to_string() +
    " pad, " +
    (symbol.codewords.length() - symbol.data_count).to_string() +
    " parity)",
  )
  println("parity verified: " + @pdf417.verify_symbol(symbol).to_string())
  println(
    "modules per row: " + @pdf417.symbol_modules(symbol.columns).to_string(),
  )
  // Low level: codewords become modules, one row at a time.
  let matrix = @pdf417.symbol_matrix(symbol) catch {
    error => {
      println("matrix failed: " + repr(error))
      return
    }
  }
  println("matrix rows: " + matrix.length().to_string())
  println(
    "matrix verified: " +
    @pdf417.verify_matrix(matrix, symbol.columns).to_string(),
  )
  println("")
  println(@pdf417.matrix_to_ascii(matrix, 1, 2))
  let svg = @pdf417.matrix_to_svg(matrix, 3, 2)
  println("")
  println("svg characters: " + svg.length().to_string())
  println("svg starts with: " + svg[0:38].to_owned() + "...")
}
