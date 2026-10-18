# Python calculator (Omarchy)

Open **Calculator (Python)** from the app launcher, or press **Super+Ctrl+Q**
(or the hardware calculator key). These bindings replace Omacalc. Repeated
launches focus the existing window rather than starting a separate calculator.
The terminal uses Omarchy's standard centered 875×600 floating-window treatment.
Its app ID is `local.python.Calculator`: a personal utility, not an official
Omarchy application. Explicit window rules retain floating and terminal tags.

Close the window normally to keep variables, imports, results, and scrollback.
Reopening attaches to the same IPython process in a dedicated tmux server.
`exit()` or Ctrl+D ends that process; the next launch starts fresh. Live state
lasts until reboot or explicitly exiting; command history remains on disk.

## Quick reference

```python
sqrt(8)                         # 2*sqrt(2), an exact symbolic expression
N(_, 20)                        # previous result, approximated to 20 digits
Rational(1, 3)                  # exact fraction (plain 1/3 is a Python float)
solve(x**2 - 9, x)               # [-3, 3]
integrate(sin(x), x)             # -cos(x)
u("60 mph").to("km/h")          # 96.56064 kilometer / hour
(5 * u.foot + 8 * u.inch).to("cm")
sqrt?                           # help; press q to leave the help pager
```

Tab completes functions and units; Ctrl+R searches command history. Completion
menus use the terminal's default foreground/background and ANSI blue selection.
Syntax highlighting also uses ANSI palette slots: green numbers, yellow strings,
magenta keywords, cyan builtins/operators, and blue function definitions. Both
follow terminal palette changes without a separate calculator theme.
Python uses
`**` for powers, not `^`. Preloaded names are SymPy's public exports, symbols
`x`, `y`, `z`, Pint's registry `u`, NumPy as `np`, and the standard `math` module.
Keep Pint quantities and SymPy expressions separate rather than mixing their
unit systems.

## Files and dependencies

The Omarchy dotfiles layer deploys:

- `~/.local/bin/python-calculator`: launch/focus and tmux attachment
- `~/.local/share/python-calculator/calculator.py`: imports, banner, IPython setup
- `~/.local/share/python-calculator/calculator.py.lock`: pinned Python dependencies
- `~/.local/share/python-calculator/tmux.conf`: isolated tmux configuration
- `~/.local/share/applications/python-calculator.desktop`: launcher entry

Requires UV, tmux, and Omarchy's terminal/launch helpers. UV installs the locked
IPython, SymPy, Pint, and NumPy dependencies into its isolated cache on first
use (internet is needed once). It does not install into system Python.
To prewarm that environment without opening a window:

```bash
uv run --quiet --locked --script ~/.local/share/python-calculator/calculator.py </dev/null
```

Calculator-specific IPython history/configuration lives in
`${XDG_STATE_HOME:-~/.local/state}/python-calculator/ipython/`; ordinary IPython
profiles are unaffected. Data files respect `XDG_DATA_HOME`. The dedicated tmux
server is named `python-calculator`, with session `calculator`, and does not
load or interfere with the normal tmux configuration.

Changes to the Python startup code or banner apply when starting a fresh session,
not when reattaching to a running one. Tests: `bash tests/calculator_test.sh`.
