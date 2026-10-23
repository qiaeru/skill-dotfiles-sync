# Claude Code: ~/.claude

The hook syncs the global Claude Code config: `settings.json`, `keybindings.json`, every `*.md` at the top of `~/.claude` (`CLAUDE.md` and the files it imports with `@~/.claude/<file>.md`), the status line script (`statusline*`, such as `statusline-command.sh`), and every file under `skills/`, `agents/`, `commands/`, `hooks/`, `rules/`, `output-styles/`, `workflows/`, `agent-memory/`, and `themes/`. A file anywhere else in `~/.claude` is ignored, so a new sensitive file Claude Code adds later is missed rather than leaked.

## Never sync

Refuse to add these by hand, and if the person asks, explain why it breaks or leaks before doing anything:

- `~/.claude.json`: OAuth and MCP tokens and machine state, rewritten constantly by every session;
- `~/.claude/.credentials.json`: the login itself;
- `~/.claude/plugins/`: caches and machine-absolute paths;
- `~/.claude/projects/`: session history and per-path memory, keyed by the absolute path of each repo.

`~/.claude/skills/synced/` stays out because claude.ai already keeps it in sync, and `~/.claude/skills/.trash/` because Claude Code moves the skills it removes there.

## Values that differ per machine

`settings.json` travels whole, so a value that only makes sense on one machine breaks the others: an `env` entry holding an absolute path (`C:\Users\...`), a browser or tool that only one OS has, a hook command that calls a Windows or macOS program. On the first apply of another machine, look for such values in the diff and ask the person where they belong. A per-machine environment variable goes in that machine's shell profile or system environment, outside `settings.json`. Avoid making `settings.json` a template: Claude Code rewrites the file itself (`/config`, permission prompts), and the hook does not capture edits to a template.

## Scripts in skills

chezmoi on Windows records no file mode, so a script added there (a skill's `scripts/*.sh` or `*.py`) lands without the executable bit on Linux and macOS, and a skill that runs it as `./script.sh` fails there. After the first sync of a Windows machine, check the scripts under `~/.claude/skills/` on a Unix one; mark those that need it with `chmod +x <path>` and a sync, which records the bit (`re-add` reads the mode from the disk outside Windows). A script saved with CRLF line endings fails on Unix too (`bad interpreter: /bin/bash^M`); convert it to LF on the machine that wrote it.

## Plugins

Plugins come back on their own on every machine: `settings.json` carries `enabledPlugins` and `extraKnownMarketplaces`, and Claude Code reinstalls from them at the next start. No plugin folder needs to travel.

## First apply on another machine

A machine that already used Claude Code has its own `settings.json` and maybe its own skills. In `chezmoi diff .claude`, look first at `settings.json`: a union of the keys is usually what the person wants (permissions, `enabledPlugins`, `env`). Write the merged file locally, then apply the other files and let the sync capture the merge.

## Project folders

The `.claude/` folder inside each repo travels with that repo when its Git tracks it. The files a project keeps out of its Git sync once the project's folder is listed: [projects.md](projects.md).
