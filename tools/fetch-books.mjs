// Regenerate the book allowlist in src/shared/Reference.luau.
// Run this if Config.BIBLE_ID changes. Spends one Platform request.

const bibleId = process.argv[2] ?? '206';
const key = process.env.YVP_APP_KEY;
if (!key) {
  console.error('Set YVP_APP_KEY to your YouVersion Platform app key (https://platform.youversion.com).');
  process.exit(2);
}

const res = await fetch(`https://api.youversion.com/v1/bibles/${bibleId}/index`, {
  headers: { 'X-YVP-App-Key': key },
});
if (!res.ok) throw new Error(`HTTP ${res.status}`);
const { books } = await res.json();
const ids = books.map((b) => b.id);
const maxChapters = Math.max(...books.map((b) => b.chapters.length));

console.log(`-- ${ids.length} books, max ${maxChapters} chapters, bible ${bibleId}`);
const rows = [];
for (let i = 0; i < ids.length; i += 10) {
  rows.push('\t' + ids.slice(i, i + 10).map((id) => `"${id}"`).join(', ') + ',');
}
console.log('local BOOK_LIST = {');
console.log(rows.join('\n'));
console.log('}');
