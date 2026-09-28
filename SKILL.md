---
name: migrate-claude-pc
description: Prepare or apply the migration of a Claude Code project (code, memory, conversation history, skills and preferences) between computers, including restoring old conversations in the Claude Desktop sidebar. Use when the user asks to "migrate to another computer", "move this project to a new PC", "prep this for a client machine", "export project to a USB drive", or asks to continue a migration on a new machine after already receiving a migration folder.
---

# Migrate a project between computers

Two phases: **export** (on the source PC) and **import** (on the destination PC). Always read `references/lessons-learned.md` first, it has important notes on what not to attempt.

## Phase 1: Export (on the source PC)

1. Ask (or confirm, if obvious from the request) which project and where the output folder should go (Desktop, Downloads, or directly a cloud/USB folder).
2. Create the output folder with this structure:
   ```
   <destination>\
     README-migration.txt          <- written fresh, specific to this project (see below)
     import-on-this-pc.ps1         <- reference script (see "scripts/" below; write a simple one if the project doesn't already have one)
     <ProjectName>\                <- project code
     claude-history-and-memory\    <- copied from ~/.claude/projects/<source-project-slug>/
     claude-global\CLAUDE.md       <- copy of this PC's ~/.claude/CLAUDE.md
     claude-global\MIGRATION-NOTE.txt
     claude-skills\<skill>\        <- only the global skills relevant to this project (see step 4)
     scripts\fix-session-paths.ps1         <- copy from this skill's scripts/, as-is
     scripts\register-sessions-sidebar.ps1 <- copy from this skill's scripts/, as-is
     scripts\import-all-sessions.ps1       <- copy too, even for a single project (this is the one the user should actually run)
   ```
   For **more than one project** at once (e.g. "migrate everything", one `projects\<name>\` folder per project instead of a single one at the root), the structure is the same but with `projects\<name1>\`, `projects\<name2>\`... and `claude-history-and-memory\<name1>\`, `claude-history-and-memory\<name2>\`... one per project. Don't repeat steps 4-8 verbatim per project, but walk through them for each.
3. Copy the project code with robocopy, excluding what regenerates on its own: `node_modules`, `.next`/`dist`/`build`, `.venv`/`__pycache__`, local databases (`.data` and similar). For large or sensitive data folders (backups, exports with real data), ask the user whether to include them or transfer separately (USB/external drive), same for any secret (non-public `.env*`).
4. Decide which global skills (`~/.claude/skills/<name>`) to copy: read the project's history/memory and `CLAUDE.md` for mentions of specific skills this project uses (don't copy all ~70+ skills, only the relevant ones). Ask the user if unsure.
5. Copy `~/.claude/projects/<slug>/` (memory + history) in full to `claude-history-and-memory\` (the slug is the project path with `:`, `\` and spaces replaced by `-`).
6. Copy `~/.claude/CLAUDE.md` to `claude-global\CLAUDE.md`, and write `claude-global\MIGRATION-NOTE.txt` explaining it should be merged (not replaced) with the destination PC's `CLAUDE.md`.
7. Copy the three generic scripts from this skill's `scripts/` (`fix-session-paths.ps1`, `register-sessions-sidebar.ps1`, `import-all-sessions.ps1`) as-is, without changes.
8. Write `README-migration.txt` fresh (don't copy an old one from another project), specific to this one: what's in the folder, what to do on the new PC, step by step, always ending with:
   - rebuild dependencies/database from the project's own code (never copy a database binary from another machine)
   - at the end, ask the user to run, themselves, in a normal PowerShell terminal (don't ask Claude to run it, it will be refused): `import-all-sessions.ps1`, pointed at the already-copied project folder
9. Show the user a summary of what's in the folder and its total size.

## Phase 2: Import (on the destination PC)

This is what has already been done successfully for real projects; follow the same path.

1. Read `README-migration.txt` from the received migration folder first.
2. Move the project code to the right place. If something with that name already exists there, don't overwrite without warning the user.
3. Read `claude-global\MIGRATION-NOTE.txt` and merge this PC's `CLAUDE.md` with the source PC's: show the merge draft to the user before saving, never save directly.
4. Copy `claude-history-and-memory\` to `~/.claude/projects/<slug-computed-for-the-new-path>/`.
5. Copy the skills from `claude-skills\` to `~/.claude/skills/`. If a skill has hardcoded paths from the other PC (e.g. a reference file location), update it and ask the user if not obvious.
6. Check what's already installed (node, npm, python, etc.) before blindly reinstalling. Install dependencies and rebuild the local database from the project's own migrations/scripts (never copy a database binary).
7. If the project uses graphify and this PC has the package installed but never wired into Claude Code, run `graphify install --platform claude` first.
8. Test that the app starts (if applicable).
9. **Don't try to run the session scripts directly** (they'll be refused, see `references/lessons-learned.md`). Instead, tell the user to run, themselves, in a normal PowerShell terminal, the consolidated script (handles one project or several at once, discovers them on its own if you don't name them):
   ```
   powershell -File "<migration-folder>\scripts\import-all-sessions.ps1"
   ```
   Only use the two individual scripts (`fix-session-paths.ps1` / `register-sessions-sidebar.ps1`) if the user wants to repeat this for one specific project afterwards. After the consolidated script, the user has to fully quit Claude Desktop (including the system tray icon) and reopen it for the sidebar to refresh. Once is enough, even with several projects.
10. **After reopening the app** (or in the next session, once the user confirms the scripts ran): group the imported sessions automatically, don't ask the user to drag them by hand. Unlike writing session files, this is a built-in app function and is not blocked:
    - `list_groups` (ccd_sidebar) to see existing groups.
    - `list_sessions` (ccd_session_mgmt, high limit) and filter by `cwd` matching the imported project's folder.
    - If a group with the project's name already exists (or something close, e.g. the user pre-created it empty on purpose): `move_sessions` there, all at once.
    - If none exists: `create_group` with the project's name, then `move_sessions`.
    - Do this for ALL sessions found for the project, not just the most recent ones.
11. Final summary to the user: what was moved, what ended up in the final `CLAUDE.md`, whether the app started, how many sessions were grouped and where.

## Notes

- The only truly manual step left for the user is running the script in `scripts\` (blocked for Claude) and reopening the app. Grouping sessions in the sidebar **is not manual**, it's done with `ccd_sidebar` (see step 10 of Phase 2) as soon as the app shows them.
- When the request is just "continue the migration in this folder" (an already-received folder with `README-migration.txt` inside), go straight to Phase 2.
- If the user says they already ran the scripts (or asks why sessions aren't grouped), step 10 alone fixes it, no need to redo the file copy.
- If a fix was already run once and something (like a file link in message content) is still broken, don't detect old paths from the live session files: read `references/lessons-learned.md`, the backup folder must be the source of truth.
