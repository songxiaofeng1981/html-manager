# Design

**English** | [中文](DESIGN.zh-CN.md)

## Parts

```
extension/                 Chrome extension, Manifest V3, plain ES modules, no build step
  manager.html, manager.css
  js/main.js       wiring: sidebar, toolbar, selection, keyboard, Trash, folder settings, status pages
  js/library.js    search, filters, sort, version families, sidebar counts (no DOM)
  js/views.js      grid and list, file links, thumbnail URLs
  js/info.js       Info panel        js/calendar.js   day filter
  js/importer.js   Import New HTML   js/host.js       Native Messaging client
  js/vocab.js      categories and tag vocabulary      js/i18n.js       English and Chinese
  js/ui.js         icons, menus, toast, confirmation  js/prefs.js      display preferences
helper/ManagerHost.swift   Native Messaging host ("Manager Helper"), one Swift file
install.sh / uninstall.sh / selftest.sh
dev/                       dev server + chrome.* shim, sample generator, protocol tests
```

The extension's ID is fixed by the public `key` in `manifest.json` (`jpencbldoocakpdbgolffgemckpimnph`).
The installer registers the helper as `com.songxiaofeng.managerhtml` with only that ID in `allowed_origins`,
and the helper itself refuses any other caller.

## Folders

The helper works with two folders, both `~/Downloads` unless set in **Folders**:

- **Library**: `.manager/` (the index `index.json` and its `backups/`; hidden in Finder), `Manager_Files/` (imported HTML; `Manager_Files/_附件/` holds files they link to) and `.thumbs/` (400×250 JPEG thumbnails named after the href, `Manager_Files__name.jpg`).
- **New files (inbox)**: where new HTML arrives. Only files directly in this folder are offered for import.

Settings are saved in `~/Library/Application Support/Manager HTML/settings.json`, not in Chrome, so removing the extension keeps them.
Before every request the helper applies the settings. A folder that no longer exists is an error
(`library_missing`, `inbox_missing`); the helper never falls back to Downloads. Saving checks that both folders exist,
that an old `Manager.html` in the library (if there is no `.manager/index.json` yet) is an index it can read, and that the inbox is not inside the library.

## Index and metadata

**The record of truth is in each file.** On import, each HTML file gets `<script type="application/json" id="doc-meta">`
before `</head>` with its title, category, tags, keywords, summary and dates, so the details travel with the file.

**The index is a cache** in the library's hidden folder, the way Apple Photos, Obsidian (`.obsidian`) and Calibre keep theirs:
`.manager/index.json` is plain JSON, `{"version": 1, "files": [row…]}`, written atomically. Each row has `href` (relative to the
library for `Manager_Files/…`, or a bare file name for the inbox), `title`, `category`, `tags`, `keywords`, `description`,
`created`, `modifiedAt`, `fileType`, `filename`, `metadataManaged` and `path`. `href` is the source of truth: the helper resolves
files from the current library plus `href`, and rewrites `path` whenever it writes the index, so a library that moved still works.
Rows with `fileType: "MD"` are kept but not listed. An index with a higher `version` is refused and left alone.

- **Backups.** Before every write the previous `index.json` is copied to `.manager/backups/index-<date-time>.json`; the newest 10 are kept.
- **Rebuilding.** When `index.json` is missing, or can't be read (it is then kept as `.manager/index-损坏-<date-time>.json`),
  and the library has documents in `Manager_Files` or backups, the helper rebuilds the index at once: one row per HTML in
  `Manager_Files` from its `doc-meta`, starting from the newest readable backup so its order, its Markdown rows and rows for files
  without `doc-meta` come back; rows whose file is gone are dropped. The page says what happened. **Rebuild Index…** in
  **Folders** does the same on request, starting from the current index. Only a library with neither documents nor backups
  shows **Start your library**, so a lost index never turns every document into one waiting to be imported.
- **Moving in an older index.** Before 1.6 the index was `Manager.html`, a page whose script starts with
  `const files = [...]; const HTML_CONTROLLED = ...`. The first time 1.6 finds it (and no `.manager/index.json`), it copies every
  row, Markdown included, into `.manager/index.json` and renames the old file `Manager-旧索引.html`; it is never deleted.
  An old `Manager.html` that isn't such an index is reported (`index`) and left alone.
- **Create Library** makes `.manager/index.json` and `Manager_Files/`. If `Manager_Files` already has documents, they go straight into the index.

## Importing

1. `discover` lists HTML in the inbox root and in `Manager_Files` that the index doesn't have. Hidden files, symbolic links,
   `.manager`, `Manager.html`, `Manager-旧索引*.html` and `_附件` are skipped. Suggestions for category and tags come from the text; the page lets you correct them.
2. `import` checks the category and 2–4 tags against the vocabulary, then for each file: rewrites local links,
   writes `doc-meta`, copies linked files, moves the file into `Manager_Files` (a unique name if taken, never overwriting),
   makes the thumbnail in its new place, and finally writes the index once.
3. If anything fails, everything done so far is undone: files moved back, original HTML restored, copied files and new thumbnails removed.

**Links.** When library and inbox are the same folder, a relative link like `chart.png` becomes `../chart.png`.
When they differ, linked local files (not other HTML pages) are copied to `Manager_Files/_附件/` and the link points there.
Links between files imported together point to their new names.

**Thumbnails** are made with macOS Quick Look (`qlmanage`): the page's scripts don't run and nothing is loaded from the web.
The top 16:10 of a 1280-pixel rendering is scaled to 400×250 with ImageIO.

## Deleting

The page asks for confirmation listing the files. The helper then moves each file to the Trash with `FileManager.trashItem`
and removes its row from the index. Nothing is ever deleted outright.

## Message protocol

Chrome Native Messaging: each message is a 4-byte little-endian length followed by UTF-8 JSON. Messages to Chrome stay under 1 MB.
Every request has an `id`; the helper answers once with the same `id`.

| Request | Reply |
|---|---|
| `{op: "config"}` | `{type: "config", version, library, inbox, defaultLibrary, defaultInbox, libraryFound, inboxFound, canSave}` |
| `{op: "setConfig", library, inbox}` (empty = default) | `config` |
| `{op: "createIndex"}` | `{type: "result", ok, created, rows}` |
| `{op: "rebuildIndex"}` | `{type: "result", ok, index, rebuilt: {html, fromFiles, fromBackup, markdown, dropped, backup}}` |
| `{op: "list"}` | `{type: "items", items: [row…]}` with `path` and `rootPath` filled in; `notice: {event: "migrated" \| "rebuilt", …}` when the index was just moved in or rebuilt |
| `{op: "discover"}` | `{type: "candidates", items, inbox, library}`; inbox items may have `attachments: [{name, size}]` |
| `{op: "import", paths: [href…], metadata: {href: {category, tags}}}` | `{type: "result", ok, imported, thumbnails, attachments}` |
| `{op: "delete", path: href}` | `{type: "result", ok, deleted, remaining}` |
| anything that fails | `{type: "error", error, code}` with `code` one of `library_missing`, `inbox_missing`, `index`, `index_missing`, `index_exists`, `permission`, `settings`, `unknown_op`, `error` |

Development flags (Chrome never passes them): `--root <folder>` (default library and inbox), `--inbox <folder>`,
`--settings <file>`, and `--selftest` (read only: it describes an old or missing index without changing anything). A wrong folder makes the helper exit instead of using Downloads.

## Look and feel

Apple Photos on macOS is the reference: light gray sidebar with foldable sections, white content, system blue as the
only accent color, red only for the Trash, system font, light and dark appearance. Cards show only the thumbnail, title,
category and date; details live in the Info panel. Selecting turns the toolbar into an action bar. The extension's
Content Security Policy forbids inline styles, so colors are set from script (`el.style`), never with `style=""` in HTML strings.

## Choices

- **No `chrome.storage`.** Documents and their metadata live in your files, and the index lives next to them in the library,
  so removing the extension, changing browsers or moving to another Mac loses nothing. Only display preferences (layout, sort,
  card size, folded sections, Info panel) are kept in the page's `localStorage`.
- **A hidden index instead of `Manager.html`.** A visible page at the top of the library was easy to delete by mistake, and
  reading data back out of a script with a regular expression was fragile. The hidden JSON file is backed up and can always be rebuilt from the files.
- **No server, no network.** The helper runs only while the page is open and talks only to Chrome.
- **One vocabulary, two copies.** `extension/js/vocab.js` and `helper/ManagerHost.swift` must list the same categories and tags.
