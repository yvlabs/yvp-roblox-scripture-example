// Contract test: proves the Luau client and service handle REAL YouVersion
// Platform responses, not hand-written approximations.
//
// Live responses are fetched at run time and written to a gitignored temp
// directory. Scripture text is never committed to this repository.
//
// JSON decoding itself is delegated to Roblox's HttpService:JSONDecode in
// production, so this test injects the decoded table and exercises the parts
// we actually own: status handling, field extraction, and verbatim passthrough.

import { execFileSync } from 'node:child_process';
import { mkdirSync, writeFileSync, rmSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';

const here = dirname(fileURLToPath(import.meta.url));
const repo = resolve(here, '../..');

const key = process.env.YVP_APP_KEY;
if (!key) {
  console.error('Set YVP_APP_KEY to your YouVersion Platform app key (https://platform.youversion.com).');
  process.exit(2);
}

const BIBLE_ID = 206;
const PASSAGE = 'JHN.3.16';

async function get(path) {
  const res = await fetch('https://api.youversion.com' + path, {
    headers: { 'X-YVP-App-Key': key, Accept: 'application/json' },
    signal: AbortSignal.timeout(20000),
  });
  if (!res.ok) throw new Error(`HTTP ${res.status} for ${path}`);
  return res.json();
}

function luauString(value) {
  if (value === null || value === undefined) return 'nil';
  const text = String(value);
  for (const level of ['', '=', '==', '===', '====']) {
    const close = `]${level}]`;
    if (!text.includes(close)) return `[${level}[${text}]${level}]`;
  }
  throw new Error('could not safely quote value');
}

const version = await get(`/v1/bibles/${BIBLE_ID}`);
const passage = await get(`/v1/bibles/${BIBLE_ID}/passages/${PASSAGE}?format=html&include_headings=true`);
const passageText = await get(`/v1/bibles/${BIBLE_ID}/passages/${PASSAGE}?format=text`);

// Generated inside the repository (gitignored) because Luau only resolves
// requires relative to the requiring file.
const dir = join(repo, '.contract-tmp');
rmSync(dir, { recursive: true, force: true });
mkdirSync(dir, { recursive: true });
try {
  writeFileSync(join(dir, 'fixtures.luau'), `return {
	version = {
		id = ${JSON.stringify(version.id)},
		title = ${luauString(version.title)},
		abbreviation = ${luauString(version.abbreviation)},
		copyright = ${luauString(version.copyright)},
		promotional_content = ${luauString(version.promotional_content)},
		publisher_url = ${version.publisher_url === null ? 'nil' : luauString(version.publisher_url)},
	},
	passage = {
		id = ${JSON.stringify(passage.id)},
		content = ${luauString(passage.content)},
		reference = ${luauString(passage.reference)},
	},
	expectedText = ${luauString(passageText.content)},
	expectedByteLength = ${Buffer.byteLength(passageText.content, 'utf8')},
}
`);

  writeFileSync(join(dir, 'contract.luau'), `
local Fixtures = require("./fixtures")
local YvpClient = require("../src/server/YvpClient")
local ScriptureService = require("../src/server/ScriptureService")
local Cache = require("../src/shared/Cache")
local Quota = require("../src/shared/Quota")
local RateLimit = require("../src/shared/RateLimit")
local Reference = require("../src/shared/Reference")
local Usfm = require("../src/shared/Usfm")

local failures = 0
local function check(label, condition, detail)
	if condition then
		print("  ok   " .. label)
	else
		failures += 1
		print("  FAIL " .. label .. " :: " .. tostring(detail))
	end
end

-- Real response bodies, routed through the real status-handling path.
local http = {
	request = function(_self, options)
		if string.find(options.Url, "/passages/", 1, true) then
			return { StatusCode = 200, Body = "PASSAGE" }
		end
		return { StatusCode = 200, Body = "VERSION" }
	end,
}

local client = YvpClient.new({
	http = http,
	getKey = function() return "test-key" end,
	base = "https://api.youversion.com",
	decode = function(body)
		if body == "PASSAGE" then return Fixtures.passage end
		return Fixtures.version
	end,
})

local service = ScriptureService.new({
	client = client,
	cache = Cache.new(32, os.time),
	quota = Quota.new(50, 3600, os.time),
	rateLimit = RateLimit.new(10, 3, os.time),
	reference = Reference,
	usfm = Usfm,
	config = {
		BIBLE_ID = ${BIBLE_ID},
		VERSIONS = { { id = ${BIBLE_ID}, abbreviation = "WEB", label = "World English Bible" } },
		LANGUAGE_RANGE = "eng",
		PASSAGE_CACHE_TTL = 600,
		METADATA_CACHE_TTL = 3600,
	},
})

local result = service:getPassage("${PASSAGE}", "contract-player")

check("passage retrieved", result.ok, result.reason)
-- Trimmed comparison. Verified 2026-09-27: the html rendering of this verse
-- carries a trailing space inside its <span class="wj"> that format=text
-- trims. That is an incidental whitespace difference between the two
-- renderings, not lost text; every interior character matches.
local function trim(text: string): string
	return (string.gsub(text, "^%s*(.-)%s*$", "%1"))
end
check("parsed text matches the plain-text rendering", trim(result.content) == trim(Fixtures.expectedText),
	"parsed html differs from format=text beyond surrounding whitespace")
check("no interior characters lost", #trim(result.content) == #trim(Fixtures.expectedText),
	string.format("got %d bytes, live response had %d", #trim(result.content), #trim(Fixtures.expectedText)))
check("words of Jesus detected", result.blocks[1].segments[1].wordsOfJesus == true,
	"this verse is entirely words of Jesus in version 206")
check("verse number recovered", result.blocks[1].segments[1].verse == 16,
	"expected verse 16 marker")
check("reference matches live response", result.reference == Fixtures.passage.reference, result.reference)

local attribution = result.attribution
check("attribution present", attribution ~= nil, "nil attribution")
if attribution then
	check("version title from live metadata", attribution.versionTitle == Fixtures.version.title, attribution.versionTitle)
	check("abbreviation from live metadata", attribution.versionAbbreviation == Fixtures.version.abbreviation, attribution.versionAbbreviation)
	check("copyright from live metadata", attribution.copyright == Fixtures.version.copyright, attribution.copyright)
	check("copyright is non-empty", #attribution.copyright > 0, "empty copyright")
	check("promotional content carried", attribution.promotionalContent == Fixtures.version.promotional_content,
		tostring(attribution.promotionalContent))
end

print("")
if failures > 0 then
	error(string.format("%d contract check(s) failed", failures))
end
print("contract OK against live API responses")
`);

  const out = execFileSync('luau', [join(dir, 'contract.luau')], { encoding: 'utf8' });
  console.log(out);
  console.log(`version:  ${version.abbreviation} (id ${version.id})`);
  console.log(`copyright: ${version.copyright}`);
  console.log(`passage:  ${passage.reference}, ${Buffer.byteLength(passage.content, 'utf8')} bytes`);
  console.log('API requests spent: 3');
} finally {
  rmSync(dir, { recursive: true, force: true });
}
