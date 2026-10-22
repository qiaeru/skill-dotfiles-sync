# GitHub CLI: config.yml

The hook syncs `config.yml` from the GitHub CLI folder: aliases, editor, `git_protocol`, and the other `gh config` values. The folder differs by OS: `$GH_CONFIG_DIR` when set, otherwise `%APPDATA%\GitHub CLI` on Windows and `~/.config/gh` elsewhere. A machine without that folder skips the domain.

## Never sync hosts.yml

`hosts.yml` sits next to `config.yml` and holds the login, often with the OAuth token in clear. Refuse to add it by hand. Each machine logs in on its own with `gh auth login`.

## Leave it out

Write `*` to `.dotfiles-sync/gh/.chezmoiignore` in the source repo. The hook commits it, so no machine syncs the GitHub CLI config from then on.
