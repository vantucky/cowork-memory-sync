# Testing cowork-memory-sync

A two-person, cross-platform test plan for validating the plugin end to end — one participant on **macOS**, one on **Windows** — sharing a real space. It front-loads the risky Windows-specific checks (Phase 0) so any showstopper surfaces before you invest in the full flow.

There is no automated test suite (the skills are prompt-driven), so this manual run *is* the validation. Please record results in the table at the bottom and note anything that fails.

## Roles used in this doc

| Role | Platform | Identity |
|---|---|---|
| **Rick** | macOS | `richard.dyer` |
| **Travis** | Windows | `travis` |

Substitute your own names/identities as needed.

## Setup (before you start)

- [ ] **One shared cloud folder both machines can see.** Easiest path: Rick shares a **OneDrive** (or Dropbox) folder with Travis's account; Travis clicks **"Add shortcut to My files"** so it mounts locally on Windows under `%USERPROFILE%\OneDrive\…`. Use a dedicated test folder, e.g. `sync-test`.
- [ ] Both install the plugin in a Cowork space:
  ```
  /plugin marketplace add vantucky/cowork-memory-sync
  /plugin install cowork-memory-sync
  ```

## Phase 0 — Windows environment sanity (do this FIRST)

These three checks cover the assumptions that could not be verified without a Windows Cowork instance. **If any fails, stop and report it** — it changes the fix.

**Helper scripts** ([`tools/`](./tools)):
- **[`tools/windows-layout-check.ps1`](./tools/windows-layout-check.ps1)** — run in **PowerShell** (or a Windows Claude Code session) to verify the app-data/sessions path, cloud mounts, and config path in one shot. Covers 0b/0c below. Paste its output back.
- **[`tools/cowork-shell-check.sh`](./tools/cowork-shell-check.sh)** — paste **inside a Cowork session** and say "run this in bash" to check whether Cowork's shell is POSIX-style with the commands the plugin uses. This is the thorough version of 0a.

- [ ] **0a — POSIX shell.** In Travis's Windows Cowork, run [`tools/cowork-shell-check.sh`](./tools/cowork-shell-check.sh) (or, quick version, ask it to run `uname -s` and `date +%Y-%m-%d`).
  - **Pass:** returns something like `MINGW64…` / `MSYS` and today's date.
  - **Fail:** "command not found" → the Windows shell isn't POSIX-style (the biggest risk). Report this.
- [ ] **0b — Cloud mount reachable.** Ask Travis's Cowork to list the shared folder, e.g. `ls "$USERPROFILE"/OneDrive*/sync-test`.
  - **Pass:** it lists the folder (after granting directory access).
  - **Fail:** wrong path → report the real path his OneDrive/Dropbox uses.
- [ ] **0c — Sessions path.** After Travis's first link (Phase 2), run **"what spaces are linked."**
  - **Pass:** it finds the link.
  - **Fail:** finds nothing → the Windows `%USERPROFILE%\AppData\Roaming\Claude\…` sessions path is wrong; report what his memory-dir path actually looks like.

## Phase 1 — Solo sanity (Rick, Mac ↔ Mac — optional, quick)

- [ ] Mac A: "link this space" → **solo**, set identity, then "snapshot this conversation."
- [ ] Mac B: link the same space to the same folder → "catch me up."
  - **Pass:** the snapshot shows up. (Confirms the baseline still works after the v3.1 rewrites.)

## Phase 2 — Shared space, cross-platform (the main event)

- [ ] **Rick (Mac):** "link this space" → **shared**, identity `richard.dyer`, point at the `sync-test` folder.
  - **Pass:** creates `_cowork-snapshots/` and `_cowork-snapshots/.participants/richard.dyer@<mac>.json`.
- [ ] **Travis (Windows):** "link this space" → **shared**, identity `travis`, point at his local view of the same folder. → run the **0c** check now.
- [ ] **Either:** "what spaces are linked."
  - **Pass:** shows mode `shared` and both participants.
- [ ] **Rick pushes:** "snapshot this conversation."
  - **Pass:** the **review gate** fires (shows the draft before writing). Push. File appears as `<date>-richard.dyer-<slug>.md`.
- [ ] **Travis catches up** (after OneDrive syncs, ~1 min): "catch me up."
  - **Pass:** sees Rick's snapshot listed with author `richard.dyer`, ingests it, and the briefing attributes it to `richard.dyer`.
- [ ] **Travis pushes** (Windows): "snapshot this conversation."
  - **Pass:** the gate fires on Windows too; file is `<date>-travis-<slug>.md`. *(This validates Windows write + `date` + filename.)*
- [ ] **Rick catches up:** "catch me up."
  - **Pass:** sees Travis's snapshot attributed to `travis`.

## Phase 3 — Safety features (the ones that matter most)

- [ ] **Confidentiality gate.** Rick pushes a snapshot whose conversation mentions a fake **`2001.1234567`** docket and a client name.
  - **Pass:** the preview **flags** those items before writing. Also exercise the **"Let me edit first"** and **"Cancel"** paths.
- [ ] **Own-files-only sweep (the data-loss guard).** Manually drop a fake old file named `2026-05-01-travis-old.md` into the folder. Then **Rick** pushes a snapshot.
  - **Pass:** Rick's sweep deletes only his own >30-day files and **leaves `travis`'s old file untouched.** *(This is the v2 bug the rewrite fixed — worth confirming for real.)*

## Phase 4 — Mode switching & scrub

- [ ] **Scrub by keyword.** Rick runs "scrub this space," filters by keyword `2001.`.
  - **Pass:** preview shows only matching files, and only *Rick's* (mine-default); backs up to `_scrubbed/…` in the memory dir; then deletes; prunes the ledger.
- [ ] **Shared → solo re-home.** Rick: "make this space private."
  - **Pass:** offers to move to a new private folder; copies **only Rick's** snapshots (not Travis's); removes Rick's presence file; offers to scrub the old folder.
- [ ] **Solo → shared.** On a solo space: "share this space with others."
  - **Pass:** warns about the private back-catalog + offers a scrub, and reminds Rick to share the folder at the cloud level.

## Phase 5 — Teardown

- [ ] Both run "what spaces are linked" → verify identity, mode, participants, and counts render correctly on **both** OSes.
- [ ] Travis runs "unlink this space."
  - **Pass:** his presence file disappears; Rick's next "what spaces are linked" no longer lists Travis.

## Known likely failure points

| Symptom | Likely cause |
|---|---|
| Windows: "command not found" for `uname`/`find`/`date` | Cowork's Windows shell isn't POSIX-style (Phase 0a) |
| "what spaces are linked" finds nothing on Windows | Windows sessions path (`AppData\Roaming\Claude\…`) differs from assumed |
| "catch me up" shows nothing right after a push | Cloud provider hasn't synced yet — wait ~1 min and retry |
| Folder-not-found on a SharePoint path | Path has spaces (e.g. `Shared Documents`) — quoting; report the exact path |
| Wrong cloud-mount root | The machine mounts OneDrive/Dropbox somewhere other than assumed — report the real root |

## Results

| Check | Rick (Mac) | Travis (Windows) | Notes |
|---|---|---|---|
| 0a POSIX shell | — | ☐ pass / ☐ fail | |
| 0b Cloud mount reachable | — | ☐ | |
| 0c Sessions path found | — | ☐ | |
| Phase 2 link (shared) | ☐ | ☐ | |
| Phase 2 push + gate | ☐ | ☐ | |
| Phase 2 catch-up + attribution | ☐ | ☐ | |
| Phase 3 confidentiality gate | ☐ | ☐ | |
| Phase 3 own-files-only sweep | ☐ | ☐ | |
| Phase 4 scrub (keyword) | ☐ | — | |
| Phase 4 shared→solo re-home | ☐ | — | |
| Phase 4 solo→shared | ☐ | — | |
| Phase 5 list-links / unlink | ☐ | ☐ | |

Report failures with the exact error text or the odd path — that's what pins down a fix.
