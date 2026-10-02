// 搬家器 v3（按函数精确取范围）—— Round 11 的结论落地
// 用法：node mover3.js <类名> <id> <前缀...>   例：node mover3.js KmSite kmsvip _km
// 核心：① 扫描器跳过 //、/* */、'…'、"…"、'''…'''、"""…"""、${}
//       ② 每个目标函数：定义行 → 它的 { 配对 → 精确范围（含上方 /// 注释）
//       ③ 区间并集 → 搬走；判据：成员齐 / 无别站函数 / **无共享函数或字段的定义** / 删完仍以 } 收尾
const fs = require('fs');
const A = 'G:/ZCode/KPXX/lib/api.dart';
const [cls, id, ...prefixes] = process.argv.slice(2);
if (!cls || !id || !prefixes.length) { console.log('用法: node mover3.js <类名> <id> <前缀...>'); process.exit(1); }
const OUT = 'G:/ZCode/KPXX/lib/sites/' + id + '.dart';
if (fs.existsSync(OUT)) { console.log('⚠️ ' + OUT + ' 已存在，先删或改名'); process.exit(1); }

let src = fs.readFileSync(A, 'utf8');
const nl = src.includes('\r\n') ? '\r\n' : '\n';
const lines = src.split('\n');
const lineStart = []; { let p = 0; for (let i = 0; i < lines.length; i++) { lineStart.push(p); p += lines[i].length + 1; } }

// ---------- 扫描器：跳过注释/字符串 ----------
function skipAware(src) {
  // 返回一个函数：给字符位置，返回"该位置是否处于代码态"以及每个括号的配对
  const st = []; let i = 0;
  const codeState = new Uint8Array(src.length); // 1 = 代码态
  while (i < src.length) {
    const c = src[i], c2 = src.substr(i, 2), c3 = src.substr(i, 3);
    const s2 = st.length ? st[st.length - 1] : null;
    if (s2 === 's' || s2 === 'd') {
      const q = s2 === 's' ? "'" : '"';
      if (c === '\\') { i += 2; continue; }
      if (c3 === q + q + q) { st.pop(); i += 3; continue; }
      if (c === q) { st.pop(); i++; continue; }
      if (c === '$' && src[i + 1] === '{') { st.push('i'); i += 2; continue; }
      i++; continue;
    }
    if (s2 === 'i') { if (c === '{') { st.push('ib'); i++; continue; } if (c === '}') { st.pop(); i++; continue; } i++; continue; }
    if (c2 === '//') { const j = src.indexOf('\n', i); i = j < 0 ? src.length : j + 1; continue; }
    if (c2 === '/*') { const j = src.indexOf('*/', i + 2); i = j < 0 ? src.length : j + 2; continue; }
    if (c3 === "'''" || c3 === '"""') { st.push(c3[0] === "'" ? 's' : 'd'); i += 3; continue; }
    if (c === "'") { st.push('s'); i++; continue; }
    if (c === '"') { st.push('d'); i++; continue; }
    codeState[i] = 1;
    i++;
  }
  return codeState;
}
const codeState = skipAware(src);
function matchBrace(openPos) {
  const open = src[openPos];
  const close = open === '{' ? '}' : open === '(' ? ')' : ']';
  let d = 0;
  for (let i = openPos; i < src.length; i++) {
    if (!codeState[i]) continue;
    const c = src[i];
    if (c === open) d++;
    else if (c === close) { d--; if (d === 0) return i; }
  }
  return -1;
}

// ---------- 找目标函数的定义行 ----------
const isDefLine = (ln, names) => {
  const t = ln.trim();
  if (t.startsWith('//') || t.startsWith('*') || t.startsWith('/*')) return false;
  if (/^(return|await|if|for|while|switch|case|throw|final|var|assert)\b/.test(t)) return false;
  // ⚠️ 不再猜"类型长什么样" ✗（`Future<Map<String, dynamic>> _kmPost(` / `Uint8List _kmBytes(String hex) {`
  //    两种都能把正则玩坏 ✗ —— Round 12 连试三版都不行 ✓）。
  // ✅ 确定规则：名字 = **行内第一个 ( 之前**（没有就取第一个 = 之前）的**最后一个标识符** ✓
  const cuts = [ln.indexOf('('), ln.indexOf('=')].filter((x) => x > 0);
  if (!cuts.length) return null;
  const head = ln.slice(0, Math.min(...cuts));
  const ids = head.match(/[_A-Za-z][A-Za-z0-9_]*/g);
  if (!ids || !ids.length) return null;
  const nm = ids[ids.length - 1];
  if (!names.some((n) => nm.startsWith(n))) return null;
  return nm;
};
const targets = [];
for (let i = 0; i < lines.length; i++) {
  const nm = isDefLine(lines[i], prefixes);
  if (!nm) continue;
  const at = lineStart[i] + lines[i].indexOf(nm);
  const openRel = lines[i].slice(lines[i].indexOf(nm)).search(/[({=]/);
  const openPos = openRel < 0 ? -1 : (lineStart[i] + lines[i].indexOf(nm) + openRel);
  if (openPos < 0) continue;
  let endPos;
  if (src[openPos] === '=') {
    // 字段：到该行末尾的分号
    endPos = src.indexOf(';', openPos);
    if (endPos < 0) continue;
    const nextBrace = src.indexOf('{', openPos);
    if (nextBrace >= 0 && nextBrace < endPos) { const e2 = matchBrace(nextBrace); if (e2 > 0) endPos = e2; }
  } else if (src[openPos] === '(') {
    // ⚠️ 名字后第一个 ( 是**参数表** ✗ —— 必须再往后找**函数体**的 { 或 => ✓
    const paramsEnd = matchBrace(openPos);
    if (paramsEnd < 0) { console.log('  ❌ ' + nm + '（行 ' + (i + 1) + '）参数表配对失败'); process.exit(1); }
    let k = paramsEnd + 1;
    while (k < src.length && (src[k] === ' ' || src[k] === '\r' || src[k] === '\n' || src[k] === '\t')) k++;
    if (src.startsWith('async', k)) { k += 5; while (k < src.length && /\s/.test(src[k])) k++; }
    if (src[k] === '{') {
      endPos = matchBrace(k);
    } else if (src.startsWith('=>', k)) {
      let j2 = k + 2, d = 0;
      while (j2 < src.length) { if (!codeState[j2]) { j2++; continue; } const c = src[j2]; if (c === '(' || c === '[' || c === '{') d++; else if (c === ')' || c === ']' || c === '}') d--; else if (c === ';' && d === 0) break; j2++; }
      endPos = j2;
    } else {
      endPos = src.indexOf(';', paramsEnd); // 抽象/声明
    }
  } else {
    endPos = matchBrace(openPos);
  }
  if (endPos < 0) { console.log('  ❌ ' + nm + '（行 ' + (i + 1) + '）配对失败'); process.exit(1); }
  const endLine = src.slice(0, endPos).split('\n').length - 1;
  // 含上方 /// 注释
  let s = i; while (s - 1 > 0 && lines[s - 1].trim().startsWith('///')) s--;
  targets.push({ name: nm, line: i, start: s, endLine });
}
if (!targets.length) { console.log('❌ 没找到任何目标（前缀 ' + prefixes.join(',') + '）'); process.exit(1); }
console.log('  找到 ' + targets.length + ' 个成员：');
targets.forEach((t) => console.log('    ' + t.name.padEnd(14) + ' 行 ' + (t.start + 1) + '~' + (t.endLine + 1)));

// ⚠️ 硬判据：显式期望清单（少一个就中止 ✗ —— 2026-10-03 Round 12 实测：
//    `_kmPost` 因正则问题被漏掉 ✗ 而判据**没报** ✗，因为"期望"是"找到什么算什么" ✗）
const EXPECT = (process.env.EXPECT || '').split(',').map((s) => s.trim()).filter(Boolean);
if (EXPECT.length) {
  const got = new Set(targets.map((t) => t.name));
  const missing = EXPECT.filter((e) => !got.has(e));
  if (missing.length) { console.log('  ❌ 期望的成员没找到: ' + missing.join(', ')); process.exit(1); }
  const extra = [...got].filter((g) => !EXPECT.includes(g));
  if (extra.length) console.log('  ⚠️ 多找到（通常没事，确认下）: ' + extra.join(', '));
  console.log('  ✓ 期望清单 ' + EXPECT.length + ' 项全中');
}

// 去重（同一 name+line）
const seen = new Set(); const uniq = [];
for (const t of targets) { const k = t.name + '@' + t.line; if (seen.has(k)) continue; seen.add(k); uniq.push(t); }

// ---------- 判据 ①：不得含共享函数/字段的定义 ----------
const SHARED = ['videoSourcesAt', '_fetchSourcesAt', '_dplayerSources', '_hlsVariants', '_secClock', '_metaDate',
  '_seriesPrefix', '_unpackJs', '_cleanSubTitle', '_videoOrdinal', '_parseArticles', '_wpDetail', '_lazyCache',
  '_lazyInflight', '_toRelPath', '_seriesPrefix'];
const hits = [];
uniq.forEach((t) => { if (SHARED.includes(t.name)) hits.push(t.name + '(' + (t.line + 1) + ')'); });
if (hits.length) { console.log('  ❌ 目标里含共享成员的定义: ' + hits.join(', ')); process.exit(1); }
// ---------- 判据 ②：范围内不得整段包住别的成员（非目标前缀）----------
const foreign = [];
for (let i = 0; i < lines.length; i++) {
  const nm = isDefLine(lines[i], ['_']);
  if (!nm || prefixes.some((p) => nm.startsWith(p))) continue;
  if (SHARED.includes(nm)) continue; // 共享的另行处理
  const rel = lines[i].indexOf(nm);
  const openPos = lineStart[i] + rel + lines[i].slice(rel).search(/[({=]/);
  if (openPos < 0 || src[openPos] === '=') continue;
  const e = matchBrace(openPos);
  if (e < 0) continue;
  const eLine = src.slice(0, e).split('\n').length - 1;
  for (const t of uniq) if (i >= t.start && eLine <= t.endLine) { foreign.push(nm + '(' + (i + 1) + '~' + (eLine + 1) + ') ⊂ ' + t.name + '(' + (t.start + 1) + '~' + (t.endLine + 1) + ')'); break; }
}
if (foreign.length) { console.log('  ❌ 范围内包住了别的成员: ' + foreign.join(' | ')); process.exit(1); }
console.log('  ✓ 判据①②：无共享成员、无外来成员');

// ---------- 合并区间 ----------
uniq.sort((a, b) => a.start - b.start);
const merged = [];
for (const t of uniq) {
  const last = merged[merged.length - 1];
  if (last && t.start <= last.endLine + 2) last.endLine = Math.max(last.endLine, t.endLine);
  else merged.push({ start: t.start, endLine: t.endLine });
}
console.log('  区间: ' + merged.map((r) => (r.start + 1) + '~' + (r.endLine + 1)).join(', '));

// ---------- 组装 ----------
const section = merged.map((r) => lines.slice(r.start, r.endLine + 1).join('\n')).join('\n\n');
let body = section.replace(/(^|[^_\w])_fetchText\(/g, '$1_f.text(')
  .replace(/(^|[^_\w])_fetchAbs\(/g, '$1_f.abs(')
  .replace(/(^|[^_\w])_hlsVariants\(/g, '$1_f.hlsVariants(')
  .replace(/(^|[^_\w])_secClock\(/g, '$1secClock(')
  .replace(/(^|[^_\w])_metaDate\(/g, '$1metaDate(')
  .replace(/(^|[^_\w])_seriesPrefix\(/g, '$1seriesPrefix(')
  .replace(/(^|[^_\w])_dplayerSources\(/g, '$1dplayerSources(');
const defined = new Set(uniq.map((t) => t.name));
for (const m of body.matchAll(/^\s{2,}(?:static\s+)?(?:final\s+)?[A-Za-z_<>?,\[\]\. ]+\s+([_A-Za-z][A-Za-z0-9_]*)\s*[({=]/gm)) defined.add(m[1]);
const used = new Set();
for (const m of body.matchAll(/(^|[^_\w])(_[a-z][A-Za-z0-9_]*)\s*\(/g)) used.add(m[2]);
const BASE = ['_f', 'hlsVariants', 'secClock', 'metaDate', 'seriesPrefix', 'dplayerSources'];
const bad = [...used].filter((u) => !defined.has(u) && !BASE.includes(u));
console.log('  未处理的外部依赖: ' + (bad.join(', ') || '无 ✓'));
if (bad.length) { console.log('  ❌ 放弃'); process.exit(1); }

console.log('  ⚠️ 通过所有判据 —— 但**本次只打印、不写盘** ✓（mover3 先做干跑验证 ✓）');
console.log('  入口名（供 api.dart 改调用用）: ' + uniq.map((t) => t.name).join(', '));
console.log('  区间数: ' + merged.length + '  成员数: ' + uniq.length);
