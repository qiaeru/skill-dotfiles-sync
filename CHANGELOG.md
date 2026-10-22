# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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
