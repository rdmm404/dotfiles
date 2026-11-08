---
name: ui-taste
description: UI taste profile and design tokens for this user. Use when building, restyling or reviewing any UI, web app or front-end for them.
---

# UI taste

Apply this look to UIs built for this user. A project's existing design system or an explicit request takes priority.

## Steps

1. Load [`references/tokens.css`](references/tokens.css), or map its values into the project's styling system. Done when every color, size and font in the UI comes from these tokens.
2. Build to the rules below. Rules hold; change a default when the product gives a reason; decide per-project items for the project.
3. Open [`references/reference.html`](references/reference.html) to compare the result with the target look. Done when a dense screen stays easy to scan and all text sits on a flat surface.

## Principles

- **Readability first.** When style and legibility conflict, choose legibility.
- **Compact and clear.** Fit a lot on screen, as long as it stays easy to read.
- **Quiet character.** Add personality through small details, and keep novelty effects out.
- **Sparing signals.** Say each state once, in a way that doesn't rely on color alone. Keep emphasis rare enough that what needs attention stands out.

## Rules

| Element | Value |
| --- | --- |
| Theme | Catppuccin Mocha, dark |
| Background | `#181825` |
| Surfaces | `#1e1e2e`, raised `#313244` |
| Text | `#cdd6f4`, secondary `#a6adc8` |
| Lines | 1px `#313244`, with no shadows |
| Accent | Purple `#bd93f9`, with black text on fills, for actions, active states and links |
| Status colors | Success `#a6e3a1`, activity `#89dceb`, warning `#f9e2af`, problems `#f38ba8`, used for status only |
| Warning and problems | Warning means still OK but needs attention soon; problems means it has already gone wrong |
| Charts | One color per chart |
| Typeface | JetBrains Mono for everything; headings weight 700 with -0.03em tracking |
| Density | 13px text, 5px spacing unit |
| Primary buttons | Solid accent fill |
| Backgrounds | Keep text on flat, solid surfaces. A subtle texture can sit behind solid panels only |

## Defaults

- **Corners:** 1px. Anything from 0 to 2px fits.
- **Headings:** 22, 18 and 15px, with hierarchy coming from size and weight. Heading sizes are for page and section titles. Names of items in lists and tables stay at text size and use weight.
- **Terminal details:** none. Add them only on request: `> ` in the accent color before page titles and `# ` in secondary text before section headings. The last section of `references/reference.html` shows them.
- **Accent amount:** moderate.
- **Background:** plain.
- **Navigation:** top bar.
- **Small labels:** monospace.
- **Icons:** use them where they make the UI clearer, and leave them out where they would only decorate. Line icons from a single set, thin or bold.

## Decide per project

- **Navigation:** a sidebar is equally acceptable.
- **Small labels:** tracked uppercase is equally acceptable.
- **Light mode, mobile layouts, motion, illustration and copy tone:** no preference on record. Choose for the project, and show the user when they matter.

## Avoid

Gradients, glossy buttons, pixel fonts for reading, full brutalist styling, the warm-paper serif look, and alternating colors within a chart.

## Variations

The user likes variety between projects. To vary a project, keep the type, density and structure and swap color:

- **Dracula:** background `#21222c`, surfaces `#282a36` and `#343746`, text `#e6e0e9`, secondary text `#b1abb4`, lines `#3a3c4e`.
- **Rosé Pine:** background `#191724`, surfaces `#1f1d2e` and `#26233a`, text `#e0def4`, secondary text `#908caa`, lines `#403d52`.
- **Accent:** Catppuccin mauve `#cba6f7`, or green `#50fa7b`.
- **True black:** background `#000000`, surfaces `#0c0c0c` and `#181818`. Use sparingly, and pair it with something other than green.
