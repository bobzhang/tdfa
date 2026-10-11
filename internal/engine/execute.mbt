///|
/// Capture offsets of a successful match: `[start0, end0, start1, end1, ...]`
/// relative to the searched view, `-1` for groups that did not participate.
struct MatchResult(Array[Int]) derive(@debug.Debug)

///|
#deprecated("Use `Debug::to_repr` instead", skip_current_package=true)
#doc(hidden)
pub extend MatchResult with @debug.Debug::{to_repr}

///|
pub fn MatchResult::group(self : MatchResult, index : Int) -> (Int, Int)? {
  // Validate before multiplying so large indices cannot wrap into a group.
  guard index >= 0 && index < self.0.length() / 2 else { None }
  let start = self.0[index * 2]
  let end = self.0[index * 2 + 1]
  guard start >= 0 && end >= 0 else { None }
  Some((start, end))
}

///|
/// Search `input` for the leftmost-first match starting at or after
/// `last_index`.
pub fn Regex::execute(
  self : Regex,
  input : StringView,
  last_index : Int,
) -> MatchResult? {
  guard last_index >= 0 && last_index <= input.length() else { panic() }
  let table = self.table
  let data = input.data()
  let shift = input.start_offset()
  let end = shift + input.length()
  let ctx = if last_index == 0 {
    self.ctx_start
  } else {
    self.sym_ctx[table.map(input.unsafe_get(last_index - 1).to_int())]
  }
  let mut base = self.start_base(ctx)
  let mut trans = self.trans
  let mut slots = self.slots
  let mut regs = self.regs
  let mut pos = shift + last_index
  // A negative `stop` is the table entry that ended the scan.
  let mut stop = 0
  while pos < end {
    let index = base + table.map(data.unsafe_get(pos).to_int())
    let mut next = trans.unsafe_get(index)
    if next < 0 {
      // Off the fast path: an unbuilt transition, or the end of the scan.
      if next == UNKNOWN {
        next = self.build(base, index - base, pos)
        trans = self.trans
        slots = self.slots
        regs = self.regs
        regs.unsafe_set(self.built_slot, pos)
        if next >= 0 {
          base = next
          pos += 1
          continue
        }
      } else {
        regs.unsafe_set(slots.unsafe_get(index), pos)
      }
      stop = next
      break
    }
    regs.unsafe_set(slots.unsafe_get(index), pos)
    base = next
    pos += 1
  }
  if stop == 0 {
    let index = base + self.nsym
    stop = trans.unsafe_get(index)
    if stop == UNKNOWN {
      stop = self.build(base, self.nsym, pos)
      regs = self.regs
      regs.unsafe_set(self.built_slot, pos)
    } else {
      regs.unsafe_set(slots.unsafe_get(index), pos)
    }
  }
  guard stop != DEAD else { None }
  // A terminal state has no threads, only the row of the match: its length
  // and then `(tag, register)` pairs.
  let key = self.kernels[terminal_state(stop)].key
  let result = Array::make(self.ntags, -1)
  for i in 0..<key[2] {
    result[key[3 + 2 * i]] = regs[key[4 + 2 * i]] - shift
  }
  Some(MatchResult(result))
}
