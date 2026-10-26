import { defineConfig } from 'vite';

export default defineConfig({
  // `npm run dev` runs the API server on 8787 next to Vite.
  server: { host: '127.0.0.1', port: 5174, proxy: { '/api': 'http://127.0.0.1:8787' } },
  build: { outDir: 'dist' },
});
