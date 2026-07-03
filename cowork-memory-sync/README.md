# cowork-memory-sync

Share Cowork space conversations across your machines **and across people**, via a cloud-synced folder.

> **Requires Claude Cowork.** This plugin depends on Cowork-only mechanics (the per-space memory directory surfaced in the system prompt, and `mcp__cowork__request_cowork_directory` for folder access). It does not work in the plain Claude Code CLI.

## What this plugin does

When you finish a conversation on one machine and want the *other* side — your second Mac, or a collaborator on their own machine — to know what you just did, this plugin lets you **snapshot the conversation**, drop it into a cloud-synced folder, and **catch up on it** from the other side — all via natural-language phrases inside Cowork.

It doesn't sync your full memory directory. You push **curated conversation snapshots**: a short summary, key decisions, open questions, and any state the other side needs cold. The receiving Claude reads the snapshot and updates its own memory naturally as it processes it.

Cross-machine and cross-user propagation is handled entirely by your cloud provider (OneDrive, iCloud Drive, Dropbox, SharePoint/Teams, Box, Syncthing). The plugin only writes and reads files.

## Solo vs shared spaces

Each linked space has a **mode**, switchable in either direction at any time:

- **`solo`** — only your own machines participate (one person, multiple Macs). No review gate; the everyday behavior.
- **`shared`** — multiple *people* participate. Every push is gated behind a **review-and-confirm step** (so you don't leak anything into a folder other people read), the auto-sweep only ever touches your own snapshots, and a presence file lets participants see who's linked.

Every snapshot is **attributed** to its author (`user` + `machine`), so a solo space can be promoted to shared with no reformatting, and a catch-up briefing can say *"Jane decided X."*

## Skills

Six skills, auto-triggered by natural-language phrases:

| Skill | Triggers on phrases like |
|---|---|
| `link-space` | "link this space," "share this space across machines," "share this space with others," "make this space private again," "move this space to a different folder," "change my sync identity" |
| `snapshot-conversation` | "snapshot this conversation," "push this convo," "save this for the other machine" |
| `catch-up` | "catch me up," "pull new convos," "what did I do on the other machine," "catch me up on what <person> did" |
| `scrub-space` | "scrub this space," "purge old snapshots," "clean up the folder before I share it," "remove memories mentioning <term>" |
| `unlink-space` | "unlink this space," "stop syncing this space," "disconnect this space" |
| `list-links` | "what spaces are linked," "show sync status," "who's in this space" |

## Prerequisites

- **Claude Cowork** (see the note at the top).
- A cloud-synced folder both sides can reach at a local path. Options that work:
  - **Your own two Macs** → your OneDrive / iCloud Drive / Dropbox syncing the same folder to both.
  - **You + a colleague on the same tenant** → a SharePoint / OneDrive-Business shared library.
  - **You + an outside person** → a OneDrive / Dropbox / Box folder **shared with their account**, mounted locally on both sides.
  The `~/Library/CloudStorage/` prefix is the usual mount point.
- Cowork directory access to the chosen folder (the `link-space` skill prompts for this on first link).

## How it works

The first time you run `link-space` in a space, you pick the mode (solo/shared), set your identity (your name + this Mac's name), and pick (or create) a folder. The skill creates a `_cowork-snapshots/` subdirectory inside it and writes `.sync-link.json` into the space's memory dir recording where snapshots live and the mode.

- **Snapshot** (push): reads the current conversation, distills it into a markdown file with attribution frontmatter (`user`, `machine`, timestamp, alias), and writes `<store_path>/<YYYY-MM-DD>-<user>-<slug>.md`. On a shared space it shows you the draft and flags likely-sensitive content **before** writing. Also sweeps *your own* snapshots older than 30 days.
- **Catch up** (pull): the same folder is already populated by the cloud provider (with your and collaborators' snapshots). The skill lists new ones with their authors, lets you pick which to ingest, reads them into context, and updates the local ledger.
- **Scrub**: bulk-removes snapshots — your own by default, filterable by age or keyword (e.g. before exposing a private back-catalog) — with a preview, confirm, and local backup.

The per-space ledger (`.sync-ledger.json`) is purely local — it tracks what *this machine* has pushed and pulled. It is never synced.

## Identity

Your identity — the `user` and `machine` stamped on your snapshots — is stored once per Mac at `~/.config/cowork-memory-sync/identity.json`. If Cowork's sandbox can't reach `~/.config/`, it falls back to per-space fields in each `.sync-link.json`. Change it any time with "change my sync identity."

## Folder convention

Snapshots go in a `_cowork-snapshots/` subdirectory of whatever project folder you choose. The leading underscore signals "system-managed." A shared space also has a `_cowork-snapshots/.participants/` folder holding one small presence file per participant.

```
OneDrive-Personal/
├── research/                           ← a solo space's folder
│   └── _cowork-snapshots/
│       ├── 2026-05-22-richard.dyer-rewrite-plugin.md
│       └── 2026-05-25-richard.dyer-scanner-bug.md
└── ...

SharePoint - Shared Documents/
└── project-atlas/                      ← a shared space's folder
    └── _cowork-snapshots/
        ├── .participants/
        │   ├── richard.dyer@workhorse.json
        │   └── jane@janes-mbp.json
        ├── 2026-06-01-richard.dyer-kickoff.md
        └── 2026-06-03-jane-design-review.md
```

Each linked space picks its own parent folder — usually the project folder the conversation is about.

## Confidentiality on shared spaces

Because a shared folder is readable by other people, `snapshot-conversation` **stops and shows you the drafted snapshot before writing** on any shared space, actively flagging likely-sensitive content (names, IDs, numbers) so you can edit or cancel. And when you promote a space from solo to shared, `link-space` offers to scrub the private back-catalog first — snapshots written while the space was private predate any sharing decision. Attribution and the own-files-only sweep mean you can never accidentally delete a collaborator's history.

## Cadence

Snapshots are user-initiated — no daemon, nothing in the background.

- **Switching machines, or joining a collaborator's space?** Run "catch me up" at the start.
- **Done with a conversation the other side should know about?** Run "snapshot this conversation" at the end.

If you forget either side, the only consequence is the other side misses that conversation. Nothing breaks.

## What this plugin does NOT do

- Sync your actual memory files (`MEMORY.md`, etc.) — those are derived state, written naturally as Claude processes snapshots. The two sides' memory dirs *will* drift slightly; that's intentional.
- Grant folder access. Sharing a folder with another person is done at the cloud level (SharePoint invite, OneDrive/Dropbox share) — the plugin writes files but never manages permissions.
- Sync chats themselves. It only sees the *current* conversation's context.
- Run in the background, or resolve cloud "conflicted copy" files (rare — the date-and-author-prefixed filenames make collisions nearly impossible).

## Versioning

[Semantic Versioning](https://semver.org/spec/v2.0.0.html). See [CHANGELOG.md](CHANGELOG.md) for history, including the v2 (single-user, snapshot-based) → v3 (multi-participant) change.
