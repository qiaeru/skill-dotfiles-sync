#!/usr/bin/env bash
# End-to-end test of hooks/sync.sh: two fake home directories share a bare
# remote, and each scenario checks what reaches the other machine. Needs
# chezmoi and git on PATH; touches nothing outside a temporary directory.
# Run from the repo root: bash tests/sync-test.sh
# check() evals its condition after the scenario runs, so the conditions are
# single-quoted and the variables they read look unused to shellcheck.
# shellcheck disable=SC2016,SC2034
set -euo pipefail

SYNC="$PWD/hooks/sync.sh"
# On macOS the temporary folder sits behind a symlink, which chezmoi resolves
# in its state and the hook would not.
SB=$(cd "$(mktemp -d)" && pwd -P)
trap 'rm -rf "$SB"' EXIT
export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.com
export GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.com
export GIT_CONFIG_GLOBAL=/dev/null

failures=0
check() {
  if eval "$2"; then
    echo "ok   $1"
  else
    echo "FAIL $1"
    failures=$((failures + 1))
  fi
}

# chezmoi reads USERPROFILE on Windows and HOME elsewhere. The hook finds the
# VS Code and GitHub CLI folders through APPDATA or XDG_CONFIG_HOME, which
# must point into the sandbox too, or it would sync the real ones.
on() {
  export HOME="$SB/$1" DOTFILES_SYNC_HOST=$1
  unset GH_CONFIG_DIR
  if command -v cygpath >/dev/null; then
    export USERPROFILE APPDATA
    USERPROFILE=$(cygpath -w "$HOME")
    APPDATA=$(cygpath -w "$HOME/AppData/Roaming")
    unset XDG_CONFIG_HOME
  else
    export XDG_CONFIG_HOME="$HOME/.config"
  fi
  cd "$HOME"
}
vscode() {
  if command -v cygpath >/dev/null; then
    echo "$HOME/AppData/Roaming/Code/User"
  elif [ "$(uname)" = Darwin ]; then
    echo "$HOME/Library/Application Support/Code/User"
  else
    echo "$HOME/.config/Code/User"
  fi
}
ghdir() {
  if command -v cygpath >/dev/null; then echo "$HOME/AppData/Roaming/GitHub CLI"; else echo "$HOME/.config/gh"; fi
}
# The hook runs under the bash that runs the test, so CI covers the bash 3.2
# of macOS with /bin/bash tests/sync-test.sh.
sync() { "$BASH" "$SYNC"; }
src() { chezmoi source-path; }

# A fake VS Code CLI, first on PATH, so the hook never touches the real
# extensions. Each home keeps its own list; a win.* extension only installs on
# machine A, as one built for a single OS would.
mkdir -p "$SB/bin"
cat >"$SB/bin/code" <<'FAKE'
#!/usr/bin/env bash
list="$HOME/.fake-code-extensions"
touch "$list"
case "$1" in
  --list-extensions) cat "$list"; exit 0 ;;
  --install-extension)
    case "$2:$HOME" in win.*:*/A) ;; win.*) exit 1 ;; esac
    echo "$2" >>"$list" ;;
  --uninstall-extension) grep -vx "$2" "$list" >"$list.tmp"; mv "$list.tmp" "$list" ;;
esac
mkdir -p "$HOME/.vscode/extensions"
touch "$HOME/.vscode/extensions/extensions.json"
FAKE
chmod +x "$SB/bin/code"
export PATH="$SB/bin:$PATH"
[ "$(command -v code)" = "$SB/bin/code" ] || { echo "the fake code is not first on PATH"; exit 1; }
exts() { LC_ALL=C sort "$HOME/.fake-code-extensions" 2>/dev/null | tr '\n' ' '; }

git init -q --bare -b main "$SB/remote.git"
chezmoi age-keygen -o "$SB/key.txt" 2>/dev/null
recipient=$(grep -o 'age1[0-9a-z]*' "$SB/key.txt")
setup_config() {
  mkdir -p "$HOME/.config/chezmoi"
  cp "$SB/key.txt" "$HOME/.config/chezmoi/key.txt"
  printf 'encryption = "age"\n[age]\n  identity = "~/.config/chezmoi/key.txt"\n  recipient = "%s"\n' \
    "$recipient" >"$HOME/.config/chezmoi/chezmoi.toml"
}

# Machine A: first setup, as the skill does it.
mkdir -p "$SB/A"
on A
mkdir -p .claude/skills/foo .claude/skills/synced/x .claude/skills/.trash/1-2-x/old .claude/commands .claude/projects/p
echo '{"model":"opus"}' >.claude/settings.json
echo '# global' >.claude/CLAUDE.md
echo 'skill' >.claude/skills/foo/SKILL.md
echo 'SECRET=1' >.claude/skills/foo/.env
mkdir -p .claude/skills/foo/__pycache__
echo 'bytecode' >.claude/skills/foo/__pycache__/x.pyc
echo 'cloud' >.claude/skills/synced/x/SKILL.md
echo 'removed' >.claude/skills/.trash/1-2-x/old/SKILL.md
mkdir -p .claude/skills/foo/.git .claude/skills/foo/node_modules/dep .claude/skills/foo/.venv/lib
echo 'ref: refs/heads/main' >.claude/skills/foo/.git/HEAD
echo 'dep' >.claude/skills/foo/node_modules/dep/index.js
echo 'venv' >.claude/skills/foo/.venv/lib/site.py
echo 'swap' >.claude/skills/foo/.SKILL.md.swp
echo 'backup' >.claude/skills/foo/SKILL.md~
echo 'cmd' >.claude/commands/hi.md
echo '{"token":1}' >.claude/.credentials.json
echo 'history' >.claude/projects/p/session.jsonl
mkdir -p .config/git .ssh/config.d
printf '[user]\n\tname = A\n' >.gitconfig
echo '*.log' >.config/git/ignore
echo 'Host *' >.ssh/config
echo 'Host work' >.ssh/config.d/work
echo 'PRIVATE KEY' >.ssh/id_ed25519
echo 'ssh-ed25519 AAAA' >.ssh/id_ed25519.pub
echo 'github.com ssh-ed25519' >.ssh/known_hosts
echo 'export A=1' >.bashrc
setup_config
chezmoi init
git -C "$(src)" checkout -q -b main
echo '* -text' >"$(src)/.gitattributes"
git -C "$(src)" add .gitattributes
git -C "$(src)" commit -q -m init
git -C "$(src)" remote add origin "$SB/remote.git"
git -C "$(src)" push -q -u origin main

out=$(sync)
remote_files=$(git --git-dir="$SB/remote.git" ls-tree -r --name-only main)
check "first sync prints nothing" '[ -z "$out" ]'
check "allow-listed files reach the remote" \
  'grep -q settings.json <<<"$remote_files" && grep -q skills/foo/encrypted_SKILL.md <<<"$remote_files" && grep -q commands/encrypted_hi.md <<<"$remote_files"'
check "secrets, caches, claude.ai skills, removed skills, and history stay out" \
  '! grep -Eq "\.env|credentials|pycache|synced|trash|projects" <<<"$remote_files"'
check "Git folders, dependencies, and editor files inside a skill stay out" \
  '! grep -Eq "dot_git/|node_modules|dot_venv|swp|~" <<<"$remote_files"'
check "the .ssh and .claude roots sync as private" \
  '! grep -Eq "^dot_(ssh|claude)/" <<<"$remote_files" && grep -q "^private_dot_ssh/" <<<"$remote_files" && grep -q "^private_dot_claude/" <<<"$remote_files"'
check "Git and SSH config reach the remote" \
  'grep -q encrypted_dot_gitconfig <<<"$remote_files" && grep -q git/encrypted_ignore <<<"$remote_files" && grep -q ssh/encrypted_config.age <<<"$remote_files" && grep -q config.d/encrypted_work <<<"$remote_files" && grep -q encrypted_id_ed25519.pub <<<"$remote_files"'
check "private keys, known_hosts, and other dotfiles stay out" \
  '! grep -Eq "id_ed25519(\.age)?$|known_hosts|bashrc" <<<"$remote_files"'
check "the remote holds only ciphertext" \
  '[ -z "$(grep -v -e "^\.gitattributes$" -e "\.age$" <<<"$remote_files")" ] && ! git --git-dir="$SB/remote.git" grep -q opus main'
commits=$(git -C "$(src)" rev-list --count HEAD)
sync >/dev/null
check "an idle sync makes no commit" '[ "$(git -C "$(src)" rev-list --count HEAD)" = "$commits" ]'

# The files CLAUDE.md imports and the status line script travel. A new file
# over 1 MB stays out, and the hook names it once.
echo '# style' >.claude/style.md
echo 'echo ok' >.claude/statusline-command.sh
head -c 2000000 /dev/zero >.claude/skills/foo/big.bin
out=$(sync)
remote_files=$(git --git-dir="$SB/remote.git" ls-tree -r --name-only main)
check "the files CLAUDE.md imports and the status line script reach the remote" \
  'grep -q "^private_dot_claude/encrypted_style.md.age$" <<<"$remote_files" && grep -q statusline-command <<<"$remote_files"'
check "a new file over 1 MB is left out and named" '! grep -q big.bin <<<"$remote_files" && grep -q "over 1 MB" <<<"$out"'
out=$(sync)
check "a large file is named only once" '! grep -q "over 1 MB" <<<"$out"'

# Machine B: joins with chezmoi init --apply, then edits, adds, deletes.
mkdir -p "$SB/B"
on B
setup_config
chezmoi init --apply "$SB/remote.git" >/dev/null
check "a new machine gets the config" '[ "$(cat .claude/settings.json)" = "{\"model\":\"opus\"}" ]'
check "a new machine gets the Git and SSH config" '[ -f .gitconfig ] && [ -f .ssh/config ] && [ -f .ssh/id_ed25519.pub ] && [ ! -e .ssh/id_ed25519 ]'
echo '{"model":"sonnet"}' >.claude/settings.json
mkdir -p .claude/agents
echo 'agent' >.claude/agents/review.md
rm .claude/commands/hi.md
printf '[user]\n\tname = B\n' >.gitconfig
rm .config/git/ignore
sync >/dev/null

on A
out=$(sync)
check "an edit propagates" '[ "$(cat .claude/settings.json)" = "{\"model\":\"sonnet\"}" ]'
check "a new file propagates" '[ -f .claude/agents/review.md ]'
check "a deletion propagates" '[ ! -e .claude/commands/hi.md ]'
check "files outside the allow-list are left alone" '[ -f .claude/.credentials.json ] && [ -f .claude/projects/p/session.jsonl ]'
check "the user hears about pulled changes" 'grep -q "from another machine" <<<"$out"'
check "a Git config edit propagates" 'grep -q "name = B" .gitconfig'
check "a deletion that empties a folder propagates" '[ ! -e .config/git/ignore ]'

# Files outside the allow-list sync once added by hand, and only those.
chezmoi add --encrypt .ssh/id_ed25519
chezmoi add .bashrc
echo 'export A=2' >.bashrc
sync >/dev/null
check "other dotfiles in the chezmoi repo are left alone" \
  '[ "$(cat .bashrc)" = "export A=2" ] && [ -n "$(git -C "$(src)" status --porcelain -- dot_bashrc)" ]'

# A hand edit in the source repo blocks the pull, and the hook says why.
echo '# hand edit' >>"$(src)/.gitattributes"
out=$(sync)
check "an uncommitted change in the source repo is named, not taken for offline" \
  'grep -q "uncommitted changes" <<<"$out" && ! grep -q offline <<<"$out"'
git -C "$(src)" checkout -q -- .gitattributes

# A root renamed by hand leaves its old path deleted; the sync stages it.
# re-add derives the mode from the disk, hence the chmod.
chmod 600 .gitconfig
chezmoi chattr +private .gitconfig
out=$(sync)
check "a root renamed by hand syncs" \
  '[ -z "$out" ] && [ -z "$(git -C "$(src)" status --porcelain -- "*gitconfig*")" ] && ! git --git-dir="$SB/remote.git" ls-tree -r --name-only main | grep -q "^encrypted_dot_gitconfig"'
on B
sync >/dev/null
check "a private key added by hand reaches the other machine" '[ "$(cat .ssh/id_ed25519)" = "PRIVATE KEY" ]'
echo 'NEW KEY' >.ssh/id_ed25519
sync >/dev/null
on A
sync >/dev/null
check "edits to a file added by hand propagate" '[ "$(cat .ssh/id_ed25519)" = "NEW KEY" ]'

echo 'cmd again' >.claude/commands/hi.md
sync >/dev/null
check "a file created again leaves the removal list" '! grep -qx .claude/commands/hi.md "$(src)/.chezmoiremove"'

# chezmoi reads .chezmoiremove lines as globs: a[1].md must not take a1.md.
echo 'x' >'.claude/commands/a[1].md'
echo 'x' >.claude/commands/a1.md
sync >/dev/null
on B
sync >/dev/null
rm '.claude/commands/a[1].md'
sync >/dev/null
on A
out=$(sync)
check "a deleted file named like a glob removes no other file" \
  '! grep -q "could not apply" <<<"$out" && [ ! -e ".claude/commands/a[1].md" ] && [ -f .claude/commands/a1.md ]'

printf '.claude/skills/private\n.config/git/attributes\n' >"$(src)/.chezmoiignore"
mkdir -p .claude/skills/private .claude/skills/public
echo 'p' >.claude/skills/private/SKILL.md
echo 'p' >.claude/skills/public/SKILL.md
echo '* -text' >.config/git/attributes
sync >/dev/null
check ".chezmoiignore keeps a file out without blocking the others" \
  '! chezmoi managed | grep -Eq "private|attributes" && chezmoi managed | grep -q public'

# Conflict: both machines edit the same file before syncing, and A also
# changes files B never touched.
echo '{"model":"A"}' >.claude/settings.json
echo '# from A' >.claude/CLAUDE.md
mkdir -p .claude/skills/from-a
echo 'a' >.claude/skills/from-a/SKILL.md
sync >/dev/null
on B
echo '{"model":"B"}' >.claude/settings.json
out=$(sync)
check "a conflict is reported as JSON only" '[ "$(printf "%s" "$out" | head -c 1)" = "{" ] && grep -q "two machines" <<<"$out"'
check "a conflict overwrites nothing" '[ "$(cat .claude/settings.json)" = "{\"model\":\"B\"}" ]'
check "a conflict leaves no rebase in progress" '[ ! -d "$(src)/.git/rebase-merge" ] && [ ! -d "$(src)/.git/rebase-apply" ]'

# The resolution the skill documents: merge by hand, realign, sync.
git -C "$(src)" fetch -q
echo '{"model":"merged"}' >.claude/settings.json
git -C "$(src)" reset -q --hard origin/main
sync >/dev/null
check "B's other changes survive the realignment" '[ -f .claude/agents/review.md ]'
check "A's other changes reach B after the realignment" \
  '[ "$(cat .claude/CLAUDE.md)" = "# from A" ] && [ -f .claude/skills/from-a/SKILL.md ]'
on A
sync >/dev/null
check "the merged version reaches A" '[ "$(cat .claude/settings.json)" = "{\"model\":\"merged\"}" ]'
check "A's other changes survive B's realignment" \
  '[ "$(cat .claude/CLAUDE.md)" = "# from A" ] && [ -f .claude/skills/from-a/SKILL.md ]'

# Machine D clones without applying, then a session ends: files it never
# received are fetched, not taken for deletions, and a local file wins.
mkdir -p "$SB/D/.claude"
on D
echo '{"model":"D"}' >.claude/settings.json
setup_config
chezmoi init "$SB/remote.git" >/dev/null
# The hold the skill sets during the setup: no sync until it is lifted.
: >"$(src)/.git/dotfiles-sync.hold"
out=$(sync)
check "a held sync says so and changes nothing" \
  'grep -q "on hold" <<<"$out" && [ ! -e .claude/skills/from-a/SKILL.md ] && [ "$(git -C "$(src)" status --porcelain)" = "" ]'
rm "$(src)/.git/dotfiles-sync.hold"
sync >/dev/null
check "a file never applied here is fetched, not deleted" \
  '[ -f .claude/skills/from-a/SKILL.md ] && git --git-dir="$SB/remote.git" ls-tree -r --name-only main | grep -q from-a'
check "a local file never applied here wins" \
  'git --git-dir="$SB/remote.git" show main:private_dot_claude/encrypted_settings.json.age | chezmoi decrypt | grep -q D'
on A

# Offline: changes wait in a local commit and leave on the next sync.
mv "$SB/remote.git" "$SB/remote.off"
echo '# offline edit' >>.claude/CLAUDE.md
out=$(sync)
check "an offline sync says so" 'grep -q offline <<<"$out"'
mv "$SB/remote.off" "$SB/remote.git"
sync >/dev/null
check "the offline edit goes out once back online" \
  'git --git-dir="$SB/remote.git" show main:private_dot_claude/encrypted_CLAUDE.md.age | chezmoi decrypt | grep -q "offline edit"'

# Projects: A and B clone the same repo at different paths, and the files its
# Git does not track travel through the dotfiles repo, as do the VS Code user
# settings.
mkdir -p code/proj .config/dotfiles-sync "$(vscode)"
git init -q code/proj
printf 'CLAUDE.md\nCLAUDE.local.md\n.claude/\n.vscode/\nnode_modules/\n' >code/proj/.gitignore
echo 'tracked' >code/proj/AGENTS.md
git -C code/proj add .gitignore AGENTS.md
git -C code/proj commit -q -m init
mkdir -p code/proj/sub code/proj/.claude/skills/s code/proj/.vscode code/proj/node_modules/pkg
echo 'root notes' >code/proj/CLAUDE.md
echo 'sub notes' >code/proj/sub/CLAUDE.md
echo 'local' >code/proj/CLAUDE.local.md
echo '{}' >code/proj/.claude/settings.local.json
echo 'skill' >code/proj/.claude/skills/s/SKILL.md
echo 'TOKEN=1' >code/proj/.claude/skills/s/.env
echo '{}' >code/proj/.vscode/settings.json
echo 'pkg' >code/proj/node_modules/pkg/CLAUDE.md
echo 'scratch' >code/proj/notes.txt
# shellcheck disable=SC2088 # The hook expands a literal ~ itself.
echo '~/code' >.config/dotfiles-sync/projects
echo '{"editor.fontSize":14}' >"$(vscode)/settings.json"
sync >/dev/null
remote_files=$(git --git-dir="$SB/remote.git" ls-tree -r --name-only main)
p=.dotfiles-sync/projects/proj
check "untracked project files reach the remote, nested ones too" \
  '(for f in encrypted_CLAUDE.md sub/encrypted_CLAUDE.md encrypted_CLAUDE.local.md dot_claude/encrypted_settings.local.json dot_claude/skills/s/encrypted_SKILL.md dot_vscode/encrypted_settings.json; do grep -q "^$p/$f.age$" <<<"$remote_files" || exit 1; done)'
check "tracked files, node_modules, secrets, and other files stay out" \
  '! grep -Eq "^$p/(encrypted_AGENTS|.*node_modules|.*notes|.*env)" <<<"$remote_files"'
check "the VS Code user settings reach the remote" 'grep -q "^.dotfiles-sync/vscode/encrypted_settings.json.age$" <<<"$remote_files"'

on B
mkdir -p src .config/dotfiles-sync "$(vscode)" other/proj
git clone -q "$SB/A/code/proj" src/proj
git init -q other/proj
# shellcheck disable=SC2088
printf '~/src\n~/other\n' >.config/dotfiles-sync/projects
out=$(sync)
check "two messages make one JSON line" \
  '[ "$(printf "%s\n" "$out" | wc -l)" -eq 1 ] && grep -q "two projects" <<<"$out" && grep -q "from another machine" <<<"$out"'
# shellcheck disable=SC2088
echo '~/src' >.config/dotfiles-sync/projects
check "a clone at another path gets the project files" \
  '[ "$(cat src/proj/CLAUDE.md)" = "root notes" ] && [ -f src/proj/sub/CLAUDE.md ] && [ -f src/proj/.claude/skills/s/SKILL.md ] && [ ! -e src/proj/node_modules ]'
check "the VS Code user settings reach the other machine" 'grep -q fontSize "$(vscode)/settings.json"'
echo 'edited on B' >src/proj/CLAUDE.md
rm src/proj/CLAUDE.local.md
sync >/dev/null
on A
sync >/dev/null
check "a project edit and a project deletion propagate" \
  '[ "$(cat code/proj/CLAUDE.md)" = "edited on B" ] && [ ! -e code/proj/CLAUDE.local.md ]'

# An unchanged project skips its chezmoi calls; an edit after an idle sync,
# with the same list of files, must still be seen.
sync >/dev/null
echo 'edited again on A' >code/proj/CLAUDE.md
sync >/dev/null
on B
sync >/dev/null
check "an edit after an idle sync propagates" '[ "$(cat src/proj/CLAUDE.md)" = "edited again on A" ]'

# A fresh clone at a path that held an older one is not a deletion.
on B
rm -rf src/proj
git clone -q "$SB/A/code/proj" src/proj
sync >/dev/null
check "a fresh clone gets its files back and deletes nothing" \
  '[ "$(cat src/proj/CLAUDE.md)" = "edited again on A" ] && git --git-dir="$SB/remote.git" ls-tree -r --name-only main | grep -q "^$p/encrypted_CLAUDE.md.age$"'

# A file the project starts tracking leaves the sync, not the disks.
on A
git -C code/proj add -f sub/CLAUDE.md
git -C code/proj commit -q -m notes
sync >/dev/null
on B
sync >/dev/null
check "a file the project starts tracking leaves the sync, not the disks" \
  '! git --git-dir="$SB/remote.git" ls-tree -r --name-only main | grep -q "^$p/sub/" && [ -f src/proj/sub/CLAUDE.md ] && [ -f "$SB/A/code/proj/sub/CLAUDE.md" ]'

# The GitHub CLI config travels, its token file never does.
mkdir -p "$(ghdir)"
printf 'aliases:\n    co: pr checkout\n' >"$(ghdir)/config.yml"
echo 'oauth_token: gho_secret' >"$(ghdir)/hosts.yml"
sync >/dev/null
check "the GitHub CLI token file stays out" \
  '! git --git-dir="$SB/remote.git" ls-tree -r --name-only main | grep -q hosts'
on A
mkdir -p "$(ghdir)"
sync >/dev/null
check "the GitHub CLI config reaches the other machine" 'grep -q "pr checkout" "$(ghdir)/config.yml"'

# VS Code extensions travel as a list, applied after the push. The sleeps
# keep the mtime checks apart on filesystems with 1 s mtimes.
sleep 1
code --install-extension a.one
code --install-extension win.only
sync >/dev/null
on B
sleep 1
out=$(sync)
check "an extension installed on one machine reaches the other" \
  '[ "$(exts)" = "a.one " ] && grep -q "1 installed" <<<"$out"'
check "an extension that fails to install is named" 'grep -q "could not install 1 VS Code" <<<"$out"'
sleep 1
code --uninstall-extension a.one
out=$(sync)
check "a failed extension is not retried" '! grep -q "could not install" <<<"$out"'
on A
sleep 1
sync >/dev/null
check "an extension removed on one machine leaves the other" '[ "$(exts)" = "win.only " ]'
code --install-extension a.two
sync >/dev/null
on D
mkdir -p "$(vscode)"
code --install-extension d.only
sync >/dev/null
check "a first run merges both lists and removes nothing" \
  '[ "$(exts)" = "a.two d.only " ]'
sleep 1
sync >/dev/null
on A
sleep 1
sync >/dev/null
check "a first run's extensions reach the other machines" '[ "$(exts)" = "a.two d.only win.only " ]'
on B
sleep 1
sync >/dev/null
check "an extension a machine could not install stays on the others" '[ "$(exts)" = "a.two d.only " ]'
on A
sync >/dev/null
check "each machine publishes its own list, in ciphertext" \
  '[ "$(git --git-dir="$SB/remote.git" ls-tree --name-only main .dotfiles-sync/vscode-extensions/ | wc -l)" -eq 3 ] && ! git --git-dir="$SB/remote.git" grep -q d.only main' 
check "A keeps the extension B could not install" '[ "$(exts)" = "a.two d.only win.only " ]'

# A tree whose apply failed is applied at the next sync, though that pull
# brings nothing new. A chezmoi earlier on PATH fails the VS Code apply once.
mkdir -p "$SB/failing"
cat >"$SB/failing/chezmoi" <<EOF
#!/usr/bin/env bash
case " \$* " in *Code/User*" apply "*) exit 1 ;; esac
exec "$(command -v chezmoi)" "\$@"
EOF
chmod +x "$SB/failing/chezmoi"
echo '{"editor.fontSize":16}' >"$(vscode)/settings.json"
sync >/dev/null
on B
out=$(PATH="$SB/failing:$PATH" sync)
check "a failed apply says so" 'grep -q "could not apply" <<<"$out" && ! grep -q 16 "$(vscode)/settings.json"'
sync >/dev/null
check "a failed apply is retried at the next sync" 'grep -q 16 "$(vscode)/settings.json"'

# The same for the home: a deletion leaves the status clean once pulled, so
# only the pending list brings it at the next sync.
mkdir -p "$SB/failhome"
cat >"$SB/failhome/chezmoi" <<EOF
#!/usr/bin/env bash
case " \$* " in " apply "*) exit 1 ;; esac
exec "$(command -v chezmoi)" "\$@"
EOF
chmod +x "$SB/failhome/chezmoi"
on A
echo 'retry' >.claude/commands/retry.md
sync >/dev/null
on B
sync >/dev/null
on A
rm .claude/commands/retry.md
sync >/dev/null
on B
out=$(PATH="$SB/failhome:$PATH" sync)
check "a failed home apply says so" 'grep -q "could not apply" <<<"$out" && [ -f .claude/commands/retry.md ]'
sync >/dev/null
check "a failed home apply is retried at the next sync" '[ ! -e .claude/commands/retry.md ]'
on A
sync >/dev/null
check "a deletion survives a failed apply elsewhere" '[ ! -e .claude/commands/retry.md ]'
on B

# A push the remote refuses for lack of credentials is not called offline.
cat >"$SB/failing/git" <<EOF
#!/usr/bin/env bash
case " \$* " in *" push "*) echo 'fatal: Authentication failed for remote' >&2; exit 128 ;; esac
exec "$(command -v git)" "\$@"
EOF
chmod +x "$SB/failing/git"
echo '{"editor.fontSize":18}' >"$(vscode)/settings.json"
out=$(PATH="$SB/failing:$PATH" sync)
check "an authentication failure is named, not taken for offline" \
  'grep -q "could not log in" <<<"$out" && ! grep -q offline <<<"$out"'
sync >/dev/null

# The extra push after extension changes names its failure too. B has
# nothing else to push, so the message can only come from that push.
on A
sleep 1
code --install-extension a.three
sync >/dev/null
on B
sleep 1
out=$(PATH="$SB/failing:$PATH" sync)
check "a failed extensions push is named" 'grep -q "1 installed" <<<"$out" && grep -q "could not log in" <<<"$out"'
sync >/dev/null

# A * in a tree's .chezmoiignore leaves that tree out, here VS Code.
echo '*' >"$(src)/.dotfiles-sync/vscode/.chezmoiignore"
echo '{"editor.fontSize":20}' >"$(vscode)/settings.json"
mkdir -p "$(vscode)/snippets"
echo '{}' >"$(vscode)/snippets/sh.json"
sync >/dev/null
check "a * in .chezmoiignore leaves VS Code out" \
  '! git --git-dir="$SB/remote.git" show main:.dotfiles-sync/vscode/encrypted_settings.json.age | chezmoi decrypt | grep -q 20 && ! git --git-dir="$SB/remote.git" ls-tree -r --name-only main | grep -q snippets'

# Without chezmoi set up, the hook must stay silent and harmless.
mkdir -p "$SB/C/.claude"
on C
out=$(sync)
check "no chezmoi source: silent no-op" '[ -z "$out" ]'

echo
if [ "$failures" -gt 0 ]; then
  echo "$failures check(s) failed"
  exit 1
fi
echo "all checks passed"
