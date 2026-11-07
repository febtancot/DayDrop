// No credentials required: verify that every private entry fails closed.
import assert from 'node:assert/strict';
const base = process.argv[2];
if (!base || !base.startsWith('https://')) throw new Error('Expected HTTPS deployment URL');
for (const path of ['/stats', '/stats.html', '/stats/']) {
  const response = await fetch(new URL(path, base));
  assert.equal(response.status, 200, `${path}: page missing`);
  assert.match(response.headers.get('cache-control') || '', /no-store/, `${path}: private page cached`);
  assert.match(await response.text(), /id="login-form"/, `${path}: login protection missing`);
}
const api = await fetch(new URL('/api/stats', base));
assert.equal(api.status, 401, 'Unauthenticated statistics API must return 401');
assert.match(api.headers.get('cache-control') || '', /no-store/);
console.log(`Statistics access protection verified: ${new URL(base).hostname}`);
