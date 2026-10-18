# /// script
# requires-python = ">=3.11"
# dependencies = [
#   "ipython>=9,<10",
#   "sympy>=1.14,<2",
#   "pint>=0.25,<1",
#   "numpy>=2,<3",
# ]
# ///
"""An isolated IPython calculator; run with uv run --script calculator.py."""

import math
import os
from pathlib import Path

import numpy as np
import pint
import sympy
from IPython.terminal.ipapp import TerminalIPythonApp
from prompt_toolkit.styles import Style, merge_styles
from prompt_toolkit.styles.pygments import style_from_pygments_dict
from pygments.token import STANDARD_TYPES, Token
from traitlets.config import Config


BANNER = """Python calculator · exact maths + units
sqrt(8)  ·  N(_, 20) for decimals
u("60 mph").to("km/h") for conversions
Tab: complete · sqrt?: help · Ctrl+R: history
Close window: keep state · exit(): reset"""


def calculator_namespace():
    namespace = {name: getattr(sympy, name) for name in sympy.__all__}
    namespace.update(
        math=math,
        np=np,
        u=pint.UnitRegistry(),
        **dict(zip(("x", "y", "z"), sympy.symbols("x y z"))),
    )
    return namespace


def configure_completion(shell):
    """Use the terminal palette, retaining IPython's other prompt styling."""
    if shell.pt_app is None:
        return  # Non-interactive/simple-prompt mode has no completion menu.
    normal = "bg:ansidefault fg:ansidefault noreverse"
    selected = "bg:ansidefault fg:ansiblue reverse"
    style = Style.from_dict({
        "completion-menu": normal,
        "completion-menu.completion": normal,
        "completion-menu.completion.current": selected,
        "completion-menu.meta.completion": normal,
        "completion-menu.meta.completion.current": selected,
        "completion-menu.multi-column-meta": normal,
        "scrollbar.background": normal,
        "scrollbar.button": "bg:ansiblue",
    })
    # Keep IPython's DynamicStyle in the chain so its own theme still refreshes.
    shell.pt_app.style = merge_styles([shell.pt_app.style, style])
    shell.pt_app.app.invalidate()


def configure_syntax(shell):
    """Map Python token types to ANSI slots, never fixed RGB colors."""
    if shell.pt_app is None:
        return
    token_colors = (
        (Token.Name.Function, "ansiblue"),
        (Token.Name.Class, "ansiyellow"),
        (Token.Name.Builtin, "ansicyan"),
        (Token.Name.Namespace, "ansiblue"),
        (Token.Keyword, "ansimagenta"),
        (Token.Number, "ansigreen"),
        (Token.String, "ansiyellow"),
        (Token.Comment, "ansibrightblack"),
        (Token.Operator, "ansicyan"),
        (Token.Error, "ansired"),
    )
    # Cover subtypes too: an inherited Pygments RGB rule must not win over
    # its parent token's ANSI color (e.g. String.Escape or Keyword.Constant).
    overrides = {}
    for token in STANDARD_TYPES:
        color = next((color for parent, color in token_colors if token in parent),
                     "ansidefault")
        overrides[token] = (
            f"fg:{color} bg:ansidefault nobold noitalic nounderline noreverse"
        )
    shell.pt_app.style = merge_styles([
        shell.pt_app.style, style_from_pygments_dict(overrides),
    ])
    shell.pt_app.app.invalidate()


def main():
    state_dir = Path(os.environ.get("XDG_STATE_HOME", Path.home() / ".local/state"))
    ipython_dir = state_dir / "python-calculator/ipython"
    ipython_dir.mkdir(parents=True, exist_ok=True)
    config = Config()
    config.TerminalInteractiveShell.banner1 = BANNER + "\n"
    config.TerminalInteractiveShell.banner2 = ""
    config.TerminalInteractiveShell.enable_tip = False
    config.TerminalInteractiveShell.confirm_exit = False
    # Keep calculator history, configuration, and startup files separate from IPython.
    app = TerminalIPythonApp.instance(config=config, user_ns=calculator_namespace())
    app.initialize(argv=["--ipython-dir", str(ipython_dir)])
    configure_completion(app.shell)
    configure_syntax(app.shell)
    app.start()


if __name__ == "__main__":
    main()
