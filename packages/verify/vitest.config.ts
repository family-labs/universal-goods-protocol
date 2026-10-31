import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { defineConfig } from 'vitest/config';

const __dirname = path.dirname(fileURLToPath(import.meta.url));

// Tests run against the workspace packages' sources, so they need no build first.
export default defineConfig({
  resolve: {
    alias: [
      {
        find: /^@universal-goods\/network-config$/,
        replacement: path.resolve(__dirname, '../network-config/src/index.ts'),
      },
      {
        find: /^@universal-goods\/lsp-utils$/,
        replacement: path.resolve(__dirname, '../lsp-utils/src/index.ts'),
      },
    ],
  },
  test: {
    environment: 'node',
    include: ['tests/**/*.test.ts'],
    testTimeout: 60_000,
  },
});
