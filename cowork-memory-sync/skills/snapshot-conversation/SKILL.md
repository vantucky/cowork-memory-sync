---
name: snapshot-conversation
description: >
  This skill should be used when the user asks to "snapshot this
  conversation", "save this for the other machine", "push this convo",
  "share this conversation", "save where we are before I switch machines",
  "capture this conversation to the snapshot folder", or similar
  phrases that ask to push a structured summary of the current
  conversation to the shared snapshot folder so another machine — or a
  collaborator — can catch up. On a shared space the push is gated
  behind a review step. Do not use for syncing memory files directly.
metadata:
  version: "3.1.0"
---

# snapshot-conversation

Distill the current conversation into a structured, **author-attributed** markdown file and Write it to the space's linked snapshot folder. On a **shared** space, show the drafted snapshot for review before writing. Also sweep *your own* snapshots older than 30 days.

## Step 1 — Read the link file

Read `MEMORY_DIR/.sync-link.json` (memory directory is in your system prompt's auto-memory section).

If missing, tell the user: *"This space isn't linked yet — run 'link this space' first."* and stop.

Extract `alias`, `store_path`, and `mode` (default `solo` if the field is absent — a legacy v2 link).

## Step 2 — Resolve your identity (user + machine)

You need `USER_NAME` and `MACHINE` for the filename and frontmatter. The config location is `CONFIG_HOME` — `$HOME/.config/cowork-memory-sync` on macOS, `$USERPROFILE/.config/cowork-memory-sync` on Windows. Check sources in priority order. **Each step degrades silently — do not prompt, do not call `mcp__cowork__request_cowork_directory`. This is a push-time path; interactive identity setup belongs in `link-space`.**

1. **Global identity** — Read `CONFIG_HOME/identity.json` with the Read tool.
   - Read succeeds → parse `user` and `machine`; use any non-empty values found. If both present, done.
   - Read fails "outside connected folders" or file-not-found → skip to source 2.
2. **Per-space fallback** — the `.sync-link.json` from Step 1 may carry `user` / `machine` fields (written by `link-space` when the global config wasn't reachable). Use them if present.
3. **Legacy `machine.txt`** — for `machine` only, Read `CONFIG_HOME/machine.txt` (v2). Use if present.
4. **Last resort** — `hostname` via Bash for `machine` (strip any trailing `.domain` yourself for portability). For `user`, if still unset, use `"unknown"`.

If `USER_NAME` ended up `"unknown"`, note in the final report that the user should run `link-space` in this space to set an identity — attribution and the own-files-only sweep both depend on it. **On a `shared` space, an unknown `USER_NAME` is unsafe** (your files can't be distinguished from others' for the sweep, and collisions become likely): stop and tell the user to run `link-space` first.

## Step 3 — Distill the conversation

Re-read the current conversation from the start. Identify:

- **Summary** (1–2 paragraphs): what was discussed, current state. Written so the other side can pick up cold.
- **Decisions** made: choices you and the user agreed on, especially if not yet implemented.
- **Open questions**: things deferred or still being researched.
- **Context / state**: file paths, account names, project codes, key numbers, deadlines — anything needed cold.

Keep the user's exact phrasing where it matters (preferences, feedback). Don't paraphrase aggressively.

**Calibration**: a typical snapshot is 200–600 words. If you have under ~100 words, the conversation may not be worth snapshotting — say so and ask whether to push or skip.

## Step 4 — Generate slug and filename

- **Date prefix**: `date +'%Y-%m-%d'` via Bash.
- **User segment**: `USER_NAME` from Step 2 (already validated to be filename-safe: no whitespace, no `/ \ :`).
- **Slug**: 3–5 word kebab-case description. Examples: `rethink-sync-architecture`, `strategy-call`, `debug-scanner`, `cleanup-old-tags`.
- **Filename**: `<date>-<USER_NAME>-<slug>.md`. (The user segment prevents collisions between participants and makes every file's author visible at a glance.)

Check for collisions with **Glob** `<store_path>/<date>-<USER_NAME>-<slug>.md` (OS-abstracted). If it exists, append `-2`, `-3`, … until unique.

## Step 5 — Timestamps

Get the current timestamp (portable — this format works on both macOS/BSD and Windows/GNU `date`):
```bash
date +'%Y-%m-%dT%H:%M:%S%z'   # NOW
```
Compute `EXPIRES_AT` as **NOW + 30 days** yourself (date arithmetic on the `YYYY-MM-DD` portion, keeping the same time and `%z` offset). Do **not** shell out with `date -v+30d` (that's BSD/macOS-only and fails on Windows/GNU).

## Step 6 — Build the snapshot file

```markdown
---
slug: <date>-<USER_NAME>-<slug>
created_at: <NOW>
user: <USER_NAME>
machine: <MACHINE>
space_alias: <alias>
schema_version: 3
---

## Summary

<1–2 paragraphs>

## Decisions

- <bullet>

## Open questions

- <bullet>

## Context / state

- <bullet>
```

Omit empty sections — one strong section beats four weak ones.

## Step 7 — SHARED-SPACE REVIEW GATE (only if `mode == "shared"`)

If this space is `shared`, **do not write yet.** Other people can read this folder, and this space may touch privileged or confidential material. Present the drafted snapshot for review first:

1. Read `<store_path>/.participants/*.json` (if present) to name who will be able to see this. If unreadable, just say "other participants."
2. Show the **full drafted snapshot** inline in your response.
3. **Actively flag likely-sensitive content** you notice in the draft and call it out above the preview — e.g. client/company names, patent docket numbers (patterns like `NNNN.NNNNNNN`), application/publication numbers, unfiled amendment or strategy details, examiner names, dollar figures, personal identifiers. List what you spotted; don't silently pass it through.
4. AskUserQuestion:
   - **Question**: "This is a **shared** space (readable by `<participants>`). Push this snapshot?"
   - **Header**: "Shared push"
   - **Options**:
     - `Push as-is`
     - `Let me edit first` → ask what to change / remove, revise the draft, then re-show and re-ask (loop until approved or cancelled)
     - `Cancel` → stop without writing
5. Only on `Push as-is` (or after edits are approved) continue to Step 8.

On a `solo` space, skip this step entirely — no other reader, no gate.

## Step 8 — Write the snapshot

Write the file at `<store_path>/<date>-<USER_NAME>-<slug>.md` using the Write tool.

- If the Write fails with **"outside this session's connected folders"**, call `mcp__cowork__request_cowork_directory` for the `store_path`'s parent and retry once.
- If the Write fails with a **permission error** (not the sandbox message — e.g. read-only filesystem / access denied), the shared folder is likely **read-only for you** (shared to you view-only). Tell the user: *"`<store_path>` looks read-only for your account — you can catch up here but can't push. Ask the folder owner for edit access, or re-home this space to a folder you can write."* Then stop (do not touch the ledger).
- Any other failure: report and stop before the ledger.

## Step 9 — Update the ledger

Read `MEMORY_DIR/.sync-ledger.json`. Append to `pushed[]`:
```json
{ "slug": "<date>-<USER_NAME>-<slug>", "pushed_at": "<NOW>", "expires_at": "<EXPIRES_AT>" }
```
Write it back, preserving existing entries, 2-space indent.

## Step 10 — Sweep YOUR OWN expired snapshots

**Critical for shared spaces: only ever delete files you authored.** Never touch another participant's history.

List **your files only** with **Glob** `<store_path>/*-<USER_NAME>-*.md` (OS-abstracted). For each, parse the leading `YYYY-MM-DD`; if it's more than 30 days before today, delete it:
```bash
rm "<store_path>/<expired_filename>"
```
Run `rm` per file; on failure, log and continue.

In a `solo` space that still has legacy v2 files (`<date>-<slug>.md`, no user segment) they're all yours, so you may sweep those too by date. In a `shared` space, **do not** sweep unsegmented legacy files — you can't prove they're yours.

After sweeping, prune the local ledger's `pushed[]` of entries whose `expires_at` is in the past. Write the ledger back.

## Step 11 — Report

> Pushed `<date>-<USER_NAME>-<slug>.md` to `<store_path>/`.
> Swept N of your expired snapshots: <list>.

Omit the sweep line if nothing was swept. For a shared space, add: *"Visible to `<participants>`."* If the cloud provider is slow to sync (OneDrive/SharePoint usually <1 min), note it gently.

## What NOT to do

- **Don't skip the review gate on a shared space.** The confirm step is the confidentiality boundary — it is mandatory when `mode == "shared"`.
- **Don't sweep files you didn't author.** The own-files-only sweep protects collaborators' history. A wrong sweep here is irrecoverable data loss for someone else.
- Don't write the snapshot anywhere other than `store_path` from the link file.
- Don't include the full conversation transcript. Snapshots are *curated summaries*.
- Don't run `catch-up` or `scrub-space` from here. Push, pull, and scrub are separate flows.
- Don't push if `.sync-link.json` is missing or malformed — treat as "not linked yet."
- Don't prompt for identity here — degrade silently and point the user to `link-space`.
