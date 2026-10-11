///|
/// A state keeps, for every thread, only the tags set on that thread's path.
/// Found in review: with one row as wide as the whole pattern per thread, a
/// wide alternation of capturing branches made a single state larger than
/// the cache budget, so the cache was dropped on every step and every step
/// rebuilt a state. 800 branches took 19 s where they now take milliseconds.
test "states of a wide capturing alternation stay small" {
  let a = char(RecharSet::char('a'))
  let b = char(RecharSet::char('b'))
  let c = char(RecharSet::char('c'))
  // `((ab)*c)`, 800 times.
  let branch = capture(
    seq([
      quantifier(capture(seq([a, b])), { min: 0, max: None, mode: Greedy, }),
      c,
    ]),
  )
  let re = compile(
    profile=oracle_profile(),
    alt(ReadOnlyArray::from_array(Array::make(800, branch))),
  )
  let input = "ab".repeat(500)
  assert_true(re.execute(input, 0) is None)
  // 800 threads, each with the start of the match and its own two groups:
  // a few thousand words, where full-width rows need 800 * 3202.
  assert_eq(re.ntags, 3202)
  for kernel in re.kernels {
    assert_true(kernel.key.length() < 16_000)
  }
  assert_true(re.cache_words < 100_000)
  // Nothing was dropped, so scanning again builds no transition.
  let built = re.epoch
  assert_true(re.execute(input, 0) is None)
  assert_eq(re.epoch, built)
}
