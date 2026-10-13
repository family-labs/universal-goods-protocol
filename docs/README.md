# Universal Goods Protocol documentation

The source of [docs.universalgoods.org](https://docs.universalgoods.org), built with [Rspress](https://rspress.rs) 2.

```sh
bun install
bun run dev       # live preview
bun run build     # static site in doc_build/
bun run check     # no broken internal links or images in doc_build/
bun run preview   # serve the built site
```

- Pages: Markdown under `docs/`. Sidebars: the `_meta.json` file in each folder. Top navigation: `docs/_nav.json`.
- Diagrams: hand-written SVG under `docs/public/diagrams/`.
- Screenshots: real captures of the hosted console under `docs/public/screenshots/`, taken with a fictional demo organisation. A capture still to be taken is shown as a text placeholder (`<div class="todo-shot">`), never as a broken image.
- Open Graph card: `scripts/og/cover.svg`, a text-only card rendered to `docs/public/og/cover.png` with `bun run og`.

No AI-generated images are used anywhere on the site.
