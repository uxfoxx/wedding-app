import { mkdirSync } from 'node:fs';
import { join } from 'node:path';
import { buildApp } from './app.ts';
import { config } from './config.ts';
import { migrate } from './migrate.ts';
import { seed } from './seed.ts';
import { startWorker } from './lib/jobs.ts';

if (config.env === 'production') {
  for (const [k, v] of [['GATEWAY_SECRET', config.gatewaySecret], ['PREVIEW_SECRET', config.previewSecret]]) {
    if (v.startsWith('dev-')) throw new Error(`${k} must be set in production`);
  }
}
mkdirSync(join(config.storageDir, 'site'), { recursive: true });
await migrate();
await seed();
const app = await buildApp();
if (config.runJobs) startWorker();
await app.listen({ port: config.port, host: '0.0.0.0' });
