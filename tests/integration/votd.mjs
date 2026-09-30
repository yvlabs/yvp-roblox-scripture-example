// Live check of the Verse of the Day path in the configured version.
// Resolves today's day -> passage_id -> text, through the real Luau parser.
import { execFileSync } from 'node:child_process';
import { mkdirSync, writeFileSync, rmSync } from 'node:fs';
import { join, dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const repo = resolve(dirname(fileURLToPath(import.meta.url)), '../..');
const key = process.env.YVP_APP_KEY;
if (!key) {
  console.error('Set YVP_APP_KEY to your YouVersion Platform app key (https://platform.youversion.com).');
  process.exit(2);
}
const H = { 'X-YVP-App-Key': key, Accept: 'application/json' };
const BIBLE_ID = Number(process.env.VOTD_BIBLE_ID ?? 206); // match Config.VOTD_BIBLE_ID

const get = async (p) => {
  const r = await fetch('https://api.youversion.com' + p, { headers: H, signal: AbortSignal.timeout(20000) });
  if (!r.ok) throw new Error(`HTTP ${r.status} for ${p}`);
  return r.json();
};

const yday = (() => {
  const now = new Date();
  const start = Date.UTC(now.getUTCFullYear(), 0, 0);
  return Math.floor((Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate()) - start) / 86400000);
})();

const votd = await get(`/v1/verse-of-the-days/${yday}`);
const passage = await get(`/v1/bibles/${BIBLE_ID}/passages/${votd.passage_id}?format=html&include_headings=true&include_notes=true`);
const version = await get(`/v1/bibles/${BIBLE_ID}`);

function luauString(t) {
  for (const lvl of ['', '=', '==', '===', '====']) if (!t.includes(`]${lvl}]`)) return `[${lvl}[${t}]${lvl}]`;
  throw new Error('quote');
}

const dir = join(repo, '.contract-tmp');
rmSync(dir, { recursive: true, force: true });
mkdirSync(dir, { recursive: true });
try {
  writeFileSync(join(dir, 'votd.luau'), `
local Reference = require("../src/shared/Reference")
local Usfm = require("../src/shared/Usfm")
local Attribution = require("../src/shared/Attribution")

local passageId = ${JSON.stringify(votd.passage_id)}
local canonical, err = Reference.canonical(passageId)
local failures = 0
local function check(label, cond, detail)
  if cond then print("  ok   " .. label) else failures += 1; print("  FAIL " .. label .. " :: " .. tostring(detail)) end
end

check("VOTD reference passes validation", canonical ~= nil, err)
check("reference round-trips unchanged", canonical == passageId, tostring(canonical))

local blocks = Usfm.parse(${luauString(passage.content)})
local text = Usfm.verseText(blocks)
check("passage parsed to text", #text > 0, "empty")
check("no leaked markup", string.find(text, "<span", 1, true) == nil, text)

local line = Attribution.line({
  versionTitle = ${luauString(version.title)},
  copyright = ${luauString(String(version.copyright ?? ''))},
  promotionalContent = ${luauString(String(version.promotional_content ?? ''))},
  publisherUrl = ${luauString(String(version.publisher_url ?? ''))},
})
check("attribution has no raw newline", string.find(line, "\\n", 1, true) == nil, "newline present")
check("version title present", string.find(line, ${luauString(version.title)}, 1, true) ~= nil, line)
check("platform credited", string.find(line, "YouVersion Platform", 1, true) ~= nil, line)

print("")
print("day ${yday}  ->  " .. passageId .. "  ->  " .. ${JSON.stringify(passage.reference)})
print("text: " .. text)
if failures > 0 then error(failures .. " check(s) failed") end
print("")
print("verse of the day OK in version ${BIBLE_ID}")
`);
  console.log(execFileSync('luau', [join(dir, 'votd.luau')], { encoding: 'utf8' }));
  console.log(`API requests spent: 3`);
} finally {
  rmSync(dir, { recursive: true, force: true });
}
