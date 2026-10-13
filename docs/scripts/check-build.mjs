// Checks the built site in doc_build/ for broken internal links and images.
// Every internal href and src must resolve to a file in the build. External links are not fetched.
//
// Run after `bun run build`: node scripts/check-build.mjs

import { readdirSync, readFileSync, statSync, existsSync } from 'node:fs';
import path from 'node:path';

const root = path.resolve(import.meta.dirname, '../doc_build');
if (!existsSync(root)) {
  console.error('doc_build/ not found. Run `bun run build` first.');
  process.exit(1);
}

function walk(dir, out = []) {
  for (const name of readdirSync(dir)) {
    const p = path.join(dir, name);
    if (statSync(p).isDirectory()) walk(p, out);
    else out.push(p);
  }
  return out;
}

function resolves(target) {
  const clean = decodeURIComponent(target.split('#')[0].split('?')[0]);
  if (clean === '' || clean === '/') return existsSync(path.join(root, 'index.html'));
  const p = path.join(root, clean);
  const candidates = [p, `${p}.html`, path.join(p, 'index.html')];
  return candidates.some((c) => existsSync(c) && statSync(c).isFile());
}

const pages = walk(root).filter((f) => f.endsWith('.html'));
const broken = [];
for (const page of pages) {
  const html = readFileSync(page, 'utf8');
  for (const [, attr, value] of html.matchAll(/\s(href|src)="([^"]+)"/g)) {
    if (!value.startsWith('/') || value.startsWith('//')) continue;
    if (!resolves(value)) broken.push(`${path.relative(root, page)}: ${attr}="${value}"`);
  }
}

console.log(`Checked ${pages.length} pages.`);
if (broken.length) {
  console.error(`${broken.length} broken internal link(s) or image(s):`);
  for (const b of [...new Set(broken)]) console.error(`  ${b}`);
  process.exit(1);
}
console.log('No broken internal links or images.');
