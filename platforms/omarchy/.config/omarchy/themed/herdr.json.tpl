{
  "background": "{{ background }}",
  "foreground": "{{ foreground }}",
  "selection": "{{ mix background accent 30% }}",
  "cursor": "{{ cursor }}",
  "ansi": [
    "{{ background }}", "{{ red }}", "{{ green }}", "{{ yellow }}",
    "{{ blue }}", "{{ magenta }}", "{{ cyan }}", "{{ foreground }}",
    "{{ muted }}", "{{ bright_red }}", "{{ bright_green }}", "{{ bright_yellow }}",
    "{{ bright_blue }}", "{{ bright_magenta }}", "{{ bright_cyan }}", "{{ bright_foreground }}"
  ],
  "colors": {
    "canvas": "{{ dark_background }}",
    "chrome": "{{ dark_background }}",
    "raised": "{{ lighter_background }}",
    "border": "{{ lighter_background }}",
    "accent": "{{ accent }}",
    "accent_foreground": "{{ background }}",
    "muted": "{{ dark_foreground }}",
    "dim": "{{ mix muted dark_foreground 50% }}"
  }
}
