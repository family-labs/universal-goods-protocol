import * as path from 'node:path';
import { defineConfig } from '@rspress/core';

const SITE_URL = 'https://docs.universalgoods.org';
const REPO_URL = 'https://github.com/family-labs/universal-goods-protocol';

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
