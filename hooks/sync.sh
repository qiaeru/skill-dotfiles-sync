#!/usr/bin/env bash
# Two-way sync of the Claude Code config, Git config, SSH config, the files
# that projects keep out of their own Git, the VS Code user settings, and the
# GitHub CLI config, through chezmoi, run by the SessionStart and SessionEnd
# hooks. Local edits, additions, and deletions are committed before the pull,
# so the forced apply at the end never overwrites unsaved work. Every exit is
# 0: a failed sync must not get in the way of a session, and the user hears
# about it through a systemMessage instead.
# Runs on the bash 3.2 that macOS ships: with set -u, an empty array must
# never be expanded, and there are no associative arrays.
set -u

# The hook's whole reach in the home folder. Managed files under these roots
# are kept in sync, including the ones added by hand.
ROOTS=(.claude .gitconfig .config/git .ssh)

# New files are picked up only from this allow-list, so a new file elsewhere
# (a private key, a token a future tool writes) is missed, never leaked.
FILES=(.claude/settings.json .claude/keybindings.json
  .gitconfig .config/git/config .config/git/ignore .config/git/attributes
  .ssh/config)
DIRS=(.claude/skills .claude/agents .claude/commands .claude/hooks
  .claude/rules .claude/output-styles .claude/workflows .claude/agent-memory
  .claude/themes .ssh/config.d)

# Project folders live at different paths on each machine, so this list is
# per machine and never synced: one path per line, a repo or a folder of repos.
# A project is known by its folder name.
PROJECTS_CONF="$HOME/.config/dotfiles-sync/projects"

# The allow-list inside a project, at any depth. Only files the project's own
# Git does not track are picked up: a tracked one travels with the project.
project_file() {
  case "/$1" in
    */node_modules/*) return 1 ;;
    */CLAUDE.md | */CLAUDE.local.md | */AGENTS.md | */.mcp.json) return 0 ;;
    */.claude/settings.json | */.claude/settings.local.json) return 0 ;;
    */.claude/skills/* | */.claude/agents/* | */.claude/commands/* | \
      */.claude/hooks/* | */.claude/rules/* | */.claude/output-styles/*) return 0 ;;
    */.vscode/settings.json | */.vscode/launch.json | */.vscode/tasks.json | \
      */.vscode/extensions.json | */.vscode/*.code-snippets) return 0 ;;
  esac
  return 1
}
# A coarse filter git applies itself, which spares the loop over a project's
# untracked files the thousands that its Git ignores (builds, dependencies).
# project_file has the final word, so this list only has to cover it.
PROJECT_SPECS=(':(glob)**/CLAUDE.md' ':(glob)**/CLAUDE.local.md' ':(glob)**/AGENTS.md'
  ':(glob)**/.mcp.json' ':(glob)**/.claude/**' ':(glob)**/.vscode/**')

# Plain stdout of a SessionStart hook lands in Claude's context, and git prints
# conflict notices there even with -q. Only finish() reaches the real stdout,
# with every say() line in one JSON object, since two would not parse.
exec 3>&1 >/dev/null
messages=
say() { messages+=${messages:+$'\n'}"dotfiles-sync: $1"; }
locked=
# shellcheck disable=SC2329 # Run by the EXIT trap.
finish() {
  [ -n "$locked" ] && rmdir "$lock" 2>/dev/null
  [ -n "$messages" ] || return 0
  local msg=${messages//\\/\\\\}
  msg=${msg//\"/\\\"}
  printf '{"systemMessage": "%s"}\n' "${msg//$'\n'/\\n}" >&3
}
trap finish EXIT

# Whether $2, a list of lines, holds the line $1. A bash test rather than a
# grep, since each process costs tens of milliseconds in Git Bash.
has_line() { [[ $'\n'$2$'\n' == *$'\n'"$1"$'\n'* ]]; }
# Reads the file $1, if any, into the variable named $2.
read_file() { [ -f "$1" ] && IFS= read -r -d '' "$2" <"$1"; return 0; }

in_scope() {
  local r
  for r in "${ROOTS[@]}"; do
    [[ $1 == "$r" || $1 == "$r"/* ]] && return 0
  done
  return 1
}

# Plain glob lines only; negations and template lines are skipped.
load_ignores() {
  ignores=()
  [ -f "$1" ] || return 0
  local p
  while IFS= read -r p; do
    p=${p%$'\r'}
    case "$p" in '' | '#'* | '!'* | *'{{'*) continue ;; esac
    ignores+=("$p")
  done <"$1"
}

excluded() {
  case "$1" in
    # claude.ai keeps this folder in sync itself.
    .claude/skills/synced | .claude/skills/synced/*) return 0 ;;
    # Where Claude Code moves the skills it removes.
    .claude/skills/.trash | .claude/skills/.trash/*) return 0 ;;
  esac
  case "${1##*/}" in
    .credentials.json | credentials.json | .env | .env.*) return 0 ;;
    # Caches a tool or an OS writes next to a skill's scripts.
    .DS_Store | Thumbs.db) return 0 ;;
  esac
  case "/$1" in
    # A skill cloned as a Git repo, or one that ships its dependencies.
    */__pycache__/* | */.git/* | */node_modules/* | */.venv/*) return 0 ;;
    # Editor swap and backup files.
    *.swp | *~) return 0 ;;
  esac
  # chezmoi add fails the whole batch on an ignored path, so the user's
  # .chezmoiignore is applied here first.
  local p
  for p in ${ignores[@]+"${ignores[@]}"}; do
    # shellcheck disable=SC2053 # $p is a glob on purpose.
    [[ $1 == $p || $1 == $p/* ]] && return 0
  done
  return 1
}

# Source paths of the managed roots, for a git add that touches nothing else.
# A root chezmoi does not manage fails the whole call, so only the roots in
# $managed go in; one emptied by this run's deletions still fails it, hence
# the call per root as a fallback.
source_roots() {
  local r roots=()
  for r in "${ROOTS[@]}"; do
    if has_line "$r" "$managed" || [[ $'\n'$managed == *$'\n'"$r"/* ]]; then roots+=("$r"); fi
  done
  [ ${#roots[@]} -gt 0 ] || return 0
  chezmoi source-path "${roots[@]}" 2>/dev/null && return 0
  for r in "${roots[@]}"; do
    chezmoi source-path "$r" 2>/dev/null
  done
}

# The target of a source path, in $target, enough to tell whether it falls
# under ROOTS: the attribute prefixes chezmoi puts in front of each name are
# dropped. Sets a variable rather than printing, to spare a subshell.
target_of() {
  local parts part
  target=
  IFS=/ read -r -a parts <<<"$1"
  for part in "${parts[@]}"; do
    while :; do
      case "$part" in
        after_* | before_* | create_* | empty_* | encrypted_* | exact_* | executable_* | \
          external_* | modify_* | once_* | onchange_* | private_* | readonly_* | \
          remove_* | run_* | symlink_*) part=${part#*_} ;;
        *) break ;;
      esac
    done
    case "$part" in dot_*) part=.${part#dot_} ;; literal_*) part=${part#literal_} ;; esac
    target+=${target:+/}${part%.age}
  done
}

# chezmoi keys its persistent state by absolute path, in its own form.
abs() {
  if [ -n "$win" ]; then cygpath -m "$@"; else printf '%s\n' "$@"; fi
}

# chezmoi reads the lines of .chezmoiremove and .chezmoiignore as globs, so a
# path holding * ? [ { would also match other files there. Sets $escaped.
escape_globs() {
  local p b=\\
  escaped=()
  for p in "$@"; do
    p=${p//\\/"$b$b"}
    p=${p//\*/"$b*"}
    p=${p//\?/"$b?"}
    p=${p//\[/"${b}["}
    p=${p//\{/"$b{"}
    escaped+=("$p")
  done
}

# Sorts chezmoi status lines into deletions and edits, read against the last
# state chezmoi wrote here. The first column flags a file deleted (D) or
# edited (M) since then. A blank one means the disk still holds what chezmoi
# wrote, so a difference came from the source (a pull, a reset) and the apply
# brings it. A file chezmoi never wrote here, as on a new machine before its
# first apply, also has a blank column: missing, the apply brings it; present
# and different, it wins and is captured, since it may hold work the repo
# never saw. With fresh=1 (a new clone of a project), every file counts as
# never written, whatever an earlier clone at the same path left in the state.
# Sets left when a line is not captured, so only the apply can bring it.
classify() {
  local status=$1 dest=$2 fresh=$3 line path
  removed=()
  changed=()
  left=
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    path=${line:3}
    [ -z "$dest" ] && ! in_scope "$path" && continue
    case "${line:0:2}" in
      D?) if [ "$fresh" = 1 ]; then left=1; else removed+=("$path"); fi ;;
      M?) changed+=("$path") ;;
      ' M')
        if [ "$fresh" = 1 ] || [[ $written != *"\"${dest:-$home_abs}/$path\":"* ]]; then
          changed+=("$path")
        else
          left=1
        fi
        ;;
      *) left=1 ;;
    esac
  done <<<"$status"
}

# A remote failure, read from git's stderr (run with LC_ALL=C, since the
# messages are translated): a credential the hook cannot ask for is not a
# network outage, and the fix differs.
remote_failed() {
  case "$2" in
    *"Authentication failed"* | *"could not read Username"* | *"terminal prompts disabled"* | \
      *"Permission denied"* | *"Host key verification failed"*)
      say "$1 failed: Git could not log in to the remote without a prompt; check its credential helper or SSH key" ;;
    *) say "$1 failed (offline?); $3" ;;
  esac
}

# An app launched from the macOS Dock or some Linux desktops gets a minimal
# PATH, without the folders chezmoi, git, and gh are often installed in.
for d in "$HOME/.local/bin" "$HOME/bin" /opt/homebrew/bin /usr/local/bin; do
  case ":$PATH:" in *":$d:"*) ;; *) [ -d "$d" ] && PATH=$PATH:$d ;; esac
done
# Git Bash on Windows, where paths go through cygpath.
win=
command -v cygpath >/dev/null 2>&1 && win=1
if ! command -v chezmoi >/dev/null 2>&1; then
  # Without chezmoi there is no source to ask for, so the default one stands in.
  [ -d "${XDG_DATA_HOME:-$HOME/.local/share}/chezmoi/.git" ] &&
    say "chezmoi is not on the PATH this session got, so nothing synced; install it or add its folder to PATH"
  exit 0
fi
src=$(chezmoi source-path 2>/dev/null) || exit 0
git -C "$src" rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0
cd "$HOME" || exit 0

# The skill holds the sync while it sets up a machine: another session must
# not sync before the person has reviewed what the first apply would change.
if [ -e "$src/.git/dotfiles-sync.hold" ]; then
  say "on hold until the setup of this machine is finished; ask Claude to finish the dotfiles-sync setup"
  exit 0
fi

# A hook has no terminal to answer a credentials prompt.
export GIT_TERMINAL_PROMPT=0
# DOTFILES_SYNC_HOST tells apart two machines that share a hostname. Bash
# sets HOSTNAME itself, which spares a process.
host=${DOTFILES_SYNC_HOST:-${HOSTNAME:-$(hostname)}}

# Two sessions starting or ending together would race on the same checkout.
lock="$src/.git/dotfiles-sync.lock"
# Machine-local, like the lock: the large files already named here.
large_file="$src/.git/dotfiles-sync.large"
if ! mkdir "$lock" 2>/dev/null; then
  # A run lasts at most 60 s, so a lock older than two minutes was left by a
  # killed one.
  [ -n "$(find "$lock" -maxdepth 0 -mmin +2 2>/dev/null)" ] || exit 0
  rmdir "$lock" 2>/dev/null
  mkdir "$lock" 2>/dev/null || exit 0
fi
locked=1

managed=$(chezmoi managed --include=files --path-style relative 2>/dev/null) || {
  say "chezmoi could not read its source state; run 'chezmoi doctor'"
  exit 0
}
is_managed() { has_line "$1" "$managed"; }
sources=$(source_roots)
load_ignores "$src/.chezmoiignore"
written=$(chezmoi state dump --format=json 2>/dev/null)
home_abs=$(abs "$HOME")

status=$(chezmoi status --include=files 2>/dev/null) || {
  say "chezmoi could not compare the files; run 'chezmoi doctor'"
  exit 0
}
classify "$status" "" 0
# The home apply runs only when something waits for it: a source-side change
# found here (a reset, a file never applied), a change the pull brings, a root
# renamed this run, or an apply that failed before.
home_apply=$left

# Deletions. Without .chezmoiremove the apply below would bring the file
# back, and the other machines would never drop it.
if [ ${#removed[@]} -gt 0 ]; then
  chezmoi forget --force --no-tty "${removed[@]}" || {
    say "could not record ${#removed[@]} deleted file(s)"
    exit 0
  }
  escape_globs "${removed[@]}"
  printf '%s\n' "${escaped[@]}" >>"$src/.chezmoiremove"
fi

# Edits to files already managed.
if [ ${#changed[@]} -gt 0 ] && ! chezmoi re-add --no-tty "${changed[@]}"; then
  say "could not capture local edits; nothing was pulled, to keep them safe"
  exit 0
fi

# New files. Encrypted like the rest, so the remote only ever holds ciphertext.
added=()
candidate() {
  [ -f "$1" ] && [ ! -L "$1" ] && ! excluded "$1" && ! is_managed "$1" && ! pending_removal "$1" && added+=("$1")
}
# A file whose pulled removal was never applied here, as when that apply
# failed, is still on disk and no longer managed: taken for new, it would
# come back on every machine. Its entry in the state is still the file
# chezmoi wrote, while a file created again after the removal has a remove
# entry, or none once forgotten. Reads $rm_lines (the removal list) and
# $rm_dest, and sets $rm_hit so the apply runs.
pending_removal() {
  [ -n "$rm_lines" ] || return 1
  escape_globs "$1"
  has_line "${escaped[0]}" "${rm_lines//$'\r'/}" || return 1
  local key="\"$rm_dest/$1\": {" e
  [[ $written == *"$key"* ]] || return 1
  e=${written#*"$key"}
  e=${e%%\}*}
  [[ $e == *'"type": "file"'* ]] || return 1
  rm_hit=1
}
# age ciphertext does not delta-compress, so each edit of a large file stores
# a full copy in the repo. A new file over 1 MB is left out of $added and
# named once per machine; added by hand, it then syncs like the rest. $1
# prefixes the paths in the message.
drop_large() {
  [ ${#added[@]} -gt 0 ] || return 0
  local big='' seen='' keep=() new=() p
  while IFS= read -r p; do
    big+=${p#./}$'\n'
  done < <(find "${added[@]/#/./}" -maxdepth 0 -size +1024k 2>/dev/null)
  [ -n "$big" ] || return 0
  [ -f "$large_file" ] && IFS= read -r -d '' seen <"$large_file"
  for p in "${added[@]}"; do
    if ! has_line "$p" "$big"; then
      keep+=("$p")
    elif ! has_line "$1$p" "$seen"; then
      new+=("$1$p")
      printf '%s\n' "$1$p" >>"$large_file"
    fi
  done
  added=(${keep[@]+"${keep[@]}"})
  [ ${#new[@]} -gt 0 ] && say "left out ${#new[@]} new file(s) over 1 MB, such as ${new[0]}; ask Claude to add one by hand to sync it anyway"
  return 0
}
# A file deleted earlier and created again must leave the removal list, or
# the next apply deletes it.
unremove() {
  [ -f "$1" ] || return 0
  escape_globs "${added[@]}"
  grep -Fxv -f <(printf '%s\n' "${escaped[@]}") "$1" >"$1.tmp"
  mv "$1.tmp" "$1"
}
rm_lines=
read_file "$src/.chezmoiremove" rm_lines
rm_dest=$home_abs
rm_hit=
for f in "${FILES[@]}"; do candidate "$f"; done
# CLAUDE.md and the files it imports, and the script the status line runs.
for f in .claude/*.md .claude/statusline*; do candidate "$f"; done
# Public keys only: a private key syncs once added by hand.
for f in .ssh/*.pub; do candidate "$f"; done
for d in "${DIRS[@]}"; do
  [ -d "$d" ] || continue
  # -type f skips symlinks, which could point outside the home folder.
  while IFS= read -r path; do
    candidate "$path"
  done < <(find "$d" -type f)
done
[ -n "$rm_hit" ] && home_apply=1
drop_large "$HOME/"
if [ ${#added[@]} -gt 0 ]; then
  chezmoi add --encrypt --no-tty "${added[@]}" || {
    say "could not add ${#added[@]} new file(s); nothing was pulled, to keep them safe"
    exit 0
  }
  unremove "$src/.chezmoiremove"
  for f in "${added[@]}"; do managed+=$'\n'$f; done
fi
# The roots as they are after the capture, a root just created included. The
# trees below reuse $managed, so this cannot wait for the commit.
now=$(source_roots)
# chezmoi on Windows records no mode, so a root it creates there would land
# as 755 on the other machines, while these two hold keys and tokens.
private=()
while IFS= read -r p; do
  case "${p##*/}" in
    *private_*) ;;
    *dot_ssh) private+=(.ssh) ;;
    *dot_claude) private+=(.claude) ;;
  esac
done <<<"$now"
if [ ${#private[@]} -gt 0 ]; then
  chezmoi chattr --no-tty +private "${private[@]}" || say "could not make ${private[*]} private in the source repo"
  # The apply sets the new mode on the folder.
  home_apply=1
  sources+=$'\n'$now
  now=$(source_roots)
fi
sources+=$'\n'$now

# Trees: each project, the VS Code user folder, and the GitHub CLI folder is
# its own chezmoi source under .dotfiles-sync, applied to a destination that
# differs by machine.
# chezmoi ignores a dot folder in the main source, so the home stays apart.
tree_src=()
tree_dest=()
tree_mark=()
names=
if [ -f "$PROJECTS_CONF" ]; then
  lines=()
  while IFS= read -r line; do
    line=${line%$'\r'}
    case "$line" in '' | '#'*) continue ;; esac
    # shellcheck disable=SC2088 # A literal ~ from the file, expanded here.
    [[ $line == '~/'* ]] && line=$HOME/${line#'~/'}
    lines+=("$line")
  done <"$PROJECTS_CONF"
  # Every line through one cygpath call.
  if [ -n "$win" ] && [ ${#lines[@]} -gt 0 ]; then
    i=0
    while IFS= read -r line; do
      lines[i]=$line
      i=$((i + 1))
    done < <(cygpath -u "${lines[@]}")
  fi
  for line in ${lines[@]+"${lines[@]}"}; do
    if [ -e "$line/.git" ]; then repos=("$line"); else repos=("$line"/*/); fi
    for repo in "${repos[@]}"; do
      repo=${repo%/}
      [ -e "$repo/.git" ] || continue
      name=${repo##*/}
      if has_line "$name" "$names"; then
        say "two projects are named $name; only the first one syncs"
        continue
      fi
      names+=$name$'\n'
      # A .git file (a worktree, a submodule) points to the real folder.
      if [ -d "$repo/.git" ]; then
        gitdir=$repo/.git
      else
        gitdir=$(git -C "$repo" rev-parse --absolute-git-dir 2>/dev/null) || continue
      fi
      # The marker sits in the clone's .git, so a fresh clone has none.
      tree_src+=("$src/.dotfiles-sync/projects/$name")
      tree_dest+=("$repo")
      tree_mark+=("$gitdir/dotfiles-sync")
    done
  done
fi
appdata=
[ -n "$win" ] && [ -n "${APPDATA:-}" ] && appdata=$(cygpath -u "$APPDATA")
if [ -n "$appdata" ]; then
  vscode=$appdata/Code/User
elif [[ $OSTYPE == darwin* ]]; then
  vscode="$HOME/Library/Application Support/Code/User"
else
  vscode=${XDG_CONFIG_HOME:-$HOME/.config}/Code/User
fi
if [ -d "$vscode" ]; then
  tree_src+=("$src/.dotfiles-sync/vscode")
  tree_dest+=("$vscode")
  tree_mark+=("")
fi
if [ -n "${GH_CONFIG_DIR:-}" ]; then
  gh=$GH_CONFIG_DIR
elif [ -n "$appdata" ]; then
  gh="$appdata/GitHub CLI"
else
  gh=${XDG_CONFIG_HOME:-$HOME/.config}/gh
fi
if [ -d "$gh" ]; then
  tree_src+=("$src/.dotfiles-sync/gh")
  tree_dest+=("$gh")
  tree_mark+=("")
fi
# The destinations in chezmoi's form, from one cygpath call.
tree_abs=()
tree_list=()
if [ ${#tree_dest[@]} -gt 0 ]; then
  while IFS= read -r p; do tree_abs+=("$p"); done < <(abs "${tree_dest[@]}")
fi

cz() { chezmoi --source "$tsrc" --destination "$tdest" "$@"; }

# VS Code extensions. Each machine publishes the list it has installed to a
# file of its own and never writes another machine's, so two machines cannot
# conflict on it. What another machine added or removed since this one last
# read its list is applied here; a machine read for the first time only adds.
ext_dir=.dotfiles-sync/vscode-extensions
ext_cache="$src/.git/dotfiles-sync-extensions"
ext_json=$HOME/.vscode/extensions/extensions.json
if [ -n "${VSCODE_EXTENSIONS:-}" ]; then
  ext_json=$VSCODE_EXTENSIONS/extensions.json
  [ -n "$win" ] && ext_json=$(cygpath -u "$ext_json")
fi
ext_on=
ext_host=
ext_cur=
ext_listed=

# The lines of $1 missing from $2.
minus() {
  local l out=''
  while IFS= read -r l; do
    [ -n "$l" ] && ! has_line "$l" "$2" && out+=$l$'\n'
  done <<<"$1"
  printf '%s' "$out"
}
sorted() { printf '%s\n' "$@" | grep -v '^$' | LC_ALL=C sort -u; }

# Each listing starts VS Code's CLI, about a second, so it runs only when
# something may have changed.
ext_list() {
  [ -n "$ext_listed" ] && return 0
  ext_cur=$(code --list-extensions 2>/dev/null | tr -d '\r' | LC_ALL=C sort -u) || return 1
  ext_listed=1
}

# A published list holds the installed extensions, one per line, and a -id
# line for each one this machine removed, so a removal also reaches a machine
# that never saw the extension in this list.
installed_of() {
  local l out=''
  while IFS= read -r l; do [ -n "$l" ] && [ "${l:0:1}" != - ] && out+=$l$'\n'; done <<<"$1"
  printf '%s' "$out"
}
removed_of() {
  local l out=''
  while IFS= read -r l; do [ "${l:0:1}" = - ] && out+=${l:1}$'\n'; done <<<"$1"
  printf '%s' "$out"
}

# Publishes $ext_cur, with the removals already published and those since.
# The cache keeps the list in clear, so an unchanged one needs no
# encryption, and its mtime says when the extensions were last listed.
ext_publish() {
  local own='' gone removed l lines
  read_file "$ext_cache/own" own
  gone=$(minus "$(installed_of "$own")" "$ext_cur")
  removed=$(minus "$(sorted "$(removed_of "$own")" "$gone")" "$ext_cur")
  lines=$(sorted "$ext_cur" "$(while IFS= read -r l; do [ -n "$l" ] && printf -- '-%s\n' "$l"; done <<<"$removed")")
  mkdir -p "$src/$ext_dir" "$ext_cache"
  if [ "$lines" != "$(sorted "$own")" ] || [ ! -f "$src/$ext_dir/$ext_host.age" ]; then
    printf '%s\n' "$lines" | chezmoi encrypt >"$src/$ext_dir/$ext_host.age.tmp" || return 1
    mv -f "$src/$ext_dir/$ext_host.age.tmp" "$src/$ext_dir/$ext_host.age"
  fi
  printf '%s\n' "$lines" >"$ext_cache/own"
}

# Before the commit: publish this machine's list when VS Code changed it.
ext_pre() {
  [ -d "$vscode" ] && command -v code >/dev/null 2>&1 || return 0
  # A * in the VS Code tree's .chezmoiignore leaves the extensions out too.
  load_ignores "$src/.dotfiles-sync/vscode/.chezmoiignore"
  excluded extensions && return 0
  ext_on=1
  ext_host=${host//[^A-Za-z0-9._-]/_}
  # Skipped only when the cache is strictly newer: bash 3.2 compares whole
  # seconds, and an install in the second of the last listing must be seen.
  [ "$ext_cache/own" -nt "$ext_json" ] && return 0
  ext_list || return 0
  ext_publish
}

# After the push, so a run cut short by the hook timeout loses no sync: apply
# what the other machines changed, then publish this machine's new list.
ext_post() {
  [ -n "$ext_on" ] || return 0
  local f h list set seen='' removes adds e failed='' n_added=0 n_dropped=0 bad=()
  read_file "$ext_cache/failed" failed
  for f in "$src/$ext_dir"/*.age; do
    [ -f "$f" ] || continue
    h=${f##*/}
    h=${h%.age}
    [ "$h" = "$ext_host" ] && continue
    # A pull rewrites the file only when that machine's list changed.
    [ "$ext_cache/seen-$h" -nt "$f" ] && continue
    list=$(chezmoi decrypt "$f" 2>/dev/null) || continue
    list=$(sorted "${list//$'\r'/}")
    set=$(installed_of "$list")
    ext_list || return 0
    seen=''
    removes=''
    if [ -f "$ext_cache/seen-$h" ]; then
      read_file "$ext_cache/seen-$h" seen
      removes=$(sorted "$(minus "$(installed_of "$seen")" "$set")" "$(minus "$(removed_of "$list")" "$(removed_of "$seen")")")
    fi
    adds=$(minus "$(minus "$(minus "$set" "$(installed_of "$seen")")" "$ext_cur")" "$failed")
    while IFS= read -r e; do
      [ -n "$e" ] || continue
      # $ext_cur is only searched line by line, and ext_publish sorts it.
      if code --install-extension "$e" >/dev/null 2>&1; then
        ext_cur+=$'\n'$e
        n_added=$((n_added + 1))
      else
        # An extension built for one OS fails on the others at every run.
        mkdir -p "$ext_cache"
        printf '%s\n' "$e" >>"$ext_cache/failed"
        failed+=$e$'\n'
        bad+=("$e")
      fi
    done <<<"$adds"
    while IFS= read -r e; do
      if [ -z "$e" ] || ! has_line "$e" "$ext_cur"; then continue; fi
      code --uninstall-extension "$e" >/dev/null 2>&1 || continue
      ext_cur=$'\n'$ext_cur$'\n'
      ext_cur=${ext_cur/$'\n'"$e"$'\n'/$'\n'}
      n_dropped=$((n_dropped + 1))
    done <<<"$removes"
    mkdir -p "$ext_cache"
    printf '%s\n' "$list" >"$ext_cache/seen-$h"
  done
  if [ $((n_added + n_dropped)) -gt 0 ]; then
    say "VS Code extensions: $n_added installed, $n_dropped removed"
    # Published at once: an extension removed here before the next run must
    # have been seen in this machine's list, or the others would keep it.
    # After a failed push, the next run sends both commits.
    if ext_publish && git -C "$src" add -- "$ext_dir/$ext_host.age" &&
      git -C "$src" commit -q -m "sync: $host extensions" && [ -z "$push_failed" ]; then
      err=$(LC_ALL=C git -C "$src" push -q 2>&1 >/dev/null) || remote_failed push "$err" "will retry next session"
    fi
  fi
  [ ${#bad[@]} -gt 0 ] && say "could not install ${#bad[@]} VS Code extension(s), such as ${bad[0]}; skipped on this machine from now on"
  return 0
}


# Same capture as the home folder, one tree at a time. Returns 1 on a failure,
# so the pull never runs over changes it could not save. A project also sets
# list, its candidate files, which the marker keeps for the next run.
capture_tree() {
  local fresh=0 specs=() tracked=() paths=() path prev=
  list=
  [ -n "$mark" ] && [ ! -e "$mark" ] && fresh=1
  cd "$tdest" || return 0
  if [ -n "$mark" ]; then
    # Stamped before the scan, so an edit made during this run is newer than
    # the stamp the next run compares with. Without a source yet there is
    # nothing to skip, so no stamp.
    [ -d "$tsrc" ] && : >"$mark.next"
    while IFS= read -r -d '' path; do
      project_file "$path" && paths+=("$path") && list+=$path$'\n'
    done < <(git ls-files --others --exclude=node_modules -z -- "${PROJECT_SPECS[@]}")
    # The same candidates as at the last sync and none modified since: no
    # local change, so the chezmoi calls that make most of a run are skipped.
    # A deletion, an addition, or a file the project starts tracking changes
    # the list.
    if [ "$fresh" = 0 ] && [ -d "$tsrc" ] && [ -f "$mark.time" ]; then
      IFS= read -r -d '' prev <"$mark"
      if [ "$list" = "$prev" ] &&
        { [ -z "$list" ] || [ -z "$(find "${paths[@]/#/./}" -newer "$mark.time" 2>/dev/null)" ]; }; then
        return 0
      fi
    fi
  fi
  load_ignores "$tsrc/.chezmoiignore"
  managed=
  if [ -d "$tsrc" ]; then
    managed=$(cz managed --include=files --path-style relative 2>/dev/null) || return 1
    # A file the project's Git now tracks travels with the project: stop
    # managing it, but leave it on the other machines. The ignore line keeps
    # a machine that has not pulled the project yet from adding it back.
    if [ -n "$mark" ] && [ -n "$managed" ]; then
      while IFS= read -r path; do specs+=(":(literal)$path"); done <<<"$managed"
      while IFS= read -r -d '' path; do tracked+=("$path"); done < <(git ls-files -z -- "${specs[@]}")
      if [ ${#tracked[@]} -gt 0 ]; then
        cz forget --force --no-tty "${tracked[@]}" || return 1
        escape_globs "${tracked[@]}"
        printf '%s\n' "${escaped[@]}" >>"$tsrc/.chezmoiignore"
        load_ignores "$tsrc/.chezmoiignore"
        managed=$(cz managed --include=files --path-style relative 2>/dev/null) || return 1
      fi
    fi
    status=$(cz status --include=files 2>/dev/null) || return 1
    classify "$status" "$tabs" "$fresh"
    if [ ${#removed[@]} -gt 0 ]; then
      cz forget --force --no-tty "${removed[@]}" || return 1
      escape_globs "${removed[@]}"
      printf '%s\n' "${escaped[@]}" >>"$tsrc/.chezmoiremove"
    fi
    if [ ${#changed[@]} -gt 0 ]; then
      cz re-add --no-tty "${changed[@]}" || return 1
    fi
  fi
  added=()
  rm_lines=
  read_file "$tsrc/.chezmoiremove" rm_lines
  rm_dest=$tabs
  rm_hit=
  if [ -n "$mark" ]; then
    for path in ${paths[@]+"${paths[@]}"}; do candidate "$path"; done
  elif [ "${tsrc##*/}" = gh ]; then
    # Never hosts.yml: it holds the GitHub token.
    candidate config.yml
  else
    for f in settings.json keybindings.json; do candidate "$f"; done
    if [ -d snippets ]; then
      while IFS= read -r path; do candidate "$path"; done < <(find snippets -type f)
    fi
  fi
  [ -n "$rm_hit" ] && rm_trees+=${tsrc#"$src"/}$'\n'
  drop_large "$tdest/"
  if [ ${#added[@]} -gt 0 ]; then
    mkdir -p "$tsrc"
    cz add --encrypt --no-tty "${added[@]}" || return 1
    unremove "$tsrc/.chezmoiremove"
  fi
  return 0
}

ext_pre
rm_trees=
for ((i = 0; i < ${#tree_src[@]}; i++)); do
  tsrc=${tree_src[$i]} tdest=${tree_dest[$i]} mark=${tree_mark[$i]} tabs=${tree_abs[$i]}
  if ! capture_tree; then
    say "could not capture the changes in $tdest; nothing was pulled, to keep them safe"
    exit 0
  fi
  tree_list[i]=$list
done
cd "$HOME" || exit 0

# The roots as they were before the capture and as they are now, so a root
# emptied by deletions and a root just created are both staged. git add
# rejects a pathspec that matches nothing, which .chezmoiremove is until the
# first deletion.
tracked=()
while IFS= read -r p; do
  [ -n "$p" ] || continue
  p=${p#"$src"/}
  [ -e "$src/$p" ] || git -C "$src" ls-files --error-unmatch "$p" >/dev/null 2>&1 && tracked+=("$p")
done < <(printf '%s\n' "$sources" .chezmoiremove .chezmoiignore .dotfiles-sync | sort -u)
# A root renamed by hand (chezmoi chattr) before this run leaves its old path
# deleted, which no pathspec above names, and the pull refuses a tree with an
# unstaged deletion.
while IFS= read -r -d '' p; do
  target_of "$p"
  in_scope "$target" && tracked+=("$p") && home_apply=1
done < <(git -C "$src" ls-files --deleted -z)
[ ${#tracked[@]} -gt 0 ] && git -C "$src" add -A -- "${tracked[@]}"
if ! git -C "$src" diff --cached --quiet; then
  git -C "$src" commit -q -m "sync: $host" || {
    say "git commit failed; set user.name and user.email in git config"
    exit 0
  }
fi

before=$(git -C "$src" rev-parse HEAD 2>/dev/null)
if ! err=$(LC_ALL=C git -C "$src" pull -q --rebase 2>&1 >/dev/null); then
  if [ -d "$src/.git/rebase-merge" ] || [ -d "$src/.git/rebase-apply" ]; then
    git -C "$src" rebase --abort 2>/dev/null
    say "the same file changed on two machines; ask Claude to resolve the dotfiles-sync conflict"
  elif ! git -C "$src" diff --quiet 2>/dev/null || ! git -C "$src" diff --cached --quiet 2>/dev/null; then
    # git refuses to rebase over changes the sync does not own, such as a
    # hand edit in the source repo or another dotfile.
    say "pull refused: the source repo has uncommitted changes the sync does not own; commit or discard them in $src"
  else
    remote_failed pull "$err" "local changes are committed and will go out next time"
  fi
  exit 0
fi

# What the pull changed: the trees' paths, and anything else for the home.
pulled_src=
if [ -z "$before" ]; then
  home_apply=1
else
  while IFS= read -r -d '' p; do
    case "$p" in
      .dotfiles-sync/*) pulled_src+=$'\n'$p ;;
      *) home_apply=1 ;;
    esac
  done < <(git -C "$src" diff -z --name-only "$before" HEAD 2>/dev/null)
fi
# Applies that failed at an earlier run, "." for the home: the pull that
# brought the change will not bring it again.
pending_file="$src/.git/dotfiles-sync.pending"
pending=
[ -f "$pending_file" ] && IFS= read -r -d '' pending <"$pending_file"
has_line . "$pending" && home_apply=1
still_pending=

# chezmoi apply refuses a root it does not manage. A root left with only
# pending removals is not listed, but the removals are, and go in one by one
# so the deletions reach this machine.
pulled=0
if [ -n "$home_apply" ]; then
  all=$(chezmoi managed --include=all --path-style relative 2>/dev/null)
  targets=()
  for r in "${ROOTS[@]}"; do
    if has_line "$r" "$all"; then
      targets+=("$r")
    else
      while IFS= read -r path; do
        [[ $path == "$r"/* ]] && targets+=("$path")
      done <<<"$all"
    fi
  done
  if [ ${#targets[@]} -gt 0 ]; then
    pulled=$(chezmoi status --include=files,remove "${targets[@]}" 2>/dev/null | wc -l)
    if ! chezmoi apply --force --no-tty "${targets[@]}"; then
      say "could not apply the pulled files; run 'chezmoi apply -v ${targets[*]}' to see why"
      has_line . "$pending" || printf '.\n' >>"$pending_file"
      exit 0
    fi
  fi
fi

# A tree is applied when the pull changed its source, when it is a fresh
# clone, which may lack files the repo already holds, or when its apply failed
# at an earlier run.
for ((i = 0; i < ${#tree_src[@]}; i++)); do
  tsrc=${tree_src[$i]} tdest=${tree_dest[$i]} mark=${tree_mark[$i]}
  [ -d "$tsrc" ] || continue
  rel=${tsrc#"$src"/}
  if { [ -n "$mark" ] && [ ! -e "$mark" ]; } || [[ $pulled_src == *$'\n'"$rel/"* ]] ||
    has_line "$rel" "$pending" || has_line "$rel" "$rm_trees"; then
    n=$(cz status --include=files,remove 2>/dev/null | wc -l)
    cz apply --force --no-tty || {
      say "could not apply the pulled files to $tdest; run 'chezmoi apply -v' there to see why"
      still_pending+=$rel$'\n'
      continue
    }
    pulled=$((pulled + n))
  fi
  if [ -n "$mark" ]; then
    printf '%s' "${tree_list[$i]}" >"$mark"
    mv -f "$mark.next" "$mark.time" 2>/dev/null
  fi
done
# Machine-local, like the markers: the source's .git never syncs.
[ -n "$pending$still_pending" ] && printf '%s' "$still_pending" >"$pending_file"
# BSD wc pads its count with spaces; the arithmetic drops them.
[ "$pulled" -gt 0 ] && say "updated $((pulled)) file(s) from another machine"

push_failed=
if [ -n "$(git -C "$src" log --format=%H '@{u}..HEAD' 2>/dev/null)" ]; then
  if ! err=$(LC_ALL=C git -C "$src" push -q 2>&1 >/dev/null); then
    remote_failed push "$err" "will retry next session"
    push_failed=1
  fi
fi
ext_post
exit 0
