# 设计说明

[English](DESIGN.md) | **中文**

## 组成

```
extension/                 Chrome 插件，Manifest V3，原生 ES 模块，不需要构建
  manager.html, manager.css
  js/main.js       连线：侧边栏、工具栏、选择、键盘、废纸篓、资料库位置、说明页
  js/library.js    搜索、筛选、排序、版本组、侧边栏计数（不操作页面）
  js/views.js      网格和列表、文件链接、缩略图地址
  js/info.js       信息面板          js/calendar.js   按天筛选
  js/importer.js   收录新 HTML       js/host.js       Native Messaging 客户端
  js/vocab.js      分类和标签词表    js/i18n.js       中英文
  js/ui.js         图标、菜单、提示条、确认面板      js/prefs.js      显示偏好
helper/ManagerHost.swift   Native Messaging 本机助手（Manager Helper），一个 Swift 文件
install.sh / uninstall.sh / selftest.sh
dev/                       开发服务器 + chrome.* 替身、示例生成、协议测试
```

插件 ID 由 `manifest.json` 里公开的 `key` 固定（`jpencbldoocakpdbgolffgemckpimnph`）。
安装程序以 `com.songxiaofeng.managerhtml` 登记本机助手，`allowed_origins` 只包含这个 ID；助手自己也会拒绝其他调用方。

## 两个文件夹

本机助手使用两个文件夹，未在“资料库位置”中设置时都是 `~/Downloads`：

- **资料库**：`Manager.html`（索引）、`Manager_Files/`（已收录的 HTML；`Manager_Files/_附件/` 存放它们引用的文件）、`.thumbs/`（400×250 JPEG 缩略图，按 href 命名，如 `Manager_Files__名称.jpg`）。
- **收件文件夹**：新 HTML 所在处。只有直接放在这个文件夹里的文件会出现在待收录列表中。

设置保存在 `~/Library/Application Support/Manager HTML/settings.json`，不放在 Chrome 里，移除插件也不会丢。
助手在每个请求前应用设置。设置的文件夹不存在就报错（`library_missing`、`inbox_missing`），绝不退回 Downloads。
保存时检查两个文件夹都存在、资料库里的 `Manager.html`（如果有）能读取、收件文件夹不在资料库里面。

## 索引和元数据

`Manager.html` 是普通 HTML 页面，脚本以 `const files = [...]; const HTML_CONTROLLED = ...` 开头。
助手只读取并原子写回 `files` 数组。每行有 `href`（`Manager_Files/…` 相对资料库，单层文件名表示收件文件夹）、
`title`、`category`、`tags`、`keywords`、`description`、`created`、`modifiedAt`、`fileType`、`filename`、`metadataManaged`、`path`。
以 `href` 为准：助手用“当前资料库 + href”定位文件，每次写回索引时更新 `path`，资料库搬家后也能用。
`fileType: "MD"` 的行会保留，但不列出。

收录时，每个 HTML 在 `</head>` 前写入 `<script type="application/json" id="doc-meta">`，包含标题、分类、标签、关键词、摘要和日期。
新资料库从一个小模板开始，直接打开它也是一份资料清单。

## 收录

1. `discover` 列出收件文件夹根目录和 `Manager_Files` 中索引里没有的 HTML。跳过隐藏文件、符号链接、`Manager.html` 和 `_附件`。
   分类和标签建议来自正文，页面上可以修改。
2. `import` 按词表检查分类和 2～4 个标签，然后逐个文件：改写本地链接、写入 `doc-meta`、复制被引用的文件、
   移入 `Manager_Files`（重名时另取名字，绝不覆盖）、在新位置生成缩略图，最后一次性写回索引。
3. 任何一步失败，就撤回已经做的：文件移回原处、恢复原 HTML、删除复制的附件和新缩略图。

**链接。** 资料库和收件文件夹相同时，`chart.png` 这样的相对链接改成 `../chart.png`。
两者不同时，被引用的本地文件（不含其他 HTML 页面）复制到 `Manager_Files/_附件/`，链接指向副本。
同一批收录的文件之间的链接会指向它们的新名字。

**缩略图** 用 macOS 快速查看（`qlmanage`）生成：页面脚本不运行，也不从网上加载内容。
取 1280 像素渲染结果顶部 16:10 的部分，用 ImageIO 缩放到 400×250。

## 删除

页面先列出文件请你确认。本机助手再用 `FileManager.trashItem` 把每个文件移到废纸篓，并从索引中删掉对应的行。从不直接删除。

## 消息协议

Chrome Native Messaging：每条消息是 4 字节小端长度加 UTF-8 JSON。发给 Chrome 的消息小于 1 MB。
每个请求带 `id`，助手用同一个 `id` 回复一次。

| 请求 | 回复 |
|---|---|
| `{op: "config"}` | `{type: "config", version, library, inbox, defaultLibrary, defaultInbox, libraryFound, inboxFound, canSave}` |
| `{op: "setConfig", library, inbox}`（留空表示默认） | `config` |
| `{op: "createIndex"}` | `{type: "result", ok, created}` |
| `{op: "list"}` | `{type: "items", items: [行…]}`，填好 `path` 和 `rootPath` |
| `{op: "discover"}` | `{type: "candidates", items, inbox, library}`；收件文件夹的条目可能带 `attachments: [{name, size}]` |
| `{op: "import", paths: [href…], metadata: {href: {category, tags}}}` | `{type: "result", ok, imported, thumbnails, attachments}` |
| `{op: "delete", path: href}` | `{type: "result", ok, deleted, remaining}` |
| 任何失败 | `{type: "error", error, code}`，`code` 为 `library_missing`、`inbox_missing`、`index`、`index_missing`、`permission`、`settings`、`unknown_op`、`error` 之一 |

开发参数（Chrome 不会传）：`--root <文件夹>`（默认资料库和收件文件夹）、`--inbox <文件夹>`、`--settings <文件>`、`--selftest`。
文件夹无效时助手直接退出，不会改用 Downloads。

## 外观

参照 macOS“照片”：可折叠分区的浅灰侧边栏、白色内容区、系统蓝为唯一强调色、红色只用于废纸篓、系统字体、浅色和深色外观。
卡片只显示缩略图、标题、分类和日期；详细信息放在信息面板里。选中资料后工具栏变成操作栏。
插件的内容安全策略不允许内联样式，所以颜色由脚本设置（`el.style`），HTML 字符串里不写 `style=""`。

## 取舍

- **不用 `chrome.storage`。** 资料和元数据都在你的文件里；只有显示偏好（视图、排序、卡片大小、折叠的分区、信息面板）存在页面的 `localStorage`。
- **没有服务器，不联网。** 本机助手只在页面打开时运行，只和 Chrome 通信。
- **一份词表，两处副本。** `extension/js/vocab.js` 和 `helper/ManagerHost.swift` 必须列出相同的分类和标签。
