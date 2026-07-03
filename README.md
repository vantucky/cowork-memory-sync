# cowork-memory-sync

A [Claude Cowork](https://claude.ai) plugin to **share space conversations across your machines and across people**, via a cloud-synced folder.

Finish a conversation on one machine, snapshot it, and catch up on it from another machine — or from a collaborator's. Snapshots are curated markdown summaries (not full transcripts, not raw memory files) written into a folder your cloud provider already syncs. **No daemon, no MCP server, no GitHub** — just files.

> **Requires Claude Cowork.** The plugin uses Cowork-only mechanics (the per-space memory directory and directory-access grants) and does not run in the plain Claude Code CLI.

## Install

```
/plugin marketplace add vantucky/cowork-memory-sync
/plugin install cowork-memory-sync
```

Then, in a Cowork space:

- **"link this space"** — pick a cloud folder and whether the space is *solo* (your machines) or *shared* (multiple people).
- **"snapshot this conversation"** — push a summary for the other side.
- **"catch me up"** — pull new snapshots (yours or a collaborator's).

## What's in it

Six skills: `link-space`, `snapshot-conversation`, `catch-up`, `scrub-space`, `unlink-space`, `list-links`.

Solo and shared modes are switchable in either direction. On **shared** spaces every push is gated behind a review-and-confirm step (so nothing leaks into a folder others read), the auto-sweep only ever touches your own snapshots, and a presence file shows who's participating. Every snapshot is attributed to its author.

Full details, prerequisites, and the folder convention are in the plugin's own README: [`cowork-memory-sync/README.md`](./cowork-memory-sync/README.md). Version history is in [`cowork-memory-sync/CHANGELOG.md`](./cowork-memory-sync/CHANGELOG.md).

## Sharing a space with someone

The plugin writes and reads files; it does **not** grant anyone access. To collaborate, share the backing folder at the cloud level:

- **Same M365 tenant** → a SharePoint / OneDrive-Business shared library.
- **Different accounts** → a OneDrive / Dropbox / Box folder shared with the other person's account, mounted locally on both sides.

Both people install this plugin, run "link this space" against their local view of that shared folder in **shared** mode, and push/pull as usual.

## Layout

```
.
├── .claude-plugin/
│   └── marketplace.json      ← marketplace manifest (one plugin)
├── README.md                 ← you are here
└── cowork-memory-sync/       ← the plugin
    ├── .claude-plugin/plugin.json
    ├── README.md
    ├── CHANGELOG.md
    └── skills/
```

## License

Provided as-is for personal and collaborative use.
