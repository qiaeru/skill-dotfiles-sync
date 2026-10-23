# Claude Code: ~/.claude

The hook syncs the global Claude Code config: `settings.json`, `keybindings.json`, and `CLAUDE.md` at the top of `~/.claude`, and every file under `skills/`, `agents/`, `commands/`, `hooks/`, `rules/`, `output-styles/`, `workflows/`, `agent-memory/`, and `themes/`. A file anywhere else in `~/.claude` is ignored, so a new sensitive file Claude Code adds later is missed rather than leaked.

## Never sync

Refuse to add these by hand, and if the person asks, explain why it breaks or leaks before doing anything:

- `~/.claude.json`: OAuth and MCP tokens and machine state, rewritten constantly by every session;
- `~/.claude/.credentials.json`: the login itself;
- `~/.claude/plugins/`: caches and machine-absolute paths;
- `~/.claude/projects/`: session history and per-path memory, keyed by the absolute path of each repo.

`~/.claude/skills/synced/` stays out because claude.ai already keeps it in sync, and `~/.claude/skills/.trash/` because Claude Code moves the skills it removes there.

## Plugins

Plugins come back on their own on every machine: `settings.json` carries `enabledPlugins` and `extraKnownMarketplaces`, and Claude Code reinstalls from them at the next start. No plugin folder needs to travel.

## First apply on another machine

A machine that already used Claude Code has its own `settings.json` and maybe its own skills. In `chezmoi diff .claude`, look first at `settings.json`: a union of the keys is usually what the person wants (permissions, `enabledPlugins`, `env`). Write the merged file locally, then apply the other files and let the sync capture the merge.

## Project folders

The `.claude/` folder inside each repo travels with that repo when its Git tracks it. The files a project keeps out of its Git sync once the project's folder is listed: [projects.md](projects.md).
