---
name: syncing-dotfiles
description: Set up, repair, or explain the encrypted sync of dotfiles across machines through chezmoi: ~/.claude, Git and SSH config, project files kept out of Git, VS Code and gh settings. Use when adding a machine or a project folder, fixing a sync conflict, syncing an SSH key, or excluding a file.
---

# Syncing dotfiles

The `dotfiles-sync` plugin keeps the global Claude Code config, the Git config, the SSH config, the files projects keep out of their own Git, the VS Code user settings, and the GitHub CLI config identical on every machine of one person. Its hook runs `${CLAUDE_PLUGIN_ROOT}/hooks/sync.sh` when a session starts and when it ends. The script captures local edits, additions, and deletions, commits them to the chezmoi source repo, pulls, applies, and pushes. It tells a local change from a pulled one by comparing each file with the last version chezmoi wrote on this machine. This skill covers what the hook cannot do alone: the one-time setup, a new machine, conflicts, exclusions, and the files that sync only on request.

The person may not know chezmoi or age. Run the commands yourself, explain each step in a sentence, and stop to ask only where a choice is theirs (the repo name, which version of a file wins, what to exclude, whether a private key syncs).

Each domain has its own reference. Read it before acting on a file of that domain:

- [references/claude-code.md](references/claude-code.md): `~/.claude`, what must never sync there, plugins;
- [references/git.md](references/git.md): `~/.gitconfig` and `~/.config/git/`, values that differ per machine;
- [references/ssh.md](references/ssh.md): `~/.ssh`, private keys, `known_hosts`, permissions;
- [references/projects.md](references/projects.md): the per-machine list of project folders, fresh clones, files a project starts tracking;
- [references/vscode.md](references/vscode.md): the VS Code user folder on each OS, VS Code's own Settings Sync;
- [references/github-cli.md](references/github-cli.md): the GitHub CLI folder, the token file that never syncs.

## What syncs

The hook reaches four roots in the home folder (`.claude`, `.gitconfig`, `.config/git`, `.ssh`), the projects listed in `~/.config/dotfiles-sync/projects`, the VS Code user folder, and the GitHub CLI folder. Inside them, it picks up new files from an allow-list only:

| Domain | Picked up automatically |
| --- | --- |
| Claude Code | `settings.json`, `keybindings.json`, every `*.md` at the top of `~/.claude` (`CLAUDE.md` and the files it imports), `statusline*` (the status line script), and every file under `skills/`, `agents/`, `commands/`, `hooks/`, `rules/`, `output-styles/`, `workflows/`, `agent-memory/`, `themes/` |
| Git | `~/.gitconfig`, `~/.config/git/config`, `~/.config/git/ignore`, `~/.config/git/attributes` |
| SSH | `~/.ssh/config`, every file under `~/.ssh/config.d/`, `~/.ssh/*.pub` |
| Projects | at any depth and only when the project's Git does not track them: `CLAUDE.md`, `CLAUDE.local.md`, `AGENTS.md`, `.claude/settings.json`, `.claude/settings.local.json`, every file under `.claude/` `skills/`, `agents/`, `commands/`, `hooks/`, `rules/`, `output-styles/`, and `.vscode/` `settings.json`, `launch.json`, `tasks.json`, `extensions.json`, `*.code-snippets`; never under `node_modules/` |
| VS Code | `settings.json`, `keybindings.json`, every file under `snippets/` |
| GitHub CLI | `config.yml`, never `hosts.yml` |

Projects, VS Code, and the GitHub CLI sit at different paths on each machine, so each one is its own chezmoi source under `.dotfiles-sync/` in the source repo (`projects/<folder name>/`, `vscode/`, `gh/`), applied with `--source` and `--destination`. A file anywhere else in the home roots (a private key, `known_hosts`) is left alone until it is added by hand with `chezmoi add --encrypt <path>`. From then on, the hook syncs its edits and its deletion like the rest. The hook also skips `.credentials.json`, `credentials.json`, `.env`, `.env.*`, `__pycache__/`, `.git/`, `node_modules/`, `.venv/`, `.DS_Store`, `Thumbs.db`, editor swap and backup files (`*.swp`, `*~`), symlinks, `~/.claude/skills/synced/`, `~/.claude/skills/.trash/` (where Claude Code moves the skills it removes), and every path matched by a plain glob line in the source repo's `.chezmoiignore`.

Other dotfiles managed in the same chezmoi repo (a `.bashrc`, say) are outside the hook's reach: it never commits, applies, or re-adds them, so the person keeps managing them with plain chezmoi.

Every file is encrypted with age before it reaches Git, so the remote holds only ciphertext. The repo should still be private: file names and commit dates are not encrypted.

## Check the state first

Before any procedure, find out where the machine stands:

```bash
command -v chezmoi git gh
chezmoi source-path && git -C "$(chezmoi source-path)" status -sb
chezmoi managed --include=files | grep -E '^\.(claude|gitconfig|config/git|ssh)' | head -20
ls "$(chezmoi source-path)/.dotfiles-sync/projects"; cat ~/.config/dotfiles-sync/projects
```

No chezmoi means the setup below. A source repo with none of these files means the first machine. A `dotfiles-sync.hold` file in the source repo's `.git` means a setup left unfinished: resume it at the review step of the matching procedure below. A source repo behind or ahead of `origin` means a sync that could not finish; a stuck conflict is handled below. On Windows the hook runs in Git Bash, which comes with Git for Windows.

## First machine

Once the source repo exists, every Claude Code session that starts or ends on this machine runs a sync. Step 5 puts the hook on hold with a `dotfiles-sync.hold` file in the source repo's `.git`, and step 7 lifts it; settle every choice before step 5 all the same.

1. Install chezmoi: `winget install twpayne.chezmoi` on Windows, `brew install chezmoi` on macOS, the distribution package or `sh -c "$(curl -fsLS get.chezmoi.io)" -- -b ~/.local/bin` on Linux. Recent chezmoi has age built in, so age needs no install. Open a new terminal or session if the command is not found yet.
2. Ask, in one go: the name of the private repo (suggest `dotfiles`), which domains to sync, and where the person keeps the projects whose untracked files should travel. Read [references/git.md](references/git.md) if `~/.gitconfig` holds values that must differ per machine, and move them now. Then list what the first sync would take from those projects, a superset of the allow-list:

   ```bash
   for r in <folder>/*/; do
     git -C "$r" ls-files --others --exclude=node_modules -- ':(glob)**/CLAUDE.md' \
       ':(glob)**/CLAUDE.local.md' ':(glob)**/AGENTS.md' ':(glob)**/.claude/**' ':(glob)**/.vscode/**' |
       sed "s|^|$r|"
   done
   ```

   Point out credentials (keys, tokens, service-account JSON) and generated files, and ask which stay local.
3. Generate the key: `chezmoi age-keygen -o ~/.config/chezmoi/key.txt`. The command prints the public key (`age1…`). Tell the person to store the content of `key.txt` in their password manager now: every other machine needs it, and without it the repo cannot be decrypted. It never goes into Git.
4. Write `~/.config/chezmoi/chezmoi.toml` (on Windows too, `~/.config` under the user profile):

   ```toml
   encryption = "age"
   [age]
     identity = "~/.config/chezmoi/key.txt"
     recipient = "age1..."
   ```

5. Create the source repo, then write the answers of step 2 right away. Ciphertext must not go through line-ending conversion, hence the `.gitattributes`:

   ```bash
   chezmoi init
   src=$(chezmoi source-path)
   touch "$src/.git/dotfiles-sync.hold"
   git -C "$src" checkout -q -b main 2>/dev/null || true
   echo '* -text' > "$src/.gitattributes"
   git -C "$src" add .gitattributes && git -C "$src" commit -q -m "chore: init"
   ```

   To leave a home domain out, add its root (`.ssh`, or `.gitconfig` and `.config/git`) to `.chezmoiignore` in the source repo; for VS Code or the GitHub CLI, see [references/vscode.md](references/vscode.md) or [references/github-cli.md](references/github-cli.md). A project file that stays local goes to `.dotfiles-sync/projects/<name>/.chezmoiignore`, a path relative to the project (`**/__pycache__` style globs work). Write the project folders to `~/.config/dotfiles-sync/projects` as [references/projects.md](references/projects.md) shows.
6. Create the private remote. With `gh` authenticated: `gh repo create <name> --private --source "$src" --remote origin --push`. Otherwise have the person create an empty private repo, then `git -C "$src" remote add origin <url>` and `git -C "$src" push -u origin main`.
7. Lift the hold and run the first sync: `rm "$src/.git/dotfiles-sync.hold"`, then `bash "${CLAUDE_PLUGIN_ROOT}/hooks/sync.sh"`. It prints nothing on success. Check with `chezmoi managed --include=files` and `git -C "$src" log --oneline -3`, then show the person the list of synced files and ask whether anything there should stay local (see exclusions below). Offer to sync a private key only if they ask; [references/ssh.md](references/ssh.md) covers it.

## Another machine

Once the repo is cloned, the next sync settles every file that exists both here and in the repo but was never applied: the local version wins and replaces the repo's on every machine. Files the repo holds and this machine lacks are only fetched. Review before that sync. Step 3 puts the hook on hold right after the clone, so no other session syncs during the review, and step 6 lifts it.

1. Install chezmoi as above.
2. Restore the key: have the person paste the content of `key.txt` from their password manager into `~/.config/chezmoi/key.txt`. Write the same `chezmoi.toml`, with the public key on the `# public key:` line of `key.txt`.
3. Clone without applying, and hold the sync at once: `chezmoi init <repo-url> && touch "$(chezmoi source-path)/.git/dotfiles-sync.hold"`. Ask where this machine keeps its projects and write its own `~/.config/dotfiles-sync/projects` (see [references/projects.md](references/projects.md)); `ls "$(chezmoi source-path)/.dotfiles-sync/projects"` lists the project names the repo already holds.
4. Show what would change: `chezmoi diff` on each root the repo holds (`.claude`, `.gitconfig`, `.config/git`, `.ssh`), then on each tree the repo holds for a folder this machine has. The same rule applies there, so a local VS Code `settings.json` that differs would replace the repo's on every machine:

   ```bash
   src=$(chezmoi source-path)
   chezmoi --source "$src/.dotfiles-sync/vscode" --destination "<VS Code user folder>" diff
   chezmoi --source "$src/.dotfiles-sync/gh" --destination "<GitHub CLI folder>" diff
   chezmoi --source "$src/.dotfiles-sync/projects/<name>" --destination "<project folder>" diff
   ```

   The folders per OS are in [references/vscode.md](references/vscode.md) and [references/github-cli.md](references/github-cli.md); run the last line for each project already cloned here. For each existing local file that differs, ask which version wins. Back up the local ones first (for example `cp -r ~/.claude ~/.claude.bak-$(date +%F)`, and the same for `~/.ssh` and `~/.gitconfig`) and say where the copies are. A `~/.gitconfig` that differs only by machine-specific values is the case [references/git.md](references/git.md) solves.
5. Check that `chezmoi source-path ~/.ssh ~/.claude` names `private_` folders. A repo whose first machine ran Windows under an earlier version of the hook may hold plain `dot_ssh` and `dot_claude`, which an apply turns into 755 folders here; run `chezmoi chattr +private ~/.ssh ~/.claude` first in that case (the next sync commits the rename). Then apply the repo versions: `chezmoi apply <root>`, or `chezmoi apply <path>` file by file when some local versions should win. For a tree, put the same `--source` and `--destination` before `apply`. A file left out keeps its local version, and the sync sends it to the other machines.
6. Lift the hold and sync: `rm "$src/.git/dotfiles-sync.hold"`, then `bash "${CLAUDE_PLUGIN_ROOT}/hooks/sync.sh"`. Files present only on this machine are added to the repo at that point.

## Conflict

The hook reports "the same file changed on two machines" when both sides edited a file between two syncs. Git cannot merge ciphertext, so the sync stops before applying anything and repeats the message at each session until the conflict is resolved. Nothing is overwritten meanwhile.

1. List the files changed on both sides:

   ```bash
   src=$(chezmoi source-path); git -C "$src" fetch -q
   comm -12 <(git -C "$src" diff --name-only origin/main...HEAD | sort) \
            <(git -C "$src" diff --name-only HEAD...origin/main | sort)
   ```

2. For each one, compare the remote version (`git -C "$src" show origin/main:<path> | chezmoi decrypt`) with the local file it maps to (`chezmoi target-path "$src/<path>"`; under `.dotfiles-sync/projects/<name>/`, `.dotfiles-sync/vscode/`, or `.dotfiles-sync/gh/`, the same relative path inside that project or app folder, with `dot_` read as `.` and `encrypted_` and `.age` dropped). Show the person the difference and merge with them; for JSON, a union of the keys usually works, and for `known_hosts` a sorted union of the lines. Write the result to the local file. `.chezmoiremove` needs nothing, and `.chezmoiignore` is plain text: keep its merged lines for step 3.
3. Realign on the remote: `git -C "$src" reset --hard origin/main`. The reset drops the local sync commits and leaves the home folder alone. Before syncing, put back what it dropped from the repo and the sync cannot find on its own: the merged `.chezmoiignore`, written to the source repo, and any file added by hand since the last successful sync (`chezmoi add --encrypt <path>`).
4. Sync: `bash "${CLAUDE_PLUGIN_ROOT}/hooks/sync.sh"`. It sends the merged file and the other local edits, and applies the other machine's changes. A file deleted on this machine since the last successful sync comes back: tell the person, and delete it again.

## Keep a file out of the sync

- Deleting a synced file deletes it on every machine at their next sync. Say so before deleting.
- To keep a file local on every machine, add its path relative to the home folder to `.chezmoiignore` in the source repo (`.claude/skills/my-skill`, globs allowed, a whole root such as `.ssh` too), then stop tracking it without touching the disk: `chezmoi forget --force <path>` followed by a sync. The hook commits `.chezmoiignore`, so the exclusion reaches the other machines too.
- In a project, VS Code, or the GitHub CLI, the same goes through that tree's own `.chezmoiignore` (`.dotfiles-sync/projects/<name>/.chezmoiignore`, paths relative to the project), and `forget` takes the tree's source and destination: `chezmoi --source "$src/.dotfiles-sync/projects/<name>" --destination <project folder> forget --force <path>`.
- A file whose content must differ per machine (a path, an OS) becomes a chezmoi template: `chezmoi chattr +template <path>`, then `chezmoi edit <path>` with `{{ if eq .chezmoi.os "windows" }}` blocks. The hook no longer captures edits to a template, so later changes go through `chezmoi edit` and a sync.

## Other situations

- To pause the sync, run `/plugin disable dotfiles-sync`; the files stay where they are.
- A lost key leaves the repo unreadable, but every machine still holds its files in clear. Generate a new key on one machine and update `chezmoi.toml`. In the source repo, delete the source paths of the four home roots (`chezmoi source-path <root>` gives each), every `*.age` file under `.dotfiles-sync/` (keep its `.chezmoiignore` files), and `.chezmoiremove`, then commit and run a sync: everything the allow-lists cover is added again under the new key. Files added by hand, such as a private key, must be added again too. Then reinstall the key on the other machines.
- For a leaked key, take the same steps, then rotate every secret a synced file holds, synced SSH private keys first.
- "chezmoi is not on the PATH this session got" means Claude Code was started with a minimal PATH, as an app launched from the macOS Dock or some Linux desktops is. The hook already looks in `~/.local/bin`, `~/bin`, `/opt/homebrew/bin`, and `/usr/local/bin`; for another folder, add it to the PATH the app inherits (on macOS, `sudo launchctl config user path <PATH>` and a restart), or put a symlink to `chezmoi` in one of those four.
- "Git could not log in to the remote without a prompt" means the pull or the push needs a credential the hook cannot type: an SSH key with a passphrase and no agent, or HTTPS with no credential helper. Fix it so that `git -C "$(chezmoi source-path)" fetch` works with no prompt (`ssh-add`, `gh auth setup-git`, or a credential helper), then sync.
- "pull refused: the source repo has uncommitted changes" means a change in the source repo that the hook does not own, such as a hand edit or another dotfile managed with chezmoi. Show `git -C "$src" status` to the person, then commit or discard with them, and sync.
- For any other sync error, run the script by hand with `bash -x "${CLAUDE_PLUGIN_ROOT}/hooks/sync.sh"` and read where it stops; `chezmoi doctor` checks the chezmoi side.
