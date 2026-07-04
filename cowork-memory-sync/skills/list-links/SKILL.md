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
  version: "3.1.1"
---

# list-links

Report on linked Cowork spaces: alias, **mode** (solo/shared), snapshot folder, snapshot count, **participants** (for shared spaces), when linked, and who you are (`user` + `machine`).

Read-only — no files written.

**Sandbox reality (read this first).** A Cowork session is sandboxed to the **current** space's folders. The **current space's** memory dir is surfaced in your system prompt and is always reachable, but the **global** Cowork sessions root and `~/.config/` are usually **not** reachable without an explicit grant. So this skill is built to *always* report the current space, and to *attempt* a full cross-space listing only as a best-effort bonus — never dead-end with "I can't access anything."

## Step 1 — Always report the current space (reachable)

The current space's memory dir (`MEMORY_DIR`) is in your system prompt's auto-memory section. **Read `MEMORY_DIR/.sync-link.json`.**

- If it exists → this space is linked; you have at least one link to report. Keep it as the "current space" row.
- If it doesn't exist → this space isn't linked (note that), but still try Step 2 for others.

This step never hits the sandbox barrier — the current space's own folder is always connected.

## Step 2 — Best-effort: find link files for *other* spaces

Try to enumerate the rest by scanning the Cowork sessions root. Detect the platform (`uname -s 2>/dev/null || echo Windows`) and pick the root:
- **macOS**: `$HOME/Library/Application Support/Claude/local-agent-mode-sessions`
- **Windows**: `$USERPROFILE/AppData/Roaming/Claude/local-agent-mode-sessions`

```bash
find "<sessions-root>" -name .sync-link.json 2>/dev/null
```

Handle the outcome:
- **Returns paths** → capture them; these are all spaces' links (includes the current one). Proceed to Step 3.
- **Fails with a permission / "outside connected folders" error, or returns nothing while the current space *is* linked** → the sandbox is blocking the global scan. Offer a one-time grant: call `mcp__cowork__request_cowork_directory` for the sessions root (tell the user: *"One-time grant so I can list every linked space on this machine, not just this one."*), then retry the `find` once.
- **Still blocked (user declines or grant doesn't cover it)** → **degrade gracefully**: report only the current space from Step 1, and add a note: *"Showing this space only — grant access to the Cowork sessions folder to list all linked spaces."* Then go to Step 3 to parse that one link and Step 6 to render.

If neither Step 1 nor Step 2 found any link, report "No linked spaces found." and stop.

## Step 3 — Parse each link file

For each link found (the current space from Step 1, plus any others from Step 2), Read the file. v3 schema:

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

## Step 4 — Count snapshots in each store path

For each unique `store_path`, count the `.md` files inside (these are the snapshots) using **Glob** `<store_path>/*.md` (OS-abstracted — works the same on macOS and Windows). The number of matches is `SNAPSHOT_COUNT` per link.

Also check whether the store_path exists at all (it might not, if OneDrive/iCloud hasn't synced it down yet, or if the user moved/deleted the folder). Note any missing paths as a warning.

For each **shared** space, also list the participants: read the presence files in `<store_path>/.participants/*.json` (each has `user`, `machine`). Collect the distinct `user` values as that space's participant list. If `.participants/` is absent or empty, show `—`.

## Step 5 — Determine this machine's identity

In many Cowork sandboxes `~/.config/` isn't reachable, so identity is stored **per-space** in the link files. Resolve it robustly:

1. **Per-space link fields (most reliable in-sandbox)** — if any link you read in Step 1/2 carries `user` / `machine`, use those (they're this machine's identity, written by `link-space`'s fallback path). If several agree, great; if only some links have them, use whatever is present.
2. **Global config** — also try to Read `CONFIG_HOME/identity.json` (`$HOME/.config/cowork-memory-sync` on macOS, `$USERPROFILE/.config/...` on Windows). If it succeeds, prefer it as authoritative; if it fails ("outside connected folders" or file-not-found), that's expected — rely on source 1.
3. **Hostname fallback** — for `machine` only, `hostname` via Bash (strip any trailing `.domain`).

Report identity as `<user>` on `<machine>`. If `user` couldn't be determined anywhere, say identity isn't set yet and point the user to "change my identity" in `link-space`.

## Step 6 — Render the report

Format a clean markdown response:

```
**This machine's identity:** `<user>` on `<machine>`

**Linked spaces:** <N>   (or: **This space** — full list needs folder access, see below)

| Alias | Mode | Folder | Snapshots | Participants | Linked |
|---|---|---|---|---|---|
| `<alias_1>` | solo | `<cloud>/research/_cowork-snapshots` | <count> | — | <YYYY-MM-DD> |
| `<alias_2>` | shared | `<cloud>/matter-x/_cowork-snapshots` | <count> | richard.dyer, jane | <YYYY-MM-DD> |

<sub>"Snapshots" is the count of `.md` files right now. "Participants" is read from each shared space's `.participants/` folder; solo spaces show `—`.</sub>
```

Mark the **current space** in the table (e.g. a `← this space` note on its row) so it's clear which one you're in.

If Step 2 degraded to current-space-only, show just that one row and add:

> ℹ Showing this space only — the Cowork sandbox blocked the machine-wide scan. Run this again and approve the folder-access grant to list every linked space.

For cleaner display, shorten `store_path` by replacing the cloud-mount prefix (macOS `~/Library/CloudStorage/`, Windows `%USERPROFILE%\OneDrive\`, etc.) with `<cloud>/`, or show the parent + `_cowork-snapshots`. Keep the table narrow.

If any store_path was missing in Step 4, add a warning line:

> ⚠ `<alias>`'s snapshot folder at `<path>` doesn't exist on this machine. The cloud provider may not have synced it down yet, or the folder was moved/deleted.

If the user identity isn't set (Step 5 fell back to hostname), add:

> 💡 To set your sync identity (your name + this machine's name, used to attribute snapshots), run `link this space` in any linked space and pick "Change my identity".

## What NOT to do

- Don't write or modify any files. This skill is read-only.
- Don't trigger `link-space`, `snapshot-conversation`, `catch-up`, or `unlink-space` as side effects. Just gather and report.
- Don't expose Cowork-internal memory dir paths to the user. They're long, opaque, and not useful. The user cares about alias + store_path.
- Don't recurse into store_paths beyond a flat Glob. If a user has 200 snapshots, just count — don't list them all.
- Don't probe the cloud-sync state of each store_path (e.g., "is OneDrive currently uploading"). The existence + count is enough; sync timing is the cloud provider's job to surface.
