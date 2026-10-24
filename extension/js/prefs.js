// Display preferences for this browser only (view, sort, card size, folded sidebar sections, Info panel).
// Documents and their metadata live in ~/Downloads, never here, so losing these only resets the look.
// 仅本浏览器的显示偏好（视图、排序、卡片大小、折叠的侧边栏分区、信息面板）。资料本身在“下载”文件夹，
// 这里丢失只会恢复默认外观。

const KEY = 'manager.prefs.v1';
const DEFAULTS = { layout: 'grid', sort: 'newest', cardSize: 220, collapsed: [], infoOpen: false };

let saved = {};
try {
  saved = JSON.parse(localStorage.getItem(KEY) || '{}') || {};
} catch {}

export const prefs = { ...DEFAULTS, ...saved };

export function setPref(key, value) {
  prefs[key] = value;
  try {
    localStorage.setItem(KEY, JSON.stringify(prefs));
  } catch {}
}
