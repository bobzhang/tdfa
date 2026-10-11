///|
/// Split the symbol alphabet so that every character set and every category
/// used by an assertion is a union of symbols.
fn symbolize(
  profile~ : Profile,
  symbol_map~ : @symbol_map.SymbolMap,
  pat : Pattern,
) -> Unit {
  match pat.desc {
    Char(set) => symbol_map.split(set)
    Sequence(pats) | Alternation(pats) =>
      for p in pats {
        symbolize(profile~, symbol_map~, p)
      }
    Quantifier(_, inner) | Preference(_, inner) | Capture(inner, ..) =>
      symbolize(profile~, symbol_map~, inner)
    Assertion(StartOfLine | EndOfLine) =>
      symbol_map.split(RecharSet::char('\n'))
    Assertion(StartOfWord | EndOfWord | NotWordBoundary) =>
      for split in profile.word_symbolize_splits {
        symbol_map.split(split)
      }
    Assertion(StartOfInput | EndOfInput) => ()
  }
}
