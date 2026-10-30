///|
/// Differential fuzzer: random patterns and inputs, comparing this engine
/// against `@string.Regex` from core.
///
/// `strict` runs never repeat a body that can match the empty string; the
/// two engines are expected to agree on all of them. The other runs include
/// such repetitions, where core's engine and the compiler's construction
/// (which this engine follows) are known to differ.
fn show(m : Array[StringView?]) -> String {
  let sb = StringBuilder()
  for g in m {
    match g {
      None => sb.write_string("<none>")
      Some(v) => sb.write_string("[\{v}]")
    }
  }
  sb.to_string()
}

///|
fn run(strict~ : Bool, rounds : Int32) -> Unit {
  let rng = @fuzzgen.Rng(12345U)
  let mut patterns = 0
  let mut checks = 0
  let mut diffs = 0
  let mut whole = 0
  for _ in 0..<rounds {
    let (pattern, _) = @fuzzgen.pattern(rng, 3, strict~)
    let expected = @string.Regex::Regex(pattern) catch { _ => continue }
    let actual = @tdfa.Regex::Regex(pattern) catch {
      _ => {
        println("PARSE DIFF \{pattern}")
        continue
      }
    }
    patterns += 1
    for _ in 0..<8 {
      let input = @fuzzgen.input(rng)
      let last_index = @fuzzgen.last_index(rng, input)
      checks += 1
      let e = expected.execute(input, last_index~)
      let a = actual.execute(input, last_index~)
      let es = match e {
        None => "no match"
        Some(m) => show([ for i in 0..<12 => m.group(i) ])
      }
      let as_ = match a {
        None => "no match"
        Some(m) => show([ for i in 0..<12 => m.group(i) ])
      }
      guard es != as_ else { continue }
      diffs += 1
      let whole_differs = match (e, a) {
        (Some(e), Some(a)) =>
          e.before().length() != a.before().length() ||
          e.content().length() != a.content().length()
        (None, None) => false
        _ => true
      }
      if whole_differs {
        whole += 1
      }
      if diffs <= 40 {
        println("DIFF /\{pattern}/ on \{input.escape()} at \{last_index}")
        println("  core: \{es}")
        println("  tdfa: \{as_}")
      }
    }
  }
  println(
    "strict=\{strict} patterns=\{patterns} checks=\{checks} diffs=\{diffs} whole_match_diffs=\{whole}",
  )
}

///|
fn main {
  run(strict=true, 150000)
  run(strict=false, 40000)
}
