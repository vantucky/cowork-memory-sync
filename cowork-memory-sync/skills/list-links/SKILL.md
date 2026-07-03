---
name: list-links
description: >
  This skill should be used when the user asks "what spaces are linked",
  "list my synced spaces", "show sync status", "show cowork sync links",
  "what's set up for sync", or similar phrases that ask for a summary
  of which Cowork spaces are currently linked on this Mac, their mode
  (solo/shared), who else participates, and where their snapshots live.
  Read-only — no changes to state.
metadata:
  version: "3.1.0"
---

# list-links

Enumerate all linked Cowork spaces on this machine and report on them: alias, **mode** (solo/shared), snapshot folder, snapshot count, **participants** (for shared spaces), and when linked. Also reports this machine's identity (`user` + `machine`) from `CONFIG_HOME/identity.json` (macOS `~/.config/cowork-memory-sync/`, Windows `%USERPROFILE%\.config\...`).

Read-only — no files written, no prompts.

## Step 1 — Find all link files on this machine

The Cowork sessions root differs by platform (detect with `uname -s 2>/dev/null || echo Windows`):
- **macOS**: `$HOME/Library/Application Support/Claude/local-agent-mode-sessions`
- **Windows**: `$USERPROFILE/AppData/Roaming/Claude/local-agent-mode-sessions`

Run via Bash against the right root, e.g. on macOS:

```bash
find "$HOME/Library/Application Support/Claude/local-agent-mode-sessions" -name .sync-link.json 2>/dev/null
```

This returns the full path to every `.sync-link.json` under all Cowork sessions. Capture the list. (This plugin runs on the macOS and Windows desktop apps; the web version has no local session folder.)

If empty, skip to Step 5 and report "No spaces linked on this machine yet."

## Step 2 — Parse each link file

For each path returned in Step 1, Read the file. v3 schema:

```
{
  "schema_version": 3,
  "alias": "<name>",
  "store_path": "<absolute path>",
  "mode": "solo" | "shared",
  "linked_at": "<ISO timestamp>",
  "user": "<optional per-space identity fallback>",
  "machine": "<optional per-space identity fallback>"
}
```

Extract `alias`, `store_path`, `mode` (default `solo` if absent — a legacy v2 link), and `linked_at` for each.

## Step 3 — Count snapshots in each store path

For each unique `store_path`, count the `.md` files inside (these are the snapshots) using **Glob** `<store_path>/*.md` (OS-abstracted — works the same on macOS and Windows). The number of matches is `SNAPSHOT_COUNT` per link.

Also check whether the store_path exists at all (it might not, if OneDrive/iCloud hasn't synced it down yet, or if the user moved/deleted the folder). Note any missing paths as a warning.

For each **shared** space, also list the participants: read the presence files in `<store_path>/.participants/*.json` (each has `user`, `machine`). Collect the distinct `user` values as that space's participant list. If `.participants/` is absent or empty, show `—`.

## Step 4 — Read this machine's identity

The config location is `CONFIG_HOME` — `$HOME/.config/cowork-memory-sync` on macOS, `$USERPROFILE/.config/cowork-memory-sync` on Windows. Read `CONFIG_HOME/identity.json` with the Read tool:

- Succeeds → parse `user` and `machine`; report as `<user>` on `<machine>`.
- File-not-found → identity not set yet. Fall back: try the legacy `CONFIG_HOME/machine.txt` (machine only), and run `hostname` via Bash (strip any trailing `.domain`) for a default. Note that the user identity isn't set.
- "outside connected folders" → the sandbox can't reach `CONFIG_HOME`; note that identity may be stored per-space instead (the `user`/`machine` fields on individual links).

## Step 5 — Render the report

Format a clean markdown response:

```
**This machine's identity:** `<user>` on `<machine>`  
*(global config: `CONFIG_HOME/identity.json`)*

**Linked spaces on this machine:** <N>

| Alias | Mode | Folder | Snapshots | Participants | Linked |
|---|---|---|---|---|---|
| `<alias_1>` | solo | `<cloud>/research/_cowork-snapshots` | <count> | — | <YYYY-MM-DD> |
| `<alias_2>` | shared | `<cloud>/matter-x/_cowork-snapshots` | <count> | richard.dyer, jane | <YYYY-MM-DD> |

<sub>"Snapshots" is the count of `.md` files right now. "Participants" is read from each shared space's `.participants/` folder; solo spaces show `—`.</sub>
```

For cleaner display, shorten `store_path` by replacing the cloud-mount prefix (macOS `~/Library/CloudStorage/`, Windows `%USERPROFILE%\OneDrive\`, etc.) with `<cloud>/`, or show the parent + `_cowork-snapshots`. Keep the table narrow.

If any store_path was missing in Step 3, add a warning line:

> ⚠ `<alias>`'s snapshot folder at `<path>` doesn't exist on this machine. The cloud provider may not have synced it down yet, or the folder was moved/deleted.

If the user identity isn't set (Step 4 fell back to hostname), add:

> 💡 To set your sync identity (your name + this machine's name, used to attribute snapshots), run `link this space` in any linked space and pick "Change my identity".

## What NOT to do

- Don't write or modify any files. This skill is read-only.
- Don't trigger `link-space`, `snapshot-conversation`, `catch-up`, or `unlink-space` as side effects. Just gather and report.
- Don't expose Cowork-internal memory dir paths to the user. They're long, opaque, and not useful. The user cares about alias + store_path.
- Don't recurse into store_paths beyond a flat Glob. If a user has 200 snapshots, just count — don't list them all.
- Don't probe the cloud-sync state of each store_path (e.g., "is OneDrive currently uploading"). The existence + count is enough; sync timing is the cloud provider's job to surface.
