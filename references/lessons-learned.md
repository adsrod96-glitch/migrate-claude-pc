# Lessons learned

Context behind this skill's design decisions, so you don't repeat attempts that are already known to fail.

## Claude Code auto-blocks two actions

When running inside the Claude Desktop app (not a plain terminal), two actions in this migration flow get refused by automatic safety classifiers, even with explicit user authorization in chat:

1. **Editing the `cwd` field (or any content) inside session `.jsonl` files** → blocked as "Session Transcript Tampering". Don't try another route (different tool, different encoding, a subagent). The fix is always: write the script (`fix-session-paths.ps1`) and ask the user to run it themselves in a normal PowerShell terminal.
2. **Creating registration files under `AppData\...\claude-code-sessions\`** (for the sidebar) → blocked as "Self-Modification". Same fix: generate the script (`register-sessions-sidebar.ps1`) and have the user run it themselves.

This is not a bug to work around, it's a deliberate guardrail. Don't keep retrying, don't burn attempts, and don't suggest the user "unblock" this except through their own permission settings.

**Important:** this does NOT apply to grouping sessions in the sidebar (`ccd_sidebar__move_sessions` / `create_group` / `list_groups`). Those are the app's own built-in functions, exposed as normal tools, and work without any block. Don't confuse "hand-crafting a `local_*.json` file" (blocked) with "moving an existing session into a group" (allowed, dedicated tool). Once `register-sessions-sidebar.ps1` has run and the app is reopened, grouping itself is always done this way, never by asking the user to drag things by hand.

## The app's data folder isn't always named "Claude"

On Microsoft Store installs, the app's data is virtualized under:
`AppData\Local\Packages\Claude_<hash>\LocalCache\Roaming\Claude\claude-code-sessions\...`

On regular installs (direct .exe installer), it's usually:
`AppData\Roaming\Claude\claude-code-sessions\...`

That's why `register-sessions-sidebar.ps1` searches for it on its own (`Get-ChildItem -Recurse -Filter "claude-code-sessions"`) instead of assuming the path. Never hardcode this path.

## The environment where Claude runs commands may not match what the user sees

In one session, Claude could read/write `AppData\Roaming\Claude\...` through its own tools (Bash/PowerShell), but that folder didn't exist in the user's real terminal (Microsoft Store install, it was a different folder). In other words: what Claude sees when running commands may not correspond 1:1 to the user's real system for folders outside `Documents`/`Desktop`/the project itself. For any path outside the project (AppData, Program Files, etc.), always confirm with the user by having them run a diagnostic command themselves, instead of trusting what Claude "saw".

## The `local_*.json` schema changes

Don't hardcode the session registration JSON's fields. Instead, read a real, already-existing `local_*.json` on the destination PC and clone its structure (`$template = Get-Content ... | ConvertFrom-Json`; `$new = $template | Select-Object *`), only overriding the fields specific to the session being imported (`sessionId`, `cliSessionId`, `cwd`, `originCwd`, dates, `model`, `title`). This is what `register-sessions-sidebar.ps1` already does.

## `fix-session-paths.ps1` must fix the whole text, not just the `cwd` field

A migrated session can have, in the message text itself, links to files generated during that session (e.g. an exported PDF) with the old absolute path. If only the `cwd` field gets fixed, those links stay broken (the app shows "Couldn't load this preview" when opening the attachment). The right fix: extract just the project's ROOT from the old `cwd` values detected (up to and including the project folder name) and replace that prefix across the whole file's text, not only inside `"cwd":"..."`. This fixes the `cwd`, tool-call paths, and file links shown in messages, all in one pass. The script also supports the posix form (`/c/Users/...`) used by sessions that ran through git-bash.

**Real trap (already happened):** never detect old paths from the LIVE files if a fix has already run before (even just to `cwd`). Once `cwd` is fixed, the old path no longer appears anywhere in those files, even though a stray old mention (e.g. that PDF link) survives in the message text, because it was never tied to a `cwd` field to begin with. Result: the second fix finds "nothing old" and exits without touching anything, even though real bugs remain. The fix: always detect from the backup folder (`<folder>.pre-fix-backup`), which holds the original state from before any fix, and apply the found replacements to the live files. The script already does this.

## `register-sessions-sidebar.ps1` must dedupe

Running the script twice on the same project (or the user asking "won't this duplicate?") must always produce the same sidebar list, never doubled. Before creating a new `local_*.json`, the script reads the `cliSessionId` of every registration already in the registration folder and skips any `.jsonl` whose original session ID is already there. Already implemented, don't remove this check if the script gets rewritten.

## What worked well and is worth repeating

- Copy the project with `robocopy /E /XJ /NFL /NDL /NP`, excluding `node_modules`, `.next`/`dist`/`build`, `.data`, and asking before including large sensitive data folders (e.g. backups with real customer data).
- Merge the global `CLAUDE.md` by showing the draft to the user before saving, never overwrite without showing it.
- Check what's already installed (node, npm, etc.) before reinstalling.
- Rebuild the local database from the project's own migrations/scripts, never copy a binary database from another machine.
- If the project has graphify installed on the destination PC but never wired into Claude Code, run `graphify install --platform claude` first, then proceed with `/graphify` normally.
