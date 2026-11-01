// Object storage behind a CDN. Development uses a local folder that the API serves at /site.
// Production swaps in an S3-compatible client (Cloudflare R2 / S3) with the same interface,
// plus a CDN purge for paths that change.
import { mkdir, writeFile, rm, readdir } from 'node:fs/promises';
import { dirname, join, normalize } from 'node:path';
import { config } from '../config.ts';

export interface Storage {
  put(path: string, body: string | Buffer, contentType: string, cacheControl?: string): Promise<void>;
  del(path: string): Promise<void>;
  list(prefix: string): Promise<string[]>;
}

function safe(root: string, p: string): string {
  const full = normalize(join(root, p));
  if (!full.startsWith(normalize(root))) throw new Error('bad storage path');
  return full;
}

export class LocalStorage implements Storage {
  root: string;
  constructor(root: string) { this.root = root; }
  async put(path: string, body: string | Buffer) {
    const f = safe(this.root, path);
    await mkdir(dirname(f), { recursive: true });
    await writeFile(f, body);
  }
  async del(path: string) { await rm(safe(this.root, path), { force: true, recursive: true }); }
  async list(prefix: string) {
    try { return (await readdir(safe(this.root, prefix))).map((n) => join(prefix, n)); } catch { return []; }
  }
}

export const storage: Storage = new LocalStorage(config.storageDir);
