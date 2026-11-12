"""The flat Herdr mods use the shared design tokens, not bare numbers.

Corners, line widths, gaps, padding and text sizes must come from the tokens
in lib/herdr_flat/flat.js, which lib/herdr_flat/sync writes into each mod's
main.js between `// <flat-tokens>` markers.
Margins are left alone: the shipped code uses them for optical alignment.
A line that must keep a literal says why with `// flat: keep`.
"""
from pathlib import Path
import re
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'lib/herdr_flat/flat.js'
MODS = ROOT / 'global/.config/herdr-app/mods'
TOKENS = set(re.findall(r'^export const (\w+)', SOURCE.read_text(), re.M))
GOVERNED = re.compile(
    r'\.(gap|gap_x|gap_y|p|px|py|pt|pb|pl|pr|text_size|rounded(?:_[a-z]+)?|border(?:_[tblrxy])?)'
    r'\(([^()]*)\)')
NUMBER = re.compile(r'(?<![\w.#])(\d+(?:\.\d+)?)(?![\w.])')
FIXED_WIDTH = re.compile(r'\.border(?:_[tblrxy])?_(?:[2-9]|\d\d)\(\)')
KEEP = '// flat: keep'


def flat_mods():
    return sorted(p for p in MODS.glob('flat-*') if p.is_dir())


def violations(path):
    found = []
    where = path.relative_to(ROOT) if path.is_relative_to(ROOT) else path.name
    for no, line in enumerate(path.read_text().splitlines(), 1):
        if KEEP in line:
            continue
        for m in GOVERNED.finditer(line):
            arg = m.group(2)
            numbers = [n for n in NUMBER.findall(arg) if float(n) != 0]
            uses_token = any(re.search(rf'\b{t}\b', arg) for t in TOKENS)
            if numbers and not uses_token:
                found.append(f'{where}:{no}: {m.group(0)}')
        for m in FIXED_WIDTH.finditer(line):
            found.append(f'{where}:{no}: {m.group(0)} (lines are LINE wide)')
    return found


class FlatTokensTest(unittest.TestCase):
    def test_there_are_flat_mods(self):
        self.assertTrue(flat_mods())

    def test_every_token_block_matches_the_source(self):
        result = subprocess.run([str(ROOT / 'lib/herdr_flat/sync'), '--check'],
                                capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_style_values_come_from_tokens(self):
        found = []
        for mod in flat_mods():
            for js in sorted(mod.glob('*.js')):
                found += violations(js)
        self.assertEqual(found, [], 'bare style numbers:\n' + '\n'.join(found))

    def test_a_bare_number_is_reported(self):
        with tempfile.TemporaryDirectory() as tmp:
            probe = Path(tmp) / 'probe.js'
            probe.write_text('div().gap(8).rounded(R).px(S2).pl(S2 + 22).p(0)\n'
                             'div().rounded(6) // flat: keep\n')
            self.assertEqual([v.rsplit(': ', 1)[1] for v in violations(probe)], ['.gap(8)'])


if __name__ == '__main__':
    unittest.main()
