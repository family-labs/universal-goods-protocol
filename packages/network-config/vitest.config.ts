import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { defineConfig } from 'vitest/config';

const __dirname = path.dirname(fileURLToPath(import.meta.url));

export default defineConfig({
  resolve: {
    alias: [
      {
        find: /^@universal-goods\/network-config$/,
        replacement: path.resolve(__dirname, 'src/index.ts'),
      },
    ],
  },
  test: {
    environment: 'node',

    include: ['tests/**/*.test.ts', 'src/**/*.test.ts'],
  },
});
