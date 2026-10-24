import { defineConfig } from 'vite';

export default defineConfig({
  server: { host: '127.0.0.1', port: 5173 },
  preview: { host: '127.0.0.1', port: 4173 },
  build: {
    // Firebase is most of the code; keep it in its own long-cached file.
    rolldownOptions: {
      output: {
        codeSplitting: {
          groups: [{ name: 'firebase', test: /node_modules[\\/](@firebase|firebase)/ }],
        },
      },
    },
    chunkSizeWarningLimit: 700,
  },
});
