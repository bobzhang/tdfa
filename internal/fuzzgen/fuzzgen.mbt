///|
/// A small deterministic generator, so that failures can be replayed.
pub struct Rng {
  mut state : UInt32
}

///|
pub fn Rng::Rng(seed : UInt32) -> Rng {
  { state: seed, }
}

///|
/// A pseudo-random integer in `0..<bound`.
pub fn Rng::next(self : Rng, bound : Int32) -> Int32 {
  self.state = self.state * 1664525U + 1013904223U
  ((self.state >> 8).reinterpret_as_int() & 0x7fffff) % bound
}

///|
let atoms : Array[String] = [
  "a", "b", "c", "a", "b", ".", "[ab]", "[^a]", "[a-c]", "😀", "\\b", "\\B", "^",
  "$", "x", "[^😀]", "[[:alpha:]]",
]

///|
let quantifiers : Array[String] = [
  "*", "+", "?", "*?", "+?", "??", "{2}", "{1,2}", "{0,2}?", "{2,}",
]

///|
/// Generate a regex pattern. Returns the pattern and whether it can match
/// the empty string. With `strict`, no quantifier is applied to a body that
/// can match the empty string.
pub fn pattern(rng : Rng, depth : Int32, strict~ : Bool) -> (String, Bool) {
  fn atom() -> (String, Bool) {
    let a = atoms[rng.next(atoms.length())]
    (a, a is ("\\b" | "\\B" | "^" | "$"))
  }

  fn quantified(body : String, nullable : Bool) -> (String, Bool) {
    if strict && nullable {
      return (body, nullable)
    }
    let q = quantifiers[rng.next(quantifiers.length())]
    (body + q, nullable || q is ("*" | "?" | "*?" | "??" | "{0,2}?"))
  }

  match rng.next(if depth <= 0 { 3 } else { 10 }) {
    0 | 1 | 2 => atom()
    3 | 4 => {
      let (a, an) = pattern(rng, depth - 1, strict~)
      let (b, bn) = pattern(rng, depth - 1, strict~)
      (a + b, an && bn)
    }
    5 => {
      let (a, an) = pattern(rng, depth - 1, strict~)
      let (b, bn) = pattern(rng, depth - 1, strict~)
      ("(?:" + a + "|" + b + ")", an || bn)
    }
    6 => {
      let (a, an) = pattern(rng, depth - 1, strict~)
      ("(" + a + ")", an)
    }
    7 => {
      let (a, an) = pattern(rng, depth - 1, strict~)
      quantified("(?:" + a + ")", an)
    }
    8 => {
      let (a, an) = pattern(rng, depth - 1, strict~)
      quantified("(" + a + ")", an)
    }
    _ => {
      let (a, an) = atom()
      quantified(a, an)
    }
  }
}

///|
let letters : Array[String] = ["a", "b", "c", "x", " ", "😀", "a", "b", "\n"]

///|
/// Generate a short input over the alphabet the patterns use.
pub fn input(rng : Rng) -> String {
  let sb = StringBuilder()
  for _ in 0..<rng.next(9) {
    sb.write_string(letters[rng.next(letters.length())])
  }
  sb.to_string()
}

///|
/// Pick a start index for `text` that is a character boundary, `0` most of
/// the time.
pub fn last_index(rng : Rng, text : String) -> Int32 {
  guard rng.next(4) == 0 && text.length() > 0 else { 0 }
  let i = rng.next(text.length() + 1)
  if i > 0 && i < text.length() && text.code_unit_at(i).is_trailing_surrogate() {
    i - 1
  } else {
    i
  }
}
