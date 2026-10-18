"""Calculator integration checks, using temporary state and no desktop windows."""

import json
import os
from pathlib import Path
import shlex
import subprocess
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
PLATFORM = ROOT / "platforms/omarchy"
LAUNCHER = PLATFORM / ".local/bin/python-calculator"
CALCULATOR = PLATFORM / ".local/share/python-calculator/calculator.py"


class CalculatorTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="calculator test ")
        self.addCleanup(self.temp.cleanup)
        self.home = Path(self.temp.name)
        self.bin = self.home / "bin"
        self.bin.mkdir()
        self.log = self.home / "arguments.json"
        self.env = dict(os.environ, HOME=str(self.home),
                        XDG_DATA_HOME=str(self.home / "data with spaces"),
                        XDG_STATE_HOME=str(self.home / "state"),
                        PATH=str(self.bin) + os.pathsep + os.environ["PATH"],
                        CALCULATOR_TEST_LOG=str(self.log))

    def fake_command(self, name):
        path = self.bin / name
        path.write_text(
            f"#!{sys.executable}\n"
            "import json, os, sys\n"
            "with open(os.environ['CALCULATOR_TEST_LOG'], 'w') as log:\n"
            "    json.dump(sys.argv[1:], log)\n"
        )
        path.chmod(0o755)

    def test_launcher_uses_focus_helper_and_dedicated_app_id(self):
        self.fake_command("omarchy-launch-or-focus")
        subprocess.run([str(LAUNCHER)], env=self.env, check=True)
        pattern, command = json.loads(self.log.read_text())
        self.assertEqual(pattern, r"^local\.python\.Calculator$")
        self.assertEqual(shlex.split(command), [
            "uwsm-app", "--", "xdg-terminal-exec",
            "--app-id=local.python.Calculator", "--title=Calculator",
            "-e", str(self.home / ".local/bin/python-calculator"), "--attach",
        ])

    def test_attach_uses_isolated_persistent_tmux_and_quotes_paths(self):
        self.fake_command("tmux")
        self.fake_command("uv")
        subprocess.run([str(LAUNCHER), "--attach"], env=self.env, check=True)
        arguments = json.loads(self.log.read_text())
        data = Path(self.env["XDG_DATA_HOME"]) / "python-calculator"
        self.assertEqual(arguments[:-1], [
            "-L", "python-calculator", "-f", str(data / "tmux.conf"),
            "new-session", "-A", "-s", "calculator", "-c", str(self.home),
        ])
        self.assertEqual(shlex.split(arguments[-1]), [
            str(self.bin / "uv"), "run", "--quiet", "--locked", "--script",
            str(data / "calculator.py"),
        ])

    def test_real_ipython_has_exact_maths_units_completion_and_help(self):
        style_checks = f"""
import runpy
from types import SimpleNamespace
from unittest.mock import Mock
from prompt_toolkit.styles import Style, default_ui_style, merge_styles
configure = runpy.run_path({str(CALCULATOR)!r})['configure_completion']
configure(SimpleNamespace(pt_app=None))
shell = SimpleNamespace(pt_app=SimpleNamespace(
    style=Style.from_dict({{'unrelated': 'ansired'}}), app=Mock()))
configure(shell)
style = merge_styles([default_ui_style(), shell.pt_app.style])
for name in ('completion-menu.completion', 'completion-menu.meta.completion',
             'completion-menu.multi-column-meta'):
    attrs = style.get_attrs_for_style_str('class:' + name)
    assert attrs.color == attrs.bgcolor == 'ansidefault'
    assert not attrs.reverse
selected = style.get_attrs_for_style_str('class:completion-menu.completion.current')
assert selected.color == 'ansiblue' and selected.bgcolor == 'ansidefault'
assert selected.reverse
assert style.get_attrs_for_style_str('class:unrelated').color == 'ansired'
shell.pt_app.app.invalidate.assert_called_once()
configure_syntax = runpy.run_path({str(CALCULATOR)!r})['configure_syntax']
configure_syntax(SimpleNamespace(pt_app=None))
syntax_shell = SimpleNamespace(pt_app=SimpleNamespace(
    style=get_ipython()._style, app=Mock()))
configure_syntax(syntax_shell)
from pygments.token import STANDARD_TYPES, Token
from prompt_toolkit.styles.pygments import pygments_token_to_classname
for token in STANDARD_TYPES:
    attrs = syntax_shell.pt_app.style.get_attrs_for_style_str(
        'class:' + pygments_token_to_classname(token))
    assert attrs.color.startswith('ansi'), (token, attrs)
    assert attrs.bgcolor == 'ansidefault', (token, attrs)
for token, color in ((Token.Number.Float, 'ansigreen'),
                     (Token.String.Escape, 'ansiyellow'),
                     (Token.Keyword.Constant, 'ansimagenta'),
                     (Token.Name.Builtin, 'ansicyan'),
                     (Token.Name, 'ansidefault')):
    assert syntax_shell.pt_app.style.get_attrs_for_style_str(
        'class:' + pygments_token_to_classname(token)).color == color
syntax_shell.pt_app.app.invalidate.assert_called_once()
"""
        checks = [
            "assert sqrt(8) == 2*sqrt(2)",
            "assert sqrt(8)**2 == 8",
            "assert Rational(1, 3) + Rational(1, 6) == Rational(1, 2)",
            "assert solve(x**2 - 9, x) == [-3, 3]",
            "assert integrate(sin(x), x) == -cos(x)",
            "assert abs(u('60 mph').to('km/h').magnitude - 96.56064) < 1e-9",
            "assert math.isclose(float(N(sqrt(2), 30)), math.sqrt(2))",
            "assert np.mean([1, 2, 3]) == 2",
            "exec(\"from IPython.core.completer import provisionalcompleter\\n"
            "with provisionalcompleter():\\n"
            "    assert 'sqrt' in [c.text for c in get_ipython().Completer.completions('sq', 2)]\\n"
            "    assert 'kilometer' in [c.text for c in get_ipython().Completer.completions('u.kilome', 8)]\")",
            f"exec({style_checks!r})",
            "print('CALCULATOR_CHECKS_OK')",
        ]
        result = subprocess.run(
            ["uv", "run", "--quiet", "--locked", "--script", str(CALCULATOR)],
            input="; ".join(checks) + "\nsqrt?\nexit()\n", env=self.env,
            text=True, capture_output=True, timeout=120,
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("CALCULATOR_CHECKS_OK", result.stdout)
        self.assertNotIn("Traceback", result.stdout)
        self.assertIn("Signature:", result.stdout)
        self.assertIn("Python calculator · exact maths + units", result.stdout)
        self.assertNotIn("Tip:", result.stdout)
        self.assertTrue((Path(self.env["XDG_STATE_HOME"]) /
                         "python-calculator/ipython/profile_default/history.sqlite").exists())
        self.assertFalse((self.home / ".ipython").exists())

    def test_desktop_entry_is_searchable_and_runs_the_launcher(self):
        desktop = (PLATFORM / ".local/share/applications/python-calculator.desktop").read_text()
        self.assertIn("Name=Calculator (Python)", desktop)
        self.assertIn("Exec=python-calculator\n", desktop)
        self.assertIn("Keywords=calculator;", desktop)
        self.assertIn("Terminal=false", desktop)
        self.assertIn("StartupWMClass=local.python.Calculator", desktop)
        rules = (PLATFORM / ".config/hypr/hyprland.lua").read_text()
        for tag in ("floating-window", "terminal"):
            self.assertIn(
                'o.window("^local\\\\.python\\\\.Calculator$", { tag = "+' + tag + '" })',
                rules,
            )


if __name__ == "__main__":
    unittest.main()
