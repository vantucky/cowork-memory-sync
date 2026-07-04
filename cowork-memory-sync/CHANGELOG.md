# Changelog

All notable changes to the **cowork-memory-sync** plugin are documented here.

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/); the project uses [Semantic Versioning](https://semver.org/spec/v2.0.0.html):

- **MAJOR** (X.0.0) — breaking changes: skill IDs renamed, link-file schema changes, backing-store contract changes.
- **MINOR** (0.X.0) — backwards-compatible additions: new skills, new optional fields, new trigger phrases.
- **PATCH** (0.0.X) — backwards-compatible fixes: bug fixes, doc updates, description tuning, internal refactors.

Bump the version in `.claude-plugin/plugin.json` in the **same commit** that introduces the change, add an entry here, then tag (`git tag cowork-memory-sync-vX.Y.Z && git push --tags`).

---

## [3.1.1] — 2026-07-04

### Fixed
- **`list-links` failed in the Cowork sandbox.** It tried to enumerate every space by scanning the global sessions root (`~/Library/Application Support/Claude/…`) and read identity from `~/.config/` — neither of which a Cowork session can reach without a grant, so the skill dead-ended with "I can't access anything." Rewritten to:
  - **Always report the current space first** from `MEMORY_DIR/.sync-link.json` (the one folder always connected in-sandbox), so the skill is never empty-handed.
  - **Attempt the machine-wide scan as a best-effort bonus**, requesting a one-time `mcp__cowork__request_cowork_directory` grant for the sessions root and **degrading gracefully** to current-space-only (with a note) if that's declined or blocked — instead of failing.
  - **Resolve identity from the per-space link fields first** (`user`/`machine` in `.sync-link.json`), since `~/.config/identity.json` is commonly unreachable in the sandbox; global config is now a preferred-if-available source, not a requirement.

No schema, filename, or other-skill changes.

## [3.1.0] — 2026-07-03

Cross-platform support: the plugin now works on **Windows** desktop Cowork as well as macOS. (The **web** version remains unsupported — no local cloud-folder mounts, so the file-based model doesn't apply.)

### Changed
- **Platform-aware paths.** Every skill resolves cloud-mount roots, the config location, and the Cowork sessions root per OS: macOS `~/Library/CloudStorage` + `~/.config/...` + `~/Library/Application Support/Claude/...`; Windows `%USERPROFILE%\OneDrive`/`Dropbox`/`iCloudDrive`/`Box` + `%USERPROFILE%\.config\...` + `%USERPROFILE%\AppData\Roaming\Claude\...`. `link-space` gained a **Platform** section defining `CLOUD_ROOTS` / `CONFIG_HOME` / `MEMORY_ROOT`, detected via `uname`.
- **Removed BSD-only commands.** `date -v+30d` (macOS-only) is gone — the 30-day expiry is now computed in-model from a portable `date +…%z`. `hostname -s` → plain `hostname` with in-model domain-stripping.
- **Fewer shell-isms.** Snapshot listing, collision checks, and counts use the OS-abstracted **Glob** tool instead of `ls`, so less rides on shell differences. Remaining shell use (`mkdir -p`, `rm`, `cp`, `grep`) is POSIX; on Windows this assumes Cowork's POSIX-style shell, and a skill stops with a clear message rather than guessing PowerShell syntax if that's absent.
- **Docs** (README) gained a Platform-support table and Windows path examples; note that a macOS user and a Windows user can share the same space (identical snapshot files, per-machine path normalization).

No schema or filename changes; v3.0.0 links and snapshots are unaffected.

## [3.0.0] — 2026-07-03

Multi-participant release. A linked space can now be shared among **multiple people** (each on their own machine), not just multiple machines of one person. Snapshots are author-attributed; shared spaces gate every push behind a review step; a new skill bulk-scrubs the folder.

### Added
- **Shared spaces (multi-user).** A space now has a `mode`: `solo` (your machines only — the prior behavior) or `shared` (multiple people). Set at link time and **switchable in either direction** later via `link-space`.
- **Identity model.** Every snapshot records its author as `user` + `machine`. Identity is stored once per Mac at `~/.config/cowork-memory-sync/identity.json`, with a per-space fallback in `.sync-link.json` when Cowork's sandbox can't reach `~/.config/`. Supersedes v2's `machine.txt` (read once for migration).
- **Author-segmented filenames.** Snapshots are now `<date>-<user>-<slug>.md` (was `<date>-<slug>.md`) so participants never collide and every file's author is visible at a glance.
- **Shared-push review gate.** On a `shared` space, `snapshot-conversation` shows the drafted snapshot and **actively flags likely-sensitive content** (client/company names, docket numbers like `NNNN.NNNNNNN`, application/pub numbers, unfiled-amendment/strategy details, examiner names, dollar figures) before writing — Push / Edit / Cancel. Solo spaces are unchanged (no gate).
- **`scrub-space` skill (new).** Bulk-remove snapshots: your own by default (everyone's is gated + double-confirmed), filtered by everything / older-than-N / **keyword (greps bodies)** / explicit selection. Always previews + confirms, and **backs up to a local non-syncing `_scrubbed/<stamp>/`** in the memory dir before deleting. Prunes the ledger.
- **Presence files.** Shared spaces get `_cowork-snapshots/.participants/<user>@<machine>.json`, so `list-links` and `catch-up` can show who participates.
- **Re-home / migrate.** `link-space` can move a space to a different folder, copying *your* snapshots (copy-verify-then-delete) and re-pointing the link. The shared→solo switch defaults to re-homing to a fresh private folder (leaving the exposed one behind) and offers to scrub your files from the old folder.

### Changed
- **Sweep is now own-files-only.** `snapshot-conversation`'s 30-day sweep matches `<date>-<user>-*.md` and never deletes another participant's history. (Under v2 the sweep deleted *every* file >30d old — data loss the moment a folder is shared.)
- **`catch-up`** shows the author per snapshot and attributes its briefing by person; ignores the `.participants/` folder.
- **`list-links`** reports this Mac's identity, each space's mode, and shared-space participants.
- **`unlink-space`** removes your presence file from a shared folder on the way out.
- **README** rewritten for the multi-user model, with an explicit "Requires Claude Cowork" note and generic examples.

### Migration (v2 → v3)
Existing v2 solo links keep working. First `link-space`/`snapshot` captures your identity and upgrades the link to `schema_version: 3` (mode defaults to `solo`). Legacy `<date>-<slug>.md` files (no author segment) are shown as `(legacy)` on catch-up; the own-files-only sweep will not touch unsegmented files on a shared space (it can't prove they're yours).

## [2.4.1] — 2026-05-21

### Fixed
- **Machine-name global config was not reachable from Cowork's sandbox**, breaking the v2.3.0 design's central premise. `~/.config/cowork-memory-sync/` isn't in Cowork's default connected folders, so both Read of `machine.txt` and Bash writes to it fail. `snapshot-conversation` was then falling through to `hostname -s` which (inside Cowork's sandbox) returns the container's hostname — useless — and the previous frontmatter ended up reading `machine: unknown`.
- `link-space` now uses a probe-and-degrade pattern (per the original `_memory_snapshot_20260521/MEMO_skill_bug.md` design):
  1. Try to Read `~/.config/cowork-memory-sync/machine.txt`.
  2. If the sandbox blocks it, call `mcp__cowork__request_cowork_directory` to ask the user to grant `~/.config/cowork-memory-sync/`. One-time per Mac.
  3. If the grant succeeds, write/read the global config as v2.3.0 designed.
  4. If the grant is declined (or the write still fails), fall back to writing the machine name into this space's `.sync-link.json` `machine` field. Works per-space — same UX as v2.2.0.
- `snapshot-conversation` read order is now explicit about silent degradation: global config → per-space `machine` field → `hostname -s` → `"unknown"`. Each step skips silently if blocked; no user prompts at push time.
- `snapshot-conversation` also sanity-checks the `hostname -s` result. If it looks like a container ID (long hex string, or contains `docker`/`container`/`linux`), it's discarded and falls through to `"unknown"`. Avoids the v2.3.0 bug of stamping container IDs into snapshot frontmatter.
- When the final machine name is `"unknown"`, `snapshot-conversation`'s user-facing report now notes that and suggests re-running `link-space` to set the name.

## [2.4.0] — 2026-05-21

### Added
- `list-links` skill — read-only summary of all linked spaces on this Mac: alias, store folder, snapshot count, linked-at timestamp. Also shows the global machine name (or notes if not set yet). Triggers on phrases like "what spaces are linked," "show sync status," "list my synced spaces."

## [2.3.0] — 2026-05-21

### Changed
- **Machine name is now machine-wide**, not per-space. Stored at `~/.config/cowork-memory-sync/machine.txt` — set once per Mac, shared by every linked space on that Mac. Previously (v2.2.0) the name was stored per-space in `.sync-link.json`, which meant linking N spaces required N separate name prompts and risked drift.
- `link-space` now: if a machine name is already registered on this Mac, asks "Keep `<existing>` or change for all spaces on this Mac?" Only asks the full picker if no name has been set yet (or the user wants to change).
- `snapshot-conversation` reads the machine name from `~/.config/cowork-memory-sync/machine.txt` first; falls back to the per-space `machine` field in `.sync-link.json` (legacy v2.2.0 links); finally to `hostname -s`.
- `link-space` no longer writes a `machine` field into newly-created `.sync-link.json` files (the global config supersedes it). Legacy `.sync-link.json` files with a `machine` field continue to work as the second-priority fallback.

### Migration (no action required)
- v2.2.0 links keep working — `snapshot-conversation`'s fallback chain handles them.
- The first time `link-space` runs on a machine after the v2.3.0 update, the user will be prompted to set the machine name (and it'll be saved to the global config). From that point on, every linked space on that Mac uses that name.
- To change a machine's name globally: re-run `link-space` in any linked space and pick "Change for all spaces on this Mac." Updates apply immediately to future snapshots from this Mac.

## [2.2.0] — 2026-05-21

### Added
- `link-space` now asks the user to pick a memorable machine name (e.g., `laptop`, `workhorse`, `desktop`, or custom). Default option is whatever `hostname -s` returns (which on macOS tends to be awkward — `Ricks-MacBook-Pro-2`, `Richards-Mac-mini`). The chosen name is stored as the optional `machine` field in `.sync-link.json`.
- `snapshot-conversation` now reads the `machine` field from `.sync-link.json` (set in Step 1) and uses it as the `machine:` frontmatter value when writing the snapshot. Falls back to `hostname -s` if the field is missing (e.g., for links created before v2.2.0 or by hand).

### Schema (backwards compatible)
- `.sync-link.json` gains an optional `machine` field. `schema_version` stays at `2` — older link files without this field continue to work; they just use the `hostname -s` fallback.

### Migration
- No action needed. Existing links keep working with `hostname -s`. To switch a space to a custom name, run `unlink-space` then `link-space` again (or hand-edit `.sync-link.json` to add a `"machine"` field).

## [2.1.2] — 2026-05-21

### Changed
- `catch-up` selection UX: instead of iterating per-snapshot with include/skip/stop prompts, the skill now writes a numbered markdown list of new snapshots inline, then asks via AskUserQuestion: `All N` / `Most recent only` / `Cancel`, with an `Other` text-input option for picking specific numbers (`1,3,5` or `2-4`).
- Made the "uningested snapshots stay out of `pulled[]`" rule explicit in the SKILL.md — only the snapshots the user actually picked to ingest get added to the ledger. Skipped ones remain in the "new" set on future catch-up runs, so the user can ingest them later. (Behavior was already correct; the doc was just implicit about it.)

## [2.1.1] — 2026-05-21

### Changed
- `link-space` no longer writes a `.link-probe` file to test Cowork sandbox access to the chosen store folder. The probe was triggering a delete-permission prompt during link, which was friction for unclear benefit (in practice, if `find` discovered the folder or `mkdir` succeeded creating it, sandbox access was already fine). If a future `snapshot-conversation` write does hit a sandbox barrier, the error surfaces there instead. Renumbered steps 4–8 accordingly (now 4–7).

## [2.1.0] — 2026-05-21

### Added
- `unlink-space` skill — removes `.sync-link.json` and `.sync-ledger.json` from the space's memory dir, severing this machine's link to the snapshot folder. Leaves the `_cowork-snapshots/` folder and its snapshot files intact (other machines may still be linked to the same folder; cleanup of the folder itself is left to the user). Triggers on phrases like "unlink this space," "stop syncing this space," "disconnect this space."

## [2.0.1] — 2026-05-21

### Fixed
- `link-space` could auto-select the snapshot folder when Step 2's discovery returned only one candidate. The SKILL.md said "Use AskUserQuestion" but didn't say "always, even when the answer seems obvious," so Claude in Cowork inferred wiggle room and skipped the prompt. The skill now states explicitly that Step 3 is always interactive — the user must confirm the folder choice every time `link-space` runs, regardless of how many candidates Step 2 found.

## [2.0.0] — 2026-05-21

### Breaking — pivot from GitHub MCP to cloud-synced folder

The plugin no longer uses a GitHub repo + GitHub MCP for snapshot storage. Instead, the user picks a cloud-synced folder (typically a project folder under `~/Library/CloudStorage/OneDrive-Personal/<project>/`) the first time a space is linked. The skill creates a `_cowork-snapshots/` subdir there, and the cloud provider (OneDrive, iCloud, Dropbox, etc.) handles cross-machine propagation. Skills use standard filesystem tools (Read, Write, Glob, Bash) — no MCP required.

**Why the pivot:** v1.0.0 was released but never functional. It depended on the `engineering-github` MCP plugin for `get_file_contents` / `create_or_update_file` tools, but that plugin's OAuth flow proved broken in the wild ("the GitHub MCP server doesn't support dynamic client registration") and exposed only auth shims, not operation tools. After exhausting fix paths (manual auth, plugin reinstall, Cowork-level GitHub connector), the cleanest path forward was to drop MCP entirely and rely on standard file tools + a cloud-synced folder. That also matches how the maintainer was manually handing snapshots between machines (via OneDrive) before the plugin existed.

### Changed
- **`.sync-link.json` schema v2**: `remote` (GitHub `owner/repo`) replaced by `store_path` (absolute path to the chosen `_cowork-snapshots/` folder). Schema version bumped to `2`.
- **Backing store**: arbitrary cloud-synced folder per space, picked at link time. Convention: `<chosen-project-folder>/_cowork-snapshots/<YYYY-MM-DD>-<slug>.md`. One folder per linked space — folder choice IS the namespace.
- **Alias**: now derived by default from the parent folder name (lowercased, whitespace/underscores → hyphens). User can override at link time.
- **link-space**: discovers candidate folders by Globbing/finding `_cowork-snapshots/` directories under `~/Library/CloudStorage/`. Offers existing ones first, then "create new" with a parent-folder picker.
- **snapshot-conversation**: writes directly to the linked folder, no remote API call. Sweep of >30-day-old files done via `rm` (Bash) after Glob.
- **catch-up**: Globs the linked folder, diffs against ledger's `pulled[]`, Reads selected files.

### Removed
- Any dependency on `engineering-github`, `mcp__plugin_engineering_github__*`, or other GitHub MCP tools.
- The `vantucky/cowork-memory-sync` GitHub repo is no longer used by the plugin. (Left in place on GitHub as historical; force-push reset on 2026-05-21 turned out to be unused by the time it landed.)

### Migration from 1.0.0
None of the v1.0.0 link files exist in the wild (the plugin never functioned, so no `.sync-link.json` was ever successfully written by it). If you somehow have one, delete it and re-run `link-space`.

### Prerequisites for 2.0.0
- A cloud-synced folder per linked space (OneDrive, iCloud Drive, Dropbox, Syncthing — anything that puts the same files on both Macs). The plugin doesn't sync; it relies on whatever the OS already does.
- Cowork directory access granted to the chosen folder (the link-space skill triggers `mcp__cowork__request_cowork_directory` if needed).

---

## [1.0.0] — 2026-05-21 (superseded by 2.0.0 the same day; never functional)

### Breaking — full architecture rewrite (later abandoned)

Rewrote from the v0.x host-daemon + symlink model to on-demand conversation snapshots via a GitHub MCP + private repo. **The GitHub MCP layer was never functional in the maintainer's install** — the `engineering-github` plugin only exposed auth shims, not operation tools. v1.0.0 was published before this was discovered. v2.0.0 (same day) replaced the GitHub backend with a cloud-synced folder. v1.0.0 is documented here for traceability only.

### Added (in 1.0.0)
- `link-space`, `snapshot-conversation`, `catch-up` — same skill names, same conceptual flow, just talking to GitHub MCP instead of a filesystem folder.

### Removed (in 1.0.0)
- `sync-link-project`, `sync-unlink-project`, `sync-now`, `checkpoint-conversation` — the v0.x skills.
- The `cowork-sync-cowork` host CLI, LaunchAgent, `~/.cowork-sync-cowork/` directory layout.

### Migration from 0.x (done manually on the maintainer's two machines on 2026-05-21)
1. `launchctl bootout "gui/$(id -u)" "$HOME/Library/LaunchAgents/com.cowork-sync-cowork.plist"; rm -f "$_"`
2. For each linked alias: `~/.cowork-sync-cowork/scripts/cowork-sync-cowork unlink <alias>` (reverts symlink → real dir with the synced files copied back in).
3. `rm -rf ~/.cowork-sync-cowork`.
4. Force-pushed a clean `main` to `vantucky/cowork-memory-sync` (one commit, README only). Then v2.0.0 stopped using the repo at all.

---

## [0.1.1] — 2026-05-20

### Fixed
- `plugin.json` `description` field said *"Three skills: link a space to the sync repo, unlink it, or force an immediate sync."* — but the plugin actually shipped **four** skills (the listed three plus `checkpoint-conversation`). Description now matches reality. Doc-only fix; no behavior change.

### Related (host-side, not in this repo)
- The companion `cowork-sync-cowork` host CLI (in `vantucky/cowork-memory-sync`, the separate daemon repo) replaced its `flock`-based lock with a portable `mkdir`-based lock so the daemon stops emitting `flock: command not found` on macOS LaunchAgent runs where `/opt/homebrew/bin` isn't on PATH. That change lived in the daemon repo, not here — but mentioned for cross-referencing. (Both the daemon and this entry are obsolete after 1.0.0.)

## [0.1.0] — 2026-05-18

### Added
- Initial release as a sideloaded `.plugin` zip; folded into the `vantucky/custom-plugins` marketplace on 2026-05-19.
- Four skills:
  - `sync-link-project` — link a Cowork space to the sync repo (natural-language triggers: "sync this project", "set up sync for this", "mirror this space").
  - `sync-unlink-project` — remove a space's link on this machine.
  - `sync-now` — force an immediate reconcile/push, bypassing the 60s LaunchAgent tick.
  - `checkpoint-conversation` — sweep the current conversation and write salient state to memory files, picked up by the daemon's next reconcile.
- Companion host CLI (`cowork-sync-cowork`, separate repo) handles the actual git pull/push and symlink management via a LaunchAgent running every 60s. `fswatch` enables sub-minute reactivity when installed.
