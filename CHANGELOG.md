# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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
