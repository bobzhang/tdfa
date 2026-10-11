"""Regenerate lexmatch_spec_test.mbt from the installed MoonBit toolchain.

Generates patterns (mostly repetitions of nullable bodies), compiles each one
as a `lexmatch` case, runs them on a fixed set of inputs, and writes the
results as test data. Run from the repository root:

    python3 scripts/generate_lexmatch_cases.py

The generated patterns avoid what `lexmatch` literals reject (`\\b`, `\\B`,
named groups) and negated classes over supplementary characters.
"""
import json
import pathlib
import random
import re
import subprocess
import tempfile

r = random.Random(207391)
QUANTIFIERS = ['*', '*?', '+', '+?', '?', '??', '{0,2}', '{0,2}?', '{2,}', '{2,3}?']


def pattern(depth):
    if depth == 0:
        return r.choice(['a', 'b', '[ab]', '.', '^', '$', '(?:)'])
    kind = r.randrange(6)
    if kind == 0:
        return pattern(0)
    if kind == 1:
        return '(?:' + pattern(depth - 1) + pattern(depth - 1) + ')'
    if kind == 2:
        return '(?:' + pattern(depth - 1) + '|' + pattern(depth - 1) + ')'
    return '(?:' + pattern(depth - 1) + ')' + r.choice(QUANTIFIERS)


patterns = ['(?:a*)*', '(?:a??)+', '(?:(?:a{0,2}?){0,2}?){2,}', '(?:$)*', '(?:$)+',
            '(?:$){2}', '(?:a|$)+', 'a$^', '(?:^|a)*']
while len(patterns) < 520:
    p = pattern(3)
    # Force a nullable body under a repetition in half of the cases.
    if len(patterns) % 2 == 0:
        p = '(?:' + p + '|)' + r.choice(['*', '+', '{2,}', '*?', '{0,3}?'])
    if p not in patterns:
        patterns.append(p)

inputs = ['', 'a', 'b', 'aa', 'ab', 'ba', 'aab', 'aba', 'bbb', 'aaaba', 'ababa', '\n', 'a\nb', ' xaa']
inputs += [''.join(r.choice('ab x\n') for _ in range(r.randrange(15))) for _ in range(10)]


def q(s):
    return json.dumps(s, ensure_ascii=False)


source = []
for i, p in enumerate(patterns):
    source.append(
        f'fn case_{i}(s : String) -> (Int, Int) {{\n'
        f'  lexmatch s {{\n'
        f'    (re{q(p)} as m, before=b, after=_) => (b.length(), m.length())\n'
        f'    _ => (-1, -1)\n'
        f'  }}\n'
        f'}}')
source.append('fn main {\n  let inputs = [' + ', '.join(map(q, inputs)) + ']')
for i in range(len(patterns)):
    source.append(f'  for s in inputs {{ let x = case_{i}(s); println("\\{{x.0}},\\{{x.1}}") }}')
source.append('}')

with tempfile.TemporaryDirectory() as tmp:
    path = pathlib.Path(tmp) / 'lexmatch_cases.mbt'
    path.write_text('\n'.join(source))
    proc = subprocess.run(['moon', 'run', str(path)], capture_output=True, text=True, timeout=600)
if proc.returncode:
    raise SystemExit(proc.stderr[-10000:])
results = [line for line in proc.stdout.splitlines() if re.fullmatch(r'-?\d+,-?\d+', line)]
assert len(results) == len(patterns) * len(inputs), (len(results), len(patterns) * len(inputs))
version = subprocess.run(['moon', 'version'], capture_output=True, text=True).stdout.split('\n')[0]
version = version.split(' (')[0]

n = len(inputs)
test = pathlib.Path('lexmatch_spec_test.mbt')
old = test.read_text()
head = old[:old.index('let lexmatch_inputs')]
head = re.sub(r'with moon \S+ \(', f'with {version} (', head)
tail = old[old.index('///|\ntest "whole matches agree'):]
tail = re.sub(r'assert_eq\(checks, \d+\)', f'assert_eq(checks, {len(results)})', tail)
out = [head + 'let lexmatch_inputs : Array[String] = [']
out.append('  ' + ', '.join(q(i) for i in inputs) + ',')
out.append(']\n\n///|\nlet lexmatch_cases : Array[(String, String)] = [')
for i, p in enumerate(patterns):
    row = ' '.join('-' if x == '-1,-1' else x for x in results[i * n:(i + 1) * n])
    out.append(f'  ({q(p)}, "{row}"),')
out.append(']\n')
test.write_text('\n'.join(out) + '\n' + tail)
subprocess.run(['moon', 'fmt'], check=False)
print(f'{len(results)} comparisons ({len(patterns)} patterns x {n} inputs) with {version}')
