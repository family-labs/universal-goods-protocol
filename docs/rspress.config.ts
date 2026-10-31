import * as path from 'node:path';
import { defineConfig } from '@rspress/core';

const SITE_URL = 'https://docs.universalgoods.org';
const REPO_URL = 'https://github.com/family-labs/universal-goods-protocol';

// Pages without a `description` get their first paragraph; llms.txt wants a one-line note.
const firstSentence = (text: string) => text.split(/(?<=\.)\s/)[0];

export default defineConfig({
  root: path.join(__dirname, 'docs'),
  title: 'Universal Goods Protocol',
  description:
    'Open infrastructure that gives every physical product a verifiable digital identity: LUKSO contracts, protocol packages and how they come together.',
  lang: 'en',
  icon: '/logo-light.svg',
  logo: {
    light: '/logo-dark.svg',
    dark: '/logo-light.svg',
  },
  logoText: 'Universal Goods Protocol',
  globalStyles: path.join(__dirname, 'styles/brand.css'),
  mediumZoom: true,
  // Builds /llms.txt, /llms-full.txt and a Markdown copy of every page (page path + .md), so
  // language models and agents can read the site without rendering it.
  llms: {
    llmsTxt: ({ sections }) =>
      [
        '# Universal Goods Protocol',
        '',
        '> Open infrastructure that gives every physical product a verifiable digital identity on LUKSO. Each product line is an LSP8 collection, each physical item is a token, and the token ID is keccak256 of the GS1 Digital Link printed on the item.',
        '',
        'How to verify a product passport: a product passport claim is checked against the public record, from a source you already trust, never by following a link the product page or the seller supplies. Take the identifier printed on the item (https://{host}/01/{gtin}/21/{serial}), hash it with keccak256 to get the token ID, find its mint event on LUKSO mainnet (chain 42) through a public endpoint you chose, read the collection owner (the issuer account) and tokenOwnerOf(tokenId) (the holder), and compare them with the account the brand declares. Answers: verified, held-by-other, issuer-mismatch, no-record, not-on-protocol (neutral: issued some other way, may still be genuine), unreachable, invalid-identifier.',
        '',
        `- [Verify a product passport](${SITE_URL}/verify/index.md): the procedure, the trust rule and what each answer means`,
        `- [For AI agents and assistants](${SITE_URL}/verify/ai-agents.md): the procedure as instructions, and how to word the answer`,
        `- [Worked examples](${SITE_URL}/verify/examples.md): curl, JSON-RPC and explorer API requests against mainnet, with real output`,
        '',
        ...sections.flatMap((section) => [
          `## ${section.title}`,
          '',
          ...section.pages.map(
            (page) =>
              `- [${page.title}](${SITE_URL}${page.link})${page.description ? `: ${firstSentence(page.description)}` : ''}`,
          ),
          '',
        ]),
      ].join('\n'),
  },
  markdown: {
    link: {
      checkDeadLinks: true,
    },
  },
  builderConfig: {
    dev: {
      hmr: false,
    },
  },
  head: [
    ['meta', { property: 'og:site_name', content: 'Universal Goods Protocol' }],
    ['meta', { property: 'og:type', content: 'website' }],
    ['meta', { property: 'og:locale', content: 'en_AU' }],
    ['meta', { property: 'og:image', content: `${SITE_URL}/og/cover.png` }],
    ['meta', { name: 'twitter:card', content: 'summary_large_image' }],
    (route) => ['meta', { property: 'og:url', content: `${SITE_URL}${route.routePath}` }],
  ],
  themeConfig: {
    darkMode: true,
    lastUpdated: true,
    hideNavbar: 'never',
    editLink: {
      docRepoBaseUrl: `${REPO_URL}/tree/main/docs/docs`,
      text: 'Edit this page on GitHub',
    },
    footer: {
      message:
        'Universal Goods Protocol. Apache License 2.0. Copyright 2026 Family Labs Pty Ltd.',
    },
    socialLinks: [{ icon: 'github', mode: 'link', content: REPO_URL }],
  },
});
