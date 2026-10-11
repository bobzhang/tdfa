///|
/// Every capture group of a match, or `"no match"`.
fn[M] render(m : M?, group : (M, Int) -> StringView?) -> String {
  guard m is Some(m) else { "no match" }
  let sb = StringBuilder()
  for i in 0..<12 {
    match group(m, i) {
      None => sb.write_string("<none>")
      Some(v) => sb.write_string("[\{v}]")
    }
  }
  sb.to_string()
}

///|
/// Random patterns that never repeat a body able to match the empty string
/// must give the same match and the same captures as `@string.Regex`.
/// `fuzz/main.mbt` runs the same comparison at a much larger scale.
test "agrees with @string.Regex outside nullable repetitions" {
  let rng = @fuzzgen.Rng(2026U)
  let mut checks = 0
  for _ in 0..<1500 {
    let (pattern, _) = @fuzzgen.pattern(rng, 3, strict=true)
    let expected = @string.Regex::Regex(pattern) catch { _ => continue }
    let actual = @tdfa.Regex::Regex(pattern)
    for _ in 0..<6 {
      let input = @fuzzgen.input(rng)
      let last_index = @fuzzgen.last_index(rng, input)
      let e = render(expected.execute(input, last_index~), (m, i) => m.group(i))
      let a = render(actual.execute(input, last_index~), (m, i) => m.group(i))
      if e != a {
        fail(
          "/\{pattern}/ on \{input.escape()} at \{last_index}: core \{e}, tdfa \{a}",
        )
      }
      checks += 1
    }
  }
  assert_true(checks > 5000)
}
