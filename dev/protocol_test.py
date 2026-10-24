#!/usr/bin/env python3
"""Talk to the helper the way Chrome does and check the answers / 像 Chrome 一样和助手通信并检查结果.

Usage / 用法:
    bash helper/build.sh
    python3 dev/protocol_test.py            # makes its own sample folders / 自动生成示例文件夹

Runs twice: library and inbox in one folder (the default, ~/Downloads), then in separate folders on two
disks (library in the system temp folder, inbox in dev/.tmp next to this repository). Never touches your
Downloads or your saved settings. "Import" makes thumbnails with macOS Quick Look, and
each run moves one sample file to the Trash.
运行两遍：资料库和收件文件夹在同一处（默认的 ~/Downloads 情形），以及分在两块磁盘上（资料库在系统临时目录，
收件文件夹在本仓库的 dev/.tmp）。不碰真正的“下载”和已保存的设置。“收录”会用 macOS 快速查看生成缩略图；
每遍会把一个示例文件移到废纸篓。
"""
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


def index_rows(library):
    text = open(os.path.join(library, "Manager.html"), encoding="utf-8").read()
    start = text.index("const files = ") + len("const files = ")
    return json.loads(text[start:text.index(";\nconst HTML_CONTROLLED")])


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
    check(tag + "createIndex starts a new library / 新建资料库", made.get("ok") is True and os.path.isdir(os.path.join(empty, "Manager_Files")), made)
    check(tag + "the new library lists nothing yet / 新资料库是空的", h.ask("list").get("items") == [])
    check(tag + "createIndex never overwrites / 不会覆盖已有索引", h.ask("createIndex").get("type") == "error")
    with open(os.path.join(empty, "Manager.html"), "w") as f:
        f.write("not an index")
    check(tag + "a broken index is refused / 拒绝格式不对的索引", h.ask("setConfig", library=empty, inbox="").get("code") == "settings")
    h.ask("setConfig", library=library, inbox=inbox)
    os.rename(library, library + "-unplugged")
    missing = h.ask("list")
    check(tag + "a missing library is reported, not replaced / 资料库不见时报错而不是改用默认", missing.get("code") == "library_missing", missing)
    check(tag + "config still answers / 设置仍可读取", h.ask("config").get("libraryFound") is False)
    os.rename(library + "-unplugged", library)
    shutil.copy(os.path.join(library, "Manager.html"), other)  # the default folder needs an index too / 默认文件夹也要有索引
    back = h.ask("setConfig", library="", inbox="")
    check(tag + "empty values go back to the defaults / 留空恢复默认", back.get("library") == other and json.load(open(settings)) == {})
    h.close()
    nosave = Helper("--root", other).ask("setConfig", library=library, inbox="")
    check(tag + "without --settings nothing can be saved / 没有设置文件时不能保存", nosave.get("code") == "settings")


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
    finally:
        shutil.rmtree(temp, ignore_errors=True)
        shutil.rmtree(other_disk, ignore_errors=True)
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
