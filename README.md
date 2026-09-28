# migrate-claude-pc

A [Claude Code](https://claude.com/claude-code) skill that migrates a project — code, memory, conversation history, global skills and preferences — from one Windows computer to another, and restores the old conversations in the **Claude Desktop sidebar** (not just via `claude --resume` in a terminal).

## Why

Claude Code stores project history under `~/.claude/projects/<encoded-path>/`, keyed by the exact absolute path of the project on that machine. Move the project to a new computer (new username, new drive letter, whatever) and the history technically still exists, but:

- `claude --resume` won't find it until the paths inside the session files are fixed.
- Even after that, Claude Desktop's sidebar still won't show it — the app keeps its own separate session registry under `AppData`, unrelated to the raw `.jsonl` files.
- File links inside old messages (a PDF you generated in that session, for example) stay broken if only the `cwd` field gets fixed and not the rest of the text.

This skill handles all three problems, end to end, and knows which parts Claude Code will refuse to do for itself (see [Why some of this has to run manually](#why-some-of-this-has-to-run-manually) below) — those are exactly the two scripts it hands you to run.

## Install

Drop this repo into your global skills folder:

```powershell
git clone https://github.com/<your-username>/migrate-claude-pc.git "$env:USERPROFILE\.claude\skills\migrate-claude-pc"
```

Claude Code will pick it up automatically. Next time you ask it to migrate a project to a new PC (or to continue a migration you already started), it uses `SKILL.md` as its playbook.

## What's in here

| File | What it does |
|---|---|
| `SKILL.md` | The playbook Claude Code follows: what to copy, in what order, what to ask you about, what to hand off to you. |
| `references/lessons-learned.md` | The real bugs and dead ends hit while building this, so Claude doesn't repeat them. |
| `scripts/fix-session-paths.ps1` | Rewrites the old computer's path inside a project's `.jsonl` session files — not just the `cwd` field, the whole text (so file links stay working too). |
| `scripts/register-sessions-sidebar.ps1` | Registers those sessions with Claude Desktop's own session index, so they appear in the sidebar. Deduplicates automatically — safe to run more than once. |
| `scripts/import-all-sessions.ps1` | Runs both of the above for every migrated project at once. Discovers the projects on its own. This is the one you'll actually run. |

## Why some of this has to run manually

Claude Code has built-in safety guardrails that refuse two specific actions when running inside the Claude Desktop app, even with your explicit go-ahead in chat:

1. Editing anything inside a session's `.jsonl` transcript (classified as session history tampering).
2. Writing a new session-registration file into the app's own `AppData` config folder (classified as self-modification).

That's by design, not a bug. So the skill's flow is: Claude does everything else automatically (copying the project, merging `CLAUDE.md`, reinstalling dependencies, rebuilding the local database, grouping sessions in the sidebar once they exist), and for those two specific steps it writes the script and asks you to run it yourself in a plain PowerShell terminal. One command, `import-all-sessions.ps1`, covers both.

## Usage

On the **source** PC, ask Claude Code something like:

> "Migrate this project to a new computer, I'll copy the folder over myself."

On the **destination** PC, after you've copied the resulting folder over (USB drive, cloud sync, whatever):

> "Here's the migration folder Claude prepared on my old PC, set it up here."

Claude reads `SKILL.md` and takes it from there. At the end it'll tell you to run:

```powershell
powershell -File "<migration-folder>\scripts\import-all-sessions.ps1"
```

then fully quit and reopen Claude Desktop. Your old conversations show up in the sidebar, grouped by project.

## Compatibility

- Windows only (PowerShell scripts, Windows path handling).
- Works with both the regular Claude Desktop installer and the Microsoft Store version (the scripts locate the right `AppData` folder on their own — the Store version virtualizes it under `AppData\Local\Packages\Claude_*\...`).
- No project-specific assumptions: no hardcoded usernames, paths, or project names. Everything is derived at runtime from the project path you give it.

## License

MIT — see [LICENSE](LICENSE).
