import { readFileSync, statSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import assert from 'node:assert/strict';

const config = JSON.parse(readFileSync(new URL('./distribution.json', import.meta.url)));
const directory = new URL('../Distribution/Dictionaries/', import.meta.url);
const manifestBytes = readFileSync(new URL('manifest.json', directory));
const catalog = JSON.parse(manifestBytes);
const ids = ['english-english', 'english-chinese', 'chinese-english'];
const digest = bytes => createHash('sha256').update(bytes).digest('hex');
assert.deepEqual(catalog.packs.map(pack => pack.id).sort(), [...ids].sort());
assert([2, 3].includes(catalog.schemaVersion));
assert.deepEqual(JSON.parse(readFileSync(new URL('../Shared/Resources/DictionaryCatalog.json', import.meta.url))), catalog);
const objects = catalog.packs.map(pack => {
  assert(/^[\w.-]+$/.test(pack.version));
  const name = `${pack.id}-${pack.version}.sqlite`;
  assert.equal(pack.url, name, 'Pack URLs must be filenames relative to the manifest');
  const file = new URL(name, directory);
  assert.equal(statSync(file).size, pack.byteCount);
  assert.equal(digest(readFileSync(file)), pack.sha256);
  return { name, sha256: pack.sha256, size: pack.byteCount, type: 'application/octet-stream' };
});
for (const id of ids) {
  const name = `${id}-licenses.txt`;
  const bytes = readFileSync(new URL(name, directory));
  assert(bytes.length > 0);
  objects.push({ name, sha256: digest(bytes), size: bytes.length, type: 'text/plain; charset=utf-8' });
}
// Publish the catalog only after every referenced object exists.
objects.push({ name: 'manifest.json', sha256: digest(manifestBytes), size: manifestBytes.length, type: 'application/json' });
const mode = process.argv[2];
assert(['check', 'upload', 'verify'].includes(mode), 'Use check, upload or verify');
console.log(`Validated ${objects.length} distribution files for ${config.bucket}.`);

for (const object of objects) {
  if (mode === 'upload') {
    const result = spawnSync(process.execPath, [
      fileURLToPath(new URL('./node_modules/wrangler/bin/wrangler.js', import.meta.url)),
      'r2', 'object', 'put', `${config.bucket}/${object.name}`, '--remote',
      '--file', fileURLToPath(new URL(object.name, directory)), '--content-type', object.type,
      // Internal testing reuses dated filenames: require revalidation.
      '--cache-control', 'no-cache',
    ], { stdio: 'inherit', env: { ...process.env, CLOUDFLARE_ACCOUNT_ID: config.accountId } });
    if (result.error) throw result.error;
    assert.equal(result.status, 0, `Upload failed: ${object.name}`);
  } else if (mode === 'verify') {
    const response = await fetch(new URL(object.name, config.baseURL), { signal: AbortSignal.timeout(180_000) });
    assert.equal(response.status, 200, object.name);
    // Text may use transfer/content encoding and omit Content-Length. SQLite
    // needs exact lengths for download progress and range requests.
    if (object.name.endsWith('.sqlite') || response.headers.has('content-length')) {
      assert.equal(response.headers.get('content-length'), String(object.size));
    }
    const hash = createHash('sha256');
    let size = 0;
    for await (const chunk of response.body) {
      size += chunk.length;
      assert(size <= object.size);
      hash.update(chunk);
    }
    assert.equal(size, object.size);
    assert.equal(hash.digest('hex'), object.sha256, object.name);
    console.log(`Verified ${object.name}: ${size} bytes, SHA-256 matches.`);
    if (object.name.endsWith('.sqlite')) {
      const range = await fetch(new URL(object.name, config.baseURL), {
        headers: { Range: 'bytes=0-15' }, signal: AbortSignal.timeout(30_000),
      });
      assert.equal(range.status, 206);
      assert.equal(range.headers.get('content-range'), `bytes 0-15/${object.size}`);
      assert.equal(Buffer.from(await range.arrayBuffer()).toString(), 'SQLite format 3\0');
    }
  }
}
