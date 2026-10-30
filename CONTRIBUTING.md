# Contributing / 参与贡献

Issues and pull requests are welcome, in English or Chinese.
欢迎提 issue 和 PR，中文英文都可以。

## Reporting a problem / 报告问题

Please use the issue templates and include:
请使用 issue 模板，并附上：

- your macOS and Chrome versions / macOS 和 Chrome 的版本
- the output of `bash "$HOME/Library/Application Support/Manager HTML/selftest.sh"` / 自检的输出
- what the Manager page showed (a screenshot helps) / 管理页显示了什么（最好附截图）

The self-test prints folder paths and counts, not file contents. Remove anything you don't want to share.
自检只打印文件夹路径和数量，不含文件内容。不想公开的内容可以先删掉。

## Development setup / 开发环境

You need the Xcode Command Line Tools (`xcode-select --install`) and Python 3 (it comes with them).
需要 Xcode 命令行工具（`xcode-select --install`），Python 3 随之附带。

```bash
bash helper/build.sh                                          # build the helper / 编译本机助手
python3 dev/protocol_test.py                                  # test the helper / 测试本机助手
python3 dev/make_samples.py /tmp/manager-lib /tmp/manager-inbox   # sample documents / 生成示例资料
python3 dev/serve.py /tmp/manager-lib /tmp/manager-inbox          # run the page / 运行管理页
```

Then open <http://127.0.0.1:8771/manager.html> in any browser (add `?lang=zh` or `?lang=en`).
The page is the real `extension/` code. `dev/chrome-shim.js` stands in for the `chrome.*` APIs and forwards
Native Messaging to the real helper, which uses the sample folders and a throwaway settings file.
Edit files and reload the page; there is no build step. `&demo=info|select|import` sets up README screenshots.

然后在任意浏览器打开 <http://127.0.0.1:8771/manager.html>（可加 `?lang=zh` 或 `?lang=en`）。
页面运行的就是 `extension/` 里的真实代码。`dev/chrome-shim.js` 代替 `chrome.*` 接口，把 Native Messaging
转发给真正的本机助手，助手使用示例文件夹和一个临时设置文件。改完文件刷新页面即可，不需要构建。`&demo=info|select|import` 用于截 README 图。

**Use sample folders, not your real Downloads.** Importing and Move to Trash really change files.
**请用示例文件夹，不要用真正的“下载”。** 收录和移到废纸篓是真的会改动文件。

`dev/protocol_test.py` makes its own sample folders (one of them inside `dev/.tmp`, to test moving across disks)
and deletes them afterwards. Each run moves a few sample files to the Trash.
`dev/protocol_test.py` 会自己生成示例文件夹（其中一个在 `dev/.tmp`，用来测试跨磁盘移动），结束后删除。每次运行会把几个示例文件移到废纸篓。

## Guidelines / 约定

- Keep it small: plain HTML, CSS and ES modules, one Swift file, no frameworks, no build step, no network.
  保持轻量：原生 HTML、CSS、ES 模块，一个 Swift 文件；不加框架、不加构建步骤、不联网。
- No `style="..."` in HTML strings: the extension's security policy blocks it. Set colors with `el.style`.
  HTML 字符串里不要写 `style="..."`，插件的安全策略会拦截；颜色用 `el.style` 设置。
- Every new interface text goes into both languages in `extension/js/i18n.js`.
  新的界面文字要在 `extension/js/i18n.js` 里中英文都加上。
- Categories and tags live in both `extension/js/vocab.js` and `helper/ManagerHost.swift`; change them together.
  分类和标签同时写在 `extension/js/vocab.js` 和 `helper/ManagerHost.swift` 里，要一起改。
- The helper must never write to stdout except protocol messages, never delete outright (Trash only),
  and never fall back to Downloads when a configured folder is missing.
  本机助手除了协议消息不往 stdout 写任何东西；只用废纸篓，从不直接删除；设置的文件夹不存在时绝不退回 Downloads。
- Don't change the extension `key`, the host name `com.songxiaofeng.managerhtml` or the helper's bundle ID: existing installs depend on them.
  不要改插件的 `key`、宿主名 `com.songxiaofeng.managerhtml` 或助手的 Bundle ID，已有的安装依赖它们。
- If you change the helper, add a check to `dev/protocol_test.py`.
  改了本机助手，请在 `dev/protocol_test.py` 里加上对应的检查。

## Checking a change by hand / 手动检查

- Light and dark mode; English and Chinese. / 浅色和深色模式；中文和英文。
- Search, sidebar filters, date, sort, grid and list, Info panel, versions. / 搜索、侧边栏筛选、日期、排序、网格和列表、信息面板、版本。
- Select (circle, ⌘-click, ⇧-click, ⌘A), copy list, Move to Trash with confirmation. / 选择、复制清单、确认后移到废纸篓。
- Import with the same folder and with separate folders (linked files copied to `_附件`). / 同一文件夹和分开的文件夹下收录（附件复制到 `_附件`）。
- Folders: invalid paths refused, a missing library shows its page, Create Library on an empty folder. / 资料库位置：无效路径被拒绝、资料库不见时的说明页、空文件夹新建资料库。
- Index: an old `Manager.html` is moved in with a notice; delete or damage `.manager/index.json` and reload (rebuilt, Markdown rows back); Folders → Rebuild Index….
  索引：旧 `Manager.html` 自动搬入并提示；删掉或弄坏 `.manager/index.json` 后刷新（自动重建、Markdown 行恢复）；资料库位置 → 重建索引…。
- No Content Security Policy errors in the console. / Console 里没有内容安全策略报错。

## Releasing / 发布

```bash
bash scripts/package.sh     # dist/html-manager-vX.Y.Z.zip with a universal helper / 含通用版本机助手
```

Bump `version` in `extension/manifest.json`, `helperVersion` in `helper/ManagerHost.swift` and `helper/Info.plist`, and add a `CHANGELOG.md` entry.
修改 `extension/manifest.json` 的 `version`、`helper/ManagerHost.swift` 的 `helperVersion` 和 `helper/Info.plist`，并在 `CHANGELOG.md` 里写更新记录。
