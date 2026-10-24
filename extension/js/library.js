// What is shown: search, filters, sort, version families and sidebar counts. No DOM here.
// 显示哪些资料：搜索、筛选、排序、版本组和侧边栏计数。这里不操作页面。

import { HTML_CONTROLLED, MD_CONTROLLED, CATEGORIES } from './vocab.js';

const DAY = 86400000;

export const normalise = value => String(value ?? '').normalize('NFKC').toLocaleLowerCase().replace(/\s+/g, ' ').trim();

/** Exact file time, used to order versions. / 文件时间（精确到秒），用于版本排序。 */
export const versionTime = file => {
  const parsed = Date.parse(String(file.modifiedAt || file.created || '').replace(' ', 'T'));
  return Number.isFinite(parsed) ? parsed : 0;
};
export const versionTimeLabel = (file, undated) => file.modifiedAt || (file.created ? `${file.created} 00:00:00` : undated);

/** Adds search text and sort keys to the helper's rows. / 给助手返回的记录加上搜索文本和排序用的字段。 */
export function prepare(rows) {
  const items = rows.map(row => ({
    ...row,
    tags: row.tags || [],
    keywords: row.keywords || [],
    _search: normalise([row.title, row.category, (row.tags || []).join(' '), (row.keywords || []).join(' '),
      row.description, row.filename, row.path, row.created].join(' ')),
    _time: versionTime(row),
  }));
  const families = groupVersions(items);
  for (const family of families) {
    for (const item of family.items) item._family = family.versioned ? family : null;
  }
  return items;
}

/**
 * Groups numbered variants of one file name in one folder: "name_2", "name-3", "name (2)", "name 副本 2".
 * The newest file comes first. Single files come back as their own one-item family.
 * 把同一文件夹里同名的编号变体归为一个版本组，最新的在前；单个文件自成一组。
 */
export function groupVersions(items) {
  const buckets = new Map();
  for (const item of items) {
    const basename = (item.filename || item.path.split('/').pop() || '').replace(/\.html?$/i, '');
    const match = basename.match(/^(.*?)(?:[_-]\d{1,3}|\s+\(\d{1,3}\)|\s+副本(?:\s*\d{1,3})?)$/i);
    const stem = (match ? match[1] : basename).normalize('NFKC').toLocaleLowerCase().replace(/[\s_-]+/g, ' ').trim();
    const folder = (item.path || '').slice(0, (item.path || '').lastIndexOf('/'));
    const key = `${folder}\u0000${stem}`;
    if (!buckets.has(key)) buckets.set(key, []);
    buckets.get(key).push({ item, numbered: !!match });
  }
  const families = [];
  for (const [key, bucket] of buckets) {
    const versions = bucket.map(x => x.item).sort((a, b) => versionTime(b) - versionTime(a) || (a.filename || '').localeCompare(b.filename || '', 'zh-CN'));
    if (versions.length > 1 && bucket.some(x => x.numbered)) families.push({ key, items: versions, versioned: true });
    else for (const item of versions) families.push({ key: item.path, items: [item], versioned: false });
  }
  return families;
}

export const isTagged = (file, tag) => file.tags.includes(tag) && (file.fileType === 'MD' || file.metadataManaged);
export const vocabularyFor = format => (format === 'MD' ? MD_CONTROLLED : HTML_CONTROLLED);

function inView(file, view, now) {
  if (view === 'all') return true;
  if (view === 'recent') return now - file._time < 7 * DAY;
  if (view === 'versions') return !!file._family;
  if (view.startsWith('cat:')) return file.category === view.slice(4);
  if (view.startsWith('tag:')) return isTagged(file, view.slice(4));
  return true;
}

function inDate(file, date) {
  if (!date) return true;
  return date === '__undated__' ? !file.created : file.created === date;
}

const SORTS = {
  newest: (a, b) => b._time - a._time || (a.title || '').localeCompare(b.title || '', 'zh-CN'),
  oldest: (a, b) => a._time - b._time || (a.title || '').localeCompare(b.title || '', 'zh-CN'),
  title: (a, b) => (a.title || '').localeCompare(b.title || '', 'zh-CN') || b._time - a._time,
};

/**
 * Filters and sorts. `items` is the flat list (list view, select all); `cards` puts each version
 * family on one card led by its newest file (grid view).
 * 筛选并排序。`items` 是平铺列表（列表视图、全选用）；`cards` 把每个版本组合成一张卡片，以最新版本为封面（网格视图）。
 */
export function compute(all, { view, search, date, format, sort }) {
  const now = Date.now();
  const terms = normalise(search).split(/\s+/).filter(Boolean);
  const items = all
    .filter(x => (!format || x.fileType === format) && inView(x, view, now) && inDate(x, date) && terms.every(term => x._search.includes(term)))
    .sort(SORTS[sort] || SORTS.newest);
  const cards = [];
  const seen = new Map();
  for (const item of items) {
    const family = item._family;
    if (!family) {
      cards.push({ key: item.path, item, versions: [item] });
      continue;
    }
    // Versions that match share one card; the newest matching version is the cover.
    // 同组中符合条件的版本共用一张卡片，封面是其中最新的版本。
    let card = seen.get(family.key);
    if (!card) {
      card = { key: `family:${family.key}`, item, versions: [] };
      seen.set(family.key, card);
      cards.push(card);
    }
    card.versions.push(item);
    if (item._time > card.item._time) card.item = item;
  }
  return { items, cards, families: [...seen.values()].filter(c => c.versions.length > 1).length };
}

/** Counts for the sidebar. / 侧边栏计数。 */
export function facets(all, format) {
  const now = Date.now();
  const scoped = format ? all.filter(x => x.fileType === format) : all;
  const categories = new Map(CATEGORIES.map(c => [c, 0]));
  for (const x of scoped) if (x.category) categories.set(x.category, (categories.get(x.category) || 0) + 1);
  const tags = new Map();
  for (const x of scoped) for (const tag of x.tags) if (isTagged(x, tag)) tags.set(tag, (tags.get(tag) || 0) + 1);
  return {
    all: scoped.length,
    recent: scoped.filter(x => inView(x, 'recent', now)).length,
    versions: scoped.filter(x => x._family).length,
    categories: [...categories],
    tags,
    hasMarkdown: all.some(x => x.fileType === 'MD'),
  };
}

/** Files per day for the calendar. / 日历上每天的文件数。 */
export function dayCounts(all, format) {
  const days = new Map();
  let undated = 0;
  for (const x of all) {
    if (format && x.fileType !== format) continue;
    if (x.created) days.set(x.created, (days.get(x.created) || 0) + 1);
    else undated++;
  }
  return { days, undated };
}
