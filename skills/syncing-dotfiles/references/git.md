# Git: ~/.gitconfig and ~/.config/git

The hook syncs `~/.gitconfig` and, under `~/.config/git/`, the `config`, `ignore` (global gitignore), and `attributes` files. A file elsewhere, such as `~/.git-credentials`, never syncs: it holds tokens in clear and belongs to one machine's credential helper. Refuse to add it.

## Values that differ per machine

A shared `~/.gitconfig` usually holds a few values that must not travel:

- `core.autocrlf` (`true` on Windows, `input` or unset elsewhere);
- `credential.helper` (`manager` on Windows, `osxkeychain` on macOS, `libsecret` or `cache` on Linux);
- `user.signingkey` and `gpg.program` when each machine signs with its own key;
- `core.sshCommand` or paths that point into a given machine's file system.

Prefer a local include over a template. It keeps the shared file captured by the hook, while a template needs `chezmoi edit` for every change:

1. Move the machine-specific values to `~/.gitconfig.local`, which is outside the allow-list and so never syncs.
2. Add to the end of `~/.gitconfig`, so the local values win:

   ```ini
   [include]
     path = ~/.gitconfig.local
   ```

3. On every other machine, create its own `~/.gitconfig.local`. Git silently skips a missing include, so a machine without one still works.

Use a chezmoi template only when the person wants one file that computes its values from the OS (`chezmoi chattr +template ~/.gitconfig`, then `chezmoi edit ~/.gitconfig` with `{{ if eq .chezmoi.os "windows" }}` blocks). Tell them that later edits go through `chezmoi edit` and a sync, since the hook does not capture edits to a template.

## Work and personal identities

For a different `user.email` per folder rather than per machine, use `includeIf` in the shared file, which syncs as is:

```ini
[includeIf "gitdir:~/work/"]
  path = ~/.config/git/work
```

`~/.config/git/work` is outside the allow-list. Add it by hand with `chezmoi add --encrypt ~/.config/git/work` if it should travel too.

## The sync's own Git

The hook runs `git pull` and `git push` with the person's own Git config. A broken `~/.gitconfig` pulled from another machine can make the next sync fail; in that case fix the file locally, then sync by hand.
