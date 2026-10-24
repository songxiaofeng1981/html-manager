// The grid of cards and the list, plus file links and thumbnails.
// 网格卡片和列表视图，以及文件链接和缩略图地址。

import { icon, escapeHtml as esc, paintDots } from './ui.js';
import { categoryTopic } from './vocab.js';
import { versionTimeLabel } from './library.js';
import { t } from './i18n.js';

/** file:// link for a path. The dev server (dev/serve.py) swaps in its own. / 路径对应的 file:// 链接；开发服务器会换成自己的地址。 */
export function fileURL(path) {
  if (globalThis.MANAGER_DEV) return globalThis.MANAGER_DEV.fileURL(path);
  return 'file://' + String(path).split('/').map(encodeURIComponent).join('/');
}

/** Thumbnail made on import: <Downloads>/.thumbs/<href with / as __>.jpg. / 收录时生成的缩略图。 */
export function thumbURL(file) {
  if (file.fileType !== 'HTML' || !/\.html?$/i.test(file.href || '')) return '';
  const root = file.rootPath || file.path.slice(0, Math.max(0, file.path.lastIndexOf('/Manager_Files/')));
  return fileURL(`${root}/.thumbs/${file.href.replaceAll('/', '__').replace(/\.html?$/i, '.jpg')}`);
}

/** Opens a document in a new tab, the same way a link would. / 像点击链接一样在新标签页打开资料。 */
export function openFile(file) {
  const a = document.createElement('a');
  a.href = fileURL(file.path);
  a.target = '_blank';
  a.rel = 'noopener';
  a.click();
}

const dateText = file => file.created || t('undated');

function thumb(file, extra = '') {
  const topic = categoryTopic(file.category);
  const src = thumbURL(file);
  return `<div class="thumb" data-topic="${topic.key}">${src ? `<img src="${esc(src)}" alt="" loading="lazy" draggable="false">` : ''}<div class="thumb-ph">${icon('doc')}<span>${esc(file.category || t('thumb.none'))}</span></div>${extra}</div>`;
}

const catDot = file => `<span class="dot" data-color="${categoryTopic(file.category).color}"></span>`;

function card(c) {
  const x = c.item;
  const badge = c.versions.length > 1 || x._family ? `<span class="badge" title="${esc(t('count.versions', x._family?.items.length || c.versions.length))}">${icon('stack')}${x._family?.items.length || c.versions.length}</span>` : '';
  return `<div class="card" role="option" tabindex="-1" data-key="${esc(c.key)}" data-path="${esc(x.path)}" title="${esc(x.filename || '')}">
    ${thumb(x, `<button type="button" class="check" tabindex="-1" aria-label="${esc(t('select'))}">${icon('check')}</button>${badge}`)}
    <div class="card-title">${esc(x.title || x.filename)}</div>
    <div class="card-meta">${catDot(x)}<span class="card-cat">${esc(x.category || '')}</span><span class="card-date">${esc(dateText(x))}</span></div>
  </div>`;
}

function row(x) {
  const tags = x.tags.length ? x.tags.map(tag => `<span class="chip">${esc(tag)}</span>`).join('') : `<span class="muted">${esc(t('info.noTags'))}</span>`;
  return `<div class="row" role="option" tabindex="-1" data-key="${esc(x.path)}" data-path="${esc(x.path)}">
    <button type="button" class="check" tabindex="-1" aria-label="${esc(t('select'))}">${icon('check')}</button>
    ${thumb(x)}
    <div class="row-title"><strong>${esc(x.title || x.filename)}</strong><span>${esc(x.filename || '')}${x._family ? ` · ${esc(t('count.versions', x._family.items.length))}` : ''}</span></div>
    <div class="row-cat">${catDot(x)}<span>${esc(x.category || '')}</span></div>
    <div class="row-tags">${tags}</div>
    <div class="row-time">${esc(versionTimeLabel(x, t('undated')))}</div>
  </div>`;
}

/** Draws the result; keeps nothing but the DOM. / 绘制结果。 */
export function renderContent(el, result, layout) {
  el.className = `content ${layout}`;
  el.setAttribute('role', 'listbox');
  el.setAttribute('aria-multiselectable', 'true');
  el.innerHTML = layout === 'list'
    ? `<div class="list-head"><span></span><span></span><span>${esc(t('list.title'))}</span><span>${esc(t('info.category'))}</span><span>${esc(t('info.tags'))}</span><span>${esc(t('info.modified'))}</span></div>${result.items.map(row).join('')}`
    : result.cards.map(card).join('');
  paintDots(el);
  markLoaded(el);
}

/** Marks images that loaded or failed, so the placeholder shows only when needed. / 标记缩略图加载结果，只在需要时显示占位。 */
export function watchImages(el) {
  el.addEventListener('load', e => e.target.matches?.('.thumb img') && e.target.parentElement.classList.add('ready'), true);
  el.addEventListener('error', e => e.target.matches?.('.thumb img') && e.target.parentElement.classList.add('failed'), true);
}

/** Images already in the cache may finish before the listeners above see them. / 缓存中的图片可能在监听前就已加载完。 */
export function markLoaded(el) {
  for (const img of el.querySelectorAll('.thumb img')) {
    if (img.complete) img.parentElement.classList.add(img.naturalWidth ? 'ready' : 'failed');
  }
}
