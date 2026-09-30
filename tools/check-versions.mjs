// Verify Config.VERSIONS against the live application key.
//
// The picker is served from static configuration so it cannot fail at
// runtime, which means a lapsed licence would go unnoticed. This is the
// staleness check for that trade-off. Run it periodically.
import { readFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const repo = resolve(dirname(fileURLToPath(import.meta.url)), '..');
// Drop Luau comment lines first, so commented-out example versions are not
// counted as enabled.
const config = readFileSync(resolve(repo, 'src/shared/Config.luau'), 'utf8')
  .split('\n').filter((line) => !line.trim().startsWith('--')).join('\n');

const versions = [...config.matchAll(
  /\{\s*id\s*=\s*(\d+),\s*abbreviation\s*=\s*"([^"]+)",\s*label\s*=\s*"([^"]*)"\s*\}/g
)].map(([, id, abbreviation, label]) => ({ id: Number(id), abbreviation, label }));

if (versions.length === 0) {
  console.error('could not parse Config.VERSIONS');
  process.exit(1);
}

const key = process.env.YVP_APP_KEY;
if (!key) {
  console.error('Set YVP_APP_KEY to your YouVersion Platform app key (https://platform.youversion.com).');
  process.exit(2);
}

let failures = 0;
console.log(`checking ${versions.length} configured versions against the live key\n`);

for (const v of versions) {
  const res = await fetch(`https://api.youversion.com/v1/bibles/${v.id}`, {
    headers: { 'X-YVP-App-Key': key }, signal: AbortSignal.timeout(20000),
  });
  if (!res.ok) {
    console.log(`  FAIL ${v.abbreviation.padEnd(6)} id=${v.id} -> HTTP ${res.status}`);
    failures++;
    continue;
  }
  const body = await res.json();
  // A passage must resolve too; metadata alone does not prove read access.
  const probe = await fetch(
    `https://api.youversion.com/v1/bibles/${v.id}/passages/JHN.3.16?format=text`,
    { headers: { 'X-YVP-App-Key': key }, signal: AbortSignal.timeout(20000) });
  const ok = probe.ok;
  if (!ok) failures++;
  console.log(`  ${ok ? 'ok  ' : 'FAIL'} ${v.abbreviation.padEnd(6)} id=${String(v.id).padEnd(5)} ${body.abbreviation}`);
  if (!body.copyright) {
    console.log(`       note: no copyright field; attribution shows title and platform credit only`);
  }
}

console.log('');
if (failures) {
  console.log(`${failures} version(s) unavailable - update Config.VERSIONS`);
  process.exit(1);
}
console.log(`all ${versions.length} configured versions readable (${versions.length * 2} requests)`);
