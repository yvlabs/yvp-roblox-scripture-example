// Proves the USFM parser loses no Scripture characters, against live responses.
//
// For each chapter it fetches both format=html and format=text, parses the
// HTML with the real Luau parser, and compares the recovered text with the
// plain-text rendering after normalising whitespace only. Any dropped word,
// duplicated verse number, or undecoded entity fails the check.
//
// Scripture is written only to a gitignored temp directory, never committed.

import { execFileSync } from 'node:child_process';
import { mkdirSync, writeFileSync, rmSync } from 'node:fs';
import { join, dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const repo = resolve(here, '../..');
const key = process.env.YVP_APP_KEY;
if (!key) {
  console.error('Set YVP_APP_KEY to your YouVersion Platform app key (https://platform.youversion.com).');
  process.exit(2);
}

// Comma-separated version ids to check, e.g. BIBLE_IDS=206,111. Defaults to
// the public-domain WEB so the test runs on any app key.
const BIBLE_IDS = (process.env.BIBLE_IDS ?? '206').split(',').map(Number);
// Prose, poetry, a heading, words of Jesus, and a long chapter.
const CHAPTERS = ['EXO.1', 'PSA.23', 'MAT.5', 'JHN.3'];

async function get(path) {
  const res = await fetch('https://api.youversion.com' + path, {
    headers: { 'X-YVP-App-Key': key, Accept: 'application/json' },
    signal: AbortSignal.timeout(25000),
  });
  if (!res.ok) throw new Error(`HTTP ${res.status} for ${path}`);
  return res.json();
}

function luauString(text) {
  for (const level of ['', '=', '==', '===', '====', '=====']) {
    if (!text.includes(`]${level}]`)) return `[${level}[${text}]${level}]`;
  }
  throw new Error('cannot quote safely');
}

const norm = (s) => s.replace(/\s+/g, ' ').trim();

// The real invariant: no Scripture character is lost, added or duplicated.
// Inter-block spacing legitimately differs between the two renderings -- the
// Platform's own format=text sometimes joins blocks with no space at all
// ("disobeysthe Son" in WEB John 3, "perfect.[Lev 19:2]" in AMP Matthew 5),
// where the parsed structure correctly separates them. Comparing with all
// whitespace removed still catches a dropped word, a duplicated verse number
// or an undecoded entity, without failing on a spacing difference where our
// output is the better of the two.
const dense = (s) => s.replace(/\s+/g, '');

const dir = join(repo, '.contract-tmp');
rmSync(dir, { recursive: true, force: true });
mkdirSync(dir, { recursive: true });

try {
  const cases = [];
  for (const bibleId of BIBLE_IDS) {
    for (const ref of CHAPTERS) {
      const html = await get(`/v1/bibles/${bibleId}/passages/${ref}?format=html&include_headings=true&include_notes=true`);
      const text = await get(`/v1/bibles/${bibleId}/passages/${ref}?format=text`);
      cases.push({ ref: `${bibleId}:${ref}`, html: html.content, text: text.content });
    }
  }

  writeFileSync(join(dir, 'cases.luau'),
    'return {\n' + cases.map(c =>
      `\t{ ref = ${JSON.stringify(c.ref)}, html = ${luauString(c.html)} },`
    ).join('\n') + '\n}\n');

  writeFileSync(join(dir, 'integrity.luau'), `
local Cases = require("./cases")
local Usfm = require("../src/shared/Usfm")

for _, case in Cases do
	local blocks = Usfm.parse(case.html)
	local recovered = Usfm.verseText(blocks)
	local verses = 0
	for _, block in blocks do
		for _, segment in block.segments do
			if segment.verse then verses += 1 end
		end
	end
	print(string.format("%s\\t%d blocks\\t%d verse marks\\t%d chars", case.ref, #blocks, verses, #recovered))
	print("RECOVERED\t" .. case.ref .. "\t" .. recovered)
end
`);

  const out = execFileSync('luau', [join(dir, 'integrity.luau')], {
    encoding: 'utf8', maxBuffer: 40 * 1024 * 1024,
  });

  const recovered = {};
  for (const line of out.split('\n')) {
    const m = line.match(/^RECOVERED\t([^\t]+)\t([\s\S]*)$/);
    if (m) recovered[m[1]] = m[2];
    else if (line.trim()) console.log('  ' + line);
  }

  let failures = 0;
  console.log('');
  for (const c of cases) {
    const got = norm(recovered[c.ref] ?? '');
    const want = norm(c.text);
    if (dense(got) === dense(want)) {
      const spacing = got === want ? '' : ' (inter-block spacing differs)';
      console.log(`  ok   ${c.ref} every character preserved (${dense(want).length} chars)${spacing}`);
    } else {
      failures++;
      console.log(`  FAIL ${c.ref}`);
      console.log(`       want ${dense(want).length} chars, got ${dense(got).length}`);
      const g = dense(got), w = dense(want);
      for (let i = 0; i < Math.max(g.length, w.length); i++) {
        if (g[i] !== w[i]) {
          console.log(`       first difference at ${i}:`);
          console.log(`         want ...${want.slice(Math.max(0, i - 40), i + 40)}...`);
          console.log(`         got  ...${got.slice(Math.max(0, i - 40), i + 40)}...`);
          break;
        }
      }
    }
    if (/&[a-z#0-9]+;/i.test(recovered[c.ref] ?? '')) {
      failures++;
      console.log(`  FAIL ${c.ref} contains an undecoded HTML entity`);
    }
  }

  console.log('');
  if (failures > 0) {
    console.log(`${failures} integrity failure(s)`);
    process.exit(1);
  }
  console.log(`parser integrity OK across ${cases.length} chapters in ${BIBLE_IDS.length} versions (${cases.length * 2} API requests)`);
} finally {
  rmSync(dir, { recursive: true, force: true });
}
