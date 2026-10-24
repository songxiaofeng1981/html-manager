# Guide for coding agents / AI 协作指南

Manager is a Chrome extension (Manifest V3, plain ES modules, no build step) plus a one-file Swift Native Messaging
helper that manages local HTML documents in a library folder. Read `docs/DESIGN.md` first; contributor rules are in `CONTRIBUTING.md`.
Manager 是一个 Chrome 插件（Manifest V3、原生 ES 模块、无构建）加一个单文件 Swift 本机助手，用来管理资料库里的本地 HTML。
先读 `docs/DESIGN.zh-CN.md`；贡献约定见 `CONTRIBUTING.md`。

## Must not change / 不能改

- `key` in `extension/manifest.json` (extension ID `jpencbldoocakpdbgolffgemckpimnph`), host name `com.songxiaofeng.managerhtml`,
  helper bundle ID `com.songxiaofeng.managerhtml.helper`, the settings file location and the `Manager.html` index format.
  插件 `key`、宿主名、助手 Bundle ID、设置文件位置和 `Manager.html` 索引格式。

## Rules / 规则

- Helper stdout carries only length-prefixed protocol JSON; diagnostics go to stderr. / 助手的 stdout 只能输出协议消息。
- Deleting only through the Trash and only after confirmation in the page. / 只能在页面确认后移到废纸篓。
- A configured folder that is missing is an error; never fall back to Downloads. / 设置的文件夹不存在时报错，绝不退回 Downloads。
- No `style=""` in HTML strings (CSP); colors via `el.style`. / HTML 字符串里不写 `style=""`。
- Interface text in both languages (`extension/js/i18n.js`); vocabulary in both `extension/js/vocab.js` and `helper/ManagerHost.swift`.
  界面文字中英文都要有；词表两处同步。
- Test with sample folders only: `python3 dev/protocol_test.py` and `python3 dev/serve.py <library> [inbox]`. Never point the helper at real data while testing.
  只用示例文件夹测试。
- Update `CHANGELOG.md` and the version in `extension/manifest.json`, `helper/Info.plist` and `helperVersion` together.
  同步更新 CHANGELOG 和三处版本号。
