// The Info panel on the right: thumbnail, details and versions of the current document.
// 右侧信息面板：当前资料的缩略图、详细信息和所有版本。

import { icon, escapeHtml as esc, paintDots } from './ui.js';
import { categoryTopic } from './vocab.js';
import { versionTimeLabel } from './library.js';
import { thumbURL, markLoaded } from './views.js';
import { t } from './i18n.js';

export function renderInfo(el, file, selectedCount) {
  if (!file) {
    el.innerHTML = `<div class="info-empty">${icon(selectedCount > 1 ? 'docs' : 'info')}<p>${esc(selectedCount > 1 ? t('info.many', selectedCount) : t('info.none'))}</p></div>`;
    return;
  }
  const topic = categoryTopic(file.category);
  const src = thumbURL(file);
  const tags = file.tags.length
    ? file.tags.map(tag => `<button type="button" class="chip link" data-go="tag:${esc(tag)}">${esc(tag)}</button>`).join('')
    : `<span class="muted">${esc(file.metadataManaged === false ? t('info.notManaged') : t('info.noTags'))}</span>`;
  const versions = file._family?.items || [];
  const rows = [
    [t('info.category'), `<button type="button" class="link-button plain-text" data-go="cat:${esc(file.category || '')}"><span class="dot" data-color="${topic.color}"></span>${esc(file.category || '')}</button>`],
    [t('info.tags'), `<div class="chips">${tags}</div>`],
    [t('info.date'), esc(file.created || t('undated'))],
    [t('info.modified'), esc(versionTimeLabel(file, t('undated')))],
    [t('info.format'), esc(file.fileType || '')],
    [t('info.file'), esc(file.filename || '')],
    [t('info.where'), `<span class="path">${esc(file.path)}</span>`],
  ];
  el.innerHTML = `
    <div class="info-thumb thumb" data-topic="${topic.key}">${src ? `<img src="${esc(src)}" alt="">` : ''}<div class="thumb-ph">${icon('doc')}<span>${esc(file.category || t('thumb.none'))}</span></div></div>
    <h3>${esc(file.title || file.filename)}</h3>
    <div class="info-actions">
      <button type="button" class="button primary small" data-act="open">${icon('openOut')}<span>${esc(t('open'))}</span></button>
      <button type="button" class="button small" data-act="copy" data-path="${esc(file.path)}">${icon('copy')}<span>${esc(t('copyPath'))}</span></button>
    </div>
    <dl>${rows.map(([k, v]) => `<dt>${esc(k)}</dt><dd>${v}</dd>`).join('')}</dl>
    ${file.description ? `<h4>${esc(t('info.summary'))}</h4><p class="summary">${esc(file.description)}</p>` : ''}
    ${file.keywords.length ? `<details class="keywords"><summary>${esc(t('info.keywords', file.keywords.length))}</summary><p>${file.keywords.map(esc).join(' · ')}</p></details>` : ''}
    ${versions.length > 1 ? `<h4>${esc(t('info.versions', versions.length))}</h4><div class="versions">${versions.map((v, i) => `
      <div class="version${v.path === file.path ? ' current' : ''}" data-path="${esc(v.path)}">
        <button type="button" class="version-main" data-act="show" data-path="${esc(v.path)}"><strong>${esc(versionTimeLabel(v, t('undated')))}</strong><span>${esc(v.filename)}${i === 0 ? ` · ${esc(t('info.latest'))}` : ''}</span></button>
        <button type="button" class="icon-button" data-act="open-version" data-path="${esc(v.path)}" title="${esc(t('open'))}" aria-label="${esc(t('open'))}">${icon('openOut')}</button>
      </div>`).join('')}</div>` : ''}
    <button type="button" class="link-button danger-text info-trash" data-act="trash">${icon('trash')}<span>${esc(t('trash'))}</span></button>`;
  paintDots(el);
  markLoaded(el);
}
