#!/usr/bin/env python3
"""Make a sample "Downloads" folder for development / 生成开发用的示例“下载”文件夹.

Usage / 用法:
    python3 dev/make_samples.py <folder>             # library and inbox in one folder / 资料库和收件文件夹是同一个
    python3 dev/make_samples.py <library> <inbox>    # separate folders / 分开的两个文件夹
The folders are emptied first. / 会先清空这些文件夹。

Creates Manager.html (the index), Manager_Files/ with indexed HTML files (doc-meta, version
families, one without doc-meta, one without a date), JPEG thumbnails in .thumbs/ (one left out
on purpose), and loose HTML files in the root for "Import New HTML", plus things the helper must
skip (a hidden file, a symbolic link). With a separate inbox, the new files go there together with a
picture and a zip they link to, and the index keeps stale absolute paths (as after moving a library).
Only uses the Python standard library and macOS `sips`.
生成 Manager.html（索引）、Manager_Files/ 中已收录的 HTML（含 doc-meta、版本组、缺 doc-meta、缺日期的条目）、
.thumbs/ 中的 JPEG 缩略图（故意少一张），以及根目录中待收录的 HTML；还有助手必须跳过的隐藏文件和符号链接。
只用 Python 标准库和 macOS 自带的 sips。
"""
import datetime
import json
import os
import shutil
import struct
import subprocess
import sys
import zlib

TODAY = datetime.datetime.now().replace(microsecond=0)

# (file name, title, category, tags, keywords, days ago, description, thumbnail colors or None)
DOCS = [
    ("NVDA_估值复盘.html", "英伟达估值与持仓复盘", "投资与市场", ["NVDA", "公司研究", "复盘"], ["数据中心", "GPU"], 0,
     "回顾 NVDA 本季度的收入结构、数据中心增速和估值区间，并记录加仓与减仓的理由。", ((118, 185, 0), (20, 80, 40))),
    ("AI算力产业链.html", "AI 算力产业链地图", "投资与市场", ["AI算力", "研究"], ["HBM", "电力", "台积电"], 1,
     "从芯片、内存、封装到供电，整理 AI 数据中心的上下游关系和主要瓶颈。", ((255, 149, 0), (255, 59, 48))),
    ("AI算力产业链_2.html", "AI 算力产业链地图（第二版）", "投资与市场", ["AI算力", "研究"], ["HBM", "电力"], 3,
     "第二版：补充液冷和电力设备环节。", ((255, 179, 64), (255, 99, 71))),
    ("AI算力产业链_3.html", "AI 算力产业链地图（第三版）", "投资与市场", ["AI算力", "研究"], ["HBM"], 6,
     "第三版：加入 HBM 供需表。", ((255, 204, 0), (255, 149, 0))),
    ("组合风险检查表.html", "组合风险检查表", "投资与市场", ["组合管理", "风险控制", "模板"], ["回撤", "杠杆"], 2,
     "每周检查仓位集中度、杠杆和止损条件的模板。", ((90, 200, 250), (0, 122, 255))),
    ("Remotion字幕组件.html", "Remotion 逐词高亮字幕组件", "视频制作与流程", ["Remotion", "字幕包装", "示例"], ["逐词", "动画"], 4,
     "可直接预览的逐词高亮字幕组件，含三种配色。", ((175, 82, 222), (255, 45, 85))),
    ("视频转场合集.html", "十种视频转场示例", "视觉设计与组件", ["视频转场", "视觉动效", "示例"], ["wipe", "zoom"], 9,
     "擦除、缩放、遮罩等十种常见转场的可交互示例。", ((52, 199, 89), (0, 122, 105))),
    ("WhisperX工作流.html", "WhisperX 转写与对齐工作流", "视频制作与流程", ["WhisperX", "工作流", "教程"], ["字幕", "时间轴"], 15,
     "用 WhisperX 生成逐词时间戳，再导入剪辑软件的完整步骤。", ((0, 122, 255), (88, 86, 214))),
    ("口播反馈记录.html", "口播反馈与表达改进", "工作与管理", ["沟通表达", "复盘"], ["节奏", "停顿"], 40,
     "整理最近十期口播的反馈意见和下一步改进点。", ((142, 142, 147), (72, 72, 74))),
    ("体检指标速查.html", "体检指标速查卡", "健康与生活资料", ["健康知识", "知识卡"], ["血脂", "血糖"], 70,
     "常见体检指标的正常范围和复查建议。", None),
]


def png(path, w, h, rgb1, rgb2):
    rows = []
    for y in range(h):
        t = y / max(h - 1, 1)
        row = bytearray([0])
        for x in range(w):
            s = (x / max(w - 1, 1) + t) / 2
            row += bytes(int(a + (b - a) * s) for a, b in zip(rgb1, rgb2))
        rows.append(bytes(row))

    def chunk(kind, data):
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)

    with open(path, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
                + chunk(b"IDAT", zlib.compress(b"".join(rows), 6)) + chunk(b"IEND", b""))


def page(title, body, meta=None):
    head = f'<meta charset="utf-8"><title>{title}</title>'
    if meta:
        head += f'\n<script type="application/json" id="doc-meta">\n{json.dumps(meta, ensure_ascii=False, indent=2)}\n</script>\n'
    return f'<!doctype html>\n<html lang="zh-CN"><head>{head}</head>\n<body><h1>{title}</h1><p>{body}</p></body></html>\n'


def set_mtime(path, when):
    ts = when.timestamp()
    os.utime(path, (ts, ts))


def main(root, inbox=None):
    for folder in [root, inbox]:
        if folder and os.path.exists(folder):
            shutil.rmtree(folder)
    os.makedirs(os.path.join(root, "Manager_Files"))
    os.makedirs(os.path.join(root, ".thumbs"))
    root = os.path.realpath(root)
    if inbox:
        os.makedirs(inbox)
        inbox = os.path.realpath(inbox)
    records = []
    for i, (name, title, category, tags, keywords, days, desc, colors) in enumerate(DOCS):
        when = TODAY - datetime.timedelta(days=days, hours=i)
        href = f"Manager_Files/{name}"
        path = os.path.join(root, href)
        managed = name != "口播反馈记录.html"  # one file without doc-meta / 一个没有 doc-meta 的文件
        meta = {"title": title, "category": category, "tags": tags, "keywords": keywords, "summary": desc,
                "created": when.strftime("%Y-%m-%d"), "modifiedAt": when.strftime("%Y-%m-%d %H:%M:%S")}
        with open(path, "w", encoding="utf-8") as f:
            f.write(page(title, desc, meta if managed else None))
        set_mtime(path, when)
        # A moved library keeps the old absolute paths; href is what counts. / 移动过的资料库仍保留旧的绝对路径，以 href 为准。
        indexed_path = f"/Users/nobody/Downloads/{href}" if inbox else path
        record = {"title": title, "category": category, "tags": tags, "keywords": keywords + [name[:-5], title],
                  "description": desc, "fileType": "HTML", "filename": name, "path": indexed_path, "href": href,
                  "created": when.strftime("%Y-%m-%d"), "modifiedAt": when.strftime("%Y-%m-%d %H:%M:%S"),
                  "metadataManaged": managed}
        if name == "体检指标速查.html":
            del record["created"]  # shows under "No date" / 显示在“未注明日期”
        records.append(record)
        if colors:
            tmp = os.path.join(root, ".thumbs", "tmp.png")
            png(tmp, 400, 250, *colors)
            out = os.path.join(root, ".thumbs", href.replace("/", "__")[:-5] + ".jpg")
            subprocess.run(["sips", "-s", "format", "jpeg", tmp, "--out", out], check=True, capture_output=True)
            os.remove(tmp)
    # A Markdown row: the helper's list leaves it out. / Markdown 记录：助手的 list 不会返回它。
    records.append({"title": "Markdown 笔记", "category": "工作与管理", "tags": ["知识管理"], "keywords": [], "description": "",
                    "fileType": "MD", "filename": "note.md", "path": os.path.join(root, "note.md"), "href": "note.md",
                    "created": TODAY.strftime("%Y-%m-%d")})
    with open(os.path.join(root, "Manager.html"), "w", encoding="utf-8") as f:
        f.write("<!doctype html><html><head><meta charset='utf-8'><title>Manager</title></head><body>\n<script>\n"
                f"const files = {json.dumps(records, ensure_ascii=False)};\nconst HTML_CONTROLLED=[];\n</script></body></html>\n")

    # Not yet imported / 待收录
    loose = [
        ("Broadcom网络芯片.html", "博通网络芯片与 AI 集群", "博通 AVGO 的交换芯片在 AI 数据中心集群中的位置，估值和风险。", 0),
        ("字幕动效草稿.html", "字幕动效草稿", "逐词高亮字幕组件的动效草稿，Remotion 示例。", 1),
        ("字幕动效草稿_2.html", "字幕动效草稿（第二稿）", "第二稿：调整字幕节奏。Remotion 示例。", 0),
    ]
    drop = inbox or root
    for name, title, body, days in loose:
        path = os.path.join(drop, name)
        with open(path, "w", encoding="utf-8") as f:
            text = page(title, body)
            if name.startswith("Broadcom"):
                # Local files this page links to / 此页面引用的本地文件
                text = text.replace("</p>", '</p><img src="AVGO%20chart.png" alt=""><a href="资料包.zip?v=1">资料包</a>')
            f.write(text)
        set_mtime(path, TODAY - datetime.timedelta(days=days, minutes=len(name)))
    png(os.path.join(drop, "AVGO chart.png"), 40, 25, (255, 149, 0), (255, 59, 48))
    with open(os.path.join(drop, "资料包.zip"), "wb") as f:
        f.write(b"PK\x05\x06" + b"\x00" * 18)
    with open(os.path.join(drop, ".hidden.html"), "w") as f:
        f.write(page("hidden", "should be skipped"))
    os.symlink(os.path.join(root, "Manager_Files", DOCS[0][0]), os.path.join(drop, "link.html"))
    print(f"Sample library / 示例资料库: {root}" + (f"\nSample inbox / 示例收件文件夹: {inbox}" if inbox else ""))


if __name__ == "__main__":
    if len(sys.argv) not in (2, 3):
        sys.exit(__doc__)
    main(*sys.argv[1:])
