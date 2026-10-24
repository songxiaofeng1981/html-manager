# Changelog / 更新记录

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
