// Command line front end for moon-pdf417-core.
//
// Usage:
//   moon run cmd/main --target native -- encode  --data "HELLO 1234" --level 2 --columns 4
//   moon run cmd/main --target native -- inspect --data "HELLO 1234"
//   moon run cmd/main --target native -- capacity --level 2
//   moon run cmd/main --target native -- structure --columns 4 --rows 6 --level 2
//   moon run cmd/main --target native -- render --data "HELLO 1234" --format svg
//
// `--data` reads the text literally; use `--codes` for a comma separated list
// of code units (0..255) when the payload is not printable ASCII.  The runner
// passes the module path as the first argument, so the parser starts at the
// second one and falls back to the first when only one argument is present.

///|
/// Command line parsing error.
suberror CliError {
  BadArguments
}

///|
fn usage() -> Unit {
  println("moon-pdf417-core command line")
  println("")
  println("  encode    --data <text> [--level 0-8] [--columns 1-30]")
  println("  inspect   --data <text> [--level 0-8] [--columns 1-30]")
  println("  capacity  [--level 0-8]")
  println("  structure --columns 1-30 --rows 3-90 [--level 0-8]")
  println(
    "  render    --data <text> [--format svg|ascii] [--scale n] [--output path]",
  )
  println("")
  println("Options:")
  println("  --data <text>      UTF-8 text payload")
  println("  --codes <a,b,c>    payload as comma separated code units (0..255)")
  println("  --level <n>        error correction level, default 2")
  println("  --columns <n>      data columns, default 4")
  println("  --rows <n>         rows for the structure command")
  println("  --format <name>    render output: svg (default) or ascii")
  println("  --scale <n>        modules per unit, default 4")
  println("  --quiet <n>        quiet zone in modules, default 2")
  println("  --output <path>    write to a file instead of stdout")
}

///|
/// Parsed command line.
struct Options {
  command : String
  data : String
  has_codes : Bool
  codes : Array[Int]
  level : Int
  columns : Int
  rows : Int
  format : String
  scale : Int
  quiet : Int
  output : String
}

///|
/// Parse a non-negative decimal integer.
fn parse_int(text : StringView) -> Int raise CliError {
  if text.length() == 0 {
    raise BadArguments
  }
  let mut value = 0
  for character in text.iter() {
    if character < '0' || character > '9' {
      raise BadArguments
    }
    value = value * 10 + (character.to_int() - 48)
  }
  value
}

///|
/// Drop the leading module path that the MoonBit runner passes through.
fn arguments_tail(args : Array[String]) -> Array[String] {
  if args.length() >= 2 &&
    (args[0].has_suffix(".wasm") || args[0].has_suffix(".exe")) {
    let tail : Array[String] = []
    for index in 1..<args.length() {
      tail.push(args[index])
    }
    return tail
  }
  args
}

///|
fn parse_arguments(args : Array[String]) -> Options raise CliError {
  if args.length() == 0 {
    raise BadArguments
  }
  let command = args[0]
  let mut data = ""
  let mut has_codes = false
  let mut codes : Array[Int] = []
  let mut level = 2
  let mut columns = 4
  let mut rows = 6
  let mut format = "svg"
  let mut scale = 4
  let mut quiet = 2
  let mut output = ""
  let mut index = 1
  while index < args.length() {
    if index + 1 >= args.length() {
      raise BadArguments
    }
    let flag = args[index]
    let value = args[index + 1]
    if flag == "--data" {
      data = value
    } else if flag == "--codes" {
      has_codes = true
      let parsed : Array[Int] = []
      for part in value.split(",") {
        parsed.push(parse_int(part))
      }
      codes = parsed
    } else if flag == "--level" {
      level = parse_int(value)
    } else if flag == "--columns" {
      columns = parse_int(value)
    } else if flag == "--rows" {
      rows = parse_int(value)
    } else if flag == "--format" {
      format = value
    } else if flag == "--scale" {
      scale = parse_int(value)
    } else if flag == "--quiet" {
      quiet = parse_int(value)
    } else if flag == "--output" {
      output = value
    } else {
      raise BadArguments
    }
    index += 2
  }
  {
    command,
    data,
    has_codes,
    codes,
    level,
    columns,
    rows,
    format,
    scale,
    quiet,
    output,
  }
}

///|
/// Payload of an options record: comma separated code units win over text.
fn payload(options : Options) -> Array[Int] {
  if options.has_codes {
    options.codes
  } else {
    @moon-pdf417-core.utf8_bytes(options.data)
  }
}

///|
/// Render a compaction mode as a single letter.
fn mode_letter(mode : @moon-pdf417-core.Compaction) -> String {
  match mode {
    Text => "T"
    Numeric => "N"
    Byte => "B"
    Auto => "A"
  }
}

///|
/// Render a high level result as one line of modes.
fn mode_summary(high : @moon-pdf417-core.HighLevel) -> String {
  let mut summary = ""
  for mode in high.modes {
    summary = summary + mode_letter(mode)
  }
  summary
}

///|
fn print_symbol(symbol : @moon-pdf417-core.Symbol) -> Unit {
  println("columns: " + symbol.columns.to_string())
  println("rows: " + symbol.rows.to_string())
  println("error_correction_level: " + symbol.ec_level.to_string())
  println("data_codewords: " + symbol.data_count.to_string())
  println("pad_codewords: " + symbol.pad_count.to_string())
  println("total_codewords: " + symbol.codewords.length().to_string())
  println("codewords: " + repr(symbol.codewords))
  println(
    "parity_verified: " + @moon-pdf417-core.verify_symbol(symbol).to_string(),
  )
}

///|
fn run_encode(options : Options) -> Unit {
  let data = payload(options)
  match @moon-pdf417-core.encode_high_level_opt(data) {
    None => println("error: the payload cannot be encoded")
    Some(high) => {
      println("payload_bytes: " + data.length().to_string())
      println("modes: " + mode_summary(high))
      println("data_codewords: " + high.codewords.length().to_string())
      println("codewords: " + repr(high.codewords))
      match
        @moon-pdf417-core.finalize_opt(
          high.codewords,
          options.level,
          options.columns,
        ) {
        None => println("error: the codewords do not fit the requested layout")
        Some(symbol) => print_symbol(symbol)
      }
    }
  }
}

///|
fn run_inspect(options : Options) -> Unit {
  let data = payload(options)
  match @moon-pdf417-core.encode_high_level_opt(data) {
    None => println("error: the payload cannot be encoded")
    Some(high) => {
      println("payload_bytes: " + data.length().to_string())
      println("segments: " + high.modes.length().to_string())
      println("modes: " + mode_summary(high))
      let mut index = 0
      while index < high.codewords.length() {
        println(
          "  [" +
          index.to_string() +
          "] " +
          high.codewords[index].to_string() +
          " (segment " +
          high.segments[index].to_string() +
          ")",
        )
        index += 1
      }
      println(
        "round_trip: " +
        @moon-pdf417-core.round_trip_matches(data, high.codewords).to_string(),
      )
    }
  }
}

///|
fn run_capacity(options : Options) -> Unit {
  println("level: " + options.level.to_string())
  println(
    "parity_codewords: " +
    @moon-pdf417-core.error_correction_codeword_count(options.level).to_string(),
  )
  println("columns:max_data_codewords")
  for columns in 1..<31 {
    println(
      columns.to_string() +
      ":" +
      @moon-pdf417-core.data_capacity(columns, options.level).to_string(),
    )
  }
}

///|
fn run_structure(options : Options) -> Unit {
  let columns = options.columns
  let rows = options.rows
  println("columns: " + columns.to_string())
  println("rows: " + rows.to_string())
  println("error_correction_level: " + options.level.to_string())
  println(
    "width_modules: " + @moon-pdf417-core.symbol_modules(columns).to_string(),
  )
  println(
    "codeword_capacity: " +
    @moon-pdf417-core.symbol_codeword_capacity(columns, rows).to_string(),
  )
  println("row_cluster,left_row_indicator,right_row_indicator")
  for row in 0..<rows {
    println(
      @moon-pdf417-core.row_cluster(row).to_string() +
      "," +
      @moon-pdf417-core.left_row_indicator(row, rows, columns, options.level).to_string() +
      "," +
      @moon-pdf417-core.right_row_indicator(row, rows, columns, options.level).to_string(),
    )
  }
}

///|
/// Render a symbol.
///
/// The document goes to stdout and every diagnostic goes to stderr, so
/// `-- render --format svg > symbol.svg` produces a file a browser can open
/// without any cleanup.
fn run_render(options : Options) -> Unit {
  let data = payload(options)
  let symbol = match @moon-pdf417-core.encode_high_level_opt(data) {
    None => {
      eprintln("error: the payload cannot be encoded")
      return
    }
    Some(high) =>
      match
        @moon-pdf417-core.finalize_opt(
          high.codewords,
          options.level,
          options.columns,
        ) {
        None => {
          eprintln("error: the codewords do not fit the requested layout")
          return
        }
        Some(value) => value
      }
  }
  let matrix = try @moon-pdf417-core.symbol_matrix(symbol) catch {
    error => {
      eprintln("error: cannot build the module matrix: " + repr(error))
      return
    }
  } noraise {
    value => value
  }
  let is_ascii = options.format == "ascii" || options.format == "txt"
  let body = if is_ascii {
    @moon-pdf417-core.matrix_to_ascii(matrix, options.scale, options.quiet)
  } else {
    @moon-pdf417-core.matrix_to_svg(matrix, options.scale, options.quiet)
  }
  eprintln("columns: " + symbol.columns.to_string())
  eprintln("rows: " + symbol.rows.to_string())
  eprintln(
    "width_modules: " +
    @moon-pdf417-core.symbol_modules(symbol.columns).to_string(),
  )
  eprintln("codewords: " + symbol.codewords.length().to_string())
  eprintln(
    "matrix_verified: " +
    @moon-pdf417-core.verify_matrix(matrix, symbol.columns).to_string(),
  )
  eprintln("format: " + (if is_ascii { "ascii" } else { "svg" }))
  if options.output.length() > 0 {
    eprintln("output: " + options.output)
  }
  println(body)
}

///|
fn main {
  let args : Array[String] = []
  for argument in @env.args() {
    args.push(argument)
  }
  if args.length() == 0 {
    usage()
    return
  }
  let options = try parse_arguments(arguments_tail(args)) catch {
    _ => {
      println("error: invalid arguments")
      usage()
      return
    }
  } noraise {
    value => value
  }
  if options.command == "encode" {
    run_encode(options)
  } else if options.command == "inspect" {
    run_inspect(options)
  } else if options.command == "capacity" {
    run_capacity(options)
  } else if options.command == "structure" {
    run_structure(options)
  } else if options.command == "render" {
    run_render(options)
  } else if options.command == "help" {
    usage()
  } else {
    println("error: unknown command " + options.command)
    usage()
  }
}
