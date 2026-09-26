///|
/// Minimal end to end example: encode a message, lay out a symbol and verify
/// the Reed-Solomon parity.
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
  println("codewords: " + repr(high.codewords))
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
  println("full codewords: " + repr(symbol.codewords))
  println("parity verified: " + @pdf417.verify_symbol(symbol).to_string())
  // The structure layer reports the module box a renderer has to fill.
  println(
    "modules per row: " + @pdf417.symbol_modules(symbol.columns).to_string(),
  )
}
