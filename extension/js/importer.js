// "Import New HTML": find HTML files not in the index yet, check category and 2–4 tags, then import.
// The helper writes doc-meta, renders a thumbnail, moves root files into Manager_Files and updates the index.
// “收录新 HTML”：找出未收录的 HTML，核对分类和 2～4 个受控标签后收录。
// 本机助手负责写入 doc-meta、生成缩略图、把根目录文件移入 Manager_Files，并更新索引。

import { host } from './host.js';
import { groupVersions, versionTimeLabel } from './library.js';
import { HTML_CONTROLLED, TAG_GROUPS, CATEGORIES, isControlledTag } from './vocab.js';
import { fileURL } from './views.js';
import { icon, escapeHtml as esc, menu } from './ui.js';
import { t } from './i18n.js';

const sizeText = bytes => (bytes < 1024 ? `${bytes} B` : bytes < 1048576 ? `${Math.round(bytes / 1024)} KB` : `${(bytes / 1048576).toFixed(1)} MB`);

const MIN_TAGS = 2;
const MAX_TAGS = 4;

export class Importer {
  constructor(dialog, { folders, imported, failed }) {
    this.folders = folders;
    this.dialog = dialog;
    this.list = dialog.querySelector('.imp-list');
    this.status = dialog.querySelector('.imp-status');
    this.confirm = dialog.querySelector('[data-imp="confirm"]');
    this.toggleAll = dialog.querySelector('[data-imp="all"]');
    this.imported = imported;
    this.failed = failed;
    this.rows = [];
    this.busy = false;

    dialog.addEventListener('click', e => {
      if (e.target === dialog && !this.busy) return dialog.close();
      const b = e.target.closest('[data-imp]');
      if (!b) return;
      const row = this.rows[Number(b.closest('[data-index]')?.dataset.index)];
      switch (b.dataset.imp) {
        case 'close': return this.busy || dialog.close();
        case 'all': return this.selectAll();
        case 'confirm': return this.run();
        case 'add': return this.tagMenu(row, b);
        case 'remove':
          row.tags = row.tags.filter(x => x !== b.dataset.tag);
          this.renderRow(row);
          return this.update();
      }
    });
    dialog.addEventListener('change', e => {
      const index = e.target.closest('[data-index]')?.dataset.index;
      if (index === undefined) return;
      const row = this.rows[Number(index)];
      if (e.target.matches('.imp-check')) row.checked = e.target.checked;
      if (e.target.matches('.imp-cat')) row.category = e.target.value;
      this.renderRow(row);
      this.update();
    });
    dialog.addEventListener('cancel', e => this.busy && e.preventDefault());
  }

  /** Opens the sheet and scans for new files. / 打开面板并查找新文件。 */
  async open() {
    const f = this.folders();
    if (f) this.dialog.querySelector('.imp-head p').textContent = t('import.introFolders', f.inbox, f.library);
    if (!this.dialog.open) this.dialog.showModal();
    this.list.focus({ focusVisible: false });
    this.rows = [];
    this.toggleAll.hidden = true;
    this.setStatus(t('import.scanning'), true);
    this.list.replaceChildren();
    this.confirm.disabled = true;
    try {
      this.load(await host.discover());
    } catch (e) {
      this.setStatus(t('import.failedScan', e.message), false, true);
    }
  }

  load(candidates, message = '') {
    this.rows = candidates.map((item, index) => ({
      item,
      index,
      checked: false,
      category: CATEGORIES.includes(item.category) ? item.category : '工作与管理',
      tags: (item.tags || []).filter(isControlledTag).slice(0, MAX_TAGS),
    }));
    if (!this.rows.length) {
      this.list.innerHTML = `<div class="imp-empty">${icon('check')}<p>${esc(t('import.none'))}</p></div>`;
    } else {
      const byPath = new Map(this.rows.map(r => [r.item.path, r]));
      this.list.innerHTML = groupVersions(candidates).map(family => {
        if (!family.versioned) return this.rowHtml(byPath.get(family.items[0].path));
        const [latest] = family.items;
        return `<details class="imp-family"><summary>${icon('chevronRight')}<span><strong>${esc(latest.title || latest.filename)}</strong><small>${esc(t('import.family', family.items.length, versionTimeLabel(latest, '')))}</small></span></summary>${family.items.map((item, i) => this.rowHtml(byPath.get(item.path), i === 0)).join('')}</details>`;
      }).join('');
      for (const row of this.rows) this.renderRow(row);
    }
    this.update(message);
  }

  rowHtml(row, latest = false) {
    const x = row.item;
    return `<div class="imp-row" data-index="${row.index}">
      <input type="checkbox" class="imp-check" aria-label="${esc(x.title || x.filename)}">
      <div class="imp-main">
        <div class="imp-name">${esc(x.title || x.filename)}${latest ? `<span class="pill">${esc(t('import.latest'))}</span>` : ''}</div>
        <div class="imp-sub">${esc(versionTimeLabel(x, ''))} · ${esc(x.href || x.filename)} · <a href="${esc(fileURL(x.path))}" target="_blank" rel="noopener">${esc(t('import.preview'))}</a></div>
        ${x.attachments?.length ? `<div class="imp-attach">${esc(t('import.attachments', x.attachments.length, sizeText(x.attachments.reduce((n, a) => n + (a.size || 0), 0)), x.attachments.map(a => a.name).join(t('list.join'))))}</div>` : ''}
        <div class="imp-fields">
          <select class="select imp-cat" aria-label="${esc(t('info.category'))}">${CATEGORIES.map(c => `<option${c === row.category ? ' selected' : ''}>${esc(c)}</option>`).join('')}</select>
          <div class="imp-tags"></div>
        </div>
      </div>
    </div>`;
  }

  renderRow(row) {
    const el = this.list.querySelector(`[data-index="${row.index}"]`);
    const tags = el.querySelector('.imp-tags');
    const n = row.tags.length;
    const hint = n < MIN_TAGS ? t('import.needMore', MIN_TAGS - n) : n > MAX_TAGS ? t('import.tooMany') : '';
    tags.innerHTML = row.tags.map(tag => `<span class="chip">${esc(tag)}<button type="button" data-imp="remove" data-tag="${esc(tag)}" aria-label="${esc(t('import.removeTag', tag))}">${icon('close')}</button></span>`).join('')
      + (n < MAX_TAGS ? `<button type="button" class="chip add" data-imp="add">${icon('plus')}${esc(t('import.addTag'))}</button>` : '')
      + (hint ? `<span class="imp-hint${row.checked ? ' warn' : ''}">${esc(hint)}</span>` : '');
    el.classList.toggle('checked', row.checked);
  }

  tagMenu(row, anchor) {
    const items = [];
    for (const group of TAG_GROUPS) {
      items.push({ heading: group });
      for (const v of HTML_CONTROLLED.filter(x => x.group === group)) {
        const on = row.tags.includes(v.tag);
        items.push({
          label: v.tag,
          checked: on,
          disabled: !on && row.tags.length >= MAX_TAGS,
          action: () => {
            row.tags = on ? row.tags.filter(x => x !== v.tag) : [...row.tags, v.tag];
            // Ticking a tag is a clear sign the file should be imported. / 选了标签，说明这篇要收录。
            row.checked = true;
            this.list.querySelector(`[data-index="${row.index}"] .imp-check`).checked = true;
            this.renderRow(row);
            this.update();
          },
        });
      }
    }
    menu(items, anchor);
  }

  valid(row) {
    return CATEGORIES.includes(row.category) && row.tags.length >= MIN_TAGS && row.tags.length <= MAX_TAGS && row.tags.every(isControlledTag);
  }

  update(message = '') {
    if (!this.rows.length) {
      this.setStatus(message || t('import.none'));
      this.confirm.disabled = true;
      this.toggleAll.hidden = true;
      return;
    }
    const picked = this.rows.filter(r => r.checked);
    const bad = picked.filter(r => !this.valid(r));
    this.confirm.disabled = this.busy || !picked.length || bad.length > 0;
    this.toggleAll.hidden = false;
    this.toggleAll.textContent = picked.length === this.rows.length ? t('import.selectNone') : t('import.selectAll');
    if (!this.busy) this.setStatus(message || (bad.length ? t('import.fixFirst') : picked.length ? t('import.selected', picked.length) : t('import.found', this.rows.length)), false, bad.length > 0 && !message);
  }

  selectAll() {
    const all = this.rows.every(r => r.checked);
    for (const row of this.rows) {
      row.checked = !all;
      this.list.querySelector(`[data-index="${row.index}"] .imp-check`).checked = !all;
      this.renderRow(row);
    }
    this.update();
  }

  setStatus(text, spinning = false, warn = false) {
    this.status.innerHTML = `${spinning ? '<span class="spinner small"></span>' : ''}<span></span>`;
    this.status.lastChild.textContent = text;
    this.status.classList.toggle('warn', warn);
  }

  async run() {
    const picked = this.rows.filter(r => r.checked);
    if (!picked.length || picked.some(r => !this.valid(r))) return;
    const paths = picked.map(r => r.item.href);
    const metadata = Object.fromEntries(picked.map(r => [r.item.href, { category: r.category, tags: r.tags }]));
    this.busy = true;
    this.dialog.classList.add('busy');
    this.confirm.disabled = true;
    this.setStatus(t('import.working', paths.length), true);
    try {
      const result = await host.import(paths, metadata);
      let left = [];
      try {
        left = await host.discover();
      } catch {
        left = this.rows.filter(r => !r.checked).map(r => r.item);
      }
      this.busy = false;
      this.load(left, t('import.done', result.imported || paths.length, left.length));
      this.imported(result, left);
    } catch (e) {
      this.busy = false;
      this.update();
      this.setStatus(e.timeout ? t('toast.timeout') : t('import.failed', e.message), false, true);
      this.failed(e);
    } finally {
      this.busy = false;
      this.dialog.classList.remove('busy');
    }
  }
}
