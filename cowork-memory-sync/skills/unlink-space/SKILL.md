---
name: unlink-space
description: >
  This skill should be used when the user asks to "unlink this space",
  "stop syncing this space", "remove this space's sync link",
  "disconnect this space from sync", "unhook this space", or similar
  phrases that ask to remove the local link between the current Cowork
  space and its cloud-synced snapshot folder. Use this skill only for
  removing the link on the current machine — the snapshot folder itself
  is left intact (other machines/people may still be linked to it).
metadata:
  version: "3.1.0"
---

# unlink-space

Remove the local link between this Cowork space and its snapshot folder. Deletes `.sync-link.json` and `.sync-ledger.json` from the space's memory dir, and — for a shared space — removes your presence file from the folder so other participants see you've left. Leaves the `_cowork-snapshots/` folder and all snapshots intact.

## When this skill is appropriate

Use when the user wants to:
- Stop syncing this space on this machine
- Re-link this space to a different folder (run `unlink-space` first, then `link-space`)
- Clean up a stale link

Do NOT use to:
- Delete snapshots in the cloud folder (the user can `rm` those manually, or wait for the 30-day sweep)
- Stop syncing on the *other* machine — this only affects the local machine the skill runs on

## Determine the memory directory

The current space's memory directory is in your system prompt under the auto-memory section. Set `MEMORY_DIR` to that path.

If you cannot find it, stop and ask the user to paste the memory folder path.

## Step 1 — Read the link file

Try to Read `MEMORY_DIR/.sync-link.json`.

- **If it exists**: extract `alias`, `store_path`, and `mode` (default `solo` if absent), continue to Step 2.
- **If it doesn't exist**: tell the user *"This space isn't linked — nothing to unlink."* and stop.

If `mode == "shared"`, also resolve your `user`/`machine` identity (global `CONFIG_HOME/identity.json` — `~/.config/cowork-memory-sync/` on macOS, `$USERPROFILE/.config/cowork-memory-sync` on Windows — → per-space `user`/`machine` fields on this link) so you can find your presence file in Step 3.

## Step 2 — Confirm with the user

Use AskUserQuestion:

- **Question**: "Unlink this space (alias: `<alias>`) from `<store_path>`? The snapshot folder itself will be left intact — only this machine's link record is removed."
- **Header**: "Unlink"
- **Options**:
  - `Yes, unlink it` — proceed to Step 3
  - `Cancel` — stop without changes

## Step 3 — Remove your presence, then delete the link files

If `mode == "shared"`, remove your presence file so other participants see you've left (best-effort — don't fail the unlink if it's already gone or the folder is unreachable):

```bash
rm -f "<store_path>/.participants/<user>@<machine>.json"
```

Then delete the local link files:

```bash
rm -f "$MEMORY_DIR/.sync-link.json" "$MEMORY_DIR/.sync-ledger.json"
```

(Using `rm -f` so it doesn't error if a file is somehow missing.)

## Step 4 — Report

Concise:

> Unlinked this space (`<alias>`).
>
> The snapshot folder at `<store_path>` is left intact — other machines/people may still be linked to it.
> <If shared:> Removed your presence file, so other participants will see you've left.
>
> To re-link (to a different folder, for example): say "link this space."

## What NOT to do

- **Don't delete the `_cowork-snapshots/` folder.** Other machines may still have active links pointing at it. The user can `rm -rf` the folder themselves if they're certain no other machine is using it.
- **Don't delete any of the snapshot `.md` files inside the folder.** Same reasoning — they belong to the shared folder, not this machine's link.
- **Don't unlink across machines.** This skill only touches the current machine's memory dir. To unlink on the other machine, the user runs the skill there.
- **Don't push or pull anything** on the way out. Unlink is purely a local operation.
- Don't expose the memory dir path in the user-facing report unless useful.
