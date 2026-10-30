import Foundation
import ImageIO
import UniformTypeIdentifiers

private let extensionID = "jpencbldoocakpdbgolffgemckpimnph"
private let helperVersion = "1.6.0"
private let fm = FileManager.default
private let args = CommandLine.arguments

// Two folders, both ~/Downloads unless the user sets them in Manager's Settings:
//   library — .manager/index.json (the index, with backups), Manager_Files/ (archived HTML) and .thumbs/ (thumbnails)
//   inbox   — where new HTML files arrive; importing moves them into library/Manager_Files.
// 两个文件夹，未设置时都是 ~/Downloads：资料库（.manager/index.json 索引及备份、Manager_Files/、.thumbs/）和收件文件夹（新 HTML 所在处，收录时移入资料库）。
// Each HTML file's doc-meta is the record of truth; the index is a cache that can be rebuilt from the files.
// 每个 HTML 里的 doc-meta 才是正本；索引只是可以从文件重建的缓存。

/** Real path of an existing folder, or nil. realpath keeps /private, unlike standardizing. / 已存在文件夹的真实路径。 */
private func existingFolder(_ path: String) -> URL? {
    let expanded = (path as NSString).expandingTildeInPath
    guard !expanded.isEmpty, let real = realpath(expanded, nil) else { return nil }
    defer { free(real) }
    let resolved = String(cString: real)
    var isDirectory: ObjCBool = false
    guard fm.fileExists(atPath: resolved, isDirectory: &isDirectory), isDirectory.boolValue else { return nil }
    return URL(fileURLWithPath: resolved, isDirectory: true)
}

// Development and test flags; Chrome never passes them. Never fall back to the real Downloads when one is wrong.
//   --root <folder>     default library (and inbox) instead of ~/Downloads; no settings file is read
//   --inbox <folder>    default inbox
//   --settings <file>   settings file to read and write
// 开发和测试参数，Chrome 不会传。参数无效时直接退出，绝不退回真正的“下载”。
private func folderFlag(_ name: String) -> URL? {
    guard let i = args.firstIndex(of: name) else { return nil }
    guard i + 1 < args.count, let url = existingFolder(args[i + 1]) else {
        fputs("\(name) needs an existing folder\n", stderr)
        exit(2)
    }
    return url
}
private let testRoot = folderFlag("--root")
private let defaultLibrary = testRoot ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Downloads", isDirectory: true).standardizedFileURL
private let defaultInbox = folderFlag("--inbox") ?? defaultLibrary
private let settingsURL: URL? = {
    if let i = args.firstIndex(of: "--settings"), i + 1 < args.count { return URL(fileURLWithPath: args[i + 1]) }
    if testRoot != nil { return nil }
    return URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support/Manager HTML/settings.json")
}()

private var library = defaultLibrary
private var inbox = defaultInbox
private var indexFolder: URL { library.appendingPathComponent(".manager", isDirectory: true) }
private var indexURL: URL { indexFolder.appendingPathComponent("index.json") }
private var backupsFolder: URL { indexFolder.appendingPathComponent("backups", isDirectory: true) }
private var legacyIndexURL: URL { library.appendingPathComponent("Manager.html") }
private let legacyRenamedStem = "Manager-旧索引"
private let indexFormatVersion = 1
private let keptBackups = 10
private var managedRoot: URL { library.appendingPathComponent("Manager_Files", isDirectory: true) }
private var thumbsRoot: URL { library.appendingPathComponent(".thumbs", isDirectory: true) }
private let attachmentFolder = "_附件"

// Compares folders after removing "." and "..". / 去掉 "." 和 ".." 后比较两个文件夹。
private func samePath(_ a: URL, _ b: URL) -> Bool { a.standardizedFileURL.path == b.standardizedFileURL.path }
private func isInboxFolder(_ url: URL) -> Bool { samePath(url, inbox) }
private var sharedFolder: Bool { samePath(library, inbox) }
private let controlledCategories = ["投资与市场", "视频制作与流程", "视觉设计与组件", "健康与生活资料", "工作与管理"]
private let controlledTags: [String: [String]] = [
    "Remotion": ["remotion"], "AVGO": ["avgo", "broadcom", "博通"], "MU": ["micron", "美光", "mu"],
    "NVDA": ["nvidia", "英伟达", "nvda"], "INTC": ["intel", "英特尔", "intc"],
    "PySceneDetect": ["pyscenedetect"], "WhisperX": ["whisperx"],
    "公司研究": ["公司", "公司研究", "company", "业务", "估值", "市值", "盈利", "收入", "股价", "投资逻辑"],
    "组合管理": ["组合", "持仓", "仓位", "portfolio", "position", "配置"],
    "风险控制": ["风险", "回撤", "止损", "杠杆", "risk", "drawdown"],
    "AI算力": ["ai", "人工智能", "gpu", "hbm", "算力", "数据中心", "芯片"],
    "视觉动效": ["视觉", "动效", "组件", "svg", "图层", "卡片", "画布", "编辑器", "png"],
    "字幕包装": ["字幕", "逐词", "姓名条", "lower third"], "视频转场": ["转场", "transition", "wipe"],
    "健康知识": ["健康", "疾病", "治疗", "检测", "症状"],
    "工作流": ["工作流", "流程", "步骤", "workflow", "pipeline"],
    "沟通表达": ["沟通", "表达", "口播", "反馈", "文案"],
    "示例": ["demo", "示例", "演示", "编辑器", "组件家族"],
    "研究": ["研究", "分析", "估值", "机会成本", "拆解", "比较"],
    "复盘": ["复盘", "回顾", "结果"], "教程": ["教程", "怎么用", "操作步骤", "使用说明"],
    "模板": ["模板", "template", "表单"], "知识卡": ["问答", "知识卡", "图鉴"]
]

private enum HostError: Error, LocalizedError {
    case invalidPath, notManaged, missingFile, unsupportedOperation, managerFormat, legacyFormat, newerIndex, indexMissing, indexExists, permission, oversized, emptySelection, invalidMetadata, thumbnailFailure
    case libraryMissing(String), inboxMissing(String), invalidSettings(String)
    var errorDescription: String? {
        switch self {
        case .invalidPath: return "Invalid file path / 文件路径无效"
        case .notManaged: return "This file is not a managed HTML file / 这个文件不在可管理的 HTML 范围内"
        case .missingFile: return "The file no longer exists; scan again / 文件已不存在，请重新扫描"
        case .unsupportedOperation: return "Unsupported operation / 不支持的操作"
        case .managerFormat: return "Cannot safely read or update the Manager index / 无法安全读取或更新 Manager 索引"
        case .legacyFormat: return "The old Manager.html in the library is not an index Manager can read; nothing was changed / 资料库里旧的 Manager.html 不是 Manager 能读取的索引，没有改动任何文件"
        case .newerIndex: return "The index was written by a newer Manager; update Manager / 索引由更新版本的 Manager 写入，请更新 Manager"
        case .indexMissing: return "There is no Manager library in this folder yet / 这个文件夹里还没有 Manager 资料库"
        case .indexExists: return "This folder already has a Manager library / 这个文件夹里已经有 Manager 资料库"
        case .permission: return "No access to the library, the new-files folder or the Trash; check file permissions / 无法访问资料库、收件文件夹或 macOS 废纸篓，请检查文件访问权限"
        case .oversized: return "The index is too large for one Chrome message / 清单数据超过 Chrome 消息限制"
        case .emptySelection: return "No HTML files selected to import / 没有选择可收录的 HTML 文件"
        case .invalidMetadata: return "A category or tag is not in the vocabulary / 分类或标签不在 Manager 受控词表中，请检查后重试"
        case .thumbnailFailure: return "No thumbnail could be made, so nothing was imported; check that the file previews in Finder (Space) and try again / 缩略图没有生成，因此这批文件尚未写入 Manager 清单；请确认文件能在访达中用空格键预览后重试"
        case .libraryMissing(let path): return "Library folder not found / 找不到资料库文件夹：\(path)"
        case .inboxMissing(let path): return "New-files folder not found / 找不到收件文件夹：\(path)"
        case .invalidSettings(let reason): return reason
        }
    }
    /// Stable code the page uses to choose what to show. / 页面据此决定显示哪种说明。
    var code: String {
        switch self {
        case .libraryMissing: return "library_missing"
        case .inboxMissing: return "inbox_missing"
        case .managerFormat, .legacyFormat, .newerIndex: return "index"
        case .indexMissing: return "index_missing"
        case .indexExists: return "index_exists"
        case .permission: return "permission"
        case .invalidSettings: return "settings"
        case .unsupportedOperation: return "unknown_op"
        default: return "error"
        }
    }
}

// ---------- settings / 设置 ----------

private func readSettings() -> [String: String] {
    guard let url = settingsURL, let data = try? Data(contentsOf: url),
          let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
    return object.compactMapValues { $0 as? String }
}

/** Applies the saved folders before each request; a missing folder is an error, never a fallback. / 每个请求前应用已保存的文件夹；找不到就报错，绝不退回默认。 */
private func applySettings() throws {
    let settings = readSettings()
    if let path = settings["library"] {
        guard let url = existingFolder(path) else { throw HostError.libraryMissing(path) }
        library = url
    } else { library = defaultLibrary }
    if let path = settings["inbox"] {
        guard let url = existingFolder(path) else { throw HostError.inboxMissing(path) }
        inbox = url
    } else { inbox = defaultInbox }
}

private func configReply(id: String) throws {
    let settings = readSettings()
    let libraryPath = settings["library"] ?? defaultLibrary.path
    let inboxPath = settings["inbox"] ?? defaultInbox.path
    try send(["id": id, "type": "config", "version": helperVersion,
              "library": libraryPath, "inbox": inboxPath,
              "defaultLibrary": defaultLibrary.path, "defaultInbox": defaultInbox.path,
              "libraryFound": existingFolder(libraryPath) != nil, "inboxFound": existingFolder(inboxPath) != nil,
              "canSave": settingsURL != nil])
}

/** Checks and saves both folders. An empty value means the default. / 检查并保存两个文件夹；留空表示默认。 */
private func setConfig(id: String, libraryPath: String, inboxPath: String) throws {
    guard let file = settingsURL else { throw HostError.invalidSettings("Settings cannot be saved in development mode / 开发模式下不能保存设置") }
    let wantedLibrary = libraryPath.trimmingCharacters(in: .whitespacesAndNewlines)
    let wantedInbox = inboxPath.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let newLibrary = wantedLibrary.isEmpty ? defaultLibrary : existingFolder(wantedLibrary) else {
        throw HostError.invalidSettings("Library folder not found / 找不到资料库文件夹：\(wantedLibrary)")
    }
    guard let newInbox = wantedInbox.isEmpty ? defaultInbox : existingFolder(wantedInbox) else {
        throw HostError.invalidSettings("New-files folder not found / 找不到收件文件夹：\(wantedInbox)")
    }
    // An inbox inside the library would mix new and archived files. / 收件文件夹在资料库里面会把新旧文件混在一起。
    guard samePath(newLibrary, newInbox) || !newInbox.standardizedFileURL.path.hasPrefix(newLibrary.standardizedFileURL.path + "/") else {
        throw HostError.invalidSettings("The new-files folder cannot be inside the library / 收件文件夹不能放在资料库文件夹里面")
    }
    let (previousLibrary, previousInbox) = (library, inbox)
    library = newLibrary
    inbox = newInbox
    // A folder without an index is fine: the page then offers to start a new library there, or the index is
    // rebuilt from Manager_Files. Only an old Manager.html that is not an index is refused: it is probably the wrong folder.
    // 没有索引的文件夹也可以：页面会提示新建资料库，或从 Manager_Files 重建索引。只拒绝不是索引的旧 Manager.html，多半是选错了文件夹。
    if !fm.fileExists(atPath: indexURL.path), fm.fileExists(atPath: legacyIndexURL.path), (try? readLegacyIndex()) == nil {
        (library, inbox) = (previousLibrary, previousInbox)
        throw HostError.invalidSettings("Manager.html in this folder cannot be read or is not an index / 这个文件夹里的 Manager.html 无法读取或格式不对：\(newLibrary.path)")
    }
    var saved: [String: String] = [:]
    if !samePath(newLibrary, defaultLibrary) { saved["library"] = newLibrary.path }
    if !samePath(newInbox, defaultInbox) { saved["inbox"] = newInbox.path }
    do {
        try fm.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: saved, options: [.prettyPrinted, .sortedKeys]).write(to: file, options: .atomic)
    } catch { throw HostError.invalidSettings("Cannot save settings / 无法保存设置：\(error.localizedDescription)") }
    try configReply(id: id)
}

private func readExactly(_ count: Int) -> Data? {
    var result = Data()
    while result.count < count {
        guard let part = try? FileHandle.standardInput.read(upToCount: count - result.count), !part.isEmpty else { return nil }
        result.append(part)
    }
    return result
}

private func send(_ value: [String: Any]) throws {
    let payload = try JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed])
    guard payload.count < 950_000 else { throw HostError.oversized }
    var count = UInt32(payload.count).littleEndian
    let header = withUnsafeBytes(of: &count) { Data($0) }
    try FileHandle.standardOutput.write(contentsOf: header + payload)
}


// ---------- index / 索引 ----------
//
// <library>/.manager/index.json is {"version": 1, "files": [row…]}. Before every write the previous file is copied to
// .manager/backups/ and the newest 10 copies are kept. A missing or damaged index is rebuilt from the doc-meta of the
// HTML in Manager_Files, starting from the newest readable backup so rows without a file of their own (Markdown) come back.
// An index from before 1.6 (Manager.html with `const files = [...]`) is moved in once and renamed Manager-旧索引.html.
// 索引是 <资料库>/.manager/index.json。每次写入前把旧文件复制到 .manager/backups/，只保留最近 10 份。
// 索引丢了或坏了，就从 Manager_Files 里各 HTML 的 doc-meta 重建，并先取最近一份能读的备份，让没有自己文件的行（Markdown）也回来。
// 1.6 之前的索引（含 `const files = [...]` 的 Manager.html）会搬进来一次，然后改名为 Manager-旧索引.html。

/// What happened to the index during this request, so the page can mention it once. / 本次请求中索引发生的事，页面提示一次。
private var indexNotice: [String: Any]?

private func timestamp() -> String {
    let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.timeZone = .current
    formatter.dateFormat = "yyyyMMdd-HHmmss-SSS"
    return formatter.string(from: Date())
}

private func readIndexFile(_ url: URL) throws -> Data {
    do { return try Data(contentsOf: url) } catch {
        if !fm.fileExists(atPath: url.path) { throw HostError.indexMissing }
        if (error as NSError).code == NSFileReadNoPermissionError { throw HostError.permission }
        throw HostError.managerFormat
    }
}

private func decodeIndex(_ data: Data) throws -> [[String: Any]] {
    guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let rows = object["files"] as? [[String: Any]] else { throw HostError.managerFormat }
    if let version = object["version"] as? Int, version > indexFormatVersion { throw HostError.newerIndex }
    return rows
}

/** Rows of an index from before 1.6. / 1.6 之前的索引（Manager.html）里的行。 */
private func readLegacyIndex() throws -> [[String: Any]] {
    let data = try readIndexFile(legacyIndexURL)
    let pattern = #"(?s)const files = (\[.*?\]);\s*const HTML_CONTROLLED"#
    guard let source = String(data: data, encoding: .utf8), let regex = try? NSRegularExpression(pattern: pattern),
          let match = regex.firstMatch(in: source, range: NSRange(source.startIndex..., in: source)),
          let jsonRange = Range(match.range(at: 1), in: source), let json = String(source[jsonRange]).data(using: .utf8),
          let rows = try? JSONSerialization.jsonObject(with: json) as? [[String: Any]] else { throw HostError.legacyFormat }
    return rows
}

/** Backups, newest first. / 备份，最新的在前。 */
private func backupFiles() -> [URL] {
    let urls = (try? fm.contentsOfDirectory(at: backupsFolder, includingPropertiesForKeys: nil)) ?? []
    return urls.filter { $0.lastPathComponent.hasPrefix("index-") && $0.pathExtension == "json" }
        .sorted { $0.lastPathComponent > $1.lastPathComponent }
}

private func newestBackupRows() -> (name: String, rows: [[String: Any]])? {
    for url in backupFiles() {
        if let data = try? Data(contentsOf: url), let rows = try? decodeIndex(data) { return (url.lastPathComponent, rows) }
    }
    return nil
}

/** Backs up the current index, then writes the new one atomically. Returns the rows as written. / 先备份当前索引，再原子写入新索引。 */
@discardableResult
private func writeIndex(_ records: [[String: Any]]) throws -> [[String: Any]] {
    // `href` is the source of truth; `path` is rewritten for the current library so the index follows a moved library.
    // 以 href 为准；写回时按当前资料库重写 path，资料库换位置后索引随之更新。
    let normalized = records.map { row -> [String: Any] in
        guard row["fileType"] as? String == "HTML", let href = row["href"] as? String, href.hasPrefix("Manager_Files/") else { return row }
        var copy = row
        copy["path"] = library.appendingPathComponent(href).path
        return copy
    }
    let data = try JSONSerialization.data(withJSONObject: ["version": indexFormatVersion, "files": normalized],
                                          options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
    do {
        try fm.createDirectory(at: backupsFolder, withIntermediateDirectories: true)
        if fm.fileExists(atPath: indexURL.path) {
            let stamp = timestamp()
            var backup = backupsFolder.appendingPathComponent("index-\(stamp).json")
            var n = 2
            while fm.fileExists(atPath: backup.path) { backup = backupsFolder.appendingPathComponent("index-\(stamp)-\(n).json"); n += 1 }
            try fm.copyItem(at: indexURL, to: backup)
            for old in backupFiles().dropFirst(keptBackups) { try? fm.removeItem(at: old) }
        }
        try data.write(to: indexURL, options: .atomic)
    } catch { throw HostError.permission }
    return normalized
}

/** HTML in Manager_Files, without _附件, hidden files and symbolic links. / Manager_Files 里的 HTML。 */
private func managedHTMLFiles() -> [URL] {
    var urls: [URL] = []
    guard let enumerator = fm.enumerator(at: managedRoot, includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey], options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return [] }
    while let url = enumerator.nextObject() as? URL {
        let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey])
        if values?.isSymbolicLink == true || (values?.isDirectory == true && url.lastPathComponent == attachmentFolder) {
            if values?.isDirectory == true { enumerator.skipDescendants() }
            continue
        }
        if values?.isRegularFile == true && url.pathExtension.lowercased() == "html" { urls.append(url) }
    }
    return urls.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
}

/** True when there is something to rebuild from, so a missing index must never look like an empty library. / 有可重建的内容。 */
private func hasLibraryContent() -> Bool { !managedHTMLFiles().isEmpty || !backupFiles().isEmpty }

private struct Rebuilt {
    var rows: [[String: Any]] = []
    var fromFiles = 0, fromBackup = 0, other = 0, dropped = 0
    var base: String?
    var summary: [String: Any] {
        ["html": fromFiles + fromBackup, "fromFiles": fromFiles, "fromBackup": fromBackup, "markdown": other, "dropped": dropped, "backup": base ?? ""]
    }
}

/**
 * Rows for every HTML in Manager_Files: from its doc-meta, or from the earlier row when the file has none.
 * Starts from `base` (the current index) or else the newest readable backup, which keeps their order and their
 * Markdown rows; rows whose file is gone are left out.
 * 为 Manager_Files 里的每个 HTML 生成一行：有 doc-meta 就用它，没有就用之前的那一行。以 `base`（当前索引）或最近一份能读的备份为底，
 * 保留原来的顺序和 Markdown 行；文件已经不在的行去掉。
 */
private func rebuildRows(base: [[String: Any]]?) -> Rebuilt {
    var result = Rebuilt()
    var earlier = base
    if earlier != nil { result.base = "index" } else if let backup = newestBackupRows() { earlier = backup.rows; result.base = backup.name }
    let files = managedHTMLFiles()
    var byHref: [String: URL] = [:]
    for url in files { byHref[relativePath(url)] = url }
    var seen = Set<String>()
    for row in earlier ?? [] {
        let href = row["href"] as? String ?? ""
        guard !seen.contains(href) else { continue }
        if row["fileType"] as? String != "HTML" {
            seen.insert(href); result.rows.append(row); result.other += 1
        } else if let url = byHref[href] {
            seen.insert(href)
            let record = makeRecord(url)
            if record["metadataManaged"] as? Bool == true { result.rows.append(record); result.fromFiles += 1 }
            else { var kept = row; kept["path"] = url.path; result.rows.append(kept); result.fromBackup += 1 }
        } else if !href.hasPrefix("Manager_Files/"), (try? safeURL(relative: href)) != nil {
            // A row from an older version for a file still in the inbox. / 旧版本留下的、文件仍在收件文件夹的行。
            seen.insert(href); result.rows.append(row); result.fromBackup += 1
        } else {
            result.dropped += 1
        }
    }
    // Every file in Manager_Files got there by being imported, so all of them belong in the index. / Manager_Files 里的文件都是收录进来的。
    for url in files where !seen.contains(relativePath(url)) {
        result.rows.append(makeRecord(url))
        result.fromFiles += 1
    }
    return result
}

/** Renames the old Manager.html so it is not mistaken for the index; never deletes it. / 把旧 Manager.html 改名，绝不删除。 */
@discardableResult
private func retireLegacyIndex() -> String? {
    var target = library.appendingPathComponent("\(legacyRenamedStem).html")
    var n = 2
    while fm.fileExists(atPath: target.path) { target = library.appendingPathComponent("\(legacyRenamedStem) \(n).html"); n += 1 }
    do { try fm.moveItem(at: legacyIndexURL, to: target) } catch { return nil }
    return target.lastPathComponent
}

/**
 * The index rows. Moves an old Manager.html in, and rebuilds a missing or damaged index when the library has
 * documents or backups. Only a library with neither reports index_missing.
 * 读取索引。会搬入旧的 Manager.html；资料库里有资料或备份时，索引丢了或坏了就自动重建。只有两者都没有才报 index_missing。
 */
private func readIndex() throws -> [[String: Any]] {
    if fm.fileExists(atPath: indexURL.path) {
        let data = try readIndexFile(indexURL)
        do { return try decodeIndex(data) } catch HostError.newerIndex { throw HostError.newerIndex } catch {}
        // Damaged: keep it aside for inspection, then rebuild. / 损坏：先另存一份，再重建。
        let aside = indexFolder.appendingPathComponent("index-损坏-\(timestamp()).json")
        do { try fm.moveItem(at: indexURL, to: aside) } catch { throw HostError.permission }
        let rebuilt = rebuildRows(base: nil)
        let rows = try writeIndex(rebuilt.rows)
        indexNotice = rebuilt.summary.merging(["event": "rebuilt", "reason": "damaged", "aside": aside.lastPathComponent]) { $1 }
        return rows
    }
    if fm.fileExists(atPath: legacyIndexURL.path) {
        let legacy = try readLegacyIndex()
        let rows = try writeIndex(legacy)
        let markdown = legacy.filter { $0["fileType"] as? String != "HTML" }.count
        indexNotice = ["event": "migrated", "html": legacy.count - markdown, "markdown": markdown, "renamed": retireLegacyIndex() ?? ""]
        return rows
    }
    guard hasLibraryContent() else { throw HostError.indexMissing }
    let rebuilt = rebuildRows(base: nil)
    let rows = try writeIndex(rebuilt.rows)
    indexNotice = rebuilt.summary.merging(["event": "rebuilt", "reason": "missing"]) { $1 }
    return rows
}

/** Rebuilds the index on request, starting from the current one when it can be read. / 按请求重建索引，当前索引能读时以它为底。 */
private func rebuildIndex(id: String) throws {
    var base: [[String: Any]]?
    var fromLegacy = false
    if fm.fileExists(atPath: indexURL.path) {
        do { base = try decodeIndex(readIndexFile(indexURL)) } catch HostError.newerIndex { throw HostError.newerIndex } catch HostError.permission { throw HostError.permission } catch {}
    } else if let legacy = try? readLegacyIndex() {
        base = legacy
        fromLegacy = true
    }
    let rebuilt = rebuildRows(base: base)
    do { try fm.createDirectory(at: managedRoot, withIntermediateDirectories: true) } catch { throw HostError.permission }
    try writeIndex(rebuilt.rows)
    if fromLegacy { retireLegacyIndex() }
    try send(["id": id, "type": "result", "ok": true, "rebuilt": rebuilt.summary, "index": indexURL.path])
}

/**
 * Turns an href from the page into a file, allowing only "<name>.html" in the inbox and
 * "Manager_Files/…/<name>.html" in the library: no "..", hidden parts, symbolic links or Manager.html.
 * 把页面传来的 href 变成文件：只允许收件文件夹根目录的 HTML 和资料库 Manager_Files 里的 HTML。
 */
private func safeURL(relative: String) throws -> URL {
    guard !relative.isEmpty, !relative.hasPrefix("/"), !relative.contains("\\") else { throw HostError.invalidPath }
    let parts = relative.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
    guard !parts.isEmpty, parts.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." && !$0.hasPrefix(".") }),
          parts.last?.lowercased().hasSuffix(".html") == true, parts.last?.lowercased() != "manager.html" else { throw HostError.invalidPath }
    let isRootFile = parts.count == 1
    let isManagerFile = parts.count >= 2 && parts[0] == "Manager_Files"
    guard isRootFile || isManagerFile else { throw HostError.invalidPath }
    let base = isRootFile ? inbox : library
    var cursor = base
    for part in parts {
        cursor.appendPathComponent(part)
        do { if try cursor.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true { throw HostError.invalidPath } }
        catch let error as HostError { throw error }
        catch { throw HostError.missingFile }
    }
    // Every part was checked above, so the path needs no standardizing (which would also drop /private).
    // 上面已逐段检查，所以不再 standardize（它还会去掉 /private 前缀）。
    guard cursor.path.hasPrefix(base.path + "/"), (try? cursor.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { throw HostError.missingFile }
    return cursor
}

/** The href for a file: "Manager_Files/…" in the library, or the bare name in the inbox. / 文件对应的 href。 */
private func relativePath(_ url: URL) -> String {
    if url.path.hasPrefix(managedRoot.path + "/") { return String(url.path.dropFirst(library.path.count + 1)) }
    return url.lastPathComponent
}
private func cleanHTML(_ text: String) -> String {
    var value = text.replacingOccurrences(of: #"(?is)<(script|style|noscript)[^>]*>.*?</\1>"#, with: " ", options: .regularExpression)
    value = value.replacingOccurrences(of: #"(?s)<[^>]+>"#, with: " ", options: .regularExpression)
    value = value.replacingOccurrences(of: "&nbsp;", with: " ").replacingOccurrences(of: "&amp;", with: "&").replacingOccurrences(of: "&lt;", with: "<").replacingOccurrences(of: "&gt;", with: ">")
    return value.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
}
private func capture(_ pattern: String, in text: String) -> String? {
    guard let regex = try? NSRegularExpression(pattern: pattern), let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)), let range = Range(match.range(at: 1), in: text) else { return nil }
    return String(text[range])
}
private func containsDocMeta(_ html: String) -> Bool {
    guard let regex = try? NSRegularExpression(pattern: #"(?is)<script\b(?=[^>]*\bid=[\"']doc-meta[\"'])"#) else { return false }
    return regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)) != nil
}
private func fileDate(_ url: URL) -> String {
    let date = DateFormatter(); date.locale = Locale(identifier: "en_US_POSIX"); date.dateFormat = "yyyy-MM-dd"
    let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date()
    return date.string(from: modified)
}
private func fileTimestamp(_ url: URL) -> String {
    let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.timeZone = .current
    formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
    let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date()
    return formatter.string(from: modified)
}
private func inferredMetadata(_ url: URL, html: String) -> [String: Any] {
    let plain = cleanHTML(html)
    let title = capture(#"(?is)<title[^>]*>(.*?)</title>"#, in: html).map(cleanHTML) ?? url.deletingPathExtension().lastPathComponent
    let corpus = (title + " " + url.lastPathComponent + " " + plain).lowercased()
    let categoryRules: [(String, [String])] = [
        ("投资与市场", ["投资", "估值", "股票", "公司", "市值", "国债", "treasury", "cagr", "股价", "组合", "持仓", "英伟达", "apple"]),
        ("视频制作与流程", ["remotion", "视频", "口播", "字幕", "剪辑", "b-roll", "whisperx", "pyscenedetect"]),
        ("视觉设计与组件", ["图层", "svg", "组件", "动效", "编辑器", "设计", "海报", "卡片", "png", "demo"]),
        ("健康与生活资料", ["健康", "疾病", "治疗", "检测", "症状", "药物"]),
        ("工作与管理", ["工作流", "管理", "沟通", "团队", "agent", "协作", "项目"])
    ]
    let category = categoryRules.map { key, words in (key, words.filter { corpus.contains($0) }.count) }
        .max { $0.1 < $1.1 }.flatMap { $0.1 > 0 ? $0.0 : nil } ?? "工作与管理"
    var tags = controlledTags.compactMap { tag, words -> (String, Int)? in
        let matches = words.filter { corpus.contains($0) }.count
        return matches > 0 ? (tag, matches) : nil
    }.sorted { $0.1 == $1.1 ? $0.0 < $1.0 : $0.1 > $1.1 }.map(\.0)
    // Keep one tag from each useful dimension when possible; the UI can adjust the suggestions before import.
    if tags.count > 4 { tags = Array(tags.prefix(4)) }
    if tags.count < 2 {
        let fallback = category == "视觉设计与组件" ? ["视觉动效", "示例"] : category == "投资与市场" ? ["公司研究", "研究"] : ["工作流", "教程"]
        for tag in fallback where !tags.contains(tag) && tags.count < 2 { tags.append(tag) }
    }
    var keywords = [url.deletingPathExtension().lastPathComponent, title]
    let asciiTerms = capture(#"(?is)<title[^>]*>(.*?)</title>"#, in: html).map { _ in plain } ?? plain
    if let regex = try? NSRegularExpression(pattern: #"[A-Za-z][A-Za-z0-9.+-]{1,}|\b\d+(?:\.\d+)?%?\b"#) {
        let ns = asciiTerms as NSString
        keywords += regex.matches(in: asciiTerms, range: NSRange(location: 0, length: ns.length)).map { ns.substring(with: $0.range) }
    }
    let domainTerms = ["AI", "SVG", "PNG", "Apple", "苹果", "国债", "机会成本", "估值", "收益率", "净利润", "CAGR", "图层编辑器", "对话气泡", "拖动", "导出", "HTML", "CSS", "JavaScript", "Remotion", "字幕", "转场", "GPU", "HBM", "NVDA", "AVGO", "Micron", "MU"]
    keywords += domainTerms.filter { corpus.localizedCaseInsensitiveContains($0) }
    if let han = try? NSRegularExpression(pattern: #"\p{Han}{2,}"#) {
        let ns = plain as NSString
        keywords += han.matches(in: plain, range: NSRange(location: 0, length: ns.length)).map { ns.substring(with: $0.range) }
    }
    keywords = Array(NSOrderedSet(array: keywords.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })) as? [String] ?? []
    let summaryText = plain.isEmpty ? title : String(plain.prefix(220))
    let summary = summaryText.count < plain.count ? summaryText + "…" : summaryText
    return ["title": title, "created": fileDate(url), "modifiedAt": fileTimestamp(url), "category": category, "tags": tags,
            "keywords": Array(keywords.prefix(30)), "summary": summary]
}
private func metadataFor(_ url: URL, html: String) -> [String: Any] {
    guard let raw = capture(#"(?is)<script\b(?=[^>]*\bid=[\"']doc-meta[\"'])[^>]*>(.*?)</script>"#, in: html),
          let data = raw.data(using: .utf8), let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        return inferredMetadata(url, html: html)
    }
    return object
}
private func writeMetadata(_ url: URL, metadata: [String: Any], htmlOverride: String? = nil) throws {
    guard let data = try? Data(contentsOf: url), var html = htmlOverride ?? String(data: data, encoding: .utf8) else { throw HostError.missingFile }
    let pattern = #"(?is)<script\b(?=[^>]*\bid=[\"']doc-meta[\"'])[^>]*>.*?</script>"#
    let jsonData = try JSONSerialization.data(withJSONObject: metadata, options: [.fragmentsAllowed, .prettyPrinted, .sortedKeys])
    guard let json = String(data: jsonData, encoding: .utf8) else { throw HostError.managerFormat }
    let snippet = "\n<script type=\"application/json\" id=\"doc-meta\">\n\(json)\n</script>\n"
    if let regex = try? NSRegularExpression(pattern: pattern), let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)), let range = Range(match.range, in: html) {
        html.replaceSubrange(range, with: "<script type=\"application/json\" id=\"doc-meta\">\n\(json)\n</script>")
    } else {
        guard let headEnd = html.range(of: #"</head\s*>"#, options: [.regularExpression, .caseInsensitive]) else { throw HostError.managerFormat }
        html.insert(contentsOf: snippet, at: headEnd.lowerBound)
    }
    try Data(html.utf8).write(to: url, options: .atomic)
}
/** Runs a system tool and waits at most `seconds`. / 运行系统工具，最多等待 `seconds` 秒。 */
private func runTool(_ path: String, _ arguments: [String], seconds: Double = 30) -> Bool {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: path)
    process.arguments = arguments
    process.standardInput = FileHandle.nullDevice; process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
    do { try process.run() } catch { return false }
    let deadline = DispatchWorkItem { if process.isRunning { process.terminate() } }
    DispatchQueue.global().asyncAfter(deadline: .now() + seconds, execute: deadline)
    process.waitUntilExit()
    deadline.cancel()
    return process.terminationStatus == 0
}

/**
 * First-screen thumbnail, 400×250 JPEG. Quick Look (built into macOS) renders the page the way Finder
 * previews it: the page's scripts do not run and nothing is loaded from the web.
 * 首屏缩略图（400×250 JPEG）。用 macOS 自带的快速查看渲染，和访达预览一样：页面脚本不运行，也不从网上加载内容。
 */
private func generateThumbnail(for url: URL, relative: String) -> Bool {
    let output = thumbnailURL(relative: relative)
    let work = fm.temporaryDirectory.appendingPathComponent("manager-thumb-\(UUID().uuidString)", isDirectory: true)
    defer { try? fm.removeItem(at: work) }
    do {
        try fm.createDirectory(at: work, withIntermediateDirectories: true)
        try fm.createDirectory(at: thumbsRoot, withIntermediateDirectories: true)
    } catch { return false }
    guard runTool("/usr/bin/qlmanage", ["-t", "-s", "1280", "-o", work.path, url.path]),
          let png = (try? fm.contentsOfDirectory(at: work, includingPropertiesForKeys: nil))?.first(where: { $0.pathExtension.lowercased() == "png" }) else { return false }
    return topThumbnail(from: png, to: output)
}

/** Keeps the top 16:10 of the rendered page and saves it as a 400×250 JPEG. / 保留页面顶部 16:10，存为 400×250 JPEG。 */
private func topThumbnail(from source: URL, to output: URL) -> Bool {
    guard let input = CGImageSourceCreateWithURL(source as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(input, 0, nil) else { return false }
    let width = image.width
    let height = min(image.height, width * 10 / 16)
    guard let top = image.cropping(to: CGRect(x: 0, y: 0, width: width, height: height)),
          let context = CGContext(data: nil, width: 400, height: 250, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return false }
    context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: 400, height: 250))
    context.interpolationQuality = .high
    let drawnHeight = 400.0 * Double(height) / Double(width)
    context.draw(top, in: CGRect(x: 0, y: 250 - drawnHeight, width: 400, height: drawnHeight))
    guard let scaled = context.makeImage(),
          let destination = CGImageDestinationCreateWithURL(output as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else { return false }
    CGImageDestinationAddImage(destination, scaled, [kCGImageDestinationLossyCompressionQuality: 0.7] as CFDictionary)
    return CGImageDestinationFinalize(destination)
}
private func thumbnailURL(relative: String) -> URL {
    let name = relative.replacingOccurrences(of: "/", with: "__").replacingOccurrences(of: #"\.html?$"#, with: ".jpg", options: .regularExpression)
    return thumbsRoot.appendingPathComponent(name)
}
private func managedDestination(for source: URL, reservedNames: inout Set<String>) -> URL {
    guard isInboxFolder(source.deletingLastPathComponent()) else { return source }
    let originalName = source.lastPathComponent
    let ext = source.pathExtension
    let stem = source.deletingPathExtension().lastPathComponent
    var name = originalName
    var suffix = 1
    while reservedNames.contains(name) || fm.fileExists(atPath: managedRoot.appendingPathComponent(name).path) || fm.fileExists(atPath: thumbnailURL(relative: "Manager_Files/\(name)").path) {
        name = "\(stem)_归档副本\(suffix).\(ext)"
        suffix += 1
    }
    reservedNames.insert(name)
    return managedRoot.appendingPathComponent(name)
}

/**
 * Local files (pictures, styles, archives…) that HTML in the inbox links to. When the library is another folder,
 * importing copies them into Manager_Files/_附件 so the library stays complete; links to other HTML are left alone.
 * 收件文件夹中 HTML 引用的本地文件（图片、样式、压缩包等）。资料库在别处时，收录会把它们复制到 Manager_Files/_附件，
 * 让资料库保持完整；指向其他 HTML 的链接保持不变。
 */
private final class AttachmentPlan {
    var names: [String: String] = [:] // source path → name in _附件 / 源路径 → 附件名
    var sources: [String: URL] = [:]
    private var reserved = Set<String>()
    var folder: URL { managedRoot.appendingPathComponent(attachmentFolder, isDirectory: true) }

    func name(for source: URL) -> String {
        if let known = names[source.path] { return known }
        let stem = source.deletingPathExtension().lastPathComponent
        let ext = source.pathExtension
        var name = source.lastPathComponent
        var n = 2
        while reserved.contains(name) || existingDiffers(name, from: source) {
            name = ext.isEmpty ? "\(stem)_\(n)" : "\(stem)_\(n).\(ext)"
            n += 1
        }
        reserved.insert(name)
        names[source.path] = name
        sources[name] = source
        return name
    }

    /// A file of the same name and size is taken as the same attachment. / 同名同大小视为同一附件。
    private func existingDiffers(_ name: String, from source: URL) -> Bool {
        let target = folder.appendingPathComponent(name)
        guard let existing = try? fm.attributesOfItem(atPath: target.path) else { return false }
        let size = (try? fm.attributesOfItem(atPath: source.path))?[.size] as? Int
        return existing[.size] as? Int != size
    }

    var summary: [[String: Any]] {
        sources.map { name, url in ["name": name, "size": (try? fm.attributesOfItem(atPath: url.path))?[.size] as? Int ?? 0] }
            .sorted { ($0["name"] as? String ?? "") < ($1["name"] as? String ?? "") }
    }
}

private func relocatedReference(_ raw: String, movingTargets: [String: String], attachments: AttachmentPlan) -> String {
    let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !value.isEmpty, !value.hasPrefix("#"), !value.hasPrefix("//"), !value.hasPrefix("/"), !value.lowercased().hasPrefix("var("), !value.lowercased().hasPrefix("env(") else { return raw }
    if value.range(of: #"^[A-Za-z][A-Za-z0-9+.-]*:"#, options: .regularExpression) != nil { return raw }
    let end = [value.firstIndex(of: "?"), value.firstIndex(of: "#")].compactMap { $0 }.min() ?? value.endIndex
    let pathPart = String(value[..<end])
    guard !pathPart.isEmpty else { return raw }
    let decoded = pathPart.removingPercentEncoding ?? pathPart
    let resolved = URL(fileURLWithPath: decoded, relativeTo: inbox).standardizedFileURL
    let suffix = String(value[end...])
    if isInboxFolder(resolved.deletingLastPathComponent()), let destination = movingTargets[resolved.lastPathComponent] {
        return destination + suffix
    }
    // Same folder for both: Manager_Files is one level down, so step back up. / 两者是同一文件夹：Manager_Files 在下一级，回到上一级即可。
    if sharedFolder { return "../" + raw }
    guard !["html", "htm"].contains(resolved.pathExtension.lowercased()),
          (try? resolved.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { return raw }
    let name = attachments.name(for: resolved)
    return "\(attachmentFolder)/" + (name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? name) + suffix
}
private func relocatingLocalReferences(in html: String, movingTargets: [String: String], attachments: AttachmentPlan) -> String {
    var output = html
    let attributes = try? NSRegularExpression(pattern: #"(?is)\b(href|src|poster|action|data|background)\s*=\s*(?:([\"'])(.*?)\2|([^\s>]+))"#)
    if let regex = attributes {
        let matches = regex.matches(in: output, range: NSRange(output.startIndex..., in: output))
        for match in matches.reversed() {
            let valueIndex = match.range(at: 3).location == NSNotFound ? 4 : 3
            guard let valueRange = Range(match.range(at: valueIndex), in: output) else { continue }
            let rewritten = relocatedReference(String(output[valueRange]), movingTargets: movingTargets, attachments: attachments)
            output.replaceSubrange(valueRange, with: rewritten)
        }
    }
    let cssURLs = try? NSRegularExpression(pattern: #"(?is)url\(\s*([\"']?)([^\"')]+)\1\s*\)"#)
    if let regex = cssURLs {
        let matches = regex.matches(in: output, range: NSRange(output.startIndex..., in: output))
        for match in matches.reversed() {
            guard let valueRange = Range(match.range(at: 2), in: output) else { continue }
            let rewritten = relocatedReference(String(output[valueRange]), movingTargets: movingTargets, attachments: attachments)
            output.replaceSubrange(valueRange, with: rewritten)
        }
    }
    return output
}
private func makeRecord(_ url: URL) -> [String: Any] {
    let relative = relativePath(url)
    let data = (try? Data(contentsOf: url)) ?? Data()
    let html = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
    let metadata = metadataFor(url, html: html)
    let rawTitle = metadata["title"] as? String ?? capture(#"(?is)<title[^>]*>(.*?)</title>"#, in: html).map(cleanHTML)
    let title = (rawTitle?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? rawTitle! : url.deletingPathExtension().lastPathComponent)
    let rawDescription = metadata["summary"] as? String ?? capture(#"(?is)<meta\s+name=[\"']description[\"']\s+content=[\"'](.*?)[\"'][^>]*>"#, in: html) ?? capture(#"(?is)<meta\s+content=[\"'](.*?)[\"']\s+name=[\"']description[\"'][^>]*>"#, in: html)
    let fallback = cleanHTML(html)
    let description = (rawDescription?.isEmpty == false ? cleanHTML(rawDescription!) : String(fallback.prefix(240)))
    var keywords = metadata["keywords"] as? [String] ?? []
    keywords += [url.deletingPathExtension().lastPathComponent, title]
    if let metaKeywords = capture(#"(?is)<meta\s+name=[\"']keywords[\"']\s+content=[\"'](.*?)[\"'][^>]*>"#, in: html) { keywords += metaKeywords.split(whereSeparator: { ",，;；".contains($0) }).map(String.init) }
    keywords = Array(NSOrderedSet(array: keywords.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })) as? [String] ?? []
    let date = DateFormatter(); date.locale = Locale(identifier: "en_US_POSIX"); date.dateFormat = "yyyy-MM-dd"
    let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date()
    return [
        "title": title, "created": metadata["created"] as? String ?? date.string(from: modified),
        "modifiedAt": metadata["modifiedAt"] as? String ?? fileTimestamp(url),
        "category": metadata["category"] as? String ?? "工作与管理",
        "tags": metadata["tags"] as? [String] ?? [], "keywords": Array(keywords.prefix(30)),
        "description": description, "fileType": "HTML", "filename": url.lastPathComponent,
        "path": url.path, "href": relative, "metadataManaged": containsDocMeta(html)
    ]
}


private func list(id: String) throws {
    let records = try readIndex()
    let items: [[String: Any]] = records.compactMap { row in
        guard row["fileType"] as? String == "HTML", let href = row["href"] as? String, let candidate = try? safeURL(relative: href) else { return nil }
        var output = row
        output["path"] = candidate.path
        output["modifiedAt"] = row["modifiedAt"] as? String ?? fileTimestamp(candidate)
        output["rootPath"] = library.path
        return output
    }
    var reply: [String: Any] = ["id": id, "type": "items", "items": items]
    if let notice = indexNotice { reply["notice"] = notice }
    try send(reply)
}

private func discoverFiles(existing: [[String: Any]]) throws -> [[String: Any]] {
    let known = Set(existing.compactMap { $0["href"] as? String })
    var urls: [URL] = []
    let rootFiles = (try? fm.contentsOfDirectory(at: inbox, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey], options: [.skipsHiddenFiles])) ?? []
    // The old index renamed by 1.6 sits in the library root, which is also the inbox by default. / 改名后的旧索引在资料库根目录，默认也是收件文件夹。
    for url in rootFiles where url.pathExtension.lowercased() == "html" && url.lastPathComponent.lowercased() != "manager.html"
        && !(sharedFolder && url.lastPathComponent.hasPrefix(legacyRenamedStem)) {
        if (try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]).isRegularFile) == true,
           (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true { urls.append(url) }
    }
    urls += managedHTMLFiles()
    return urls.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        .filter { !known.contains(relativePath($0)) }
        .map { url in
            var record = makeRecord(url)
            // Files that importing would copy along, so the page can list them first. / 收录时会一起复制的文件，先在页面上列出。
            if !sharedFolder, isInboxFolder(url.deletingLastPathComponent()), let html = try? String(contentsOf: url, encoding: .utf8) {
                let plan = AttachmentPlan()
                _ = relocatingLocalReferences(in: html, movingTargets: [:], attachments: plan)
                record["attachments"] = plan.summary
            }
            return record
        }
}

private func discover(id: String) throws {
    let records = try readIndex()
    try send(["id": id, "type": "candidates", "items": discoverFiles(existing: records), "inbox": inbox.path, "library": library.path])
}

private func importFiles(id: String, paths: [String], metadataByPath: [String: [String: Any]]) throws {
    guard !paths.isEmpty else { throw HostError.emptySelection }
    let records = try readIndex()
    let candidates = try discoverFiles(existing: records)
    let allowed = Set(candidates.compactMap { $0["href"] as? String })
    let selected = Array(Set(paths)).filter { allowed.contains($0) }
    guard !selected.isEmpty else { throw HostError.emptySelection }
    var reservedNames = Set<String>()
    var targetBySource: [String: URL] = [:]
    for relative in selected {
        guard let sourceURL = try? safeURL(relative: relative) else { continue }
        targetBySource[relative] = managedDestination(for: sourceURL, reservedNames: &reservedNames)
    }
    var movingTargets: [String: String] = [:]
    for (source, target) in targetBySource where source != relativePath(target) {
        movingTargets[URL(fileURLWithPath: source).lastPathComponent] = target.lastPathComponent
    }
    let attachments = AttachmentPlan()
    var additions: [[String: Any]] = []
    var thumbnailCount = 0
    var originalHTML: [URL: Data] = [:]
    var movedFiles: [(source: URL, destination: URL)] = []
    var copiedAttachments: [URL] = []
    var thumbnailBackups: [URL: Data] = [:]
    var thumbnailsInitiallyAbsent = Set<URL>()
    do {
        for relative in selected {
            guard let url = try? safeURL(relative: relative), let destination = targetBySource[relative], let data = try? Data(contentsOf: url), let html = String(data: data, encoding: .utf8) else { continue }
            originalHTML[url] = data
            var metadata = metadataFor(url, html: html)
            if metadata["modifiedAt"] as? String == nil { metadata["modifiedAt"] = fileTimestamp(url) }
            let submitted = metadataByPath[relative] ?? [:]
            if let category = submitted["category"] as? String, controlledCategories.contains(category) { metadata["category"] = category }
            guard controlledCategories.contains(metadata["category"] as? String ?? "") else { throw HostError.invalidMetadata }
            let allowedTags = Set(controlledTags.keys)
            let submittedTags = submitted["tags"] as? [String]
            let validTags = (submittedTags ?? metadata["tags"] as? [String] ?? []).filter { allowedTags.contains($0) }
            guard (2...4).contains(validTags.count) else { throw HostError.invalidMetadata }
            metadata["tags"] = validTags
            let destinationRelative = relativePath(destination)
            let preparedHTML = destination == url ? html : relocatingLocalReferences(in: html, movingTargets: movingTargets, attachments: attachments)
            try writeMetadata(url, metadata: metadata, htmlOverride: preparedHTML)
            let thumb = thumbnailURL(relative: destinationRelative)
            if !thumbnailBackups.keys.contains(thumb) && !thumbnailsInitiallyAbsent.contains(thumb) {
                if let existing = try? Data(contentsOf: thumb) { thumbnailBackups[thumb] = existing }
                else { thumbnailsInitiallyAbsent.insert(thumb) }
            }
            // Linked files go in first, so the thumbnail and the page find them. / 先放好附件，缩略图和页面才能找到它们。
            for (name, sourceURL) in attachments.sources {
                let target = attachments.folder.appendingPathComponent(name)
                if fm.fileExists(atPath: target.path) { continue }
                try fm.createDirectory(at: attachments.folder, withIntermediateDirectories: true)
                try fm.copyItem(at: sourceURL, to: target)
                copiedAttachments.append(target)
            }
            if destination != url {
                try fm.createDirectory(at: managedRoot, withIntermediateDirectories: true)
                // moveItem copies and then deletes when the library is on another disk. / 资料库在另一块磁盘时，moveItem 会先复制再删除。
                try fm.moveItem(at: url, to: destination)
                movedFiles.append((url, destination))
            }
            // Rendered in its new place, so its rewritten links resolve. / 在新位置渲染，改写后的链接才能找到文件。
            guard generateThumbnail(for: destination, relative: destinationRelative) else { throw HostError.thumbnailFailure }
            thumbnailCount += 1
            additions.append(makeRecord(destination))
        }
        guard !additions.isEmpty else { throw HostError.missingFile }
        try writeIndex(records + additions)
    } catch {
        for move in movedFiles.reversed() { try? fm.moveItem(at: move.destination, to: move.source) }
        for (url, data) in originalHTML { try? data.write(to: url, options: .atomic) }
        for url in copiedAttachments { try? fm.removeItem(at: url) }
        for (url, data) in thumbnailBackups { try? data.write(to: url, options: .atomic) }
        for url in thumbnailsInitiallyAbsent { try? fm.removeItem(at: url) }
        throw error
    }
    try send(["id": id, "type": "result", "ok": true, "imported": additions.count, "thumbnails": thumbnailCount, "thumbnailFailures": 0, "attachments": copiedAttachments.count])
}

private func deleteHTML(id: String, relative: String) throws {
    let records = try readIndex()
    guard records.contains(where: { ($0["href"] as? String) == relative && $0["fileType"] as? String == "HTML" }),
          let candidate = try? safeURL(relative: relative) else { throw HostError.notManaged }
    do { var trashedURL: NSURL?; try fm.trashItem(at: candidate, resultingItemURL: &trashedURL) } catch { throw HostError.permission }
    let updated = records.filter { ($0["href"] as? String) != relative }
    try writeIndex(updated)
    try send(["id": id, "type": "result", "ok": true, "deleted": relative, "destination": "废纸篓", "remaining": updated.count])
}

/** Starts a library: .manager/index.json and Manager_Files. Never empties a library that has documents. / 新建资料库，绝不清空已有资料。 */
private func createIndex(id: String) throws {
    guard !fm.fileExists(atPath: indexURL.path), !fm.fileExists(atPath: legacyIndexURL.path) else { throw HostError.indexExists }
    // Documents already in Manager_Files are indexed, not left waiting for import. / Manager_Files 里已有的资料直接进索引，不会变成待收录。
    let rows = hasLibraryContent() ? rebuildRows(base: nil).rows : []
    do { try fm.createDirectory(at: managedRoot, withIntermediateDirectories: true) } catch { throw HostError.permission }
    try writeIndex(rows)
    try send(["id": id, "type": "result", "ok": true, "created": indexURL.path, "rows": rows.count])
}

private func handle(_ request: [String: Any]) {
    let id = request["id"] as? String ?? ""
    indexNotice = nil
    do {
        switch request["op"] as? String {
        case "config": try configReply(id: id)
        case "setConfig":
            try setConfig(id: id, libraryPath: request["library"] as? String ?? "", inboxPath: request["inbox"] as? String ?? "")
        case "createIndex": try applySettings(); try createIndex(id: id)
        case "rebuildIndex": try applySettings(); try rebuildIndex(id: id)
        case "list": try applySettings(); try list(id: id)
        case "discover": try applySettings(); try discover(id: id)
        case "import":
            try applySettings()
            let raw = request["metadata"] as? [String: Any] ?? [:]
            let metadata = raw.compactMapValues { $0 as? [String: Any] }
            try importFiles(id: id, paths: request["paths"] as? [String] ?? [], metadataByPath: metadata)
        case "delete":
            try applySettings()
            guard let path = request["path"] as? String else { throw HostError.invalidPath }
            try deleteHTML(id: id, relative: path)
        default: throw HostError.unsupportedOperation
        }
    } catch let error as HostError {
        try? send(["id": id, "type": "error", "error": error.localizedDescription, "code": error.code])
    } catch {
        try? send(["id": id, "type": "error", "error": error.localizedDescription, "code": "error"])
    }
}

// `--selftest` checks the setup without Chrome (see selftest.sh). / `--selftest` 不经过 Chrome 检查设置（见 selftest.sh）。
if args.contains("--selftest") {
    print("Manager Helper \(helperVersion)")
    do {
        try applySettings()
        print("Library / 资料库: \(library.path)")
        print("New files / 收件文件夹: \(inbox.path)")
        // Read only: an old or missing index is described here and moved in or rebuilt when the page opens.
        // 只读：旧索引或缺失的索引在这里只做说明，打开管理页时才搬入或重建。
        let records: [[String: Any]]
        print("Index / 索引: \(indexURL.path)")
        if fm.fileExists(atPath: indexURL.path) {
            do { records = try decodeIndex(readIndexFile(indexURL)) } catch {
                print("Problem / 问题: the index is damaged; it will be rebuilt when you open Manager / 索引已损坏，打开 Manager 时会自动重建")
                records = newestBackupRows()?.rows ?? []
            }
        } else if fm.fileExists(atPath: legacyIndexURL.path) {
            records = try readLegacyIndex()
            print("Old Manager.html found; it will be moved into .manager/index.json when you open Manager / 发现旧的 Manager.html，打开 Manager 时会搬进 .manager/index.json")
        } else if hasLibraryContent() {
            print("No index yet; it will be rebuilt from Manager_Files when you open Manager / 还没有索引，打开 Manager 时会从 Manager_Files 重建")
            records = rebuildRows(base: nil).rows
        } else { throw HostError.indexMissing }
        print("Backups / 备份: \(backupFiles().count)")
        let html = records.filter { $0["fileType"] as? String == "HTML" }
        let found = html.filter { ($0["href"] as? String).flatMap { try? safeURL(relative: $0) } != nil }
        print("Indexed HTML found / 已收录且找得到的 HTML: \(found.count) / \(html.count)")
        print("Waiting to import / 待收录: \(try discoverFiles(existing: records).count)")
    } catch let error as HostError {
        print("Problem / 问题: \(error.localizedDescription) [\(error.code)]")
    } catch {
        print("Problem / 问题: \(error.localizedDescription)")
    }
    print("Quick Look thumbnails / 快速查看缩略图: \(fm.isExecutableFile(atPath: "/usr/bin/qlmanage") ? "OK" : "missing / 缺失")")
    exit(0)
}

guard args.dropFirst().contains(where: { $0 == "chrome-extension://\(extensionID)" || $0 == "chrome-extension://\(extensionID)/" }) else {
    fputs("Rejected caller origin\n", stderr); exit(2)
}
while let header = readExactly(4) {
    let length = header.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self).littleEndian }
    guard length > 0, length <= 2 * 1024 * 1024, let body = readExactly(Int(length)) else { break }
    do { if let request = try JSONSerialization.jsonObject(with: body) as? [String: Any] { handle(request) } }
    catch { try? send(["id": "", "type": "error", "error": "Cannot read the request / 无法解析请求", "code": "error"]) }
}
