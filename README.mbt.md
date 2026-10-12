# bobzhang/tdfa

A runtime regex engine with the same interface as `@string.Regex` from
`moonbitlang/core`, built on the algorithm the MoonBit compiler uses for
`lexmatch` and `=~`: a priority-ordered tagged NFA turned into a tagged DFA.
The compiler builds that DFA ahead of time; this package builds it lazily
while matching.

It exists so that a regex matched at run time gives the same answer as the
same regex compiled into a `lexmatch`.

> **Status: merged into `moonbitlang/core`, and deprecated here.** Since
> [moonbitlang/core#4371](https://github.com/moonbitlang/core/pull/4371)
> (merged 2026-10-11), `@string.Regex` in core runs on this engine. Use
> `@string.Regex` from a core that includes that change. This module stays
> as the place the engine was developed; 0.1.3 is the last release and
> matches what was merged.

```mbt check
///|
test "search with capture groups" {
  let re = @tdfa.Regex::unsafe_from_string("(?<user>[a-z]+)@(?<host>[a-z.]+)")
  guard re.execute("mail bob@example.com now") is Some(m) else {
    fail("expected a match")
  }
  inspect(m.content(), content="bob@example.com")
  inspect(m.before(), content="mail ")
  inspect(m.named_group("host").unwrap(), content="example.com")
}
```

## Interface

The public API is `Regex` and `MatchResult` with the methods of
`@string.Regex`: `Regex(pattern)`, `unsafe_from_string`, `string`, `execute`
(with `last_index`), `find`, `split`, `replace_by`, `capture`, `repeat`, `+`
and `|`, and `MatchResult::{content, before, after, group, named_group}`.
The pattern syntax is the same, because the parser is the one from core.

Regex literals (`re"..."`) always produce `@string.Regex`, so patterns for
this package are written as strings.

## How it works

1. **Parse.** `internal/regex_parser` (from core) turns the pattern into an
   AST over Unicode scalars; the front end lowers character sets to UTF-16
   code units, with supplementary characters as surrogate pairs.
2. **Tagged NFA.** `internal/engine/nfa.mbt` follows the compiler's
   `Regex_compile2.build_tnfa`. Alternatives are ordered by priority, greedy
   and lazy quantifiers differ only in that order, capture endpoints are tag
   nodes, and `x*` over a body that can match the empty string is built as
   `(x+)?`. An unanchored pattern gets a lazy "any code unit" loop in front,
   the same way the compiler prepares an unanchored `lexmatch` case.
3. **Lazy tagged DFA.** `internal/engine/dfa.mbt` does the compiler's subset
   construction (`Tnfa2.epsilon_closure` and `Tnfa2_to_tdfa`, `First_match`
   strategy) one transition at a time, the first time a state meets a symbol.
   Reaching the accepting node discards every lower-priority thread, which
   makes the match leftmost-first.
4. **Scan.** `Regex::execute` is a table walk: map the code unit to a symbol,
   load the next state, store the position into one register.

### Differences from the compiler's construction

- **Assertions.** The compiler supports `^` and `$` only. To add `\b` and
  `\B`, the closure of a state is taken when the next symbol is known, so a
  look-ahead is decided against that symbol and a look-behind against a small
  context kept in the state.
- **Registers.** The compiler renumbers tag versions densely on every state,
  which keeps the generated code small but needs register copies. Here a
  thread keeps its registers while it lives. All tags set by one transition
  have the same value, so a transition writes at most one register and never
  copies. Two states that only differ in which registers they name are
  therefore two states, where the compiler has one. While the cache has room
  both are kept; when it is full, the search enters the one it has and moves
  the register values there, and that transition is kept with its moves.
- **Match candidate.** The best match so far is part of the DFA state instead
  of being saved aside, so finding a match costs nothing extra per step.
- **No minimisation**, and a memory budget instead: when a state does not
  fit and no cached state can stand in for it, the cache is dropped and
  rebuilt on demand (see Memory below).
- **Leftmost-first only.** There is no `longest` strategy.

## Compared with `@string.Regex`

Measured against `moonbitlang/core` 0.10.15 on 2026-10-11, that is, against
the engine core used before it adopted this one. Version 0.1.2 of this
package was measured; the performance numbers below were not taken again for
0.1.3.

### Behaviour

The interface and the pattern syntax are the same. Core's own `string` test
suite (285 tests) passes when this engine is swapped into a copy of core,
on native, wasm-gc, JS and wasm.

The two engines give different answers in one situation: a quantifier that
repeats a body able to match the empty string, such as `(a*)*`, `(a|\b)+` or
`(a??){2,}`. Here this engine does what compile-time `lexmatch` and `=~` do,
so a pattern means the same whether it is compiled or run:

| pattern | input | `@string.Regex` | `lexmatch` and this package |
| --- | --- | --- | --- |
| `(((a)){0,2}?)+` | `a` | `a` | empty match at 0 |
| `([a-c]\|[^😀]{0,2}?){2,}` | `a xac` | `a xac` | `a` |
| `((a{0,2}?){0,2}?){2,}` | `aaaba` | `aaa` | empty match at 0 |

The rule behind it: an iteration that would loop back without consuming
input ends the repetition, instead of being retried in a way that consumes
more. In the fuzz runs only the matched text differed, never whether there
is a match.

Capture groups inside such a repetition differ too. `lexmatch` cannot
capture inside a repetition, so there is no compile-time answer to follow;
this engine keeps the last iteration that did something:

| pattern | input | group 1 in `@string.Regex` | group 1 here |
| --- | --- | --- | --- |
| `([ab]*)*` | `ab` | empty | `ab` |
| `(((a))?){2,}` | `aabaa` | empty | `a` |

How this was checked:

- `internal/engine/oracle_wbtest.mbt` compares the lazy DFA with a Pike-style
  reference matcher over the same NFA, which is a valid oracle for nullable
  repetitions too: 48,000 comparisons per test run on each backend.
- `lexmatch_spec_test.mbt` holds the whole-match results of compile-time
  `lexmatch` for 520 patterns on 24 inputs, mostly nullable repetitions. All
  12,480 agree.
- `fuzz/main.mbt` compares the two engines on random patterns and inputs,
  including `last_index` and every capture group. Without repetition of a
  nullable body, 1,200,000 comparisons show no difference. With it, about
  0.5% differ.
- 238 of the cases where the matched text differs were also compiled as
  `lexmatch` cases. Compile-time agreed with this engine on 237 and with
  core's on none. The remaining case is a pattern where the released
  compiler splits a surrogate pair.

Sub-pattern preferences (`longest`, `shortest`) exist in core's engine but
are not reachable from `@string.Regex`. This engine is leftmost-first
throughout, like the compiler's default strategy.

### Performance

Time of this engine divided by time of `@string.Regex` on the same workload;
below 1 is faster. Fastest batch over two runs of
`moon bench -p bobzhang/tdfa/benchmarks`, release builds, Apple M2 Ultra,
moon 0.1.20261010. The machine was busy, so read differences of a few
percent as noise.

| workload | native | wasm-gc | JS |
| --- | --- | --- | --- |
| `aa?b` at the end of 1 MB of `a` | 0.99 | 1.00 | 0.93 |
| phone numbers, 35 short lines | 0.50 | 0.70 | 0.68 |
| 38-way alternation over 20,000 file names | 0.60 | 0.71 | 0.84 |
| literal not present in 300 KB | 1.00 | 1.01 | 0.89 |
| `find` digits | 0.66 | 0.88 | 0.84 |
| `find` emails, three named groups | 0.71 | 0.92 | 0.87 |
| `find` words with `\b` | 0.69 | 0.91 | 0.85 |
| `find` with lazy `.*?` | 0.82 | 0.94 | 0.98 |
| anchored prefix over 20,000 file names | 0.51 | 0.70 | 0.71 |
| `split` | 0.67 | 0.91 | 0.85 |
| `replace_by` | 0.63 | 0.83 | 0.82 |
| `find` runs of non-ASCII | 0.95 | 0.95 | 0.95 |
| compile and first match, email pattern | 0.56 | 0.67 | 0.69 |
| compile and first match, 38-way alternation | 0.68 | 0.65 | 0.69 |

Long scans are at parity because both engines run the same inner loop: one
symbol lookup, one table load, one store. The gains come from cheaper
matches (the match is part of the state, nothing is copied when one is
found), fewer allocations per `execute`, and a cheaper first use.

A small program that builds one regex and calls `find` and `replace_by`
compiles to 75.3 KB with this package and 81.8 KB with `@string.Regex` on
wasm-gc, and 251 KB against 303 KB on JS (release builds).

### Memory

The lazy DFA is a cache with a budget of 16 million machine words (64 MB) of
table and state data, plus up to as much again for register moves. The
engine core used before never dropped its cache, so its memory grew with the
number of DFA states.

- A state stores, per live match attempt, only the tags set on that
  attempt's path, so a state is as large as its attempts need and not as wide
  as the pattern. (Up to 0.1.2 every attempt had a row as wide as the whole
  pattern; 800 alternatives with two groups each made one state larger than
  the budget and every step rebuilt it.)
- When the cache is full and holds a state that only differs from the new
  one in the names of its registers, the search enters that state and moves
  the register values. The cache is only dropped for a state it has no such
  copy of.

What does not fit the budget is rebuilt, which is slower than a cached step.
On `(?:a{241}){12}b` against a run of `a`, 2,892 match attempts are alive at
once and the budget leaves room for one copy of the steady state, so every
character moves 2,892 registers: 4 µs per character, where the previous
engine of core took 1.4 ns per character and several GB. A pattern that
needs more states than the budget holds before it reaches a steady state,
such as `(?:a{250}){20}b`, rebuilds them on every search. A long run of
capture groups makes every attempt carry every group it has passed, and
those states are 1.6 to 2.6 times slower to build than in the previous
engine.

## Layout

- `regex*.mbt`: the public `Regex` front end, adapted from core.
- `internal/engine`: the tagged NFA and lazy tagged DFA.
- `internal/regex_parser`, `internal/ast`, `internal/shared_types`,
  `internal/rechar_set`, `internal/symbol_map`: copied from
  `moonbitlang/core`, where they are internal packages.
- `internal/fuzzgen`, `fuzz`: random pattern generator and differential
  fuzzer against core.
- `scripts/generate_lexmatch_cases.py`: regenerates `lexmatch_spec_test.mbt`
  from the installed toolchain.
- `benchmarks`: paired benchmarks against `@string.Regex`.

## Commands

```bash
moon test
```

```bash
moon run fuzz --target native
```

```bash
moon bench -p bobzhang/tdfa/benchmarks --target native
```
