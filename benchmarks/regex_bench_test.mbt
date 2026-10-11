///|
/// Inputs shared by the paired benchmarks.
let one_mb : String = "a".repeat(1024 * 1024 - 1) + "b"

///|
let phone_lines : Array[String] = [
  "datafile for regex matching of phone numbers test", "", "the following numbers should match:",
  "", "(111) 111 1111", "111 222-2222", "(111) 333-3333", "111 444 4444", "", "foo (111) 555 5555",
  "foo 111 666-6666", "foo (111) 777-7777", "foo 111 888 8888", "", "foo (111) 999 9999 bar",
  "foo 111 000-0000 bar", "foo (111) 232-1111 bar", "foo 111 242 1111 bar", "", "The following should fail to match:",
  "", "2(212) 222 2222", "2232 222-2222", "(242) 222-22222", "2252 222 2222", "",
  "foo (262) 2222222", "foo 272 2222222", "foo (282) 222-22227", "foo 292 222 22222",
  "", "foo (202).222 2222 bar", "foo 211@22222222 bar", "foo (213 222-2222 bar",
  "foo 214) 222 2222 bar",
]

///|
fn padded3(i : Int) -> String {
  "\{i}".pad_start(3, '0')
}

///|
let large_pattern : String = {
  let parts = Array()
  for i in 0..<38 {
    let idx = padded3(i)
    parts.push(".*(?:src_\{idx}|tmp_\{idx}|cache_\{idx})\\.(?:log|tmp|cache)$")
  }
  parts.join("|")
}

///|
let filenames : Array[String] = {
  let filenames = Array(capacity=20_000)
  for i in 0..<20_000 {
    if i % 5 == 0 {
      let idx = padded3(i % 38)
      let stem = if i % 3 == 0 {
        "src"
      } else if i % 3 == 1 {
        "tmp"
      } else {
        "cache"
      }
      let ext = if i % 3 == 0 {
        "log"
      } else if i % 3 == 1 {
        "tmp"
      } else {
        "cache"
      }
      filenames.push("repo/subdir/\{stem}_\{idx}.\{ext}")
    } else {
      filenames.push("repo/subdir/other_\{i}.txt")
    }
  }
  filenames
}

///|
/// About 300KB of prose-like text with numbers, emails and a few emoji.
let prose : String = {
  let sb = StringBuilder()
  for i in 0..<4000 {
    sb.write_string(
      "The quick brown fox \{i} jumps over the lazy dog; contact user\{i}@example.com or call 555-\{1000 + i % 9000}. ",
    )
    if i % 50 == 0 {
      sb.write_string("😀 unicode line 你好 \n")
    }
  }
  sb.to_string()
}

///|
let email_pattern : String = "(?<user>[a-zA-Z0-9_.+\\-]+)@(?<domain>[a-zA-Z0-9\\-]+)\\.(?<tld>[a-z]+)"

///|
test "aa?b on 1MB / core" (it : @bench.T) {
  let re = @string.Regex::unsafe_from_string("aa?b")
  it.bench(() => re.execute(one_mb) |> ignore)
}

///|
test "aa?b on 1MB / tdfa" (it : @bench.T) {
  let re = @tdfa.Regex::unsafe_from_string("aa?b")
  it.bench(() => re.execute(one_mb) |> ignore)
}

///|
test "phone lines / core" (it : @bench.T) {
  let re = @string.Regex::unsafe_from_string(
    "([(][0-9]{3}[)]|[0-9]{3}) [0-9]{3}[ \\-][0-9]{4}",
  )
  it.bench(() => {
    for line in phone_lines {
      re.execute(line) |> ignore
    }
  })
}

///|
test "phone lines / tdfa" (it : @bench.T) {
  let re = @tdfa.Regex::unsafe_from_string(
    "([(][0-9]{3}[)]|[0-9]{3}) [0-9]{3}[ \\-][0-9]{4}",
  )
  it.bench(() => {
    for line in phone_lines {
      re.execute(line) |> ignore
    }
  })
}

///|
test "large pattern / core" (it : @bench.T) {
  let re = @string.Regex::unsafe_from_string(large_pattern)
  it.bench(() => {
    for filename in filenames {
      re.execute(filename) |> ignore
    }
  })
}

///|
test "large pattern / tdfa" (it : @bench.T) {
  let re = @tdfa.Regex::unsafe_from_string(large_pattern)
  it.bench(() => {
    for filename in filenames {
      re.execute(filename) |> ignore
    }
  })
}

///|
test "literal miss in prose / core" (it : @bench.T) {
  let re = @string.Regex::unsafe_from_string("needle in haystack")
  it.bench(() => re.execute(prose) |> ignore)
}

///|
test "literal miss in prose / tdfa" (it : @bench.T) {
  let re = @tdfa.Regex::unsafe_from_string("needle in haystack")
  it.bench(() => re.execute(prose) |> ignore)
}

///|
test "find digits / core" (it : @bench.T) {
  let re = @string.Regex::unsafe_from_string("[[:digit:]]+")
  it.bench(() => {
    let mut n = 0
    for m in re.find(prose) {
      n += m.content().length()
    }
    ignore(n)
  })
}

///|
test "find digits / tdfa" (it : @bench.T) {
  let re = @tdfa.Regex::unsafe_from_string("[[:digit:]]+")
  it.bench(() => {
    let mut n = 0
    for m in re.find(prose) {
      n += m.content().length()
    }
    ignore(n)
  })
}

///|
test "find emails with groups / core" (it : @bench.T) {
  let re = @string.Regex::unsafe_from_string(email_pattern)
  it.bench(() => {
    let mut n = 0
    for m in re.find(prose) {
      n += m.named_group("domain").unwrap().length()
    }
    ignore(n)
  })
}

///|
test "find emails with groups / tdfa" (it : @bench.T) {
  let re = @tdfa.Regex::unsafe_from_string(email_pattern)
  it.bench(() => {
    let mut n = 0
    for m in re.find(prose) {
      n += m.named_group("domain").unwrap().length()
    }
    ignore(n)
  })
}

///|
test "find words alternation / core" (it : @bench.T) {
  let re = @string.Regex::unsafe_from_string(
    "\\b(?:fox|dog|call|user[0-9]+)\\b",
  )
  it.bench(() => {
    let mut n = 0
    for m in re.find(prose) {
      n += m.content().length()
    }
    ignore(n)
  })
}

///|
test "find words alternation / tdfa" (it : @bench.T) {
  let re = @tdfa.Regex::unsafe_from_string("\\b(?:fox|dog|call|user[0-9]+)\\b")
  it.bench(() => {
    let mut n = 0
    for m in re.find(prose) {
      n += m.content().length()
    }
    ignore(n)
  })
}

///|
test "lazy dot star / core" (it : @bench.T) {
  let re = @string.Regex::unsafe_from_string("quick.*?lazy")
  it.bench(() => {
    let mut n = 0
    for m in re.find(prose) {
      n += m.content().length()
    }
    ignore(n)
  })
}

///|
test "lazy dot star / tdfa" (it : @bench.T) {
  let re = @tdfa.Regex::unsafe_from_string("quick.*?lazy")
  it.bench(() => {
    let mut n = 0
    for m in re.find(prose) {
      n += m.content().length()
    }
    ignore(n)
  })
}

///|
test "anchored short / core" (it : @bench.T) {
  let re = @string.Regex::unsafe_from_string("^[a-z]+/[a-z]+/")
  it.bench(() => {
    for filename in filenames {
      re.execute(filename) |> ignore
    }
  })
}

///|
test "anchored short / tdfa" (it : @bench.T) {
  let re = @tdfa.Regex::unsafe_from_string("^[a-z]+/[a-z]+/")
  it.bench(() => {
    for filename in filenames {
      re.execute(filename) |> ignore
    }
  })
}

///|
test "split on punctuation / core" (it : @bench.T) {
  let re = @string.Regex::unsafe_from_string("[;,.] ?")
  it.bench(() => {
    let mut n = 0
    for part in re.split(prose) {
      n += part.length()
    }
    ignore(n)
  })
}

///|
test "split on punctuation / tdfa" (it : @bench.T) {
  let re = @tdfa.Regex::unsafe_from_string("[;,.] ?")
  it.bench(() => {
    let mut n = 0
    for part in re.split(prose) {
      n += part.length()
    }
    ignore(n)
  })
}

///|
test "replace digits / core" (it : @bench.T) {
  let re = @string.Regex::unsafe_from_string("[0-9]+")
  it.bench(() => re.replace_by(prose, _m => "#") |> ignore)
}

///|
test "replace digits / tdfa" (it : @bench.T) {
  let re = @tdfa.Regex::unsafe_from_string("[0-9]+")
  it.bench(() => re.replace_by(prose, _m => "#") |> ignore)
}

///|
test "unicode class / core" (it : @bench.T) {
  let re = @string.Regex::unsafe_from_string("[^ -~]+")
  it.bench(() => {
    let mut n = 0
    for m in re.find(prose) {
      n += m.content().length()
    }
    ignore(n)
  })
}

///|
test "unicode class / tdfa" (it : @bench.T) {
  let re = @tdfa.Regex::unsafe_from_string("[^ -~]+")
  it.bench(() => {
    let mut n = 0
    for m in re.find(prose) {
      n += m.content().length()
    }
    ignore(n)
  })
}

///|
test "cold compile and match email / core" (it : @bench.T) {
  let line = "contact user42@example.com or call 555-1042"
  it.bench(() => {
    let re = @string.Regex::unsafe_from_string(email_pattern)
    re.execute(line) |> ignore
  })
}

///|
test "cold compile large pattern / core" (it : @bench.T) {
  it.bench(() => {
    let re = @string.Regex::unsafe_from_string(large_pattern)
    re.execute(filenames[0]) |> ignore
  })
}

///|
test "cold compile and match email / tdfa" (it : @bench.T) {
  let line = "contact user42@example.com or call 555-1042"
  it.bench(() => {
    let re = @tdfa.Regex::unsafe_from_string(email_pattern)
    re.execute(line) |> ignore
  })
}

///|
test "cold compile large pattern / tdfa" (it : @bench.T) {
  it.bench(() => {
    let re = @tdfa.Regex::unsafe_from_string(large_pattern)
    re.execute(filenames[0]) |> ignore
  })
}
