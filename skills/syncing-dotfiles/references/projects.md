# Projects: files kept out of their own Git

The hook carries the files a project keeps out of its Git, such as `CLAUDE.md`, `CLAUDE.local.md`, or `.claude/`, between machines, encrypted like the rest, even when the project folder sits at a different path on each one.

## The list of project folders

Each machine has its own `~/.config/dotfiles-sync/projects`, which never syncs. One path per line, `~/` allowed, and on Windows a `C:\...` path works too:

```text
# A folder of repos: each subfolder with a .git is a project.
~/Documents/GitHub
# A single repo outside that folder.
~/work/client-app
```

A project is known by its folder name, so `C:\Users\me\Documents\GitHub\foo` on one machine and `~/dev/foo` on another are the same project. Ask the person for the folders on each machine and write the file there; the folder names must match across machines. When two listed projects share a name, only the first one syncs, and the hook says so at each run. A clone renamed on one machine is a different project.

## What syncs

At any depth in the project, and only when the project's Git does not track the file: `CLAUDE.md`, `CLAUDE.local.md`, `AGENTS.md`, `.mcp.json`, `.claude/settings.json`, `.claude/settings.local.json`, every file under `.claude/skills/`, `.claude/agents/`, `.claude/commands/`, `.claude/hooks/`, `.claude/rules/`, `.claude/output-styles/`, and in `.vscode/` the files `settings.json`, `launch.json`, `tasks.json`, `extensions.json`, and `*.code-snippets`. Nothing under `node_modules/` syncs, nor `.env` or `credentials.json` files. A tracked file travels with the project's own Git, so the hook leaves it alone.

To sync another kind of file, the allow-list in `hooks/sync.sh` (`project_file`) has to change; adding it by hand with chezmoi does not work here, since each project is its own chezmoi source.

## A fresh clone

After `git clone` on a machine whose list covers the folder, the next sync brings the project's files. A clone is fresh until its first sync (the hook leaves a marker in the clone's `.git`), and in a fresh clone a missing file is fetched, never taken for a deletion, even when an older clone stood at the same path. If Claude Code was already open in that project, the files it reads at startup, such as `CLAUDE.md`, apply from the next session; running the sync by hand before opening the project avoids that.

Deleting a whole project folder deletes nothing on the other machines. Deleting one synced file inside it does.

## Drop a project

A deleted or abandoned project keeps its files in the source repo, and any machine with a clone of that name gets them back. To drop it from the sync for good, delete `.dotfiles-sync/projects/<name>` in the source repo, then sync. The files stay in every existing clone.

## A file the project starts tracking

When a synced file gets committed to the project's Git, the hook stops managing it and writes its path to `.dotfiles-sync/projects/<name>/.tracked` in the source repo, so a machine that has not pulled the project yet does not add it back. The file stays on every disk, and from then on travels with the project.

When the project stops tracking it (`git rm --cached`), the hook syncs it again, since the project's history shows it was tracked once, and drops its line from `.tracked`. A machine whose `git pull` of the project deleted the file gets it back at its next sync. Earlier versions of the hook wrote these paths to the project's `.chezmoiignore` instead: a line there that names a file the project no longer tracks keeps that file out of the sync for good, so delete the line, then sync.
