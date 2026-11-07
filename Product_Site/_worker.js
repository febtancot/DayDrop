import catalog from './release-catalog.js';
import { authenticated, authAction } from './stats-auth.js';

const TIME_ZONE = 'Asia/Shanghai';
const DAY_MS = 86400000;
const kinds = ['website', 'update', 'check', 'direct'];
export function dayInShanghai(date = new Date()) {
  return new Date(date.getTime() + 8 * 3600000).toISOString().slice(0, 10);
}

// Request counts, never unique users or completed installations. No identifiers
// or raw user agents are stored. Only known versions can become SQL dimensions.
export function classify(request, response) {
  const url = new URL(request.url);
  const agent = request.headers.get('user-agent') || '';
  if (request.method !== 'GET' || url.searchParams.has('verify') ||
      /bot|crawler|spider|headless|curl|wget/i.test(agent) ||
      /prefetch|prerender/i.test(`${request.headers.get('purpose')} ${request.headers.get('sec-purpose')}`)) return null;
  const sparkle = /\bSparkle\//i.test(agent) && /\bDayDrop\//i.test(agent);
  if (url.pathname === '/updates/appcast.xml') {
    if (!sparkle || ![200, 304].includes(response.status)) return null;
    const version = agent.match(/\bDayDrop\/([\d.]+)/i)?.[1];
    return { kind: 'check', version: catalog.versions.includes(version) ? version : 'unknown', packageType: 'feed' };
  }
  const asset = catalog.assets[url.pathname];
  if (!asset || ![200, 206].includes(response.status) ||
      /text\/html/i.test(response.headers.get('content-type') || '')) return null;
  // Count only the initial range; non-zero/suffix/multi-range resume traffic is
  // excluded. Retrying the initial request can still count again.
  const range = request.headers.get('range');
  if (range && !/^bytes=0-\d*$/i.test(range)) return null;
  if (response.status === 206 && !/^bytes 0-\d+\/\d+$/i.test(response.headers.get('content-range') || '')) return null;
  return { ...asset, kind: sparkle ? 'update' : url.searchParams.get('source') === 'website' ? 'website' : 'direct' };
}

export async function record(db, event, now = new Date()) {
  await db.prepare(`INSERT INTO daily_stats(day, kind, version, package_type, count)
    VALUES (?, ?, ?, ?, 1)
    ON CONFLICT(day, kind, version, package_type) DO UPDATE SET count = count + 1`)
    .bind(dayInShanghai(now), event.kind, event.version, event.packageType).run();
}

function json(body, status = 200) {
  return Response.json(body, { status, headers: {
    'Cache-Control': 'no-store', 'X-Content-Type-Options': 'nosniff',
  } });
}

export async function stats(request, env, now = new Date()) {
  if (request.method !== 'GET') return json({ error: 'method_not_allowed' }, 405);
  const days = Number(new URL(request.url).searchParams.get('days') || 30);
  if (![7, 30, 90].includes(days)) return json({ error: 'invalid_range' }, 400);
  if (!env.STATS_DB) return json({ error: 'stats_unavailable' }, 503);
  const end = dayInShanghai(now);
  const start = dayInShanghai(new Date(now.getTime() - (days - 1) * DAY_MS));
  try {
    const [meta, rows] = await env.STATS_DB.batch([
      env.STATS_DB.prepare("SELECT value FROM stats_meta WHERE key = 'started_at'"),
      env.STATS_DB.prepare(`SELECT day, kind, version, package_type, count FROM daily_stats
        WHERE day >= ? AND day <= ? ORDER BY day`).bind(start, end),
    ]);
    if (!meta.results[0]) return json({ error: 'stats_unavailable' }, 503);
    const empty = () => Object.fromEntries(kinds.map(kind => [kind, 0]));
    const totals = empty();
    const daily = Array.from({ length: days }, (_, i) => ({
      day: dayInShanghai(new Date(now.getTime() - (days - 1 - i) * DAY_MS)), ...empty(),
    }));
    const byDay = new Map(daily.map(row => [row.day, row]));
    const versions = new Map();
    let delta = 0;
    for (const row of rows.results) {
      if (!kinds.includes(row.kind)) continue;
      totals[row.kind] += row.count;
      byDay.get(row.day)[row.kind] += row.count;
      if (!versions.has(row.version)) versions.set(row.version, { version: row.version, ...empty(), delta: 0 });
      const version = versions.get(row.version);
      version[row.kind] += row.count;
      if (row.kind === 'update' && row.package_type === 'delta') { delta += row.count; version.delta += row.count; }
    }
    return json({ timeZone: TIME_ZONE, startedAt: meta.results[0].value, generatedAt: now.toISOString(),
      days, start, end, totals, delta, daily, versions: [...versions.values()].sort((a, b) => b.version.localeCompare(a.version, 'en', { numeric: true })),
    });
  } catch {
    console.error('stats_read_failed');
    return json({ error: 'stats_unavailable' }, 503);
  }
}

export default {
  async fetch(request, env, ctx) {
    const path = new URL(request.url).pathname;
    if (['/api/stats/login', '/api/stats/logout'].includes(path)) return authAction(request, env);
    const isStatsPage = ['/stats', '/stats/', '/stats.html', '/stats-login', '/stats-login.html'].includes(path);
    if (isStatsPage || path === '/api/stats') {
      const authorized = await authenticated(request, env);
      if (path === '/api/stats') {
        if (!authorized) return json({ error: 'unauthorized' }, 401);
        return stats(request, env);
      }
      const url = new URL(request.url);
      url.pathname = authorized ? '/stats' : '/stats-login';
      const page = await env.ASSETS.fetch(new Request(url, request));
      const headers = new Headers(page.headers);
      headers.set('Cache-Control', 'private, no-store');
      headers.set('X-Robots-Tag', 'noindex, nofollow');
      headers.set('X-Frame-Options', 'DENY');
      headers.set('Content-Security-Policy', "default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self'; connect-src 'self'; frame-ancestors 'none'; form-action 'self'; base-uri 'none'");
      return new Response(page.body, { status: page.status, headers });
    }
    if (path.startsWith('/api/')) return json({ error: 'not_found' }, 404);
    const response = await env.ASSETS.fetch(request);
    const event = classify(request, response);
    if (event) {
      if (env.STATS_DB) ctx.waitUntil(record(env.STATS_DB, event).catch(() => console.error('stats_write_failed')));
      else console.error('stats_binding_missing');
    }
    // Preserve signed appcast bytes, streaming DMGs, and all asset headers.
    return response;
  },
};
