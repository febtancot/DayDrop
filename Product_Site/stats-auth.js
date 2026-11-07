const encoder = new TextEncoder();
const COOKIE = 'daydrop_stats';
const TTL = 12 * 3600;
const denied = (status, error) => Response.json({ error }, { status, headers: { 'Cache-Control': 'no-store' } });
const hex = bytes => Array.from(new Uint8Array(bytes), b => b.toString(16).padStart(2, '0')).join('');
async function key(secret) {
  return crypto.subtle.importKey('raw', encoder.encode(secret), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign', 'verify']);
}
async function validPassword(actual, expected) {
  // Fixed-length digest comparison; neither raw password is logged or stored.
  const [a, b] = await Promise.all([actual, expected].map(value => crypto.subtle.digest('SHA-256', encoder.encode(value))));
  const x = new Uint8Array(a), y = new Uint8Array(b);
  let diff = 0;
  for (let i = 0; i < x.length; i++) diff |= x[i] ^ y[i];
  return diff === 0;
}
export function configured(env) { return typeof env.STATS_PASSWORD === 'string' && env.STATS_PASSWORD.length >= 24; }
export async function authenticated(request, env, now = Date.now()) {
  if (!configured(env)) return false;
  const cookie = (request.headers.get('cookie') || '').split(';').map(x => x.trim()).find(x => x.startsWith(`${COOKIE}=`))?.slice(COOKIE.length + 1);
  if (!cookie || !/^\d{10}\.[a-f0-9]{64}$/.test(cookie)) return false;
  const [expiry, signature] = cookie.split('.');
  if (Number(expiry) <= now / 1000 || Number(expiry) > now / 1000 + TTL) return false;
  const bytes = Uint8Array.from(signature.match(/../g), value => parseInt(value, 16));
  return crypto.subtle.verify('HMAC', await key(env.STATS_PASSWORD), bytes, encoder.encode(`daydrop-stats:${expiry}`));
}
export async function authAction(request, env, now = Date.now()) {
  if (request.method !== 'POST') return denied(405, 'method_not_allowed');
  const url = new URL(request.url);
  if (request.headers.get('origin') !== url.origin) return denied(403, 'invalid_origin');
  const cookieFlags = `Path=/; HttpOnly; SameSite=Strict${url.protocol === 'https:' ? '; Secure' : ''}`;
  if (url.pathname === '/api/stats/logout') return new Response(null, { status: 204, headers: { 'Cache-Control': 'no-store', 'Set-Cookie': `${COOKIE}=; Max-Age=0; ${cookieFlags}` } });
  if (!configured(env)) return denied(503, 'stats_unavailable');
  if (!request.headers.get('content-type')?.startsWith('application/json')) return denied(415, 'invalid_content_type');
  // Bound streamed input too, even when Content-Length is absent or dishonest.
  const reader = request.body?.getReader();
  if (!reader) return denied(400, 'invalid_body');
  let size = 0; const chunks = [];
  while (true) {
    const { done, value } = await reader.read(); if (done) break;
    size += value.length;
    if (size > 1024) { await reader.cancel(); return denied(413, 'body_too_large'); }
    chunks.push(value);
  }
  let password;
  try { password = JSON.parse(await new Blob(chunks).text()).password; } catch { return denied(400, 'invalid_body'); }
  if (typeof password !== 'string' || password.length > 256 || !await validPassword(password, env.STATS_PASSWORD)) return denied(401, 'invalid_password');
  const expiry = String(Math.floor(now / 1000) + TTL);
  const signature = hex(await crypto.subtle.sign('HMAC', await key(env.STATS_PASSWORD), encoder.encode(`daydrop-stats:${expiry}`)));
  return new Response(null, { status: 204, headers: { 'Cache-Control': 'no-store', 'Set-Cookie': `${COOKIE}=${expiry}.${signature}; Max-Age=${TTL}; ${cookieFlags}` } });
}
