# Configuration composition proposal

## Problem

Some applications need shared settings plus a small platform-specific override. VS Code has no native include or OS-conditional user settings, while the deployment layer currently links whole files with Stow.

## Proposed direction

Add explicit configuration composition to `dot` for declared files:

1. Load the shared configuration.
2. Load the active platform overlay.
3. Merge the overlay into the shared configuration.
4. Deploy the composed result and verify its ownership.

The first candidate is VS Code `settings.json`, with the macOS theme as the initial overlay.

## Interim decision

Do not add composition logic yet. macOS currently owns a complete copy of the VS Code settings file so it can select its theme independently; the shared copy remains theme-neutral for Omarchy and WSL. This duplication is intentional and should be replaced by composition if the platform-specific settings grow.
