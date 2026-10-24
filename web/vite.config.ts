import { defineConfig } from 'vite';

import { resolve } from 'node:path';

export default defineConfig({
  // The virtual robot loads the firmware's WebAssembly build from ../firmware.
  server: { host: '127.0.0.1', port: 5173, fs: { allow: ['..'] } },
  preview: { host: '127.0.0.1', port: 4173 },
  build: {
    // Firebase is most of the code; keep it in its own long-cached file.
    rolldownOptions: {
      input: { main: resolve(__dirname, 'index.html'), robot: resolve(__dirname, 'robot.html') },
      output: {
        codeSplitting: {
          groups: [{ name: 'firebase', test: /node_modules[\\/](@firebase|firebase)/ }],
        },
      },
    },
    chunkSizeWarningLimit: 700,
  },
});
