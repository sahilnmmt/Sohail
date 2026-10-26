import { fileURLToPath } from 'node:url';
import { createApp } from './app.ts';

const port = Number(process.env.PORT ?? 8787);
const host = process.env.HOST ?? '127.0.0.1';
const staticDir = fileURLToPath(new URL('../../dist', import.meta.url));

createApp({ staticDir }).listen(port, host, () => {
  console.log(`Price compare running at http://${host === '0.0.0.0' ? 'localhost' : host}:${port}`);
});
