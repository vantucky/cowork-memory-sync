---
name: catch-up
description: >
  This skill should be used when the user asks to "catch me up",
  "pull new convos in this space", "what did I do on the other machine",
  "load the latest conversations", "sync this space down", "get me up
  to speed", or similar phrases that ask to fetch conversation
  snapshots from the shared snapshot folder so the assistant can read
  them into the current conversation — your own from another machine, or
  a collaborator's on a shared space. Do not use for pushing snapshots;
  that's snapshot-conversation.
metadata:
  version: "3.1.0"
---

# catch-up

Fetch new snapshots from the linked snapshot folder, read them into the current conversation, and update the local ledger so they aren't re-fetched. Any memory writes happen naturally as Claude processes what it reads.

## Step 1 — Read the link file and ledger

Read `MEMORY_DIR/.sync-link.json` (memory dir is in your system prompt's auto-memory section).

If missing, tell the user: *"This space isn't linked yet — run 'link this space' first."* and stop.

Read `MEMORY_DIR/.sync-ledger.json`. If missing, treat `pulled` as `[]`.

Extract `alias`, `store_path`, and the existing pulled slugs.

## Step 2 — List snapshots in the folder

Use Glob (or Bash `ls`) to list all `*.md` files in `<store_path>` (ignore the `.participants/` subfolder — those are presence files, not snapshots). Strip the `.md` suffix from each filename to get the slug.

**Parse the author** from each filename: v3 snapshots are named `<YYYY-MM-DD>-<user>-<slug>.md`, so the segment after the date is the author. Legacy v2 files are `<YYYY-MM-DD>-<slug>.md` with no author segment — treat their author as `(legacy)`. (Snapshots from *any* participant appear here — the folder is the shared rendezvous — so you'll see collaborators' files alongside your own.)

If `<store_path>` doesn't exist or is empty, tell the user *"No snapshots in this space yet."* and stop.

If the Read/Glob fails with "outside this session's connected folders," call `mcp__cowork__request_cowork_directory` for `<store_path>`'s parent and retry. (Shouldn't normally fire — `link-space` already granted access.)

## Step 3 — Compute the new set

Filter the slugs to those NOT already in the ledger's `pulled[]`.

Sort by the `YYYY-MM-DD` date prefix, ascending (oldest first — they should be ingested in chronological order).

If the new set is empty, tell the user *"You're already caught up — nothing new since you last pulled here."* and stop.

## Step 4 — List the new set inline

Before asking what to ingest, write the new snapshots out as a **numbered markdown list** in your response. One row per snapshot — show **author** alongside the date and topic (from the filename parse in Step 2), so the user can see who wrote each. No per-file Read needed yet:

```
Found <N> new snapshots since you last caught up here:

1. 2026-05-22 · richard.dyer · rewrite-sync-plugin
2. 2026-05-25 · jane · scanner-bug
3. 2026-05-28 · richard.dyer · strategy-call
...
```

The numbering is what the user will refer to in the next step. If the new set spans multiple authors, that's expected on a shared space.

## Step 5 — Ask which to ingest

Use AskUserQuestion:

- **Question**: "Which snapshots to ingest? (Pick 'Other' to specify numbers, e.g. `1,3,5`.)"
- **Header**: "Ingest"
- **Options**:
  - `All <N>` — ingest every new one
  - `Most recent only` — ingest just the newest by date prefix (the highest-numbered row)
  - `Cancel` — stop without ingesting anything

(Users can always pick `Other` and type a custom answer — that's where they specify numbers like `1,3,5` or `2-4`.)

Parse the user's response into a list of indices:
- `All <N>` → all rows
- `Most recent only` → the last row in the numbered list
- `Cancel` → stop the skill with no ledger changes
- Custom text — parse comma-separated numbers (`1,3,5`) and/or ranges (`2-4` → `2,3,4`). Reject and re-ask if any index is out of range or unparseable.

The chosen indices map back to slugs from your numbered list in Step 4.

## Step 6 — Fetch the selected snapshots

For each selected snapshot, Read the full file from `<store_path>/<slug>.md`. Display each one inline in your response so it lands in your conversation context.

## Step 7 — Synthesize and respond

After all snapshots are read, write a brief paragraph (3–5 sentences) synthesizing what happened elsewhere. **Attribute by author** — on a shared space this is a handoff from specific people, so say *"Jane decided X"* / *"you (richard.dyer) left Y open"* rather than a faceless "the other machine." Use the `user`/`machine` frontmatter (or the parsed filename author) to attribute. Highlight:

- The most recent state of any ongoing project mentioned in the snapshots
- Decisions made — and by whom — that affect what you'd recommend now
- Open questions that haven't been resolved, and who raised them

This is your handoff briefing — pull out what matters, don't just regurgitate.

If, as you process the snapshots, you notice something genuinely worth remembering (a stated preference, a new project, a feedback rule, a reference to an external resource), let auto-memory writes happen naturally — just like in any other conversation. Don't force memory writes; only when something is genuinely memorable.

## Step 8 — Get current timestamp

Run via Bash:

```bash
date +'%Y-%m-%dT%H:%M:%S%z'
```

Capture as `NOW`.

## Step 9 — Update the ledger

For each **fetched** snapshot (not skipped/uningested ones), append to the ledger's `pulled[]`:

```json
{
  "slug": "<slug>",
  "pulled_at": "<NOW>"
}
```

Write the updated ledger back, preserving all existing entries.

**Snapshots the user did NOT pick stay out of `pulled[]`.** That's deliberate — on the next catch-up run, they'll show up again in the "new" list. The user might have intentionally skipped them because they weren't relevant at the time, or because they ran out of energy mid-list. They should remain ingestible later.

## Step 10 — Report

Concise:

> Fetched <N> snapshot(s) from `<store_path>/`. Caught up through `<latest-slug>`.

## What NOT to do

- **Don't mark uningested snapshots as reviewed.** Only add to `pulled[]` the snapshots the user actually picked to ingest. Skipped/unselected ones must remain in the "new" list on future catch-up runs — the user may want to come back and ingest them later when they have more context or energy.
- Don't write the fetched snapshots into the local memory dir or copy them elsewhere. They live in the linked folder only; you ingest them into context for this conversation.
- Don't mass-write memory files based on snapshot content. Trust auto-memory's normal triggers.
- Don't fetch the same snapshot twice in one session — once it's in `pulled[]`, skip it.
- Don't fetch from any folder other than the one in this space's `.sync-link.json`.
- Don't trigger `snapshot-conversation` from here. Push and pull are separate flows.
- Don't expose the memory dir path in user-facing text. The store_path itself IS user-meaningful (they picked it).
