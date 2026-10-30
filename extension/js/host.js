// Client for the Mac helper (本机助手), over Chrome Native Messaging.
// Every request carries a unique id; the helper answers with one message with the same id:
//   config / setConfig → config, list → items (with a `notice` when the index was just moved in or rebuilt),
//   discover → candidates, import / delete / createIndex / rebuildIndex → result, or error (with a `code`:
//   library_missing, inbox_missing, index, index_missing, index_exists, permission, settings, unknown_op, error).
// The helper reads two folders, both ~/Downloads unless set in Settings: the library (.manager/index.json,
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
  /** True when the index cannot be read and was not rebuilt (an old Manager.html that is not an index, or a newer index). / 索引无法读取且没有自动重建。 */
  get badIndex() {
    return this.code === 'index';
  }
  /** True for a helper older than this page (it does not know an operation, or reports an older version). / 助手比页面旧。 */
  get outdated() {
    return this.code === 'unknown_op' || this.code === 'old_helper' || (!this.code && /不支持的操作/.test(this.message));
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
  rebuildIndex: () => request('rebuildIndex', {}, 120000),
  // { items, notice? } / 资料行，以及索引刚搬入或重建时的说明
  list: () => request('list').then(r => ({ items: r.items || [], notice: r.notice || null })),
  discover: () => request('discover', {}, 60000).then(r => r.items || []),
  // Each file is rendered for its thumbnail, so allow time per file. / 每个文件都要渲染缩略图，按文件数放宽时限。
  import: (paths, metadata) => request('import', { paths, metadata }, 60000 + 45000 * paths.length),
  delete: href => request('delete', { path: href }),
};
