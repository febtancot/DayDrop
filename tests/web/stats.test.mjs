import test from 'node:test';
import assert from 'node:assert/strict';
import { DatabaseSync } from 'node:sqlite';
import { readFileSync } from 'node:fs';
import worker, { classify, record, stats, dayInShanghai } from '../../Product_Site/_worker.js';
import { authenticated, authAction } from '../../Product_Site/stats-auth.js';

const origin = 'https://daydrop.liveby.app';
const browser = 'Mozilla/5.0';
const sparkle = 'DayDrop/1.3.0 Sparkle/2.7.1';
const password = 'test-only-password-never-deploy-12345';
const request = (path, options = {}) => new Request(origin + path, { headers: { 'user-agent': browser }, ...options });
function db() {
  const sql = new DatabaseSync(':memory:');
  sql.exec(readFileSync(new URL('../../migrations/0001_download_stats.sql', import.meta.url), 'utf8'));
  return {
    prepare(query) {
      let args = [];
      const statement = { bind(...values) { args = values; return statement; },
        async run() { return sql.prepare(query).run(...args); },
        async all() { return { results: sql.prepare(query).all(...args) }; } };
      return statement;
    },
    async batch(statements) { return Promise.all(statements.map(statement => statement.all())); },
  };
}
const response = () => new Response('signed bytes', { headers: { 'Content-Type': 'application/octet-stream' } });
const loginRequest = (value = password, path = '/api/stats/login') => request(path, { method: 'POST', headers: { origin, 'content-type': 'application/json' }, body: JSON.stringify({ password: value }) });

test('Shanghai date rolls at UTC 16:00', () => {
  assert.equal(dayInShanghai(new Date('2026-10-27T16:00:00Z')), '2026-10-28');
});
test('website, direct, full update and delta update remain distinct', () => {
  assert.equal(classify(request('/downloads/DayDrop-1.4.0.dmg?source=website'), response()).kind, 'website');
  assert.equal(classify(request('/downloads/DayDrop-1.4.0.dmg'), response()).kind, 'direct');
  assert.equal(classify(request('/downloads/DayDrop-1.4.0.dmg?source=website', { headers: { 'user-agent': sparkle } }), response()).kind, 'update');
  assert.deepEqual(classify(request('/downloads/DayDrop12-11.delta', { headers: { 'user-agent': sparkle } }), response()), { kind: 'update', version: '1.4.0', packageType: 'delta' });
});
test('only DayDrop Sparkle checks count, including 304', () => {
  assert.equal(classify(request('/updates/appcast.xml'), response()), null);
  assert.equal(classify(request('/updates/appcast.xml', { headers: { 'user-agent': sparkle } }), new Response(null, { status: 304 })).version, '1.3.0');
  assert.equal(classify(request('/updates/appcast.xml', { headers: { 'user-agent': 'DayDrop/999.0 Sparkle/2' } }), response()).version, 'unknown');
});
test('excludes probes, bots, errors, unknown files and noninitial ranges', () => {
  for (const req of [request('/downloads/DayDrop-1.4.0.dmg', { method: 'HEAD' }), request('/downloads/DayDrop-1.4.0.dmg?verify=123'), request('/downloads/DayDrop-9.9.9.dmg'), request('/downloads/DayDrop-1.4.0.dmg.sha256'), ...['bytes=100-', 'bytes=-100', 'bytes=0-2,10-20'].map(range => request('/downloads/DayDrop-1.4.0.dmg', { headers: { range } })), request('/downloads/DayDrop-1.4.0.dmg', { headers: { 'user-agent': 'Googlebot' } }), request('/downloads/DayDrop-1.4.0.dmg', { headers: { 'sec-purpose': 'prefetch' } })]) assert.equal(classify(req, response()), null);
  for (const status of [302, 404, 500]) assert.equal(classify(request('/downloads/DayDrop-1.4.0.dmg'), new Response(null, { status })), null);
  assert.equal(classify(request('/downloads/DayDrop-1.4.0.dmg'), new Response('fallback', { headers: { 'content-type': 'text/html' } })), null);
});
test('counts only a successful initial range', () => {
  const req = request('/downloads/DayDrop-1.4.0.dmg', { headers: { range: 'bytes=0-99' } });
  assert.ok(classify(req, new Response('part', { status: 206, headers: { 'content-range': 'bytes 0-99/1000' } })));
  assert.equal(classify(req, new Response('part', { status: 206, headers: { 'content-range': 'bytes 100-199/1000' } })), null);
});
test('real SQLite counters aggregate atomically, zero-fill and filter dates', async () => {
  const database = db(), now = new Date('2026-10-28T03:00:00Z');
  await Promise.all(Array.from({ length: 25 }, () => record(database, { kind: 'website', version: '1.4.0', packageType: 'full' }, now)));
  await record(database, { kind: 'update', version: '1.4.0', packageType: 'delta' }, now);
  await record(database, { kind: 'check', version: '1.3.0', packageType: 'feed' }, new Date('2026-10-01'));
  const data = await (await stats(request('/api/stats?days=7'), { STATS_DB: database }, now)).json();
  assert.equal(data.daily.length, 7); assert.equal(data.daily[0].website, 0);
  assert.deepEqual(data.totals, { website: 25, update: 1, check: 0, direct: 0 });
  assert.equal(data.delta, 1); assert.equal(data.versions[0].version, '1.4.0');
  assert.equal((await stats(request('/api/stats?days=999'), { STATS_DB: database }, now)).status, 400);
});
test('missing database is unavailable, not false zero', async () => {
  assert.equal((await stats(request('/api/stats'), {})).status, 503);
});
test('login, signed cookie, tampering, expiry, password rotation and logout', async () => {
  const env = { STATS_PASSWORD: password }, now = Date.now();
  const loggedIn = await authAction(loginRequest(), env, now);
  assert.equal(loggedIn.status, 204);
  const cookie = loggedIn.headers.get('set-cookie');
  assert.match(cookie, /Secure/); assert.match(cookie, /HttpOnly/); assert.match(cookie, /SameSite=Strict/);
  const req = request('/api/stats', { headers: { cookie } });
  assert.equal(await authenticated(req, env, now), true);
  assert.equal(await authenticated(req, env, now + 13 * 3600000), false);
  assert.equal(await authenticated(req, { STATS_PASSWORD: password + 'rotated' }, now), false);
  assert.equal(await authenticated(request('/api/stats', { headers: { cookie: cookie.replace(/=[0-9]/, '=9') } }), env, now), false);
  assert.equal((await authAction(loginRequest('wrong'), env)).status, 401);
  assert.equal((await authAction(loginRequest(), {})).status, 503);
  assert.equal((await authAction(loginRequest(password, '/api/stats/logout'), env)).headers.get('set-cookie').includes('Max-Age=0'), true);
});
test('login rejects cross-origin and oversized input', async () => {
  const req = loginRequest(); req.headers.set('origin', 'https://evil.example');
  assert.equal((await authAction(req, { STATS_PASSWORD: password })).status, 403);
  assert.equal((await authAction(loginRequest('x'.repeat(2000)), { STATS_PASSWORD: password })).status, 413);
});
test('both page aliases and API fail closed without credentials', async () => {
  const env = { ASSETS: { fetch: req => new Response(new URL(req.url).pathname) } };
  assert.equal((await worker.fetch(request('/api/stats'), env, {})).status, 401);
  for (const path of ['/stats', '/stats/', '/stats.html', '/stats-login.html']) {
    const res = await worker.fetch(request(path), env, {});
    assert.match(await res.text(), /stats-login/);
    assert.equal(res.headers.get('cache-control'), 'private, no-store');
  }
});
test('signed assets are byte-preserved and DB failures do not block downloads', async () => {
  const pending = [];
  const env = { ASSETS: { fetch: () => response() }, STATS_DB: { prepare() { throw new Error('offline'); } } };
  const result = await worker.fetch(request('/downloads/DayDrop-1.4.0.dmg'), env, { waitUntil: promise => pending.push(promise) });
  assert.equal(await result.text(), 'signed bytes'); assert.equal(result.status, 200);
  await Promise.all(pending);
});
