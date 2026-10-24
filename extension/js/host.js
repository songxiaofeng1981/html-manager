// Client for the Mac helper (本机助手), over Chrome Native Messaging.
// Every request carries a unique id; the helper answers with one message with the same id:
//   config / setConfig → config, list → items, discover → candidates, import / delete → result,
//   createIndex → result, or error (with a `code`: library_missing, inbox_missing, index, index_missing,
//   permission, settings, unknown_op, error).
// The helper reads two folders, both ~/Downloads unless set in Settings: the library (Manager.html,
// Manager_Files, .thumbs) and the inbox (where new HTML arrives).
// 与本机助手通信（Chrome Native Messaging）。每个请求带唯一 id，助手用同一个 id 回复一条消息。

export const HOST_NAME = 'com.songxiaofeng.managerhtml';

let port = null;
let seq = 0;
const pending = new Map();

function connect() {
  if (port) return port;
  port = chrome.runtime.connectNative(HOST_NAME);
  port.onMessage.addListener(msg => {
    const p = pending.get(msg.id);
    if (!p) return;
    pending.delete(msg.id);
    clearTimeout(p.timer);
    if (msg.type === 'error') p.reject(new HostError(msg.error || 'helper error', { code: msg.code }));
    else p.resolve(msg);
  });
  port.onDisconnect.addListener(() => {
    const reason = chrome.runtime.lastError?.message || 'disconnected';
    port = null;
    for (const [id, p] of pending) {
      pending.delete(id);
      clearTimeout(p.timer);
      p.reject(new HostError(reason));
    }
  });
  return port;
}

export class HostError extends Error {
  constructor(message, { timeout = false, code = '' } = {}) {
    super(message);
    this.timeout = timeout;
    this.code = code;
  }
  /** True when Chrome could not start the helper at all (not installed or not registered). */
  get notInstalled() {
    return /not found|forbidden|native messaging host|disconnected|exited/i.test(this.message);
  }
  /** True when macOS refused access to Downloads. / macOS 拒绝访问“下载”文件夹。 */
  get permissionDenied() {
    return this.code === 'permission';
  }
  /** True when Manager.html is missing or not in the expected format. / Manager.html 缺失或格式不对。 */
  get badIndex() {
    return this.code === 'index';
  }
  /** True for a helper from before 1.5, which has no settings. / 1.5 之前的助手，没有设置功能。 */
  get outdated() {
    return this.code === 'unknown_op' || (!this.code && /不支持的操作/.test(this.message));
  }
}

function request(op, details = {}, timeoutMs = 20000) {
  const id = `mgr-${Date.now().toString(36)}-${++seq}`;
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => {
      pending.delete(id);
      reject(new HostError('timeout', { timeout: true }));
    }, timeoutMs);
    pending.set(id, { resolve, reject, timer });
    try {
      connect().postMessage({ id, op, ...details });
    } catch (e) {
      clearTimeout(timer);
      pending.delete(id);
      reject(new HostError(e.message));
    }
  });
}

export const host = {
  config: () => request('config'),
  setConfig: (library, inbox) => request('setConfig', { library, inbox }),
  createIndex: () => request('createIndex'),
  list: () => request('list').then(r => r.items || []),
  discover: () => request('discover', {}, 60000).then(r => r.items || []),
  // Each file is rendered for its thumbnail, so allow time per file. / 每个文件都要渲染缩略图，按文件数放宽时限。
  import: (paths, metadata) => request('import', { paths, metadata }, 60000 + 45000 * paths.length),
  delete: href => request('delete', { path: href }),
};
