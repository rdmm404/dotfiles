# Phase 3 review 1

## Files Reviewed
- Phase specs: `docs/dot-cli-spec.md`, `docs/migration-plan.md`, `docs/migration-tasks.md`, `docs/migration-overview.md`
- Deployment/doctor: `lib/deploy.sh`, `lib/doctor.sh`
- Installers: `installers/macos.sh`, `installers/wsl.sh`, `installers/omarchy.sh`
- Shared configuration: `global/**`
- Platform configuration: `platforms/{macos,wsl,omarchy}/**`
- Tests and cleanup changes

## Must haves

- Ensure all new Phase 3 files are tracked before committing; the initial review saw the platform files and `tests/configuration_test.sh` only as untracked files.
- Preserve a route for the unrelated `skills/` Stow package when removing the broad Makefile deployment behavior.
- Align Omarchy installation detection with the locations that the Omarchy Zsh foundation actually loads, and fail clearly when no foundation is sourced.
- Make doctor’s canonical-path check validate canonical files and adapter targets instead of printing unconditional success.
- Use a deployed/home-resolvable Ghostty include path and test that the include works, rather than relying on repository-relative traversal and link-only assertions.

## Nice to haves

- Source only the first matching Omarchy plugin path to avoid duplicate initialization.
- Verify that `${userHome}` is supported by the VS Code custom-CSS setting.
- Assert adapter link targets, not only that they are symlinks.

## Summary

The global/platform separation was broadly sound, but the initial review was not approved due to untracked implementation files, the lost skills deployment route, inconsistent Omarchy foundation detection, an unchecked doctor success, and a Ghostty include path that was not valid from the deployed configuration.
