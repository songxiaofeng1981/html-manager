// Development only: stands in for the chrome.* APIs so the manager page runs in a normal tab.
// See dev/serve.py. / 仅供开发：代替 chrome.* 接口，让管理页能在普通标签页运行。见 dev/serve.py。
(() => {
  // Like Chrome, every connectNative() call gives a new port. / 和 Chrome 一样，每次 connectNative() 返回新的端口。
  const connectNative = () => {
    const listeners = { message: [], disconnect: [] };
    let open = true;
    return {
      onMessage: { addListener: f => listeners.message.push(f) },
      onDisconnect: { addListener: f => listeners.disconnect.push(f) },
      async postMessage(request) {
        if (!open) throw new Error('Attempting to use a disconnected port object');
        const r = await fetch('/__native', { method: 'POST', body: JSON.stringify(request) });
        const messages = await r.json();
        if (!Array.isArray(messages)) {
          open = false;
          listeners.disconnect.forEach(f => f());
          return;
        }
        for (const m of messages) listeners.message.forEach(f => f(m));
      },
    };
  };
  window.chrome = {
    runtime: { lastError: null, connectNative, getURL: p => `/${p}` },
    i18n: { getUILanguage: () => navigator.language },
  };
  // file:// links cannot open from an http page; the dev server serves the sample folder instead.
  // http 页面打不开 file:// 链接，改由开发服务器提供示例文件夹里的文件。
  window.MANAGER_DEV = { fileURL: path => '/__file' + String(path).split('/').map(encodeURIComponent).join('/') };
})();

// ?demo=select | info | import | settings puts the page in a state for README screenshots.
// ?demo=select | info | import | settings 用于生成 README 截图。
(() => {
  const demo = new URLSearchParams(location.search).get('demo');
  if (!demo) return;
  const wait = ms => new Promise(r => setTimeout(r, ms));
  addEventListener('load', async () => {
    await wait(1200);
    const cards = [...document.querySelectorAll('.card')];
    if (demo === 'select') for (const i of [0, 2, 3]) cards[i]?.querySelector('.check').click();
    if (demo === 'info') {
      cards[1]?.click();
      document.querySelector('#infoToggle').click();
    }
    if (demo === 'settings') document.querySelector('#settings').click();
    if (demo === 'import') {
      document.querySelector('[data-action="import"]')?.click();
      await wait(1500);
      const sheet = document.querySelector('#importDialog');
      sheet.querySelector('.imp-family')?.setAttribute('open', '');
      sheet.querySelector('.imp-row:last-child .imp-check')?.click();
    }
  });
})();
