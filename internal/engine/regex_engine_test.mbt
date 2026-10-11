// Copyright 2026 International Digital Economy Academy
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

///|
let profile : @engine.Profile = Profile(
  valid=@engine.RecharSet::char_range(0, 0x10FFFF),
  word=@engine.RecharSet::char_range('a', 'z') +
    @engine.RecharSet::char_range('A', 'Z') +
    @engine.RecharSet::char_range('0', '9') +
    @engine.RecharSet::char('_'),
  category=c => {
    match c {
      'a'..<='z' | 'A'..<='Z' | '0'..<='9' | '_' => @engine.Category::word()
      '\n' => @engine.Category::newline()
      _ => @engine.Category::not_word()
    }
  },
)

///|
test "abc" {
  let pat = @engine.seq([
    @engine.char(@engine.RecharSet::char('a')),
    @engine.char(@engine.RecharSet::char('b')),
    @engine.char(@engine.RecharSet::char('c')),
  ])
  let re = @engine.compile(profile~, pat)
  guard re.execute("abc", 0) is Some(result) else { fail("Expected match") }
  @test.assert_eq(result.group(0), Some((0, 3)))
  @test.assert_eq(result.group(1), None)
}

///|
test "anchored start-of-input mismatch" {
  let pat = @engine.seq([
    @engine.start_of_input,
    @engine.char(@engine.RecharSet::char('a')),
  ])
  let re = @engine.compile(profile~, pat)
  assert_true(re.execute("b", 0) is None)
}

///|
test "execute with last_index and cached transitions/start-state" {
  let pat = @engine.char(@engine.RecharSet::char('a'))
  let re = @engine.compile(profile~, pat)
  guard re.execute("ba", 1) is Some(mr) else { fail("Expected match") }
  @test.assert_eq(mr.group(0), Some((1, 2)))
  // second run hits cached start state + transition
  guard re.execute("ba", 1) is Some(mr2) else { fail("Expected match") }
  @test.assert_eq(mr2.group(0), Some((1, 2)))
}

///|
test "execute with last_index and cached failure transitions" {
  let pat = @engine.char(@engine.RecharSet::char('a'))
  let re = @engine.compile(profile~, pat)
  assert_true(re.execute("bb", 1) is None)
  // second run hits cached start state + failed transition
  assert_true(re.execute("bb", 1) is None)
}

///|
test "nested stars execute repeatedly" {
  let a = @engine.char(@engine.RecharSet::char('a'))
  let inner = @engine.quantifier(a, { min: 0, max: None, mode: Greedy, })
  let outer = @engine.quantifier(inner, { min: 0, max: None, mode: Greedy, })
  let pat = @engine.seq([@engine.start_of_input, outer, @engine.end_of_input])
  let re = @engine.compile(profile~, pat)
  guard re.execute("aaa", 0) is Some(mr1) else { fail("Expected match") }
  @test.assert_eq(mr1.group(0), Some((0, 3)))
  // Repeat the same execution path to exercise cached transitions.
  guard re.execute("aaa", 0) is Some(mr2) else { fail("Expected match") }
  @test.assert_eq(mr2.group(0), Some((0, 3)))
}

///|
test "alternation compiles and matches" {
  let pat = @engine.alt([
    @engine.char(@engine.RecharSet::char('a')),
    @engine.char(@engine.RecharSet::char('b')),
  ])
  let re = @engine.compile(profile~, pat)
  guard re.execute("b", 0) is Some(mr) else { fail("Expected match") }
  @test.assert_eq(mr.group(0), Some((0, 1)))
}

///|
test "finite quantifiers greedy vs non-greedy compile" {
  let a = @engine.char(@engine.RecharSet::char('a'))
  let greedy = @engine.quantifier(a, { min: 0, max: Some(2), mode: Greedy, })
  let pat1 = @engine.seq([greedy, a])
  let re1 = @engine.compile(profile~, pat1)
  guard re1.execute("aa", 0) is Some(_mr) else { fail("Expected match") }
  let nongreedy = @engine.quantifier(a, {
    min: 0,
    max: Some(2),
    mode: NonGreedy,
  })
  let pat2 = @engine.seq([nongreedy, a])
  let re2 = @engine.compile(profile~, pat2)
  guard re2.execute("aa", 0) is Some(_mr) else { fail("Expected match") }
}

///|
test "nested sequence vs flattened sequence preserve effective-tail preference" {
  let any = @engine.char(@engine.RecharSet::char_range(0, 0x10FFFF))
  let dot = @engine.char(@engine.RecharSet::char('.'))
  let space = @engine.char(@engine.RecharSet::char(' '))
  let reluctant_any = @engine.shortest(
    @engine.quantifier(any, { min: 0, max: None, mode: Greedy, }),
  )
  let nested_pat = @engine.seq([
    @engine.seq([reluctant_any, dot]),
    @engine.epsilon,
    space,
  ])
  let flat_pat = @engine.seq([reluctant_any, dot, @engine.epsilon, space])
  let nested_re = @engine.compile(profile~, nested_pat)
  let flat_re = @engine.compile(profile~, flat_pat)
  guard nested_re.execute("abc. ", 0) is Some(nested_match) else {
    fail("Expected nested match")
  }
  guard flat_re.execute("abc. ", 0) is Some(flat_match) else {
    fail("Expected flattened match")
  }
  @test.assert_eq(nested_match.group(0), Some((0, 5)))
  @test.assert_eq(flat_match.group(0), Some((0, 5)))
}

///|
test "epsilon in sequences (translate eps optimizations)" {
  let a = @engine.char(@engine.RecharSet::char('a'))
  let pat1 = @engine.seq([
    @engine.start_of_input, a, @engine.end_of_input, @engine.epsilon,
  ])
  let re1 = @engine.compile(profile~, pat1)
  guard re1.execute("a", 0) is Some(mr1) else { fail("Expected match") }
  @test.assert_eq(mr1.group(0), Some((0, 1)))
  let pat2 = @engine.seq([
    @engine.start_of_input, @engine.epsilon, a, @engine.end_of_input,
  ])
  let re2 = @engine.compile(profile~, pat2)
  guard re2.execute("a", 0) is Some(mr2) else { fail("Expected match") }
  @test.assert_eq(mr2.group(0), Some((0, 1)))
}

///|
test "line assertions" {
  let a = @engine.char(@engine.RecharSet::char('a'))

  // StartOfLine should match after newline.
  let pat1 = @engine.seq([@engine.start_of_line, a])
  let re1 = @engine.compile(profile~, pat1)
  guard re1.execute("\na", 0) is Some(mr1) else { fail("Expected match") }
  @test.assert_eq(mr1.group(0), Some((1, 2)))

  // EndOfLine is a lookahead (needs next-cat check).
  let pat2 = @engine.seq([a, @engine.end_of_line])
  let re2 = @engine.compile(profile~, pat2)
  guard re2.execute("a\n", 0) is Some(mr2) else { fail("Expected match") }
  @test.assert_eq(mr2.group(0), Some((0, 1)))
}

///|
test "word boundary assertions" {
  let a = @engine.char(@engine.RecharSet::char('a'))
  let b = @engine.char(@engine.RecharSet::char('b'))
  let pat1 = @engine.seq([@engine.start_of_word, a])
  let re1 = @engine.compile(profile~, pat1)
  guard re1.execute("a", 0) is Some(mr1) else { fail("Expected match") }
  @test.assert_eq(mr1.group(0), Some((0, 1)))
  let pat2 = @engine.seq([a, @engine.end_of_word])
  let re2 = @engine.compile(profile~, pat2)
  guard re2.execute("a!", 0) is Some(mr2) else { fail("Expected match") }
  @test.assert_eq(mr2.group(0), Some((0, 1)))
  assert_true(re2.execute("ab", 0) is None)
  let pat3 = @engine.seq([a, @engine.not_word_boundary, b])
  let re3 = @engine.compile(profile~, pat3)
  guard re3.execute("ab", 0) is Some(mr3) else { fail("Expected match") }
  @test.assert_eq(mr3.group(0), Some((0, 2)))
}

///|
test "quantifier min > 0 uses iter step" {
  let a = @engine.char(@engine.RecharSet::char('a'))
  let pat = @engine.seq([
    @engine.start_of_input,
    @engine.quantifier(a, { min: 2, max: Some(3), mode: Greedy, }),
    @engine.end_of_input,
  ])
  let re = @engine.compile(profile~, pat)
  guard re.execute("aa", 0) is Some(mr) else { fail("Expected match") }
  @test.assert_eq(mr.group(0), Some((0, 2)))
}

///|
test "preference node triggers enforce_pref(First, k)" {
  let a = @engine.char(@engine.RecharSet::char('a'))
  let b = @engine.char(@engine.RecharSet::char('b'))
  let c = @engine.char(@engine.RecharSet::char('c'))
  let pat = @engine.seq([
    @engine.start_of_input,
    @engine.alt([@engine.shortest(@engine.seq([a, b])), @engine.seq([a, c])]),
    @engine.end_of_input,
  ])
  let re = @engine.compile(profile~, pat)
  guard re.execute("ab", 0) is Some(mr) else { fail("Expected match") }
  @test.assert_eq(mr.group(0), Some((0, 2)))
}

///|
test "Regex::group_names includes capture name" {
  let a = @engine.char(@engine.RecharSet::char('a'))
  let pat = @engine.seq([
    @engine.start_of_input,
    @engine.capture(name="x", a),
    @engine.end_of_input,
  ])
  let re = @engine.compile(profile~, pat)
  let names = re.group_names()
  @test.assert_eq(names.length(), 2)
  @test.assert_eq(names[0], None)
  @test.assert_eq(names[1], Some("x"))
}

///|
test "slot indices above 2047 keep matching" {
  // Regression: the packed state id used to reserve 11 bits for the slot, so
  // once more than 2047 positions had to be remembered at once the encoding
  // silently corrupted and the match was lost. Every start position of the
  // literal run below needs its own slot for the group-0 start mark.
  let n = 2100
  let pat = @engine.seq([
    @engine.capture(@engine.char(@engine.RecharSet::char('a'))),
    @engine.quantifier(@engine.char(@engine.RecharSet::char('a')), {
      min: n,
      max: Some(n),
      mode: Greedy,
    }),
  ])
  let re = @engine.compile(profile~, pat)
  guard re.execute("a".repeat(n + 100), 0) is Some(m) else {
    fail("Expected match")
  }
  @test.assert_eq(m.group(0), Some((0, n + 1)))
  @test.assert_eq(m.group(1), Some((0, 1)))
}
