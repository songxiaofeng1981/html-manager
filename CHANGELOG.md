# Changelog / 更新记录

## 1.6.0 — index in a hidden folder / 索引改放隐藏文件夹

**English**

- The index moves from `Manager.html` at the top of the library to the hidden `.manager/index.json` (plain JSON, written atomically). Each file's `doc-meta` stays the record of truth.
- Before every write the previous index is copied to `.manager/backups/`; the newest 10 are kept.
- A missing or damaged index is rebuilt from the `doc-meta` in `Manager_Files`, with Markdown rows and rows for files without `doc-meta` taken from the newest backup. A damaged file is kept aside. A lost index no longer offers to start an empty library, which would have turned every document into one waiting to be imported.
- **Rebuild Index…** in **Folders**, and on the "Cannot read the Manager index" page.
- An old `Manager.html` index is moved in automatically the first time, Markdown rows included, and renamed `Manager-旧索引.html` (not deleted).
- **Create Library** makes `.manager/index.json` and `Manager_Files`; documents already in `Manager_Files` go straight into the index.
- The page asks for the 1.6 helper, since an older one can't read the new index.
- Protocol: new `rebuildIndex` operation, `notice` on `list`, error code `index_exists`. 98 protocol checks.

**中文**

- 索引从资料库最上层的 `Manager.html` 改放到隐藏的 `.manager/index.json`（普通 JSON，原子写入）。每个文件里的 `doc-meta` 仍是正本。
- 每次写索引前把旧索引复制到 `.manager/backups/`，只保留最近 10 份。
- 索引丢了或坏了，就从 `Manager_Files` 里的 `doc-meta` 重建，Markdown 行和没有 `doc-meta` 的文件的行取自最近一份备份；损坏的文件另存保留。索引丢了不再提示“新建资料库”（那会把所有资料变成待收录）。
- “资料库位置”里和“无法读取 Manager 索引”页面上新增 **“重建索引…”**。
- 第一次遇到旧的 `Manager.html` 索引时自动搬入（含 Markdown 行），旧文件改名为 `Manager-旧索引.html`，不删除。
- “新建资料库”创建 `.manager/index.json` 和 `Manager_Files`；`Manager_Files` 里已有的资料直接进索引。
- 页面要求 1.6 的本机助手，因为旧助手读不了新索引。
- 协议：新增 `rebuildIndex` 操作、`list` 的 `notice`、错误码 `index_exists`。98 项协议测试。

## 1.5.0 — first public release / 首个公开版本

**English**

- New interface modeled on Apple Photos: light gray sidebar with foldable sections (library, categories, tags), toolbar with search, day calendar, sort, grid/list and card size, an Info panel with every version, selection like Photos, a confirmation sheet for the Trash, keyboard shortcuts (`?`), light and dark mode, English and Chinese.
- Library and new-files folder can be set separately (**Folders**), so the library can live on an external disk. A missing folder is reported, never replaced by Downloads.
- **Create Library** on first use: a new `Manager.html` and `Manager_Files` folder.
- Importing across folders copies linked local files into `Manager_Files/_附件` and fixes the links.
- Thumbnails are made with macOS Quick Look: no Node, Playwright or Chrome needed, page scripts don't run and nothing is loaded from the web.
- The index follows `href`, so a moved library keeps working; `path` is refreshed whenever the index is written.
- Universal helper (Apple silicon and Intel), `install.sh` / `uninstall.sh` / `selftest.sh`, registration for Chrome, Edge, Brave, Arc and Vivaldi.
- Development: dev server with a `chrome.*` shim, sample generator and 70 protocol checks.

**中文**

- 界面参照 Apple“照片”重做：可折叠的浅灰侧边栏（资料库、分类、标签）、工具栏（搜索、日历、排序、网格/列表、卡片大小）、显示全部版本的信息面板、和“照片”一样的多选、移到废纸篓前的确认面板、键盘快捷键（按 `?`）、浅色/深色模式、中英文界面。
- 资料库和收件文件夹可以分开设置（“资料库位置”），资料库可以放在移动硬盘上。文件夹不存在时只提示，绝不改用 Downloads。
- 第一次使用时可以“新建资料库”（创建 `Manager.html` 和 `Manager_Files`）。
- 跨文件夹收录时，被引用的本地文件复制到 `Manager_Files/_附件` 并改好链接。
- 缩略图改用 macOS 快速查看生成：不再需要 Node、Playwright 或 Chrome，页面脚本不运行，也不从网上加载内容。
- 索引以 `href` 为准，资料库搬家后仍可用；每次写回索引时更新 `path`。
- 通用版本机助手（Apple 芯片和 Intel），`install.sh` / `uninstall.sh` / `selftest.sh`，可登记到 Chrome、Edge、Brave、Arc、Vivaldi。
- 开发：带 `chrome.*` 替身的开发服务器、示例生成和 70 项协议测试。

## 1.3–1.4 — private trial / 私有试用版

Search, filters, card and list views, importing with metadata and thumbnails, version families, and Move to Trash, as a personal trial.
搜索、筛选、卡片和列表视图、带元数据和缩略图的收录、版本组、移到废纸篓，个人试用版本。
