// Starts the manager page and connects the pieces: sidebar, toolbar, grid or list, Info panel,
// date filter, import sheet, and the actions (open, copy, move to the Trash).
// 启动管理页，把侧边栏、工具栏、网格/列表、信息面板、日期筛选、收录面板和各种操作连在一起。

import { host, HostError } from './host.js';
import { prepare, compute, facets, dayCounts, vocabularyFor } from './library.js';
import { renderContent, watchImages, openFile } from './views.js';
import { renderInfo } from './info.js';
import { Calendar, dateLabel } from './calendar.js';
import { Importer } from './importer.js';
import { TAG_GROUPS, categoryTopic } from './vocab.js';
import { prefs, setPref } from './prefs.js';
import { icon, fillIcons, paintDots, escapeHtml as esc, toast, hideToast, closeMenu, menuOpen, confirmSheet, copyText } from './ui.js';
import { t, localizePage } from './i18n.js';

const $ = s => document.querySelector(s);
const content = $('#content');

const state = {
  all: [],
  byPath: new Map(),
  view: 'all',
  search: '',
  date: '',
  format: '',
  result: { items: [], cards: [], families: 0 },
  current: null, // path shown in the Info panel / 信息面板显示的资料
  selected: new Set(), // paths / 选中的路径
  anchor: null, // start of a ⇧-click range / ⇧ 点按范围的起点
  pending: null, // files waiting to be imported / 待收录文件
  loaded: false,
  config: null, // library and inbox folders from the helper / 本机助手报告的资料库和收件文件夹
};

const calendar = new Calendar($('#calendar'), {
  picked: value => {
    state.date = value;
    closeCalendar();
    refresh({ keepScroll: false });
  },
});

const importer = new Importer($('#importDialog'), {
  folders: () => state.config,
  imported: async (result, left) => {
    await load({ quiet: true });
    state.pending = left;
    renderSidebar();
    toast(t('import.done', result.imported || 0, left.length));
  },
  failed: () => {},
});

// ---------- loading / 读取 ----------

async function start() {
  localizePage();
  fillIcons();
  $('#sort').value = prefs.sort;
  $('#size').value = prefs.cardSize;
  $('#dateLabel').textContent = dateLabel('');
  watchImages(content);
  watchImages($('#info'));
  await load();
}

async function load({ quiet = false } = {}) {
  if (!quiet) showStatus('loading');
  try {
    state.config = await host.config();
    $('#helperLabel').title = t('helper.where', state.config.library);
    const rows = await host.list();
    state.all = prepare(rows);
    state.byPath = new Map(state.all.map(x => [x.path, x]));
    for (const path of state.selected) if (!state.byPath.has(path)) state.selected.delete(path);
    if (state.current && !state.byPath.has(state.current)) state.current = null;
    state.loaded = true;
    showStatus(null);
    refresh();
    if (!quiet) findPending();
  } catch (e) {
    console.error(e);
    state.loaded = false;
    const library = state.config?.library || '~/Downloads';
    if (!(e instanceof HostError)) return showStatus('missing', e.message);
    if (e.outdated) return showStatus('outdated', e.message);
    if (e.code === 'library_missing') return showStatus('library', e.message, library);
    if (e.code === 'inbox_missing') return showStatus('inbox', e.message, state.config?.inbox);
    if (e.code === 'index_missing') return showStatus('noindex', '', library);
    if (e.permissionDenied) return showStatus('permission', e.message);
    if (e.badIndex) return showStatus('index', e.message, library);
    showStatus('missing', e.message);
  }
}

/** Counts new HTML files for the sidebar, without blocking the page. / 在后台统计待收录文件数。 */
function findPending() {
  host.discover().then(items => {
    state.pending = items;
    renderSidebar();
  }, () => {});
}

function showStatus(kind, detail = '', path = '') {
  const el = $('#status');
  document.body.classList.toggle('has-status', !!kind);
  $('#helperDot').className = `helper-dot ${kind ? (kind === 'loading' ? 'busy' : 'bad') : 'ok'}`;
  $('#helperLabel').textContent = kind === 'loading' ? t('helper.loading') : kind ? t('helper.notConnected') : t('helper.connected');
  if (!kind) {
    el.hidden = true;
    return;
  }
  el.hidden = false;
  content.replaceChildren();
  $('#viewTitle').textContent = t('appName');
  $('#empty').hidden = true;
  if (kind === 'loading') {
    el.innerHTML = `<div class="spinner"></div><p>${esc(t('status.loading'))}</p>`;
    return;
  }
  const steps = t(`status.${kind}.steps`).split('|');
  el.innerHTML = `
    <div class="status-card">
      <div class="status-icon">${icon(kind === 'permission' || kind === 'library' || kind === 'inbox' ? 'folder' : kind === 'index' ? 'doc' : kind === 'noindex' ? 'docs' : 'tray')}</div>
      <h2>${esc(t(`status.${kind}.title`))}</h2>
      <p>${esc(t(`status.${kind}.body`, path))}</p>
      <ol>${steps.map(s => `<li>${esc(s)}</li>`).join('')}</ol>
      <div class="status-actions">
        ${kind === 'noindex' ? `<button type="button" class="button primary" id="createIndex">${esc(t('status.create'))}</button>` : ''}
        <button type="button" class="button${kind === 'noindex' ? '' : ' primary'}" id="retry">${esc(t('retry'))}</button>
        ${['library', 'inbox', 'index', 'permission', 'noindex'].includes(kind) ? `<button type="button" class="button" id="statusSettings">${icon('folder')}<span>${esc(t('status.openSettings'))}</span></button>` : ''}
      </div>
      ${detail ? `<details><summary>${esc(t('status.details'))}</summary><code>${esc(detail)}</code></details>` : ''}
    </div>`;
  $('#retry').onclick = () => load();
  if ($('#statusSettings')) $('#statusSettings').onclick = openSettings;
  if ($('#createIndex')) {
    $('#createIndex').onclick = async () => {
      try {
        await host.createIndex();
        await load();
      } catch (e) {
        toast(t('toast.error', e.message), { error: true });
      }
    };
  }
}

// ---------- folders / 资料库位置 ----------

async function openSettings() {
  const dialog = $('#settingsDialog');
  const error = $('#settingsError');
  error.hidden = true;
  try {
    state.config = await host.config();
  } catch (e) {
    return toast(e.outdated ? t('status.outdated.title') : t('toast.error', e.message), { error: true });
  }
  const c = state.config;
  const fill = (input, value, fallback) => {
    input.value = value === fallback ? '' : value;
    input.placeholder = t('settings.default', fallback);
  };
  fill($('#setLibrary'), c.library, c.defaultLibrary);
  fill($('#setInbox'), c.inbox, c.defaultInbox);
  $('#settingsSave').disabled = !c.canSave;
  if (!c.canSave) {
    error.textContent = t('settings.cannotSave');
    error.hidden = false;
  }
  dialog.showModal();
}

$('#settingsSave').addEventListener('click', async () => {
  const error = $('#settingsError');
  const button = $('#settingsSave');
  button.disabled = true;
  error.hidden = true;
  try {
    state.config = await host.setConfig($('#setLibrary').value, $('#setInbox').value);
    $('#settingsDialog').close();
    state.pending = null;
    state.selected.clear();
    state.current = null;
    await load();
    toast(t('settings.saved'));
  } catch (e) {
    error.textContent = e.message;
    error.hidden = false;
  } finally {
    button.disabled = !state.config?.canSave;
  }
});

// ---------- rendering / 显示 ----------

function refresh({ keepScroll = true } = {}) {
  if (!state.loaded) return;
  state.result = compute(state.all, { view: state.view, search: state.search, date: state.date, format: state.format, sort: prefs.sort });
  const scroller = $('#scroller');
  const top = scroller.scrollTop;
  content.style.setProperty('--card', `${prefs.cardSize}px`);
  renderContent(content, state.result, prefs.layout);
  scroller.scrollTop = keepScroll ? top : 0;
  renderSidebar();
  renderHeader();
  renderTools();
  renderSelection();
  renderEmpty();
}

function viewTitle(view) {
  if (view === 'all') return t('view.all');
  if (view === 'recent') return t('view.recent');
  if (view === 'versions') return t('view.versions');
  return view.slice(4);
}

function renderHeader() {
  const { items, families } = state.result;
  $('#viewTitle').textContent = viewTitle(state.view);
  const parts = [t('count.docs', items.length)];
  if (prefs.layout === 'grid' && families) parts.push(t('count.families', families));
  $('#viewSub').textContent = parts.join(' · ');
  document.title = `${viewTitle(state.view)} · ${t('appName')}`;
}

function renderTools() {
  const f = facets(state.all, '');
  $('#format').hidden = !f.hasMarkdown;
  $('#format').value = state.format;
  $('#dateLabel').textContent = dateLabel(state.date);
  $('#dateButton').classList.toggle('active', !!state.date);
  for (const b of $('#layout').querySelectorAll('button')) {
    const on = b.dataset.layout === prefs.layout;
    b.classList.toggle('active', on);
    b.setAttribute('aria-pressed', String(on));
  }
  $('#zoom').hidden = prefs.layout !== 'grid';
  for (const b of [$('#infoToggle'), $('#selInfo')]) {
    b.classList.toggle('active', prefs.infoOpen);
    b.setAttribute('aria-pressed', String(prefs.infoOpen));
  }
  $('#info').hidden = !prefs.infoOpen;
}

function filtersOn() {
  return !!(state.search || state.date || state.format || state.view !== 'all');
}

function renderEmpty() {
  const el = $('#empty');
  const empty = !state.result.items.length;
  el.hidden = !empty;
  if (!empty) return;
  const none = !state.all.length;
  el.innerHTML = `<div class="empty-icon">${icon(none ? 'docs' : 'search')}</div>
    <h2>${esc(t(none ? 'empty.none.title' : 'empty.search.title'))}</h2>
    <p>${esc(t(none ? 'empty.none.body' : 'empty.search.body'))}</p>
    <div class="status-actions">${none
      ? `<button type="button" class="button primary" data-empty="import">${icon('inbox')}<span>${esc(t('view.pending'))}</span></button>`
      : filtersOn() ? `<button type="button" class="button" data-empty="clear">${esc(t('empty.clear'))}</button>` : ''}</div>`;
}

// ---------- sidebar / 侧边栏 ----------

const SHOW_FIRST = 5;
const expanded = new Set();

function sideItem(view, label, count, iconHtml = '', attr = 'data-view') {
  const active = attr === 'data-view' && state.view === view;
  return `<button type="button" class="side-item${active ? ' active' : ''}${iconHtml ? '' : ' plain'}" ${attr}="${esc(view)}">${iconHtml}<span class="side-label">${esc(label)}</span><span class="side-count">${count}</span></button>`;
}

function sideSection(id, title, rows, { extraHeading = '', keepEmpty = false, limit = SHOW_FIRST } = {}) {
  if (!keepEmpty) rows = rows.filter(r => r[2] > 0 || state.view === r[0]);
  if (!rows.length) return '';
  const folded = prefs.collapsed.includes(id);
  const out = [`<div class="side-section${folded ? ' folded' : ''}"><div class="side-heading"><button type="button" class="side-fold" data-fold="${id}" aria-expanded="${!folded}">${esc(title)}${icon('chevronDown')}</button>${extraHeading}</div>`];
  if (!folded) {
    const activeAt = rows.findIndex(r => r[0] === state.view);
    const all = expanded.has(id) || rows.length <= limit + 1 || activeAt >= limit;
    for (const r of all ? rows : rows.slice(0, limit)) out.push(sideItem(...r));
    if (rows.length > limit + 1) out.push(`<button type="button" class="side-more" data-more="${id}">${esc(all ? t('side.showLess') : t('side.showAll', rows.length))}</button>`);
  }
  out.push('</div>');
  return out.join('');
}

function renderSidebar() {
  if (!state.loaded) return;
  const f = facets(state.all, state.format);
  const html = [];
  const pending = state.pending ? state.pending.length : '';
  html.push(sideSection('library', t('side.library'), [
    ['all', t('view.all'), f.all, icon('docs')],
    ['recent', t('view.recent'), f.recent, icon('clock')],
    ['versions', t('view.versions'), f.versions, icon('stack')],
    ['import', t('view.pending'), pending, icon('inbox'), 'data-action'],
  ], { keepEmpty: true, limit: Infinity }));
  html.push(sideSection('categories', t('side.categories'),
    f.categories.map(([name, n]) => [`cat:${name}`, name, n, `<span class="dot" data-color="${categoryTopic(name).color}"></span>`]),
    { limit: Infinity }));
  const vocab = vocabularyFor(state.format);
  TAG_GROUPS.forEach((group, i) => {
    const rows = vocab.filter(v => v.group === group).map(v => [`tag:${v.tag}`, v.tag, f.tags.get(v.tag) || 0])
      .sort((a, b) => b[2] - a[2] || a[1].localeCompare(b[1], 'zh-CN'));
    const info = i === 0 ? `<button type="button" class="side-add" id="vocabButton" title="${esc(t('side.vocab'))}" aria-label="${esc(t('side.vocab'))}">${icon('info')}</button>` : '';
    html.push(sideSection(`tags-${group}`, t('side.tags', group), rows, { extraHeading: info }));
  });
  $('#sideNav').innerHTML = html.join('');
  paintDots($('#sideNav'));
}

function setView(view) {
  state.view = view;
  state.selected.clear();
  refresh({ keepScroll: false });
}

// ---------- selection and Info / 选择和信息面板 ----------

const nodes = () => [...content.querySelectorAll('[data-path]')];

function renderSelection() {
  const n = state.selected.size;
  document.body.classList.toggle('selecting', n > 0);
  $('#selCount').textContent = t('selection.count', n);
  for (const node of nodes()) {
    node.classList.toggle('selected', state.selected.has(node.dataset.path));
    node.classList.toggle('current', node.dataset.path === state.current);
    node.setAttribute('aria-selected', String(state.selected.has(node.dataset.path)));
  }
  renderInfoPanel();
}

function renderInfoPanel() {
  if (!prefs.infoOpen) return;
  const n = state.selected.size;
  const path = state.current || (n === 1 ? [...state.selected][0] : null);
  renderInfo($('#info'), state.byPath.get(path), n);
}

function setCurrent(path, { scroll = false } = {}) {
  state.current = path;
  renderSelection();
  if (scroll) {
    const node = content.querySelector(`[data-path="${CSS.escape(path)}"]`);
    node?.scrollIntoView({ block: 'nearest' });
    node?.focus({ preventScroll: true });
  }
}

function toggleSelected(path) {
  state.selected.has(path) ? state.selected.delete(path) : state.selected.add(path);
  state.anchor = path;
}

function setInfoOpen(open) {
  setPref('infoOpen', open);
  renderTools();
  renderInfoPanel();
}

/** Paths to act on: the selection, or else the current document. / 要操作的路径：选中的，否则是当前资料。 */
function targets() {
  if (state.selected.size) return [...state.selected];
  return state.current ? [state.current] : [];
}

content.addEventListener('click', e => {
  const node = e.target.closest('[data-path]');
  if (!node) return;
  const path = node.dataset.path;
  if (e.target.closest('.check') || e.metaKey || e.ctrlKey) {
    toggleSelected(path);
  } else if (e.shiftKey && state.anchor) {
    const list = nodes().map(n => n.dataset.path);
    const [a, b] = [list.indexOf(state.anchor), list.indexOf(path)].sort((x, y) => x - y);
    if (a >= 0) for (const p of list.slice(a, b + 1)) state.selected.add(p);
  } else if (state.selected.size) {
    // While selecting, a click adds or removes, as in Photos. / 选择状态下点按即增减，和“照片”一样。
    toggleSelected(path);
  } else {
    state.anchor = path;
  }
  setCurrent(path);
  node.focus({ preventScroll: true, focusVisible: false });
});

content.addEventListener('dblclick', e => {
  const node = e.target.closest('[data-path]');
  if (node && !e.target.closest('.check')) openFile(state.byPath.get(node.dataset.path));
});

$('#info').addEventListener('click', async e => {
  const go = e.target.closest('[data-go]');
  if (go) return setView(go.dataset.go);
  const b = e.target.closest('[data-act]');
  if (!b) return;
  const file = state.byPath.get(state.current || [...state.selected][0]);
  switch (b.dataset.act) {
    case 'open': return file && openFile(file);
    case 'copy': return copyPaths([b.dataset.path]);
    case 'show': return setCurrent(b.dataset.path, { scroll: true });
    case 'open-version': return openFile(state.byPath.get(b.dataset.path));
    case 'trash': return file && trash([file.path]);
  }
});

// ---------- actions / 操作 ----------

async function copyPaths(paths) {
  if (!paths.length) return;
  const ok = await copyText(paths.join('\n'));
  toast(ok ? t('copy.paths', paths.length) : t('toast.error', 'clipboard'), { error: !ok });
}

async function copyArchiveList() {
  const paths = [...state.selected];
  if (!paths.length) return;
  const ok = await copyText(t('selection.listText', paths.length, paths.map(p => `- ${p}`).join('\n')));
  toast(ok ? t('selection.listCopied', paths.length) : t('toast.error', 'clipboard'), { error: !ok });
}

async function trash(paths) {
  const files = paths.map(p => state.byPath.get(p)).filter(Boolean);
  const html = files.filter(f => f.fileType === 'HTML' && /\.html?$/i.test(f.filename || ''));
  if (!html.length) return toast(t('trash.onlyHtml'), { error: true });
  const shown = html.slice(0, 8).map(f => f.filename);
  if (html.length > 8) shown.push(t('trash.more', html.length - 8));
  const ok = await confirmSheet({ title: t('trash.title', html.length), body: t('trash.body'), lines: shown, confirm: t('trash'), danger: true });
  if (!ok) return;
  let done = 0;
  try {
    for (const file of html) {
      toast(t('trash.working', done + 1, html.length), { sticky: true });
      await host.delete(file.href);
      state.selected.delete(file.path);
      done++;
    }
    hideToast();
    await load({ quiet: true });
    toast(t('trash.done', done));
  } catch (e) {
    await load({ quiet: true });
    toast(e.timeout ? t('toast.timeout') : t('trash.partial', done, e.message), { error: true });
  }
}

function openImporter() {
  importer.open().then(() => {
    state.pending = importer.rows.map(r => r.item);
    renderSidebar();
  });
}

function openVocab() {
  const counts = facets(state.all, state.format).tags;
  $('#vocabRows').innerHTML = vocabularyFor(state.format).map(v =>
    `<tr><td><span class="pill">${esc(v.group)}</span></td><td><strong>${esc(v.tag)}</strong></td><td class="num">${counts.get(v.tag) || 0}</td><td>${esc(v.scope)}</td></tr>`).join('');
  $('#vocabDialog').showModal();
}

function openCalendar() {
  calendar.show(dayCounts(state.all, state.format), state.date);
  $('#calendar').hidden = false;
  $('#dateButton').setAttribute('aria-expanded', 'true');
}

function closeCalendar() {
  $('#calendar').hidden = true;
  $('#dateButton').setAttribute('aria-expanded', 'false');
}

function moveCurrent(key) {
  const list = nodes();
  if (!list.length) return;
  let i = list.findIndex(n => n.dataset.path === state.current);
  if (i < 0) return setCurrent(list[0].dataset.path, { scroll: true });
  let step = 1;
  if (prefs.layout === 'grid' && (key === 'ArrowUp' || key === 'ArrowDown')) {
    const top = list[0].offsetTop;
    step = Math.max(1, list.findIndex(n => n.offsetTop !== top));
    if (step === 0 || list.every(n => n.offsetTop === top)) step = list.length;
  }
  if (prefs.layout === 'list' && (key === 'ArrowLeft' || key === 'ArrowRight')) return;
  i += key === 'ArrowLeft' || key === 'ArrowUp' ? -step : step;
  if (i < 0 || i >= list.length) return;
  setCurrent(list[i].dataset.path, { scroll: true });
}

// ---------- events / 事件 ----------

$('#sideNav').addEventListener('click', e => {
  const fold = e.target.closest('[data-fold]');
  if (fold) {
    const set = new Set(prefs.collapsed);
    set.has(fold.dataset.fold) ? set.delete(fold.dataset.fold) : set.add(fold.dataset.fold);
    setPref('collapsed', [...set]);
    return renderSidebar();
  }
  const more = e.target.closest('[data-more]');
  if (more) {
    expanded.has(more.dataset.more) ? expanded.delete(more.dataset.more) : expanded.add(more.dataset.more);
    return renderSidebar();
  }
  if (e.target.closest('#vocabButton')) return openVocab();
  if (e.target.closest('[data-action="import"]')) return openImporter();
  const b = e.target.closest('[data-view]');
  if (b) setView(b.dataset.view);
});

$('#empty').addEventListener('click', e => {
  const b = e.target.closest('[data-empty]');
  if (b?.dataset.empty === 'import') return openImporter();
  if (b?.dataset.empty === 'clear') {
    state.search = '';
    state.date = '';
    state.format = '';
    $('#search').value = '';
    setView('all');
  }
});

let searchTimer = null;
$('#search').addEventListener('input', e => {
  clearTimeout(searchTimer);
  searchTimer = setTimeout(() => {
    state.search = e.target.value;
    refresh({ keepScroll: false });
  }, 120);
});
$('#format').addEventListener('change', e => {
  state.format = e.target.value;
  if (state.view.startsWith('tag:')) state.view = 'all';
  state.date = '';
  refresh({ keepScroll: false });
});
$('#sort').addEventListener('change', e => {
  setPref('sort', e.target.value);
  refresh({ keepScroll: false });
});
$('#size').addEventListener('input', e => {
  setPref('cardSize', Number(e.target.value));
  content.style.setProperty('--card', `${prefs.cardSize}px`);
});
$('#layout').addEventListener('click', e => {
  const b = e.target.closest('[data-layout]');
  if (!b) return;
  setPref('layout', b.dataset.layout);
  refresh({ keepScroll: false });
});
$('#dateButton').addEventListener('click', () => ($('#calendar').hidden ? openCalendar() : closeCalendar()));
document.addEventListener('pointerdown', e => {
  if (!$('#calendar').hidden && !e.target.closest('.date-wrap')) closeCalendar();
});
$('#infoToggle').onclick = () => setInfoOpen(!prefs.infoOpen);
$('#selInfo').onclick = () => setInfoOpen(!prefs.infoOpen);
$('#rescan').onclick = () => load();
$('#settings').onclick = openSettings;
$('#shortcuts').onclick = () => $('#keysDialog').showModal();
$('#selDone').onclick = () => {
  state.selected.clear();
  renderSelection();
};
$('#selAll').onclick = () => {
  for (const node of nodes()) state.selected.add(node.dataset.path);
  renderSelection();
};
$('#selCopy').onclick = copyArchiveList;
$('#selTrash').onclick = () => trash([...state.selected]);

document.addEventListener('keydown', e => {
  if (menuOpen() || document.querySelector('dialog[open]')) return;
  const typing = e.target.matches('input, textarea, select');
  const cmd = e.metaKey || e.ctrlKey;
  const key = e.key.toLowerCase();
  if ((cmd && key === 'f') || (!typing && e.key === '/')) {
    e.preventDefault();
    return $('#search').focus();
  }
  if (typing) {
    if (e.key === 'Escape') e.target.blur();
    if (e.key === 'ArrowDown' && e.target.id === 'search') {
      e.preventDefault();
      e.target.blur();
      moveCurrent('ArrowRight');
    }
    return;
  }
  if (e.key === 'Escape') {
    if (!$('#calendar').hidden) return closeCalendar();
    state.selected.clear();
    return renderSelection();
  }
  if (cmd && key === 'a') {
    e.preventDefault();
    return $('#selAll').click();
  }
  if (cmd && key === 'c') return copyPaths(targets());
  if (cmd && key === 'i') {
    e.preventDefault();
    return setInfoOpen(!prefs.infoOpen);
  }
  if (cmd && (key === '1' || key === '2')) {
    e.preventDefault();
    setPref('layout', key === '1' ? 'grid' : 'list');
    return refresh({ keepScroll: false });
  }
  if (cmd && (e.key === '=' || e.key === '+' || e.key === '-')) {
    e.preventDefault();
    const v = Math.max(160, Math.min(360, prefs.cardSize + (e.key === '-' ? -40 : 40)));
    $('#size').value = v;
    setPref('cardSize', v);
    return content.style.setProperty('--card', `${v}px`);
  }
  if (e.key === ' ') {
    e.preventDefault();
    return setInfoOpen(!prefs.infoOpen);
  }
  if (e.key.startsWith('Arrow') && !cmd) {
    e.preventDefault();
    return moveCurrent(e.key);
  }
  if ((e.key === 'Enter' || (cmd && e.key === 'ArrowDown') || (cmd && key === 'o')) && state.current) {
    e.preventDefault();
    return openFile(state.byPath.get(state.current));
  }
  if (e.key === 'Backspace' || e.key === 'Delete') {
    const paths = targets();
    if (paths.length) return trash(paths);
  }
  if (e.key === '?') return $('#keysDialog').showModal();
});

addEventListener('scroll', closeMenu, true);

start();
