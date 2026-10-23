# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- VS Code extensions sync: what one machine installs or removes follows on the others, and a new machine only gains extensions. An extension that fails to install, such as one built for another OS, is named once and skipped there.
- A project's `.mcp.json` now syncs when the project's Git does not track it.

### Changed

- The hook starts fewer processes, which shortens a sync on Windows, and skips the apply in the home folder when there is nothing to apply.

### Fixed

- A file deleted on one machine no longer comes back everywhere when the apply of that deletion fails on another: the next sync applies it instead of taking the file for a new one.
- Deleting a file whose name holds `[`, `*`, `?`, or `{`, such as `a[1].md`, no longer blocks the sync on the other machines, or deletes files there whose names match it as a pattern.
- A failed push after VS Code extension changes is now reported like any other push.

## [1.2.0] - 2026-10-23

### Added

- The Markdown files at the top of `~/.claude`, such as the ones `CLAUDE.md` imports, and the status line script now sync.
- A new file over 1 MB is left out and named once, so large files don't bloat the repo with a full encrypted copy at each edit.
- The skill covers settings and scripts that only work on one OS: absolute paths in `settings.json`, scripts added on Windows without the executable bit, and macOS-only SSH options such as `UseKeychain`.

### Fixed

- `~/.ssh` and `~/.claude` no longer land as 755 folders on Linux and macOS when the first machine runs Windows.
- `~/.claude/skills/.trash/`, and the `.git/`, `node_modules/`, `.venv/`, and editor swap or backup files inside a skill, no longer sync.
- A root renamed in the source repo, for example by `chezmoi chattr`, no longer blocks every following sync.
- The hook finds chezmoi when Claude Code starts with a minimal PATH, as an app launched from the macOS Dock does, and says so when it still cannot.
- A failed pull or push names its cause: uncommitted changes in the source repo, or a credential Git cannot ask for, instead of "offline?".

## [1.1.0] - 2026-10-22

### Added

- The setup puts the sync on hold until it is finished, so another session cannot sync a new machine before its files have been reviewed.
- The skill explains how to drop a deleted or abandoned project from the sync.

### Changed

- The setup asks every question, and lists the project files the first sync would take, before it creates the source repo.

### Fixed

- `__pycache__/`, `.DS_Store`, and `Thumbs.db` files no longer sync.
- A sync with nothing to do runs faster when projects hold many files their Git ignores, or when a home folder such as `~/.config/git` does not exist.

## [1.0.0] - 2026-10-22

### Added

- Initial release.
