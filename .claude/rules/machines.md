<!-- Copy of <personal OneDrive>\ClaudeCode-sync\machines.md, kept in the repository so that cloud sessions
     and fresh clones know the layout too. Edit the OneDrive copy and refresh this one with
     ClaudeCode-sync\Publish-MachinesRule.ps1. -->

# Computers that share Claude Code chats

The same person works on three Windows computers. Chats (transcripts, project memory, edit history,
the desktop app's session list) travel between them as snapshots in the personal OneDrive folder
`ClaudeCode-sync`, one sub-folder per computer. Code travels through git. Nothing else is shared.

| Label     | Role                         | Windows name | User       | Home                 | Repo roots                                               |
|-----------|------------------------------|--------------|------------|----------------------|----------------------------------------------------------|
| IP_LEGION | main laptop                  | IP_LEGION    | `goras`    | `C:\Users\goras`     | `D:\Apps\<repo>`, `D:\Projects\<repo>`                   |
| IP_KZZL   | university PC                | (see machines.json) | `iorpawec` | `C:\Users\iorpawec` | GitHub Desktop clones, `C:\Users\iorpawec\Documents\GitHub\<repo>` |
| IP_DORM   | dorm PC                      | GORASZ       | `PC`       | `C:\Users\PC`        | `E:\Apps\<repo>`, `E:\Projects\<repo>`                   |

`machines.json` next to this file is the authoritative registry (`Sync-ClaudeCode.ps1` reads it);
this table is a readable copy. Repos under the `apps` root: silvasim, obiastudio, rgeopl. Under
`projects`: IoTreesNet, _BAZA_MARTWYCH_DRZEW, 9_paper_deeplearning. Personal OneDrive folders such as
`<home>\OneDrive\5_DYDAKTYKA` exist on every computer under that computer's home.

## How a session knows where it is

A `SessionStart` hook runs `Sync-ClaudeCode.ps1 -Status -Brief` and prints `[claude-sync]` lines:
this computer's label, the current repo (branch, uncommitted files, commits not pushed), whether this
computer's own snapshot is older than its chats, and which other computers' snapshots are not yet
imported here. Trust those lines over the user's memory of which computer they sit at; if the user
says otherwise, point out the mismatch. `/sync` (skill) and the `machine-check` agent give the full
status on demand.

## Routine when switching computers

Leaving a computer:
1. `git push` in every repo touched (the hook line "commits NOT PUSHED" is the reminder).
2. `Sync-ClaudeCode.ps1 -Export` (from the sync folder). Writes `ClaudeCode-sync\<this label>`.

Arriving at a computer:
1. `git pull` in the repos that will be used.
2. Close the Claude app and any `claude` terminals.
3. `Sync-ClaudeCode.ps1 -Import` (add `-DryRun` first to preview). Path maps are built from
   `machines.json` automatically; newer files win, nothing is deleted.
4. Open the Claude app, Code tab; `claude --resume` inside a project folder works too.

Code must be pushed before the chat is exported, otherwise the chat remembers edits the files do not
have. If the hook reports "commits NOT PUSHED" or "behind origin", say so before doing other work.

## Where memory lives (and what to write where)

| Kind of knowledge                                   | Put it in                                            | Travels by |
|-----------------------------------------------------|------------------------------------------------------|------------|
| Project facts, conventions, how to run and test      | repo `CLAUDE.md`, `.claude/rules/*.md`                | git        |
| Per-computer, per-project notes (paths, venv quirks) | repo `CLAUDE.local.md` (gitignored)                   | stays local |
| This computer's identity                            | `~\.claude\CLAUDE.md` block written by `-Setup`       | stays local |
| Auto memory Claude writes during sessions           | `~\.claude\projects\<folder>\memory\MEMORY.md`         | snapshot (export/import) |
| Conversation history                                | `~\.claude\projects\<folder>\*.jsonl`                  | snapshot (export/import) |

Prefer the repo files for anything that should outlive one computer: they need no sync step.
When the user asks to "remember" something about a project, write it to the repo's `CLAUDE.md` or
`.claude/rules/`, not only to auto memory, unless it is private or machine-specific.

## Cloud sessions (claude.ai/code)

A cloud session runs in a container, not on any of these computers. It sees only the repository
and has no `[claude-sync]` hook. It cannot read or write the local chats, the OneDrive folder or
`~\.claude` on the computers. Work done there reaches the computers through git only.

## Changing the setup

- New computer: add an entry to `machines.json` (label, user, home, roots), run
  `Sync-ClaudeCode.ps1 -Setup` there once (it fills in `computerName`), then `-Import`.
- Repo moved or cloned elsewhere: change `roots` (or add the repo to `layout`) in `machines.json`.
- `Sync-ClaudeCode.ps1 -Setup` is safe to re-run; it rewrites only its own block in `CLAUDE.md`
  and its own hook entry in `settings.json`.
