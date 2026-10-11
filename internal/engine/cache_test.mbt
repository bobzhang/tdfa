///|
fn chars(lo : Char, hi : Char) -> @engine.Pattern {
  @engine.char(@engine.RecharSet::char_range(lo.to_int(), hi.to_int()))
}

///|
/// `([a-c]+)x([a-c]{1,3})|(b+)c`: enough threads and captures to make the
/// lazy DFA grow over a varied input.
fn sample_pattern() -> @engine.Pattern {
  let abc = chars('a', 'c')
  @engine.alt([
    @engine.seq([
      @engine.capture(
        @engine.quantifier(abc, { min: 1, max: None, mode: Greedy, }),
      ),
      chars('x', 'x'),
      @engine.capture(
        @engine.quantifier(abc, { min: 1, max: Some(3), mode: Greedy, }),
      ),
    ]),
    @engine.seq([
      @engine.capture(
        @engine.quantifier(chars('b', 'b'), { min: 1, max: None, mode: Greedy, }),
      ),
      chars('c', 'c'),
    ]),
  ])
}

///|
/// With a tiny cache budget the cache is dropped over and over in the middle
/// of a scan. Threads keep their registers across a flush, so results must
/// not change.
test "flushing the lazy DFA cache does not change results" {
  let roomy = @engine.compile(profile~, sample_pattern())
  let tight = @engine.compile(profile~, sample_pattern(), max_cache_words=1)
  let letters = ["a", "b", "c", "x", "y"]
  let mut seed = 7U
  let mut matches = 0
  for _ in 0..<2000 {
    let sb = StringBuilder()
    for _ in 0..<12 {
      seed = seed * 1664525U + 1013904223U
      sb.write_string(letters[((seed >> 10) % 5U).reinterpret_as_int()])
    }
    let input = sb.to_string()
    let expected = roomy.execute(input, 0)
    let actual = tight.execute(input, 0)
    if expected is Some(_) {
      matches += 1
    }
    for group in 0..<4 {
      @test.assert_eq(
        actual.map(m => m.group(group)),
        expected.map(m => m.group(group)),
      )
    }
  }
  assert_true(matches > 500)
}
