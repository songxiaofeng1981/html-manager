#!/usr/bin/env python3
"""Run the manager page in any browser tab, talking to the real helper / 在普通浏览器标签页里运行管理页，连接真正的本机助手.

Usage / 用法:
    bash helper/build.sh
    python3 dev/make_samples.py /tmp/manager-lib /tmp/manager-inbox
    python3 dev/serve.py /tmp/manager-lib /tmp/manager-inbox   # then open http://127.0.0.1:8771/manager.html
    (one folder for both also works / 也可以只给一个文件夹)

The page is served from extension/ with dev/chrome-shim.js injected. The shim stands in for
chrome.runtime.connectNative (forwarded to the helper started with --root/--inbox and a throwaway
--settings file) and maps file:// links to /__file/, which only serves files inside the sample folders. Point it at a sample folder, not
your real Downloads: importing and deleting really change files.
页面来自 extension/，并注入 dev/chrome-shim.js：它代替 chrome.runtime.connectNative（转发给用 --root 启动的助手），
并把 file:// 链接换成 /__file/（只提供示例文件夹里的文件）。请指向示例文件夹而不是真正的“下载”：收录和删除会真的改动文件。
"""
import json
import os
import queue
import struct
import subprocess
import sys
import tempfile
import threading
import urllib.parse
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer

HERE = os.path.dirname(os.path.abspath(__file__))
EXT = os.path.join(HERE, "..", "extension")
BIN = os.path.join(HERE, "..", "helper", "build", "ManagerHelper.app", "Contents", "MacOS", "manager-host")
ORIGIN = "chrome-extension://jpencbldoocakpdbgolffgemckpimnph/"
CSP = json.load(open(os.path.join(EXT, "manifest.json")))["content_security_policy"]["extension_pages"]
FINAL = ("items", "candidates", "result", "error")


class Bridge:
    def __init__(self, root, inbox):
        # Settings saved from the page go to a throwaway file, never your real one. / 页面保存的设置写到临时文件，不碰真正的设置。
        settings = os.path.join(tempfile.mkdtemp(prefix="manager-dev-"), "settings.json")
        flags = ["--root", root, "--settings", settings] + (["--inbox", inbox] if inbox != root else [])
        self.p = subprocess.Popen([BIN, ORIGIN, *flags], stdin=subprocess.PIPE, stdout=subprocess.PIPE)
        self.lock = threading.Lock()
        self.waiting = {}
        self.counter = 0
        threading.Thread(target=self.read, daemon=True).start()

    def read(self):
        while True:
            head = self.p.stdout.read(4)
            if len(head) < 4:
                return
            msg = json.loads(self.p.stdout.read(struct.unpack("<I", head)[0]))
            q = self.waiting.get(msg.get("id"))
            if q:
                q.put(msg)

    def ask(self, request):
        # Page ids restart on every reload, so use our own unique id with the helper.
        # 页面每次刷新 id 都从头开始，所以和助手通信时换成自己的唯一 id。
        page_id = request["id"]
        q = queue.Queue()
        with self.lock:
            self.counter += 1
            own = f"dev-{self.counter}"
            self.waiting[own] = q
            body = json.dumps({**request, "id": own}).encode()
            self.p.stdin.write(struct.pack("<I", len(body)) + body)
            self.p.stdin.flush()
        try:
            msg = q.get(timeout=600)
            return [{**msg, "id": page_id}]
        finally:
            self.waiting.pop(own, None)


class Handler(SimpleHTTPRequestHandler):
    def __init__(self, *a, **kw):
        super().__init__(*a, directory=EXT, **kw)

    def log_message(self, *a):
        pass

    def end_headers(self):
        # Always serve the files as they are on disk while developing. / 开发时总是返回磁盘上的最新文件。
        self.send_header("Cache-Control", "no-store")
        # Same Content Security Policy as the extension, so violations show up here too.
        # 使用和插件相同的内容安全策略，违规在这里也能看到。
        if not self.path.startswith("/__file/"):
            self.send_header("Content-Security-Policy", CSP)
        super().end_headers()

    def do_GET(self):
        path = self.path.split("?")[0]
        if path in ("/", "/manager.html"):
            html = open(os.path.join(EXT, "manager.html"), encoding="utf-8").read()
            html = html.replace('<script type="module"', '<script src="/__dev/chrome-shim.js"></script>\n  <script type="module"', 1)
            return self.reply(200, "text/html; charset=utf-8", html.encode())
        if path == "/__dev/chrome-shim.js":
            return self.reply(200, "text/javascript", open(os.path.join(HERE, "chrome-shim.js"), "rb").read())
        if path.startswith("/__file/"):
            # Only files inside the sample folder. / 只提供示例文件夹里的文件。
            target = os.path.realpath(urllib.parse.unquote(path[len("/__file"):]))
            if not any(target.startswith(r + os.sep) for r in self.server.roots) or not os.path.isfile(target):
                return self.reply(404, "text/plain", b"not found")
            kind = "image/jpeg" if target.lower().endswith(".jpg") else "image/png" if target.lower().endswith(".png") else "text/html; charset=utf-8"
            return self.reply(200, kind, open(target, "rb").read())
        return super().do_GET()

    def do_POST(self):
        request = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
        try:
            self.reply(200, "application/json", json.dumps(self.server.bridge.ask(request)).encode())
        except Exception as e:  # noqa: BLE001
            self.reply(500, "application/json", json.dumps({"error": str(e)}).encode())

    def reply(self, code, kind, body):
        self.send_response(code)
        self.send_header("Content-Type", kind)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


def main():
    root = os.path.realpath(sys.argv[1] if len(sys.argv) > 1 else "/tmp/manager-samples")
    inbox = os.path.realpath(sys.argv[2]) if len(sys.argv) > 2 else root
    port = int(os.environ.get("PORT", "8771"))
    server = ThreadingHTTPServer(("127.0.0.1", port), Handler)
    server.roots = [root, inbox]
    server.bridge = Bridge(root, inbox)
    print(f"Library {root}\nInbox {inbox}\nOpen http://127.0.0.1:{port}/manager.html  (add ?lang=zh or ?lang=en)", flush=True)
    server.serve_forever()


if __name__ == "__main__":
    main()
