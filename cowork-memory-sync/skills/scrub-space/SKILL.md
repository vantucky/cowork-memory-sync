---
name: scrub-space
description: >
  This skill should be used when the user asks to "scrub this space",
  "purge snapshots", "clear old memories", "delete snapshots from the
  folder", "clean up the snapshot folder", "remove memories before I
  share this", "wipe my snapshots from this space", or similar phrases
  that ask to bulk-remove snapshot files from a linked space's folder.
  Destructive — always previews and confirms, backs up before deleting,
  and defaults to only the current user's own snapshots. Do not use to
  remove the local link (that's unlink-space) or to push/pull (that's
  snapshot-conversation / catch-up).
metadata:
  version: "3.1.0"
---

# scrub-space

Bulk-remove snapshot files from a linked space's folder. Destructive, so it is deliberately separate from the everyday push/pull, always previews the exact files first, backs them up locally before deleting, and defaults to touching **only your own** snapshots.

The `link-space` skill may delegate here during a solo→shared promotion (scrub the private back-catalog) or a shared→solo re-home (leave your files behind you). It also runs on demand.

## Step 1 — Read the link file and resolve identity

Read `MEMORY_DIR/.sync-link.json` (memory dir is in your system prompt's auto-memory section). If missing, tell the user *"This space isn't linked — nothing to scrub. (Run 'link this space' first, or delete files in the folder manually.)"* and stop. Extract `alias`, `store_path`, `mode`.

Resolve `USER_NAME` the same way `snapshot-conversation` does (global `CONFIG_HOME/identity.json` → per-space `user` field → legacy → `hostname`; `CONFIG_HOME` is `~/.config/cowork-memory-sync` on macOS, `$USERPROFILE/.config/cowork-memory-sync` on Windows). You need it to identify "your own" files.

If a caller (link-space) passed an explicit target `store_path` different from the link file's (e.g. scrubbing the *old* folder during a re-home), use the passed path.

## Step 2 — Choose scope

AskUserQuestion:
- **Question**: "Scrub which snapshots in `<alias>`?"
- **Header**: "Scope"
- **Options**:
  - `Only mine` (default) — files matching `<date>-<USER_NAME>-*.md`.
  - `Everyone's in this folder` — **all** `*.md`. Only offer/allow this for a folder the user owns; if `mode == "shared"`, add a warning that this deletes **other participants'** memories too.
  - `Cancel`

If `Everyone's` is chosen on a shared space, require a second explicit confirm before proceeding (*"This removes snapshots authored by other people too. Type-confirm by choosing 'Yes, everyone's'."*).

## Step 3 — Choose filter

AskUserQuestion:
- **Question**: "Which ones?"
- **Header**: "Filter"
- **Options**:
  - `Everything in scope`
  - `Older than N days` → ask for N (default 30); match by the `YYYY-MM-DD` filename prefix.
  - `Mentioning a keyword` → ask for the term(s). This is the confidentiality path — grep snapshot **bodies**, not just names. Example terms: a client name, a docket prefix like `2001.`, an application number.
  - `Let me pick from a list`

## Step 4 — Build the candidate set

Start from the scope (Step 2): **Glob** `<store_path>/*.md` (OS-abstracted), then restrict to `*-<USER_NAME>-*.md` if scope is "Only mine".

Apply the filter:
- **Everything in scope** — all of them.
- **Older than N** — keep files whose date prefix is > N days before today (`date +'%Y-%m-%d'`).
- **Keyword** — for each candidate, search its contents:
  ```bash
  grep -il -e "<term1>" -e "<term2>" "<store_path>"/<candidate>.md
  ```
  Keep the matches. (Case-insensitive. Read a match inline if you want to show the user *why* it matched.)
- **Pick from a list** — present a numbered list (slug + date + author) and use AskUserQuestion (`All` / `Cancel`, Other for `1,3,5` / ranges) exactly like `catch-up` Step 5's parsing.

If the candidate set is empty, tell the user *"Nothing matches — nothing to scrub."* and stop.

## Step 5 — Preview and confirm (mandatory)

List the matching files clearly — count, and one row each (`<date>` · `<author>` · `<slug>`). For a keyword scrub, note the matched term per file. Then AskUserQuestion:
- **Question**: "Delete these `<N>` snapshot(s)? They'll be backed up locally first (recoverable)."
- **Header**: "Confirm scrub"
- **Options**: `Yes, delete them` / `Cancel`

Never delete without this confirm.

## Step 6 — Back up, then delete

Back up to a **local, non-syncing** folder inside the space's memory dir (always reachable from the sandbox, and it will not re-sync into the cloud folder):

```bash
STAMP=$(date +'%Y-%m-%d-%H%M%S')
BACKUP="$MEMORY_DIR/_scrubbed/$STAMP"
mkdir -p "$BACKUP"
```

For each file: `cp` it to `$BACKUP/`, verify the copy exists, then `rm` the original from `store_path`. Copy-verify-delete per file so a failure can't lose data. If any single delete fails, log it and continue.

(The cloud provider's own recycle bin — OneDrive/SharePoint — is a secondary safety net, but the local backup is the primary one.)

## Step 7 — Prune the ledger

Read `MEMORY_DIR/.sync-ledger.json`. Remove from `pushed[]` any entry whose `slug` was deleted. Leave `pulled[]` alone (you may still want a record you once ingested a now-deleted file). Write the ledger back.

## Step 8 — Report

> Scrubbed `<N>` snapshot(s) from `<alias>` (`<store_path>`).
> Backed up to `_scrubbed/<STAMP>/` in this space's memory dir (recoverable).
> <If keyword scope:> Matched on: `<terms>`.

If scope was "Everyone's" on a shared space, restate that other participants' files were removed. If any deletes failed, list them.

## What NOT to do

- **Don't delete without the Step 5 preview + confirm.** This is destructive and, for other people's files, irrecoverable-to-them.
- **Don't skip the backup.** Copy-verify-delete, always.
- **Don't default to everyone's files.** "Only mine" is the safe default; deleting others' snapshots requires an explicit, warned, double-confirmed choice.
- **Don't back up into the cloud folder or any cloud-sync mount** (macOS `~/Library/CloudStorage`, Windows `%USERPROFILE%\OneDrive`, etc.) — it would re-sync the "deleted" files right back. The backup lives in the local memory dir.
- **Don't remove the link or presence files here** — that's `unlink-space`/`link-space`. Scrub only touches snapshot `.md` files.
- **Don't touch the `.participants/` folder.**
