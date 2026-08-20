# Dotfiles migration plan

## Working rules

Every phase must leave the repository usable. WSL keeps working until the Omarchy machine is ready, and unrelated repository changes stay untouched.

Prefer test-driven development for every public behavior:

1. Write a small failing command or filesystem test.
2. Make it pass with the smallest useful change.
3. Run the full fast test suite.
4. Clean up while the tests stay green.

Avoid unit-testing private functions. Test `dot` through its public commands, temporary home directories, real Stow, and fake package-manager commands. Use real machines and the Omarchy VM only for checks that cannot be faked safely.

## Code & testing thoroughness

Follow the green thread: plan, confirm, change, and verify. Keep the code and tests focused on the main supported path and the important safety rules. We do not need tests for every possible combination of unusual inputs, timing, or hostile filesystem changes. Add more edge-case coverage when a real bug, a requirement, or a supported use case needs it.

## Phase 1: Build the foundation

### Work

- Add a small Bash test runner, temporary-home helpers, and recording package-manager fakes.
- Add failing command-level tests for manifests, platform selection, planning, and install choices.
- Add the root-level `dot` command.
- Add focused modules under `lib/`.
- Add platform installers for macOS, WSL, and Omarchy.
- Add universal `core`, `development`, and `optional` manifests.
- Implement platform detection, plans, prompts, and clear output until the tests pass.
- Add Bash/Zsh syntax checks, ShellCheck, config parsing, link checks, and absolute-path checks.

### Keep out

- Do not move current configuration yet.
- Do not install anything during development without an explicit test.

### Done when

- `dot help`, `doctor`, `plan`, and install planning work.
- Manifest errors are clear.
- Tests run without touching the real home directory.

## Phase 2: Add safe deployment

### Work

- Add failing fake-home tests for clean and repeated deployment.
- Add failing tests for conflict refusal and safe legacy-link replacement.
- Add failing tests for adoption, restore, cleanup, and undeploy.
- Implement deployment of `global/` (including tracked agent skills) followed by the current platform until the tests pass.
- Detect all target conflicts before changing anything.
- Implement `deploy --adopt` with timestamped backups.
- Implement backup list, restore, remove, and prune commands.
- Implement `undeploy`.
- Add failure-path coverage that proves no partial changes are left behind.

### Done when

- A failed preflight leaves the target unchanged.
- Repeated deployment makes no unnecessary changes.
- Every adopted file has a restorable backup.
- Undeploy removes only repository-owned links.

## Phase 3: Restructure the existing configuration

### Work

- Create `global/` and the three platform layers.
- Move shared Zsh aliases, exports, and functions into `global/`.
- Keep Zap foundations in macOS and WSL.
- Add an Omarchy foundation based on `omarchy-zsh`.
- Move WSL-only, macOS-only, and local settings out of shared files.
- Remove broken or duplicated aliases and plugin setup.
- Preserve the fnm-based Pi wrapper only on macOS and WSL.
- Move Starship to the shared layer.
- Keep shared VS Code settings theme-neutral, with a temporary complete macOS copy for its platform-owned theme; remove the Poetry virtualenv path.
- Make RTK configuration canonical with platform path adapters.
- Preserve VS Code custom CSS.
- Prepare Ghostty so Omarchy can own its theme and font.
- Remove the old package directories and Makefile only after the new deployment works.

### Done when

- The fake-home target has the expected paths for every platform.
- Shared files contain no hard-coded WSL, macOS, username, or home paths.
- Current behavior still works on WSL.

## Phase 4: Validate existing systems

### WSL

- Run doctor and plan.
- Adopt the current files through the safe backup flow.
- Start a clean Zsh session.
- Check Starship, zoxide, FZF, aliases, RTK, and the Pi wrapper.
- Repeat bootstrap and confirm there is no unnecessary work.

### macOS

- Test on at least one Mac before deploying to both.
- Check Zap and the retained plugins.
- Check VS Code platform settings and RTK path adapters.
- Check Homebrew application detection.
- Verify deploy, backup, restore, and undeploy behavior.

### Done when

- Shell and fake-home tests pass.
- WSL passes its smoke test.
- At least one Mac passes its smoke test.

## Phase 5: Test Omarchy in a VM

### Setup

- Install the released Omarchy 4 image in a disposable VM.
- Clone this repository.
- Run `dot doctor`, `plan`, and `bootstrap`.
- Resolve any unsupported package names through Omarchy's supported commands.

### Shell checks

- Install and use `omarchy-zsh`.
- Verify Omarchy commands and completions.
- Verify autosuggestions, autopair, history substring search, and `git-open`.
- Confirm Omarchy owns FZF, eza, zoxide, Starship startup, and syntax highlighting.
- Confirm Zsh starts without errors.

### Desktop checks

- Install and select Ghostty through Omarchy.
- Install VS Code through Omarchy.
- Let Omarchy control fonts and application colors.
- Confirm the existing Starship prompt renders correctly.
- Confirm VS Code custom CSS still works.
- Compare available Dracula themes, then choose whether to use, pin, or fork one.

### Configuration capture

- Customize Hyprland and Omarchy normally in the VM.
- Review the changed user-owned files.
- Manually add only intentional configuration to `platforms/omarchy/`.
- Include Hyprland, Omarchy shell, terminal selection, theme, hooks, or XCompose only when deliberately changed.
- Run another deploy and ensure the live links behave correctly.

### Acceptance checklist

- Omarchy boots normally.
- Its updater and menu still work.
- Zsh and Omarchy shell features work together.
- Ghostty and VS Code launch correctly.
- Theme and font changes work through Omarchy.
- VS Code custom CSS remains active.
- A second bootstrap is clean.
- Doctor reports no unexpected errors.
- Adoption, restore, and undeploy work in the VM.

## Phase 6: Move to the physical machine

### Work

- Back up important personal data separately.
- Install Omarchy 4 on the physical machine.
- Clone the repository and run doctor and plan first.
- Run bootstrap only after reviewing the plan.
- Apply the tested Omarchy configuration.
- Reauthenticate GitHub, SSH, cloud tools, and other services manually.
- Compare the machine against the VM checklist.

### Done when

- The physical machine passes the same checks as the VM.
- No secret-transfer helper is needed.
- The WSL machine and Macs still use their correct platform layers.

## Later, only if needed

- VS Code extension installation
- Pi installation
- More GUI applications
- More Omarchy machines and machine-specific layers
- Automatic Omarchy configuration capture
- Explicit application upgrade commands
