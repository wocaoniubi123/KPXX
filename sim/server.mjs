// KPXX 数据/界面模拟器 —— 本地小服务
//
// 只干三件事：
//   1. 托管 sim/index.html（手机界面模拟页）
//   2. /proxy?url=...  转发站点请求（浏览器直连会被 CORS 拦，站点 HTML 不给跨域头）
//   3. 本文件被改动时自动重启自己（改服务端逻辑不用手动重开模拟器）
//
// 零依赖：只用 Node 内置模块。启动：
//     node sim/server.mjs
// 然后浏览器打开提示的地址（改完页面刷新即可，不用重新构建 App）。
import http from 'node:http';
import https from 'node:https';
import net from 'node:net';
import tls from 'node:tls';
import { execSync, spawn } from 'node:child_process';
import { readFile } from 'node:fs/promises';
import { watch } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const PORT = Number(process.env.KPXX_PORT || 8787);
const DIR = dirname(fileURLToPath(import.meta.url));
const SITES_DART = join(DIR, '..', 'lib', 'sites.dart');

// 与 App 里 config.dart / api.dart / player_widget.dart 保持一致
const UA =
  'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) ' +
  'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1';

/** 文件里 `const List<SiteTab> _xxx = [ ... ]` 形式的具名子分类表（供下面的引用解析） */
function parseNamedTabLists(src) {
  const map = new Map();
  const re = /const\s+List<SiteTab>\s+(\w+)\s*=\s*\[/g;
  let m;
  while ((m = re.exec(src))) {
    let depth = 0;
    let j = m.index + m[0].length - 1;
    for (; j < src.length; j++) {
      if (src[j] === '[') depth++;
      else if (src[j] === ']') {
        depth--;
        if (depth === 0) break;
      }
    }
    map.set(m[1], parseTabs(src.slice(m.index + m[0].length, j + 1), map));
  }
  return map;
}

/** 把 `categories: [ SiteTab('k','n',[SiteTab(...)]) ]` 解析成 tab 树。
 *  第三个参数可以是内联数组，也可以是文件里定义的常量名（如 _hgSorts）。 */
function parseTabs(block, named = new Map()) {
  const out = [];
  let i = 0;
  while (true) {
    const at = block.indexOf('SiteTab(', i);
    if (at < 0) break;
    let depth = 0;
    let j = at + 'SiteTab('.length - 1;
    for (; j < block.length; j++) {
      if (block[j] === '(') depth++;
      else if (block[j] === ')') {
        depth--;
        if (depth === 0) break;
      }
    }
    const raw = block.slice(at + 'SiteTab('.length, j);
    const km = /^\s*'([^']*)'\s*,\s*'([^']*)'/.exec(raw);
    let subs = [];
    const s0 = raw.indexOf('[');
    if (s0 >= 0) {
      const s1 = raw.lastIndexOf(']');
      subs = parseTabs(raw.slice(s0, s1 + 1), named);
    } else {
      // 引用常量：SiteTab('k','n', _hgSorts)
      const ref = /^\s*'[^']*'\s*,\s*'[^']*'\s*,\s*(\w+)/.exec(raw);
      if (ref && named.has(ref[1])) subs = named.get(ref[1]);
    }
    if (km) out.push({ key: km[1], name: km[2], subs });
    i = j + 1;
  }
  return out;
}

/** 把 lib/sites.dart 解析成 JSON。
 *  站点清单只有这一份来源（改 Dart 文件这里自动跟着变，不会两边写两遍）。
 *  只认这个文件的固定格式；解析不出东西就返回 error，宁可报错也不给假数据。 */
async function loadSites() {
  const src = await readFile(SITES_DART, 'utf8');
  const start = src.indexOf('const List<SiteEntry> kSites');
  if (start < 0) return { error: '没在 lib/sites.dart 里找到 kSites' };
  const body = src.slice(start);

  // 具名子分类表（const List<SiteTab> _xxx = [...]），SiteTab 第三参可以引用它
  const namedTabs = parseNamedTabLists(src);

  // 按括号配对切出每个 SiteEntry(...)
  const blocks = [];
  let i = 0;
  while (true) {
    const at = body.indexOf('SiteEntry(', i);
    if (at < 0) break;
    let depth = 0;
    let j = at + 'SiteEntry('.length - 1;
    for (; j < body.length; j++) {
      if (body[j] === '(') depth++;
      else if (body[j] === ')') {
        depth--;
        if (depth === 0) break;
      }
    }
    blocks.push(body.slice(at, j + 1));
    i = j + 1;
  }

  const pick = (b, re) => {
    const m = re.exec(b);
    return m ? m[1] : '';
  };
  const listOf = (b, re) => [...b.matchAll(re)].map((m) => m[1]);

  const sites = blocks
    .map((b) => {
      const hostsBlock = /hosts:\s*\[([^\]]*)\]/.exec(b);
      // categories 块用括号配对提取：不能要求后面紧跟 "color:"——
      // Pektino 这类条目在 categories 和 color 之间还有 filters:
      const catsBlock = (() => {
        const at = b.indexOf('categories:');
        if (at < 0) return null;
        const s0 = b.indexOf('[', at);
        if (s0 < 0 || s0 - at > 40) return null;
        let depth = 0;
        for (let k = s0; k < b.length; k++) {
          if (b[k] === '[') depth++;
          else if (b[k] === ']') {
            depth--;
            if (depth === 0) return [null, b.slice(s0 + 1, k)];
          }
        }
        return null;
      })();
      return {
        name: pick(b, /name:\s*'([^']*)'/),
        kind: /kind:\s*SiteKind\.web/.test(b) ? 'web' : 'native',
        template: pick(b, /template:\s*SiteTemplate\.(\w+)/) || 'wordpress',
        portraitCovers: /portraitCovers:\s*true/.test(b),
        showRelated: !/showRelated:\s*false/.test(b),
        iconUrl: pick(b, /iconUrl:\s*'([^']*)'/),
        url: pick(b, /\burl:\s*'([^']*)'/),
        hosts: hostsBlock ? listOf(hostsBlock[1], /'([^']+)'/g) : [],
        categories: catsBlock ? parseTabs(catsBlock[1], namedTabs) : [],
        color: pick(b, /color:\s*Color\(0x([0-9A-Fa-f]+)\)/) || 'FF7043',
      };
    })
    .filter((s) => s.name);

  return { sites };
}

/* -------------------------------------------------------------------------
   代理支持
   本机（以及不少国内环境）浏览器走系统代理才能访问这些站点，
   而 Node 默认不走系统代理 → 直连全部超时。这里自动探测并跟随：
     1) 环境变量 https_proxy / HTTPS_PROXY / http_proxy / HTTP_PROXY
     2) Windows 注册表的系统代理（ProxyEnable=1 时的 ProxyServer）
   ------------------------------------------------------------------------- */
function detectProxy() {
  for (const k of ['https_proxy', 'HTTPS_PROXY', 'http_proxy', 'HTTP_PROXY', 'all_proxy', 'ALL_PROXY']) {
    const v = process.env[k];
    if (v) {
      try {
        const u = new URL(v.includes('://') ? v : 'http://' + v);
        return { host: u.hostname, port: Number(u.port || 80) };
      } catch (e) {}
    }
  }
  if (process.platform === 'win32') {
    try {
      const key = 'HKCU\\Software\\Microsoft\\Windows\\CurrentVersion\\Internet Settings';
      const q = (name) =>
        execSync(`reg query "${key}" /v ${name}`, { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] });
      const enabled = /0x1/.test(q('ProxyEnable'));
      if (enabled) {
        const raw = /REG_SZ\s+(.+)/.exec(q('ProxyServer'));
        if (raw) {
          // 可能是 "127.0.0.1:7890"，也可能是 "http=...;https=..."
          let val = raw[1].trim();
          const m = /https=([^;]+)/.exec(val);
          if (m) val = m[1];
          else if (val.includes('=')) val = (val.split(';').map((x) => x.split('=')[1]).filter(Boolean)[0] || '');
          const [h, pt] = val.split(':');
          if (h && pt) return { host: h.trim(), port: Number(pt.trim()) };
        }
      }
    } catch (e) {}
  }
  return null;
}

/** 列表/图标/代理/vproxy 共用（CORS 头）——模块级，handleRequest 和 streamVideo 都要用 */
const cors = {
  'Access-Control-Allow-Origin': '*',
  'Cache-Control': 'no-store',
};

const PROXY = detectProxy();

/** 手写 HTTP 响应解析（含 chunked），给走代理的隧道用 */
function decodeChunked(buf) {
  const out = [];
  let i = 0;
  while (i < buf.length) {
    const j = buf.indexOf('\r\n', i);
    if (j < 0) break;
    const size = parseInt(buf.slice(i, j).toString('latin1').split(';')[0], 16);
    if (!size) break;
    out.push(buf.slice(j + 2, j + 2 + size));
    i = j + 2 + size + 2;
  }
  return Buffer.concat(out);
}
function parseHttpResponse(buf) {
  const idx = buf.indexOf('\r\n\r\n');
  if (idx < 0) return null;
  const head = buf.slice(0, idx).toString('latin1').split('\r\n');
  const status = parseInt(head[0].split(' ')[1] || '0', 10);
  const headers = {};
  for (const line of head.slice(1)) {
    const k = line.indexOf(':');
    if (k > 0) headers[line.slice(0, k).trim().toLowerCase()] = line.slice(k + 1).trim();
  }
  let body = buf.slice(idx + 4);
  if ((headers['transfer-encoding'] || '').includes('chunked')) body = decodeChunked(body);
  return { status, headers, body };
}

/** 通过 HTTP 代理抓 HTTPS：CONNECT 隧道 + TLS + 手写 HTTP */
function viaProxy(u, headers, timeoutMs) {
  return new Promise((resolve, reject) => {
    const sock = net.connect(PROXY.port, PROXY.host);
    let settled = false;
    const fail = (e) => {
      if (settled) return;
      settled = true;
      try { sock.destroy(); } catch (err) {}
      reject(e);
    };
    sock.setTimeout(timeoutMs, () => fail(new Error('代理连接超时')));
    sock.on('error', fail);
    sock.on('connect', () => {
      sock.write(
        `CONNECT ${u.hostname}:443 HTTP/1.1\r\nHost: ${u.hostname}:443\r\n` +
          `Proxy-Connection: keep-alive\r\n\r\n`
      );
    });
    let hs = Buffer.alloc(0);
    const onHs = (d) => {
      hs = Buffer.concat([hs, d]);
      const idx = hs.indexOf('\r\n\r\n');
      if (idx < 0) return;
      sock.removeListener('data', onHs);
      const status = parseInt(hs.slice(0, idx).toString('latin1').split(' ')[1] || '0', 10);
      if (status !== 200) return fail(new Error('代理 CONNECT 返回 ' + status));
      const tlsSock = tls.connect({ socket: sock, servername: u.hostname }, () => {
        const lines = Object.entries(headers).map(([k, v]) => `${k}: ${v}\r\n`).join('');
        tlsSock.write(
          `GET ${u.pathname}${u.search} HTTP/1.1\r\nHost: ${u.host}\r\n${lines}` +
            'Accept-Encoding: identity\r\nConnection: close\r\n\r\n'
        );
      });
      const chunks = [];
      tlsSock.on('data', (c) => chunks.push(c));
      tlsSock.on('end', () => {
        if (settled) return;
        settled = true;
        const r = parseHttpResponse(Buffer.concat(chunks));
        if (!r) return reject(new Error('代理响应解析失败'));
        resolve({ status: r.status, headers: r.headers, body: r.body });
      });
      tlsSock.on('error', fail);
    };
    sock.on('data', onHs);
  });
}

/** /vproxy：**视频中转（流式）**。
 *  内置浏览器直连被墙的视频 CDN（如 video.twimg.com）时，由 Node（跟随系统代理）
 *  去拉、边收边转给播放器；转发 Range 头、回传 206/Content-Range（拖进度条能用）。
 *  仅模拟器用——App 是直连架构，不经过这里。 */
function streamVideo(req, res, targetUrl) {
  let u;
  try {
    u = new URL(targetUrl);
  } catch (e) {
    res.writeHead(400, { ...cors, 'Content-Type': 'text/plain; charset=utf-8' });
    res.end('URL 不合法');
    return;
  }
  const hdrs = {
    'User-Agent': UA,
    Referer: `${u.protocol}//${u.host}/`,
    'Accept-Encoding': 'identity',
    Accept: '*/*',
    ...(req.headers.range ? { Range: req.headers.range } : {}),
  };
  let settled = false; // 头一旦发出，后面的错误只能断流（不能再改状态码）
  const fail = (e) => {
    if (settled) return;
    settled = true;
    try {
      res.writeHead(502, { ...cors, 'Content-Type': 'text/plain; charset=utf-8' });
      res.end('中转失败：' + ((e && e.message) || e));
    } catch (_) {}
  };
  const PASS = ['content-type', 'content-length', 'content-range', 'accept-ranges', 'last-modified', 'etag'];
  const pickHeaders = (raw) => {
    const out = {};
    for (const [k, v] of raw) {
      if (PASS.includes(k)) out[k] = v;
    }
    return out;
  };

  if (PROXY && u.protocol === 'https:') {
    // CONNECT 隧道 + TLS，流式解析响应头后直接回传 body
    const sock = net.connect(PROXY.port, PROXY.host);
    const die = (e) => {
      try { sock.destroy(); } catch (_) {}
      fail(e);
    };
    sock.setTimeout(30000, () => die(new Error('代理连接超时')));
    sock.on('error', die);
    sock.on('connect', () => {
      sock.write(
        `CONNECT ${u.hostname}:443 HTTP/1.1\r\nHost: ${u.hostname}:443\r\n` +
          `Proxy-Connection: keep-alive\r\n\r\n`
      );
    });
    let hs = Buffer.alloc(0);
    const onHs = (d) => {
      hs = Buffer.concat([hs, d]);
      const idx = hs.indexOf('\r\n\r\n');
      if (idx < 0) return;
      sock.removeListener('data', onHs);
      const status = parseInt(hs.slice(0, idx).toString('latin1').split(' ')[1] || '0', 10);
      if (status !== 200) return die(new Error('代理 CONNECT 返回 ' + status));
      const tlsSock = tls.connect({ socket: sock, servername: u.hostname }, () => {
        const lines = Object.entries(hdrs).map(([k, v]) => `${k}: ${v}\r\n`).join('');
        tlsSock.write(
          `GET ${u.pathname}${u.search} HTTP/1.1\r\nHost: ${u.host}\r\n${lines}Connection: close\r\n\r\n`
        );
      });
      let head = Buffer.alloc(0);
      let headDone = false;
      tlsSock.on('data', (c) => {
        if (headDone) {
          res.write(c); // 已在流式回传，直接转发
          return;
        }
        head = Buffer.concat([head, c]);
        const cut = head.indexOf('\r\n\r\n');
        if (cut < 0) return;
        headDone = true;
        const hLines = head.slice(0, cut).toString('latin1').split('\r\n');
        const st = parseInt(hLines[0].split(' ')[1] || '0', 10) || 502;
        const out = {};
        for (const line of hLines.slice(1)) {
          const k = line.indexOf(':');
          if (k <= 0) continue;
          const key = line.slice(0, k).trim().toLowerCase();
          if (PASS.includes(key)) out[key] = line.slice(k + 1).trim();
        }
        settled = true;
        res.writeHead(st, { ...cors, ...out });
        const rest = head.slice(cut + 4);
        if (rest.length) res.write(rest);
      });
      tlsSock.on('end', () => { try { res.end(); } catch (_) {} });
      tlsSock.on('error', (e) => {
        if (!settled) die(e);
        else { try { res.destroy(); } catch (_) {} }
      });
    };
    sock.on('data', onHs);
    return;
  }

  // 直连兜底（没检测到代理 / http 地址）：Node 原生流式转发
  const lib = u.protocol === 'https:' ? https : http;
  const preq = lib.get(u, { headers: hdrs }, (pres) => {
    settled = true;
    res.writeHead(pres.statusCode || 502, { ...cors, ...pickHeaders(Object.entries(pres.headers)) });
    pres.pipe(res);
  });
  preq.setTimeout(30000, () => { try { preq.destroy(); } catch (_) {} });
  preq.on('error', (e) => {
    if (!settled) fail(e);
  });
}

/** 带重定向跟随的 GET（最多 5 跳），返回 { status, headers, body } */
function fetchUrl(url, redirects = 0, timeoutMs = 20000) {
  return new Promise((resolve, reject) => {
    let u;
    try {
      u = new URL(url);
    } catch (e) {
      reject(new Error('URL 不合法: ' + url));
      return;
    }
    const hdrs = {
      'User-Agent': UA,
      Referer: `${u.protocol}//${u.host}/`,
      Accept: 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
      'Accept-Language': 'zh-CN,zh;q=0.9',
    };
    if (PROXY && u.protocol === 'https:') {
      viaProxy(u, hdrs, timeoutMs)
        .then((r) => {
          const code = r.status;
          if ([301, 302, 303, 307, 308].includes(code) && r.headers.location && redirects < 5) {
            resolve(fetchUrl(new URL(r.headers.location, u).href, redirects + 1, timeoutMs));
            return;
          }
          resolve(r);
        })
        .catch(reject);
      return;
    }
    const lib = u.protocol === 'https:' ? https : http;
    const req = lib.get(
      u,
      {
        headers: {
          'User-Agent': UA,
          Referer: `${u.protocol}//${u.host}/`,
          Accept: 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
          'Accept-Language': 'zh-CN,zh;q=0.9',
        },
      },
      (res) => {
        const code = res.statusCode || 0;
        if ([301, 302, 303, 307, 308].includes(code) && res.headers.location && redirects < 5) {
          res.resume();
          resolve(fetchUrl(new URL(res.headers.location, u).href, redirects + 1, timeoutMs));
          return;
        }
        const chunks = [];
        res.on('data', (c) => chunks.push(c));
        res.on('end', () =>
          resolve({ status: code, headers: res.headers, body: Buffer.concat(chunks) })
        );
      }
    );
    req.on('error', reject);
    req.setTimeout(timeoutMs, () => req.destroy(new Error('请求超时')));
  });
}

/** 记住每个站点最近跑通的域名（同 App 的 Api._host） */
const preferred = new Map();

/** 按站点名 + 站内路径抓取：依次试 hosts，跑通的记住下次优先。
 *  本机网络下有些域名连不上（浏览器能通、Node 不通），所以必须逐个试。 */
async function fetchSite(name, path) {
  const data = await loadSites();
  const site = (data.sites || []).find((s) => s.name === name);
  if (!site) throw new Error('未知站点：' + name);
  const order = [...new Set([preferred.get(name), ...site.hosts].filter(Boolean))];
  const tried = [];
  for (const h of order) {
    // 5xx 是站点偶发（51fans1 实测会间歇性 500），同一个域名再试一次
    for (let attempt = 0; attempt < 2; attempt++) {
      try {
        // 超时给宽一点：51fans1 这类站冷启动要 3s+，加上浏览器同时拉一堆封面图，
        // 6s 会偶发"代理连接超时"（App 侧是 8s，站点点慢就会一直加载失败）
        const r = await fetchUrl('https://' + h + path, 0, 12000);
        if (r.status === 200) {
          if (preferred.get(name) !== h) console.log(`[站点] ${name} 用 ${h}${path}`);
          preferred.set(name, h);
          return { ...r, host: h };
        }
        tried.push(`${h} HTTP ${r.status}`);
        if (r.status < 500) break; // 4xx 重试没用
      } catch (e) {
        tried.push(`${h} ${e.message}`);
        break; // 超时/连接失败：换下一个域名
      }
    }
  }
  throw new Error(`所有域名均无法访问：${tried.join('；')}`);
}

async function handleRequest(req, res) {
  const me = new URL(req.url, `http://localhost:${PORT}`);

  try {
    if (me.pathname === '/' || me.pathname === '/index.html') {
      const html = await readFile(join(DIR, 'index.html'));
      res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8', ...cors });
      res.end(html);
      return;
    }

    if (me.pathname === '/sites') {
      const data = await loadSites();
      res.writeHead(200, { 'Content-Type': 'application/json; charset=utf-8', ...cors });
      res.end(JSON.stringify(data));
      return;
    }

    if (me.pathname === '/icon') {
      const name = me.searchParams.get('name') || '';
      const data = await loadSites();
      const site = (data.sites || []).find((s) => s.name === name);
      if (!site || !site.iconUrl) {
        res.writeHead(404, { ...cors });
        res.end();
        return;
      }
      // 绝对地址（如 hanime1 的 tab_logo.png 带签名）直接抓；站内路径走"逐域名试"
      const abs = /^https?:\/\//i.test(site.iconUrl);
      const p = site.iconUrl.startsWith('/') ? site.iconUrl : '/' + site.iconUrl;
      const r = abs ? await fetchUrl(site.iconUrl) : await fetchSite(name, p);
      res.writeHead(200, {
        'Content-Type': r.headers['content-type'] || 'image/x-icon',
        'X-Sim-Host': r.host || '',
        ...cors,
      });
      res.end(r.body);
      return;
    }

    if (me.pathname === '/site') {
      const name = me.searchParams.get('name') || '';
      const path = me.searchParams.get('path') || '/';
      const r = await fetchSite(name, path);
      res.writeHead(200, {
        'Content-Type': r.headers['content-type'] || 'text/html; charset=utf-8',
        'X-Sim-Host': r.host,
        ...cors,
      });
      res.end(r.body);
      return;
    }

    if (me.pathname === '/proxy') {
      const target = me.searchParams.get('url');
      if (!target) {
        res.writeHead(400, { 'Content-Type': 'text/plain; charset=utf-8', ...cors });
        res.end('缺少 url 参数');
        return;
      }
      const r = await fetchUrl(target);
      res.writeHead(r.status, {
        'Content-Type': r.headers['content-type'] || 'application/octet-stream',
        ...cors,
      });
      res.end(r.body);
      return;
    }

    if (me.pathname === '/vproxy') {
      // 视频中转（流式，支持 Range）：见 streamVideo 注释
      const target = me.searchParams.get('url');
      if (!target) {
        res.writeHead(400, { 'Content-Type': 'text/plain; charset=utf-8', ...cors });
        res.end('缺少 url 参数');
        return;
      }
      streamVideo(req, res, target);
      return;
    }

    res.writeHead(404, { 'Content-Type': 'text/plain; charset=utf-8', ...cors });
    res.end('not found');
  } catch (e) {
    res.writeHead(500, { 'Content-Type': 'text/plain; charset=utf-8', ...cors });
    res.end(String(e && e.message ? e.message : e));
  }
}

/** 监听端口；被占用就等一会儿再试（热重载时新旧进程会短暂抢同一个端口） */
let activeServer = null; // 当前在监听的 server（热重载时要先关掉它，把端口让出来）

function listen(attempt = 0) {
  const server = http.createServer(handleRequest);
  activeServer = server;
  server.once('error', (err) => {
    if (err.code === 'EADDRINUSE' && attempt < 20) {
      setTimeout(() => listen(attempt + 1), 500);
    } else {
      console.error(`启动失败：${err.message}`);
      process.exit(1);
    }
  });
  server.listen(PORT, () => {
    console.log(PROXY ? `出站代理：${PROXY.host}:${PROXY.port}` : '出站代理：未检测到（直连）');
    console.log(`KPXX 模拟器已启动： http://localhost:${PORT}`);
    console.log(`（index.html 与 lib/sites.dart 每次请求现读，改完刷新页面即可）`);
    console.log(`（本文件 server.mjs 改动会自动重启，不用手动重开）`);
    console.log(`停止：Ctrl+C`);
  });
}
listen();

/* ---- 自热重载：server.mjs 变了就自动重启自己 ----
   index.html 每次请求现读、lib/sites.dart 每次请求现解析，都不需要重启；
   只有本文件是服务端逻辑，改了不重启不生效 —— 所以这里盯着自己重起。
   想关掉：KPXX_NO_RELOAD=1 node sim/server.mjs */
if (!process.env.KPXX_NO_RELOAD) {
  let reloading = false;
  const reload = () => {
    if (reloading) return;
    reloading = true;
    console.log('[热重载] server.mjs 变了，自动重启…');
    // 先关掉自己占的端口，新进程才能立刻接上（否则要等重试窗口）
    try { activeServer && activeServer.close(); } catch (e) {}
    try {
      const child = spawn(process.execPath, [fileURLToPath(import.meta.url)], {
        detached: true,
        stdio: 'inherit',
        env: process.env,
      });
      child.unref();
    } catch (e) {
      console.error('[热重载] 启动新进程失败：' + e.message);
      reloading = false;
      return;
    }
    setTimeout(() => process.exit(0), 150);
  };
  try {
    // 盯目录而不是盯文件：编辑器保存常是"替换文件"，盯文件会跟丢
    watch(DIR, (_ev, fname) => {
      if (fname && String(fname).toLowerCase().endsWith('server.mjs')) reload();
    });
  } catch (e) {
    console.log('热重载不可用（不影响使用）：' + e.message);
  }
}
