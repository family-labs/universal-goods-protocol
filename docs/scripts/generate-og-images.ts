/**
 * Renders the text-only Open Graph cards in scripts/og/*.svg to 1200x630 PNG files in
 * docs/public/og/, where the built site serves them at /og/<name>.png.
 *
 * The cards are drawn as code (plain SVG text and shapes). No generated imagery is used.
 * The PNGs are committed, so the site build does not need to run this script.
 *
 * Run: bun run og
 */

import { readdir, mkdir, readFile } from 'node:fs/promises';
import path from 'node:path';
import sharp from 'sharp';

const SOURCE_DIR = path.resolve(import.meta.dirname, 'og');
const OUTPUT_DIR = path.resolve(import.meta.dirname, '../docs/public/og');
const OG_WIDTH = 1200;
const OG_HEIGHT = 630;

async function generate() {
  await mkdir(OUTPUT_DIR, { recursive: true });
  const cards = (await readdir(SOURCE_DIR)).filter((f) => f.endsWith('.svg'));

  for (const file of cards) {
    const name = file.replace(/\.svg$/, '');
    const svg = await readFile(path.join(SOURCE_DIR, file));
    await sharp(svg, { density: 144 })
      .resize(OG_WIDTH, OG_HEIGHT, { fit: 'contain', background: '#F5F6FC' })
      .png()
      .toFile(path.join(OUTPUT_DIR, `${name}.png`));
    console.log(`  og/${name}.png`);
  }
}

generate().catch((err) => {
  console.error('OG image generation failed:', err);
  process.exit(1);
});
