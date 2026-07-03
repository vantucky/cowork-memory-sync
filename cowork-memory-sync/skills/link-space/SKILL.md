---
name: link-space
description: >
  This skill should be used when the user asks to "link this space",
  "set up sync for this space", "share this space across machines",
  "connect this space to OneDrive/iCloud/Dropbox/SharePoint", and also
  for reconfiguring an already-linked space: "share this space with
  others", "make this space multi-user", "make this space private
  again", "switch this space to solo", "move this space to a different
  folder", "re-home this space", or "change my sync identity/name".
  Handles both the initial link and later changes to mode (solo vs
  shared), backing folder, and identity. Do not trigger for generic
  cloud-storage requests unrelated to Cowork sync.
metadata:
  version: "3.1.0"
---

# link-space

Link a Cowork space to a cloud-synced snapshot folder, and reconfigure that link later. A linked space has two files in its memory dir: `.sync-link.json` (where snapshots live + the mode) and `.sync-ledger.json` (this machine's local push/pull record).

**Modes:**
- **`solo`** — only your own machines share this space. No confirm-before-push gate; the sweep may clean any file (all files are yours).
- **`shared`** — multiple *people* participate. `snapshot-conversation` gates every push behind a review-and-confirm step; the sweep only ever deletes your own files; a presence file advertises you to other participants.

Every snapshot is attributed to its author (`user` + `machine`) regardless of mode, so a solo space can later be promoted to shared with no reformatting.

## Platform (macOS and Windows)

This plugin works on the **desktop** Cowork app on macOS and Windows, which mount cloud-sync folders locally. The **web** version has no local cloud-folder mounts and is not supported. Detect the platform once so every path and command below is correct:

```bash
uname -s 2>/dev/null || echo Windows
```
- `Darwin` → **macOS**
- `MINGW*` / `MSYS*` / `CYGWIN*` / `Linux` (WSL) / command-not-found or `Windows` → **Windows** (Cowork provides a POSIX-style shell — `mkdir`, `rm`, `cp`, `ls`, `grep` behave the same)

Set these platform variables and use them everywhere the flows say `CLOUD_ROOTS` / `CONFIG_HOME` / `MEMORY_ROOT`:

| Variable | macOS | Windows |
|---|---|---|
| `CLOUD_ROOTS` (where cloud folders mount) | `$HOME/Library/CloudStorage`, `$HOME/Library/Mobile Documents/com~apple~CloudDocs`, `$HOME/Dropbox` | `$USERPROFILE` subfolders: `OneDrive*`, `iCloudDrive`, `Dropbox`, `Box` (in the POSIX shell, `$USERPROFILE` ≈ `/c/Users/<name>`) |
| `CONFIG_HOME` (global identity) | `$HOME/.config/cowork-memory-sync` | `$USERPROFILE/.config/cowork-memory-sync` |
| `MEMORY_ROOT` (Cowork sessions) | `$HOME/Library/Application Support/Claude/local-agent-mode-sessions` | `$USERPROFILE/AppData/Roaming/Claude/local-agent-mode-sessions` |

If any command errors because the shell isn't POSIX-style, stop and tell the user their Cowork build's shell isn't supported — don't guess with PowerShell syntax. Prefer the Glob/Read/Write tools (OS-abstracted) over shell `ls`/`cat` wherever a step offers both.

## Determine the memory directory

The current space's memory directory is in your system prompt under the auto-memory section. On macOS it looks like:

```
/Users/<user>/Library/Application Support/Claude/local-agent-mode-sessions/<session>/<install>/spaces/<SPACE_ID>/memory/
```

(On Windows the prefix is `C:\Users\<user>\AppData\Roaming\Claude\...` — take whatever path the system prompt actually shows; don't assume the macOS shape.)

Set `MEMORY_DIR` to that path. The link file and ledger live there. If you cannot find a path of this shape, stop and ask the user to paste the space's memory folder path.

## Resolve this Mac's identity (user + machine)

Every snapshot records **who** wrote it (`user`) and on **which machine** (`machine`). Both are stored once per machine at `CONFIG_HOME/identity.json` (see the Platform table — `~/.config/cowork-memory-sync/identity.json` on macOS):

```json
{ "user": "richard.dyer", "machine": "workhorse" }
```

If Cowork's sandbox can't reach `CONFIG_HOME`, the values fall back to per-space fields in `.sync-link.json` — same effect, just set per-link.

### Probe global identity

Try to **Read** `CONFIG_HOME/identity.json` (use the Read tool, not Bash — Bash in Cowork's sandbox returns a misleading permission error for paths outside connected folders; Read returns a clean "outside connected folders" error).

- **Read succeeds** → parse `user` and `machine`. If both present, capture as `IDENTITY_USER` / `IDENTITY_MACHINE`; global identity is usable. Skip to the branch selector below (unless the user explicitly asked to change identity).
- **Read fails, file-not-found** → directory reachable, not set yet. `IDENTITY_USER = ""`, `IDENTITY_MACHINE = ""`. Continue to "Migrate legacy machine.txt".
- **Read fails, "outside this session's connected folders"** → sandbox barrier. Call `mcp__cowork__request_cowork_directory` for `CONFIG_HOME` (tell the user: *"One-time grant so I can store your sync identity — your name + this machine's name — shared across all linked spaces."*). Retry the Read once. If it still fails, set `USE_PER_SPACE_IDENTITY = true` and gather identity per-space in the flow below.

### Migrate legacy machine.txt (v2 → v3)

If `identity.json` didn't exist, also try to Read `CONFIG_HOME/machine.txt` (the v2 machine-name file). If it exists, use its contents as the default `IDENTITY_MACHINE`. (v3 supersedes `machine.txt` with `identity.json`; once you write `identity.json`, `machine.txt` is ignored.)

### Ask for any missing identity fields

If `IDENTITY_USER` is empty, call AskUserQuestion:
- **Question**: "What name should identify you in shared snapshot spaces? (Others will see this as the author of your snapshots.)"
- **Header**: "Your name"
- **Options**: `Use '<email-local-part>'` (derive from the user's email if visible in context, e.g. `richard.dyer@stwiplaw.com` → `richard.dyer`) · `Use '<hostname-based>'` · (Other to type). Validate: under 40 chars, no whitespace, no `/ \ :`.

If `IDENTITY_MACHINE` is empty, get a default host name via Bash — `hostname` (plain; strip any trailing DNS domain after the first `.` yourself, so it's portable across macOS and Windows) — as `DEFAULT_HOST`, then AskUserQuestion:
- **Question**: "What should this machine be called in snapshots? System hostname is `<DEFAULT_HOST>`."
- **Header**: "Machine"
- **Options**: `Use '<DEFAULT_HOST>'` · `laptop` · `workhorse` · `desktop` (Other to type). Same validation.

Write the resolved identity (unless `USE_PER_SPACE_IDENTITY`):

```bash
mkdir -p "$CONFIG_HOME"     # CONFIG_HOME from the Platform table
```

Then **Write** `CONFIG_HOME/identity.json` with `{ "user": "<IDENTITY_USER>", "machine": "<IDENTITY_MACHINE>" }` (2-space indent). If `USE_PER_SPACE_IDENTITY` is true, skip the global write — the values get stored in `.sync-link.json` when the link is written.

## Branch selector — new link vs reconfigure

Read `MEMORY_DIR/.sync-link.json`.

- **Missing** → this is a fresh link. Go to **Flow A — Initial link**.
- **Exists and well-formed** → the space is already linked. Read its `alias`, `store_path`, `mode` (default `solo` if absent — a v2 link). Call AskUserQuestion:
  - **Question**: "This space is linked as `<alias>` (`<mode>`) at `<store_path>`. What do you want to do?"
  - **Header**: "Reconfigure"
  - **Options** (offer the ones that apply):
    - `Switch to shared` (show only if currently solo) → **Flow B**
    - `Switch to solo` (show only if currently shared) → **Flow C**
    - `Move to a different folder` → **Flow D — Re-home**
    - `Change my identity` → re-run the identity section forcing the questions, rewrite `identity.json`, report, stop.
    - `Cancel`

---

## Flow A — Initial link

### A1 — Choose solo or shared
AskUserQuestion:
- **Question**: "Who will share this space?"
- **Header**: "Mode"
- **Options**:
  - `Just my machines (solo)` → `MODE = solo`
  - `Me and other people (shared)` → `MODE = shared`

### A2 — Discover existing snapshot folders
Search each mount in `CLOUD_ROOTS` (from the Platform table) for existing snapshot folders. On macOS:
```bash
find "$HOME/Library/CloudStorage" -maxdepth 6 -type d -name _cowork-snapshots 2>/dev/null
```
On Windows, run the equivalent over the Windows roots, e.g.:
```bash
find "$USERPROFILE"/OneDrive* "$USERPROFILE"/Dropbox "$USERPROFILE"/iCloudDrive "$USERPROFILE"/Box -maxdepth 5 -type d -name _cowork-snapshots 2>/dev/null
```
For each hit, note the parent folder name (the conventional alias) and the count of `*.md` files (Glob `<path>/*.md`). These may include shared folders that a collaborator shared into your cloud storage.

### A3 — Pick the folder (always interactive)
**Always** call AskUserQuestion — never auto-select, even with one candidate.

- **If folders were found**: options = one per discovered folder (label = parent name + snapshot count, e.g. `research (8 snapshots)`), plus `Create a new one` and `Cancel`. If the user picks an existing folder, set `STORE_PATH` to it and derive `ALIAS` from the parent basename (lowercase; whitespace/underscores → hyphens).
- **If none, or "Create a new one"**: list candidate parent folders under `CLOUD_ROOTS`. On macOS:
  ```bash
  find "$HOME/Library/CloudStorage" -maxdepth 3 -mindepth 2 -type d 2>/dev/null | grep -v "/_" | sort
  ```
  On Windows, run over the Windows roots (`"$USERPROFILE"/OneDrive*`, `Dropbox`, `iCloudDrive`, `Box`) with a shallower `-maxdepth 2`. Present the results (label = path relative to its cloud root) plus `Type a custom path` and `Cancel`. For a custom path, validate `[[ -d "<path>" ]]`. Set `PARENT = <chosen>`, `STORE_PATH = $PARENT/_cowork-snapshots`, derive `ALIAS` from `PARENT`'s basename. Then `mkdir -p "$STORE_PATH"`.

Confirm or override the derived `ALIAS` via AskUserQuestion (`Use '<derived>'` / custom).

**Shared-mode note:** if `MODE = shared`, remind the user that *the folder itself must be shared at the cloud level* (SharePoint/Teams library, or a OneDrive/Dropbox/Box folder shared with the other people's accounts) — this plugin writes files but does not grant anyone access. If the chosen folder isn't obviously a shared location, say so and let them proceed or pick another.

### A4 — Write link + ledger, and presence (if shared)
Get `NOW`: `date +'%Y-%m-%dT%H:%M:%S%z'`.

Write `MEMORY_DIR/.sync-link.json` (include `user`/`machine` **only** if `USE_PER_SPACE_IDENTITY`):
```json
{
  "schema_version": 3,
  "alias": "<ALIAS>",
  "store_path": "<STORE_PATH>",
  "mode": "<MODE>",
  "linked_at": "<NOW>"
}
```
Write `MEMORY_DIR/.sync-ledger.json`:
```json
{ "schema_version": 3, "alias": "<ALIAS>", "store_path": "<STORE_PATH>", "pushed": [], "pulled": [] }
```
2-space indent for both.

If `MODE = shared`, drop a presence file so other participants can see you (see **Presence file** below).

### A5 — Offer catch-up
If the folder already had snapshots (existing folder in A3), AskUserQuestion: *"Pull existing snapshots from `<ALIAS>` now?"* → `Yes — catch me up` / `Not now`. If yes, delegate to the `catch-up` skill. Then go to **Report**.

---

## Flow B — Switch solo → shared

Going shared exposes this space's snapshots to other people. Two risks to handle, in order:

1. **Back-catalog leak.** The snapshots already in `<store_path>` were written while this space was private and may contain sensitive content. **Before** enabling sharing, offer a scrub:
   - AskUserQuestion: *"This folder has `<N>` existing snapshots written while the space was private. Review/remove any before you share the folder?"* → `Scrub some first (recommended)` / `They're fine — continue` / `Cancel`.
   - If `Scrub some first`, **delegate to the `scrub-space` skill** (keyword or selection mode), then resume here.
2. **Cloud-level share.** Remind the user that going shared in the plugin does nothing until the folder is actually shared at the cloud level. Ask them to confirm they've set that up (or will).

Then: set `mode = "shared"` in `.sync-link.json` (rewrite preserving other fields), drop your **presence file**, and go to **Report** describing the new shared behavior (confirm-before-push gate now active).

---

## Flow C — Switch shared → solo

Flipping *your* flag to solo turns **off** your confirm-before-push gate — but other participants may still be linked to and reading `<store_path>`. Sitting on the still-shared folder in "solo" mode is a false sense of privacy. So **default to re-homing** to a fresh private folder:

AskUserQuestion:
- **Question**: "Other people may still have access to `<store_path>`. Going solo turns off the review gate. How do you want to go private?"
- **Header**: "Go solo"
- **Options**:
  - `Move to a new private folder (recommended)` → run **Flow D — Re-home** with `MODE = solo`, then additionally offer to scrub your files from the *old* shared folder (delegate to `scrub-space` targeting the old `store_path`). Also remove your presence file from the old folder.
  - `Stay on this folder anyway` → set `mode = "solo"` in place; remove your presence file; **warn** clearly that others may still read anything you push here going forward. Go to **Report**.
  - `Cancel`

---

## Flow D — Re-home (move to a different folder)

Used by "move this space to a different folder" and by Flow C. Migrates *your* snapshots to a new location and re-points the link. Never touches other people's files.

1. **Pick the destination** using the A3 folder-picker logic → new `STORE_PATH_NEW` (create with `mkdir -p`). Derive/confirm a new `ALIAS` (or keep the current one).
2. **Determine the effective `MODE`** — inherited from the caller (Flow C forces `solo`); otherwise ask solo/shared as in A1, defaulting to the current mode.
3. **Copy your own snapshots** from the old `store_path` to `STORE_PATH_NEW`. Your files are those whose name matches `<date>-<IDENTITY_USER>-*.md` — list them with **Glob** `<old_store_path>/*-<IDENTITY_USER>-*.md` (OS-abstracted; avoids shell differences). Copy each with `cp` (do **not** move yet — copy first, verify, so a failure can't lose data). If the space had legacy v2 files (`<date>-<slug>.md`, no user segment) and history indicates they're yours (solo origin), copy those too.
4. **Rewrite `.sync-link.json`** with `store_path = STORE_PATH_NEW`, the new `alias`, and `mode`. **Rewrite `.sync-ledger.json`**'s `store_path` to match (keep the `pushed`/`pulled` history — the slugs are still valid).
5. **Presence files:** if new mode is `shared`, drop a presence file in `STORE_PATH_NEW`. Remove your presence file from the old folder (in all re-home cases).
6. Go to **Report**, noting the old folder is left intact (others may still use it) and — if this came from Flow C — offer the scrub of your old files.

---

## Presence file (shared spaces)

So other participants can see who's linked, drop one file per participant into a `.participants/` subfolder of the store:

```bash
mkdir -p "<store_path>/.participants"
```
Write `<store_path>/.participants/<IDENTITY_USER>@<IDENTITY_MACHINE>.json`:
```json
{ "schema_version": 3, "user": "<IDENTITY_USER>", "machine": "<IDENTITY_MACHINE>", "alias": "<ALIAS>", "linked_at": "<NOW>" }
```

To **remove** your presence (going solo, re-homing, unlinking): `rm -f "<store_path>/.participants/<IDENTITY_USER>@<IDENTITY_MACHINE>.json"`.

## Report

Tailor to what happened. Always show `store_path` verbatim. Examples:

- New solo link: *"Linked this space as `<alias>` (solo) at `<store_path>`. You're `<user>` on `<machine>`."*
- New/updated shared link: *"Linked this space as `<alias>` (**shared**) at `<store_path>`. Every push now shows you a review before writing, since others can read this folder. Participants: `<list from .participants/>`."*
- Switched to solo via re-home: *"Moved your snapshots to `<new_store_path>` and set this space to solo. The old shared folder `<old>` is left intact — others may still use it."*

Common footer:
> - "Snapshot this conversation" pushes the current conversation.
> - "Catch me up" pulls new conversations (yours and collaborators').
> - "Scrub this space" removes snapshots from the folder.

## What NOT to do

- **Don't auto-pick a folder.** Always surface the choice via AskUserQuestion, even with one candidate.
- **Don't move files before copying + verifying.** Re-home copies first; only after the copy is confirmed may you offer to scrub the originals.
- **Don't copy other people's snapshots during a re-home.** Only files matching your `<date>-<user>-` prefix (plus legacy solo files) are yours to take.
- **Don't silently drop the confirm gate.** Switching shared→solo while staying on a shared folder must warn the user explicitly.
- **Don't push or pull from this skill** beyond delegating to `catch-up`/`scrub-space`. Pushing is `snapshot-conversation`'s job.
- **Don't pick a folder outside a real cloud-sync mount (`CLOUD_ROOTS`) without warning** — it won't sync, and for shared mode it won't reach other people at all.
- **Don't expose the opaque Cowork memory-dir path** in user-facing text. The `store_path` IS useful (the user picked it); the memory dir isn't.
