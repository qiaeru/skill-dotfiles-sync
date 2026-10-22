# VS Code: the user folder

The hook syncs `settings.json`, `keybindings.json`, and every file under `snippets/` from the VS Code user folder, which differs by OS:

- Windows: `%APPDATA%\Code\User`;
- macOS: `~/Library/Application Support/Code/User`;
- Linux: `~/.config/Code/User` (or `$XDG_CONFIG_HOME/Code/User`).

A machine without that folder skips the domain. VS Code Insiders and VSCodium use other folders and are not covered. Extensions, profiles, and UI state do not sync.

## VS Code's own Settings Sync

VS Code has a built-in Settings Sync, tied to a GitHub or Microsoft account, which also covers extensions. If the person already uses it, two syncs writing the same `settings.json` fight each other: ask which one to keep. Settings Sync is the better pick for someone who wants their extensions to follow; the hook keeps everything in the one encrypted repo.

## Values that differ per OS

VS Code already scopes the main per-OS settings by name (`terminal.integrated.profiles.windows`, `.linux`, `.osx`), so one shared `settings.json` usually works as is. A setting holding an absolute path (an interpreter, a font file) is the exception: say so when the first sync of a second machine shows one.

## Leave VS Code out

Write `*` to `.dotfiles-sync/vscode/.chezmoiignore` in the source repo. The hook commits it, so no machine syncs VS Code from then on; the files already synced stay on every disk.
