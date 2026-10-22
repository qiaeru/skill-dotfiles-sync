# Dotfiles sync for Claude Code

`dotfiles-sync`, a Claude Code plugin that keeps your dotfiles identical on every machine you use: the global Claude Code config (`settings.json`, `CLAUDE.md`, your skills, agents, commands, and more), your Git config, your SSH config and public keys, the `CLAUDE.md`, `.claude/`, and `.vscode/` files your projects keep out of their own Git, your VS Code user settings, and your GitHub CLI config. The files travel encrypted with [age](https://age-encryption.org) through a private Git repo that [chezmoi](https://www.chezmoi.io) manages, and the sync runs on its own when a Claude Code session starts and when it ends.

Once a machine is set up, there is nothing to run: edit a setting, add a skill, or add a host to your SSH config on one machine, and the next session on another machine has it. The same goes for the untracked `CLAUDE.md` of a project, even when the project sits at another path on the other machine. A skill, `syncing-dotfiles`, walks Claude through what a hook cannot do alone: the one-time setup, adding a machine, resolving a conflict, syncing an SSH private key on request, and keeping a file out of the sync.

## How it works

The plugin's hooks run [sync.sh](hooks/sync.sh) at `SessionStart` (on startup and resume) and at `SessionEnd`. Each run does, in order:

1. capture local changes into the chezmoi source repo: edits to synced files, new files from the allow-list (encrypted on the way in), and deletions (recorded in `.chezmoiremove` so the other machines drop the file too);
2. commit them;
3. pull with a rebase;
4. apply the pulled files to your home folder, your projects, and the VS Code and GitHub CLI folders;
5. push.

Local changes are committed before the pull, so the forced apply never overwrites unsaved work. A change counts as local when the file differs from the version chezmoi last wrote on this machine: a file the repo holds and this machine never received is fetched, never taken for a deletion. When both machines changed the same file between two syncs, Git cannot merge the ciphertext: the run stops before applying anything, tells you, and the skill guides the merge. Offline, the changes wait in a local commit and leave on the next run.

A file edited outside a Claude Code session, a `~/.gitconfig` changed from a terminal for instance, goes out at the start of the next session.

The script prints nothing when all goes well. Otherwise it shows one line to you (a `systemMessage`), never to the model, and it always exits successfully, so a failed sync never blocks a session.

## What syncs

The hook reaches four places in your home folder (`~/.claude`, `~/.gitconfig`, `~/.config/git`, `~/.ssh`), the project folders you list, and the VS Code and GitHub CLI folders. Inside them it picks up new files from an allow-list, so a sensitive file that a tool adds there later is missed, not leaked:

| Domain | Synced | Never synced unless you ask |
| --- | --- | --- |
| Claude Code | `settings.json`, `keybindings.json`, `CLAUDE.md`, and the `skills/`, `agents/`, `commands/`, `hooks/`, `rules/`, `output-styles/`, `workflows/`, `agent-memory/`, `themes/` folders | |
| Git | `~/.gitconfig`, `~/.config/git/config`, `~/.config/git/ignore`, `~/.config/git/attributes` | |
| SSH | `~/.ssh/config`, `~/.ssh/config.d/`, public keys (`*.pub`) | private keys, `known_hosts`, `authorized_keys` |
| Projects | files the project's Git does not track, at any depth: `CLAUDE.md`, `CLAUDE.local.md`, `AGENTS.md`, `.claude/settings.json` and `settings.local.json`, the `.claude/` `skills/`, `agents/`, `commands/`, `hooks/`, `rules/`, `output-styles/` folders, and the `settings`, `launch`, `tasks`, `extensions` JSON files and `*.code-snippets` of `.vscode/` | |
| VS Code | `settings.json`, `keybindings.json`, `snippets/` of the user folder (`%APPDATA%\Code\User` on Windows, `~/.config/Code/User` on Linux) | |
| GitHub CLI | `config.yml` (`%APPDATA%\GitHub CLI` on Windows, `~/.config/gh` elsewhere) | |

A file in the last column syncs once you ask Claude to add it, and from then on like the others. The skill advises against it for private keys (one key per machine can be revoked alone) and warns that a shared `known_hosts` conflicts each time two machines meet a new host between two syncs.

Some files never sync, and the skill refuses to add them: `.credentials.json`, `credentials.json`, `.env` and `.env.*` files, `~/.claude.json` (OAuth and MCP tokens, machine state), `~/.claude/plugins/` (caches and machine-absolute paths), `~/.claude/projects/` (session history, per-path memory), `~/.claude/skills/synced/` (claude.ai already syncs it), `~/.git-credentials`, and the GitHub CLI's `hosts.yml` (its token). Symlinks are not followed.

Plugins come back on their own: `settings.json` carries `enabledPlugins` and `extraKnownMarketplaces`, and Claude Code reinstalls from them. Git values that must differ per machine, such as `core.autocrlf` or `credential.helper`, go in an unsynced `~/.gitconfig.local` that the shared file includes; the skill sets it up. Add any path to `.chezmoiignore` in the source repo to keep it local, or a whole folder such as `.ssh` to leave a domain out.

Your projects sit at different paths on each machine, so each machine lists its own project folders in `~/.config/dotfiles-sync/projects`, which never syncs: a repo, or a folder of repos, per line. A project is known by its folder name, so `C:\Users\you\Documents\GitHub\foo` on Windows and `~/dev/foo` on Linux are the same project. A file the project's Git tracks travels with the project, and the hook leaves it alone. A fresh clone gets its files at the next sync, and deleting a whole project folder deletes nothing on the other machines.

Other dotfiles you manage with chezmoi in the same repo, a `.bashrc` for instance, are outside the hook's reach: it never commits or applies them, so you keep managing them by hand.

## Security model

- Every synced file is encrypted with age before it reaches Git. The remote, and whoever can read it, sees only ciphertext.
- File names, folder structure, commit dates, and the machine name in commit messages are not encrypted. That is why the repo should be private all the same.
- The age key (`~/.config/chezmoi/key.txt`) never goes into Git. Keep a copy in your password manager: every new machine needs it, and without it the repo cannot be decrypted. The skill covers a lost or leaked key.
- An SSH private key you choose to sync is only as safe as that age key. If the age key leaks, rotate the SSH keys too; the skill walks through it.
- The sync runs only in your own sessions, with your own Git credentials. Nothing is sent anywhere but the Git remote you chose.

## Requirements

- A recent [chezmoi](https://www.chezmoi.io/install/), one with the `chezmoi age-keygen` command: its age support is built in, so age needs no separate install.
- Git, and on Windows Git for Windows, whose Git Bash runs the hook.
- A private Git repo you can push to without a prompt (SSH key or credential helper). The [GitHub CLI](https://cli.github.com) lets Claude create it for you.

## Installation

Inside Claude Code, add this repository as a marketplace, then install the plugin:

```text
/plugin marketplace add qiaeru/skill-dotfiles-sync
/plugin install dotfiles-sync@skill-dotfiles-sync
```

Then ask Claude to set up the sync (for example "set up dotfiles-sync on this machine"), or invoke the skill by name with `/dotfiles-sync:syncing-dotfiles`. On the first machine, Claude installs chezmoi, generates the key, creates the private repo, asks which domains to sync, and runs the first sync. On every other machine, it installs chezmoi, asks you to paste the key from your password manager, shows what would change in your existing files, and asks which version wins before applying anything.

Until chezmoi is set up, the hooks do nothing, silently.

## Usage

There is nothing to run day to day. The skill also covers:

- When the hook reports that a file changed on two machines, ask Claude to resolve the dotfiles-sync conflict. It shows both versions, merges them with you, and syncs the result.
- To sync an SSH private key or `known_hosts`, ask Claude. It explains the risk, adds the file encrypted and with the right permissions, and syncs.
- To keep a file local, ask Claude to exclude its path from the sync. Deleting a synced file, by contrast, deletes it on every machine.
- To sync a new project folder, ask Claude to add it to this machine's list; the next sync picks up its untracked files.
- A value that differs per machine goes in a local include for Git, and in a chezmoi template for any other file, edited with `chezmoi edit` from then on.
- `/plugin disable dotfiles-sync` pauses the sync and leaves the files where they are.

## Layout

```text
skill-dotfiles-sync/
├── .claude-plugin/
│   ├── plugin.json
│   └── marketplace.json
├── .github/
│   ├── scripts/
│   │   └── validate.mjs
│   ├── workflows/
│   │   └── validate.yml
│   ├── dependabot.yml
│   └── FUNDING.yml
├── hooks/
│   ├── hooks.json
│   └── sync.sh
├── skills/
│   └── syncing-dotfiles/
│       ├── SKILL.md
│       └── references/
│           ├── claude-code.md
│           ├── git.md
│           ├── github-cli.md
│           ├── projects.md
│           ├── ssh.md
│           └── vscode.md
├── tests/
│   └── sync-test.sh
├── .gitattributes
├── .gitignore
├── .markdownlint-cli2.jsonc
├── README.md
├── CHANGELOG.md
└── LICENSE
```

The repository doubles as the `dotfiles-sync` plugin and as its own marketplace: `plugin.json` describes the plugin (the whole repository, with the hooks under `hooks/` and the skill under `skills/`), and `marketplace.json` lists it so Claude Code can install and update it straight from GitHub. The skill keeps the shared procedures in `SKILL.md` and what is specific to each domain in `references/`, which Claude reads only when a file of that domain is involved.

## Tests

[sync-test.sh](tests/sync-test.sh) runs the hook end to end: two fake home folders share a bare Git remote in a temporary folder, and the test checks the first setup, the allow-list and exclusions across the home domains, encryption on the remote, edits, additions and deletions in both directions, a private key added by hand, other chezmoi dotfiles left alone, a conflict and its resolution, a new machine that syncs before its first apply, an offline run, a failed apply retried at the next sync, project files across two paths with a fresh clone and a file the project starts tracking, the VS Code user settings, the GitHub CLI config without its token file, and a machine without chezmoi. It needs chezmoi and Git, and touches nothing outside its temporary folder:

```text
bash tests/sync-test.sh
```

On every push, every pull request, and once a week, the [validate.yml](.github/workflows/validate.yml) workflow runs that test on Linux, Windows, and macOS (with the bash 3.2 that macOS ships), lints both scripts with ShellCheck, and checks the markdown, the plugin manifests (`plugin validate`), and the repository invariants in [validate.mjs](.github/scripts/validate.mjs).

## Limits

- One person, several machines. The sync is not built for sharing a config within a team: a project's Git already does that for the files it tracks.
- A project must keep the same folder name on every machine, and its file allow-list is fixed in the hook: another kind of untracked file needs a change to `project_file` in `sync.sh`.
- A conflict on a file stops the whole sync on that machine until it is resolved, so the other changes wait too.
- The sync runs only around Claude Code sessions. A machine where you never open Claude Code never receives the changes.
- The hook has 30 seconds at session start and 60 at the end. A project with no local change since its last sync costs about a tenth of a second, so dozens of listed projects fit in that time. A run cut short leaves a lock that the next run clears after two minutes; nothing is lost, since the files stay on disk and the next run captures them.
- `.chezmoiignore` lines that use templates or negations are honored by chezmoi but not by the hook's discovery of new files, which only reads plain globs.

## License

MIT, see [LICENSE](LICENSE).
