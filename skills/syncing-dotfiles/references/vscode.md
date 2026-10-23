# VS Code: the user folder

The hook syncs `settings.json`, `keybindings.json`, and every file under `snippets/` from the VS Code user folder, which differs by OS:

- Windows: `%APPDATA%\Code\User`;
- macOS: `~/Library/Application Support/Code/User`;
- Linux: `~/.config/Code/User` (or `$XDG_CONFIG_HOME/Code/User`).

A machine without that folder skips the domain. VS Code Insiders and VSCodium use other folders and are not covered. Profiles and UI state do not sync.

## Extensions

The installed extensions sync too, through the `code` command, which must be on the PATH (on macOS, run "Shell Command: Install 'code' command in PATH" from VS Code's command palette). A machine without it skips extensions and syncs the rest.

Each machine publishes the list it has installed, encrypted, to `.dotfiles-sync/vscode-extensions/<hostname>.age`, with a `-<id>` line for each extension it removed, and never writes another machine's file, so extensions never raise a conflict. After the push, the hook installs what another machine added since this one last read its list, and uninstalls what it removed. The first time a machine reads another one's list, it only installs: nothing goes away on a new machine. A list is read only when a pull changed it, and the hook runs `code --list-extensions` (about a second) only when VS Code's `extensions.json` changed since the last listing.

- An extension that fails to install, often one built for another OS, is named once and skipped on that machine from then on. To retry it, delete its line from `$src/.git/dotfiles-sync-extensions/failed`.
- Two machines with the same hostname would share one file: set `DOTFILES_SYNC_HOST` to a distinct name on one of them, in the environment Claude Code starts with.
- A machine that leaves for good keeps its file in the repo, which the others ignore once they have read it; delete `.dotfiles-sync/vscode-extensions/<hostname>.age` and sync to drop it.

## VS Code's own Settings Sync

VS Code has a built-in Settings Sync, tied to a GitHub or Microsoft account. With the hook syncing settings and extensions, it is redundant: two syncs writing the same `settings.json` or the same extensions fight each other. If the person already uses it, ask which one to keep, and turn off the overlapping kinds in the other.

## Values that differ per OS

VS Code already scopes the main per-OS settings by name (`terminal.integrated.profiles.windows`, `.linux`, `.osx`), so one shared `settings.json` usually works as is. A setting holding an absolute path (an interpreter, a font file) is the exception: say so when the first sync of a second machine shows one.

## Leave VS Code out

Write `*` to `.dotfiles-sync/vscode/.chezmoiignore` in the source repo. The hook commits it, so no machine syncs VS Code from then on, extensions included; the files already synced stay on every disk. To keep the files but leave the extensions out, write a line `extensions` there instead.
