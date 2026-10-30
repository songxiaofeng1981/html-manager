#!/usr/bin/env python3
"""Talk to the helper the way Chrome does and check the answers / 像 Chrome 一样和助手通信并检查结果.

Usage / 用法:
    bash helper/build.sh
    python3 dev/protocol_test.py            # makes its own sample folders / 自动生成示例文件夹

Runs twice: library and inbox in one folder (the default, ~/Downloads), then in separate folders on two
disks (library in the system temp folder, inbox in dev/.tmp next to this repository). Never touches your
Downloads or your saved settings. "Import" makes thumbnails with macOS Quick Look, and
each run moves one sample file to the Trash. Then checks the index: moving in an old Manager.html, backups,
and rebuilding a missing or damaged index from the files.
运行两遍：资料库和收件文件夹在同一处（默认的 ~/Downloads 情形），以及分在两块磁盘上（资料库在系统临时目录，
收件文件夹在本仓库的 dev/.tmp）。不碰真正的“下载”和已保存的设置。“收录”会用 macOS 快速查看生成缩略图；
每遍会把一个示例文件移到废纸篓。然后检查索引：搬入旧的 Manager.html、备份、索引丢失或损坏后从文件重建。
"""
import glob
import json
import os
import shutil
import struct
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
BIN = os.path.join(HERE, "..", "helper", "build", "ManagerHelper.app", "Contents", "MacOS", "manager-host")
ORIGIN = "chrome-extension://jpencbldoocakpdbgolffgemckpimnph/"
sys.path.insert(0, HERE)
import make_samples  # noqa: E402

LOOSE = ["Broadcom网络芯片.html", "字幕动效草稿.html", "字幕动效草稿_2.html"]


class Helper:
    def __init__(self, *flags):
        self.p = subprocess.Popen([BIN, ORIGIN, *flags], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        self.n = 0

    def ask(self, op, **kw):
        self.n += 1
        body = json.dumps({"id": f"t{self.n}", "op": op, **kw}).encode()
        self.p.stdin.write(struct.pack("<I", len(body)) + body)
        self.p.stdin.flush()
        size = struct.unpack("<I", self.p.stdout.read(4))[0]
        msg = json.loads(self.p.stdout.read(size))
        assert msg["id"] == f"t{self.n}", msg
        return msg

    def close(self):
        self.p.stdin.close()
        self.p.wait(timeout=10)


failed = False


def check(label, ok, detail=""):
    global failed
    print(("PASS  " if ok else "FAIL  ") + label + (f"  ({detail})" if detail and not ok else ""))
    failed |= not ok


def index_path(library):
    return os.path.join(library, ".manager", "index.json")


def index_rows(library):
    return json.load(open(index_path(library), encoding="utf-8"))["files"]


def backups(library):
    return sorted(glob.glob(os.path.join(library, ".manager", "backups", "index-*.json")))


def run(library, inbox, settings):
    split = library != inbox
    flags = ["--root", library] + (["--inbox", inbox] if split else []) + ["--settings", settings]
    h = Helper(*flags)
    tag = "[split] " if split else "[shared] "

    cfg = h.ask("config")
    check(tag + "config reports the folders / 返回文件夹设置", cfg.get("library") == library and cfg.get("inbox") == inbox and cfg.get("canSave") is True, cfg)

    listed = h.ask("list")
    items = listed.get("items", [])
    check(tag + "list returns indexed HTML / 列出已收录 HTML", listed["type"] == "items" and len(items) == len(make_samples.DOCS), f"{len(items)} items")
    check(tag + "list leaves out Markdown rows / 不返回 Markdown", all(i["fileType"] == "HTML" for i in items))
    check(tag + "list paths point into the library / 路径指向资料库", all(i["path"].startswith(library + "/Manager_Files/") and i.get("rootPath") == library for i in items))

    found = h.ask("discover").get("items", [])
    names = sorted(i["filename"] for i in found)
    check(tag + "discover finds new HTML only / 只发现待收录 HTML", names == sorted(LOOSE), names)
    check(tag + "discover suggests 2–4 tags / 建议 2–4 个标签", all(2 <= len(i["tags"]) <= 4 for i in found))
    broadcom = next((i for i in found if i["filename"] == LOOSE[0]), {})
    if split:
        check(tag + "discover lists files to copy along / 列出要一起复制的附件",
              sorted(a["name"] for a in broadcom.get("attachments", [])) == ["AVGO chart.png", "资料包.zip"], broadcom.get("attachments"))
    else:
        check(tag + "no attachments when the folder is shared / 同一文件夹时不复制附件", "attachments" not in broadcom)

    bad = h.ask("import", paths=[LOOSE[0]], metadata={LOOSE[0]: {"category": "投资与市场", "tags": ["不存在"]}})
    check(tag + "import rejects tags outside the vocabulary / 拒绝词表外标签", bad["type"] == "error")
    check(tag + "rejected import leaves the file in place / 失败时文件不动", os.path.exists(os.path.join(inbox, LOOSE[0])))

    for op, extra in [("delete", {"path": "../etc/passwd.html"}), ("delete", {"path": "Manager.html"}),
                      ("delete", {"path": "/tmp/x.html"}), ("delete", {"path": "link.html"}), ("nope", {})]:
        r = h.ask(op, **extra)
        check(tag + f"refuses {op} {extra.get('path', '')} / 拒绝越界请求", r["type"] == "error")
    check(tag + "unknown operations say so / 未知操作有错误码", h.ask("nope").get("code") == "unknown_op")

    ok = h.ask("import", paths=[LOOSE[0]], metadata={LOOSE[0]: {"category": "投资与市场", "tags": ["AVGO", "公司研究", "研究"]}})
    check(tag + "import succeeds / 收录成功", ok.get("ok") is True and ok.get("imported") == 1, ok)
    moved = os.path.join(library, "Manager_Files", LOOSE[0])
    check(tag + "import moves the file into the library / 归档到资料库", os.path.exists(moved) and not os.path.exists(os.path.join(inbox, LOOSE[0])))
    html = open(moved, encoding="utf-8").read()
    check(tag + "import writes doc-meta / 写入 doc-meta", 'id="doc-meta"' in html)
    if split:
        files = os.path.join(library, "Manager_Files", "_附件")
        check(tag + "import copies linked files / 复制附件", os.path.exists(os.path.join(files, "AVGO chart.png")) and os.path.exists(os.path.join(files, "资料包.zip")))
        check(tag + "links point to the copies / 链接指向附件副本", 'src="_附件/AVGO%20chart.png"' in html and "_附件/%E8%B5%84%E6%96%99%E5%8C%85.zip?v=1" in html, html[-300:])
        check(tag + "originals stay in the inbox / 原文件留在收件文件夹", os.path.exists(os.path.join(inbox, "资料包.zip")))
        check(tag + "attachments are not offered for import / 附件夹不会被当作待收录", all("_附件" not in i["href"] for i in h.ask("discover").get("items", [])))
    else:
        check(tag + "links step back to the shared folder / 链接回到上一级", 'src="../AVGO%20chart.png"' in html)
    check(tag + "import makes a thumbnail in the library / 缩略图在资料库", os.path.exists(os.path.join(library, ".thumbs", f"Manager_Files__{LOOSE[0][:-5]}.jpg")))
    rows = index_rows(library)
    check(tag + "import updates the index / 更新索引", any(r.get("href") == f"Manager_Files/{LOOSE[0]}" for r in rows))
    check(tag + "writing the index fixes old paths / 写回索引时修正旧路径",
          all(r["path"].startswith(library + "/") for r in rows if r.get("fileType") == "HTML"), [r["path"] for r in rows][:2])
    check(tag + "index keeps the Markdown row / 索引保留 Markdown 行", any(r.get("fileType") == "MD" for r in rows))
    check(tag + "writing the index keeps a backup / 写索引前留备份", len(backups(library)) == 1 and len(json.load(open(backups(library)[0]))["files"]) == len(rows) - 1)
    check(tag + ".manager is never offered for import / .manager 不会被当作待收录", all(".manager" not in i["href"] for i in h.ask("discover").get("items", [])))

    gone = h.ask("delete", path="Manager_Files/口播反馈记录.html")
    check(tag + "delete moves to Trash / 删除移到废纸篓", gone.get("ok") is True and not os.path.exists(os.path.join(library, "Manager_Files", "口播反馈记录.html")), gone)
    check(tag + "delete updates the index / 删除后更新索引", not any(r.get("href") == "Manager_Files/口播反馈记录.html" for r in index_rows(library)))
    h.close()


def settings_tests(base):
    """Saving folders, checking them, and a library that disappears. / 保存和检查文件夹，以及资料库消失的情形。"""
    library, other, inbox = (os.path.join(base, n) for n in ("lib", "other", "inbox"))
    make_samples.main(library)
    os.makedirs(other)
    os.makedirs(inbox)
    library, other, inbox = (os.path.realpath(p) for p in (library, other, inbox))
    settings = os.path.join(base, "conf", "settings.json")
    h = Helper("--root", other, "--settings", settings)
    tag = "[settings] "
    check(tag + "a missing folder is refused / 拒绝不存在的文件夹", h.ask("setConfig", library=os.path.join(base, "nope"), inbox="").get("code") == "settings")
    nested = os.path.join(library, "新下载")
    os.makedirs(nested)
    check(tag + "an inbox inside the library is refused / 拒绝放在资料库里的收件文件夹", h.ask("setConfig", library=library, inbox=nested).get("code") == "settings")
    check(tag + "nothing saved after refusals / 被拒绝时不保存", not os.path.exists(settings))
    saved = h.ask("setConfig", library=library, inbox=inbox)
    check(tag + "valid folders are saved / 保存有效的文件夹", saved.get("type") == "config" and json.load(open(settings)) == {"library": library, "inbox": inbox}, saved)
    check(tag + "list then reads the saved library / 之后从新资料库读取", len(h.ask("list").get("items", [])) == len(make_samples.DOCS))
    empty = os.path.realpath(os.path.join(base, "new-library"))
    os.makedirs(empty)
    check(tag + "an empty folder can become the library / 空文件夹可以设为资料库", h.ask("setConfig", library=empty, inbox=inbox).get("type") == "config")
    check(tag + "it reports a missing index / 报告还没有索引", h.ask("list").get("code") == "index_missing")
    made = h.ask("createIndex")
    check(tag + "createIndex starts a new library / 新建资料库", made.get("ok") is True and os.path.isdir(os.path.join(empty, "Manager_Files"))
          and index_rows(empty) == [] and not os.path.exists(os.path.join(empty, "Manager.html")), made)
    check(tag + "the new library lists nothing yet / 新资料库是空的", h.ask("list").get("items") == [])
    check(tag + "createIndex never overwrites / 不会覆盖已有索引", h.ask("createIndex").get("code") == "index_exists")
    stray = os.path.realpath(os.path.join(base, "stray"))
    os.makedirs(stray)
    with open(os.path.join(stray, "Manager.html"), "w") as f:
        f.write("not an index")
    check(tag + "a folder whose Manager.html is not an index is refused / 拒绝 Manager.html 不是索引的文件夹",
          h.ask("setConfig", library=stray, inbox="").get("code") == "settings")
    h.ask("setConfig", library=library, inbox=inbox)
    os.rename(library, library + "-unplugged")
    missing = h.ask("list")
    check(tag + "a missing library is reported, not replaced / 资料库不见时报错而不是改用默认", missing.get("code") == "library_missing", missing)
    check(tag + "config still answers / 设置仍可读取", h.ask("config").get("libraryFound") is False)
    os.rename(library + "-unplugged", library)
    shutil.copytree(os.path.join(library, ".manager"), os.path.join(other, ".manager"))  # the default folder needs an index too / 默认文件夹也要有索引
    back = h.ask("setConfig", library="", inbox="")
    check(tag + "empty values go back to the defaults / 留空恢复默认", back.get("library") == other and json.load(open(settings)) == {})
    h.close()
    nosave = Helper("--root", other).ask("setConfig", library=library, inbox="")
    check(tag + "without --settings nothing can be saved / 没有设置文件时不能保存", nosave.get("code") == "settings")


def index_tests(base):
    """The index in .manager: moving in, backups, rebuilding. / .manager 里的索引：搬入、备份、重建。"""
    tag = "[index] "
    os.makedirs(base, exist_ok=True)
    lib = os.path.join(os.path.realpath(base), "lib")
    make_samples.main(lib, legacy=True)
    legacy_text = open(os.path.join(lib, "Manager.html"), encoding="utf-8").read()
    start = legacy_text.index("const files = ") + len("const files = ")
    legacy_rows = json.loads(legacy_text[start:legacy_text.index(";\nconst HTML_CONTROLLED")])
    settings = os.path.join(base, "s.json")
    h = Helper("--root", lib, "--settings", settings)

    # Moving in the index from before 1.6 / 搬入 1.6 之前的索引
    first = h.ask("list")
    notice = first.get("notice", {})
    check(tag + "an old Manager.html is moved in / 搬入旧的 Manager.html", notice.get("event") == "migrated" and len(first.get("items", [])) == len(make_samples.DOCS), notice)
    rows = index_rows(lib)
    check(tag + "every row comes along, Markdown too / 所有行（含 Markdown）都搬过来",
          [r["href"] for r in rows] == [r["href"] for r in legacy_rows] and notice.get("markdown") == 1 and notice.get("html") == len(make_samples.DOCS))
    check(tag + "rows are copied unchanged / 行内容原样保留", all({k: v for k, v in a.items() if k != "path"} == {k: v for k, v in b.items() if k != "path"} for a, b in zip(rows, legacy_rows)))
    check(tag + "the old file is renamed, not deleted / 旧文件改名而不是删除",
          not os.path.exists(os.path.join(lib, "Manager.html")) and open(os.path.join(lib, "Manager-旧索引.html"), encoding="utf-8").read() == legacy_text)
    check(tag + "the next list says nothing / 之后不再提示", "notice" not in h.ask("list"))
    names = sorted(i["filename"] for i in h.ask("discover").get("items", []))
    check(tag + "the renamed old index and .manager are not offered / 改名的旧索引和 .manager 不是待收录", names == sorted(LOOSE), names)

    # Backups / 备份
    for _ in range(12):
        r = h.ask("rebuildIndex")
    check(tag + "rebuildIndex reports what it found / 手动重建报告结果",
          r.get("ok") is True and r["rebuilt"]["html"] == len(make_samples.DOCS) and r["rebuilt"]["markdown"] == 1 and r["rebuilt"]["dropped"] == 0, r)
    check(tag + "only the newest 10 backups are kept / 只保留最近 10 份备份", len(backups(lib)) == 10, len(backups(lib)))
    check(tag + "the newest backup is the previous index / 最新备份就是上一版索引", json.load(open(backups(lib)[-1]))["files"] == index_rows(lib))

    # A damaged index / 索引损坏
    with open(index_path(lib), "w") as f:
        f.write('{"version": 1, "files": [')
    damaged = h.ask("list")
    notice = damaged.get("notice", {})
    check(tag + "a damaged index is rebuilt / 索引损坏时自动重建",
          notice.get("event") == "rebuilt" and notice.get("reason") == "damaged" and len(damaged.get("items", [])) == len(make_samples.DOCS), notice)
    check(tag + "the damaged file is kept aside / 损坏的文件另存保留", len(glob.glob(os.path.join(lib, ".manager", "index-损坏-*.json"))) == 1)
    check(tag + "the Markdown row comes back from a backup / Markdown 行从备份恢复", any(r.get("fileType") == "MD" for r in index_rows(lib)))

    # A missing index, with backups / 索引丢失，有备份
    os.remove(index_path(lib))
    missing = h.ask("list")
    notice = missing.get("notice", {})
    check(tag + "a missing index is rebuilt, never an empty library / 索引丢失时自动重建，而不是新建空资料库",
          notice.get("event") == "rebuilt" and notice.get("reason") == "missing" and len(missing.get("items", [])) == len(make_samples.DOCS), missing.get("code") or notice)
    rows = index_rows(lib)
    check(tag + "the Markdown row comes back again / Markdown 行再次恢复", any(r.get("fileType") == "MD" for r in rows))
    plain = next(r for r in rows if r["filename"] == "口播反馈记录.html")
    doc = next(d for d in make_samples.DOCS if d[0] == "口播反馈记录.html")
    check(tag + "a file without doc-meta keeps its row from the backup / 没有 doc-meta 的文件沿用备份里的行",
          plain["description"] == doc[6] and plain["metadataManaged"] is False and notice.get("fromBackup") == 1, plain)
    nvda = next(r for r in rows if r["filename"] == make_samples.DOCS[0][0])
    check(tag + "other rows come from doc-meta / 其他行来自 doc-meta", nvda["title"] == make_samples.DOCS[0][1] and nvda["metadataManaged"] is True)

    # A missing index and no backups: rebuilt from the files alone / 索引和备份都没了：只从文件重建
    shutil.rmtree(os.path.join(lib, ".manager"))
    bare = h.ask("list")
    check(tag + "without backups every file in Manager_Files is still indexed / 没有备份时 Manager_Files 里的文件仍全部进索引",
          len(bare.get("items", [])) == len(make_samples.DOCS) and bare.get("notice", {}).get("fromBackup") == 0, bare.get("notice"))
    check(tag + "nothing is waiting to import afterwards / 之后没有误报待收录", sorted(i["filename"] for i in h.ask("discover").get("items", [])) == sorted(LOOSE))

    # A gone file is dropped from a rebuild / 文件已不在的行在重建时去掉
    os.remove(os.path.join(lib, "Manager_Files", "体检指标速查.html"))
    r = h.ask("rebuildIndex")
    check(tag + "rows for missing files are dropped / 去掉文件已不在的行", r.get("rebuilt", {}).get("dropped") == 1 and len(index_rows(lib)) == len(make_samples.DOCS) - 1, r)

    # Written by a newer Manager / 更新版本写入的索引
    newer = json.dumps({"version": 99, "files": []})
    with open(index_path(lib), "w") as f:
        f.write(newer)
    check(tag + "a newer index is refused and left alone / 拒绝并保留新版本的索引",
          h.ask("list").get("code") == "index" and open(index_path(lib)).read() == newer and h.ask("rebuildIndex").get("code") == "index")
    h.close()

    # An old Manager.html that is not an index / 不是索引的旧 Manager.html
    odd = os.path.join(os.path.realpath(base), "odd")
    make_samples.main(odd, legacy=True)
    with open(os.path.join(odd, "Manager.html"), "w") as f:
        f.write("not an index")
    h = Helper("--root", odd, "--settings", settings)
    check(tag + "an unreadable Manager.html is reported, not changed / 读不了的 Manager.html 报错且不改动",
          h.ask("list").get("code") == "index" and open(os.path.join(odd, "Manager.html")).read() == "not an index")
    r = h.ask("rebuildIndex")
    check(tag + "the page can rebuild from the files instead / 可改为从文件重建",
          r.get("ok") is True and len(index_rows(odd)) == len(make_samples.DOCS) and open(os.path.join(odd, "Manager.html")).read() == "not an index", r)
    h.close()

    # Create Library where documents already are / 已有资料的文件夹里新建资料库
    filled = os.path.join(os.path.realpath(base), "filled")
    make_samples.main(filled)
    shutil.rmtree(os.path.join(filled, ".manager"))
    h = Helper("--root", filled, "--settings", settings)
    made = h.ask("createIndex")
    check(tag + "Create Library indexes the documents already there / 新建资料库时已有资料直接进索引",
          made.get("ok") is True and made.get("rows") == len(make_samples.DOCS), made)
    h.close()
    selftest = subprocess.run([BIN, "--selftest", "--root", filled], capture_output=True, text=True).stdout
    check(tag + "selftest names the index / 自检显示索引位置", ".manager/index.json" in selftest and f"{len(make_samples.DOCS)} / {len(make_samples.DOCS)}" in selftest, selftest)


def main():
    temp = os.path.realpath(tempfile.mkdtemp(prefix="manager-protocol-"))
    other_disk = os.path.join(HERE, ".tmp")
    os.makedirs(other_disk, exist_ok=True)
    try:
        p = subprocess.run([BIN, "chrome-extension://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/", "--root", temp], input=b"", capture_output=True)
        check("rejects other extensions / 拒绝其他扩展", p.returncode == 2)
        p = subprocess.run([BIN, ORIGIN, "--root", os.path.join(temp, "missing")], input=b"", capture_output=True)
        check("a missing --root folder stops the helper / --root 文件夹不存在时直接退出", p.returncode == 2)

        shared = os.path.join(temp, "shared")
        make_samples.main(shared)
        run(os.path.realpath(shared), os.path.realpath(shared), os.path.join(temp, "s1.json"))

        library = os.path.join(temp, "library")
        inbox = tempfile.mkdtemp(prefix="inbox-", dir=other_disk)
        make_samples.main(library, inbox)
        run(os.path.realpath(library), os.path.realpath(inbox), os.path.join(temp, "s2.json"))

        settings_tests(os.path.join(temp, "settings"))
        index_tests(os.path.join(temp, "index"))
    finally:
        shutil.rmtree(temp, ignore_errors=True)
        shutil.rmtree(other_disk, ignore_errors=True)
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
