// The date filter: a month calendar that marks days with documents, plus "No date".
// 日期筛选：标出有资料的日子的月历，另有“未注明日期”。

import { escapeHtml as esc, icon } from './ui.js';
import { t } from './i18n.js';

const pad = n => String(n).padStart(2, '0');

export class Calendar {
  constructor(el, { picked }) {
    this.el = el;
    this.picked = picked;
    const now = new Date();
    this.month = new Date(now.getFullYear(), now.getMonth(), 1);
    this.value = '';
    this.counts = { days: new Map(), undated: 0 };
    el.addEventListener('click', e => {
      const b = e.target.closest('button');
      if (!b || b.disabled) return;
      if (b.dataset.nav) {
        this.month.setMonth(this.month.getMonth() + Number(b.dataset.nav));
        return this.render();
      }
      if (b.dataset.date !== undefined) this.picked(b.dataset.date === this.value ? '' : b.dataset.date);
    });
  }

  /** Opens on the month of the chosen day, or the newest month with documents. / 打开时显示所选日期或最近有资料的月份。 */
  show(counts, value) {
    this.counts = counts;
    this.value = value;
    const anchor = value && value !== '__undated__' ? value : [...counts.days.keys()].sort().pop();
    if (anchor) this.month = new Date(Number(anchor.slice(0, 4)), Number(anchor.slice(5, 7)) - 1, 1);
    this.render();
  }

  render() {
    const y = this.month.getFullYear();
    const m = this.month.getMonth();
    const offset = (new Date(y, m, 1).getDay() + 6) % 7;
    const days = new Date(y, m + 1, 0).getDate();
    const cells = Array(offset).fill('<span></span>');
    for (let d = 1; d <= days; d++) {
      const date = `${y}-${pad(m + 1)}-${pad(d)}`;
      const n = this.counts.days.get(date) || 0;
      cells.push(`<button type="button" class="cal-day${n ? ' has' : ''}${this.value === date ? ' picked' : ''}" data-date="${date}" ${n ? '' : 'disabled'} title="${esc(t('date.label', m + 1, d))}${n ? ` · ${esc(t('date.files', n))}` : ''}"><span>${d}</span>${n ? `<small>${n}</small>` : ''}</button>`);
    }
    this.el.innerHTML = `
      <div class="cal-head">
        <button type="button" class="icon-button" data-nav="-1" aria-label="${esc(t('date.prev'))}">${icon('chevronLeft')}</button>
        <strong>${esc(t('date.month', y, m + 1))}</strong>
        <button type="button" class="icon-button" data-nav="1" aria-label="${esc(t('date.next'))}">${icon('chevronRight')}</button>
      </div>
      <div class="cal-week">${t('date.weekdays').split('|').map(w => `<span>${esc(w)}</span>`).join('')}</div>
      <div class="cal-grid">${cells.join('')}</div>
      <div class="cal-foot">
        ${this.counts.undated ? `<button type="button" class="cal-undated${this.value === '__undated__' ? ' picked' : ''}" data-date="__undated__"><span>${esc(t('date.undated'))}</span><small>${esc(t('date.files', this.counts.undated))}</small></button>` : '<span></span>'}
        <button type="button" class="button small plain" data-date="" ${this.value ? '' : 'disabled'}>${esc(t('date.clear'))}</button>
      </div>`;
  }
}

export function dateLabel(value) {
  if (!value) return t('date.button');
  if (value === '__undated__') return t('date.undated');
  return t('date.label', Number(value.slice(5, 7)), Number(value.slice(8, 10)));
}
