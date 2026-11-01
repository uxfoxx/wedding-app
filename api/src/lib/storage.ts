// Object storage behind a CDN. Development uses a local folder that the API serves at /site.
// Production swaps in an S3-compatible client (Cloudflare R2 / S3) with the same interface,
// plus a CDN purge for paths that change.
import { mkdir, writeFile, rm, readdir, stat } from 'node:fs/promises';
import { dirname, join, normalize } from 'node:path';
import { config } from '../config.ts';

export interface Storage {
  put(path: string, body: string | Buffer, contentType: string, cacheControl?: string): Promise<void>;
  del(path: string): Promise<void>;
  list(prefix: string): Promise<string[]>;
  /** Size in bytes, or null if missing (production: a HEAD request to object storage). */
  size(path: string): Promise<number | null>;
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
  async size(path: string) {
    try { return (await stat(safe(this.root, path))).size; } catch { return null; }
  }
  async list(prefix: string) {
    try { return (await readdir(safe(this.root, prefix))).map((n) => join(prefix, n)); } catch { return []; }
  }
}

/**
 * S3-compatible object storage (Cloudflare R2, AWS S3, Backblaze B2…). Guest pages and media are
 * served from the bucket's public URL / CDN; the API only writes small files and signs uploads.
 */
export class S3Storage implements Storage {
  client: any;
  bucket: string;
  mod: any;
  presign: any;
  constructor(bucket: string) { this.bucket = bucket; }
  async init() {
    this.mod = await import('@aws-sdk/client-s3');
    this.presign = (await import('@aws-sdk/s3-request-presigner')).getSignedUrl;
    this.client = new this.mod.S3Client({
      region: process.env.S3_REGION ?? 'auto',
      endpoint: process.env.S3_ENDPOINT || undefined,               // e.g. https://<account>.r2.cloudflarestorage.com
      credentials: { accessKeyId: process.env.S3_ACCESS_KEY_ID ?? '', secretAccessKey: process.env.S3_SECRET_ACCESS_KEY ?? '' },
      forcePathStyle: !!process.env.S3_ENDPOINT,
    });
    return this;
  }
  async put(path: string, body: string | Buffer, contentType: string, cacheControl?: string) {
    await this.client.send(new this.mod.PutObjectCommand({ Bucket: this.bucket, Key: path, Body: body, ContentType: contentType, CacheControl: cacheControl }));
  }
  async del(path: string) {
    // Deleting a "folder" removes everything under it.
    const keys = path.includes('.') ? [path] : await this.list(path, true);
    for (const Key of keys) await this.client.send(new this.mod.DeleteObjectCommand({ Bucket: this.bucket, Key }));
  }
  async list(prefix: string, deep = false) {
    const out: string[] = [];
    let token: string | undefined;
    do {
      const r = await this.client.send(new this.mod.ListObjectsV2Command({ Bucket: this.bucket, Prefix: prefix.replace(/\/?$/, '/'), ContinuationToken: token, Delimiter: deep ? undefined : '/' }));
      for (const o of r.Contents ?? []) out.push(o.Key);
      token = r.IsTruncated ? r.NextContinuationToken : undefined;
    } while (token);
    return out;
  }
  async size(path: string) {
    try { return (await this.client.send(new this.mod.HeadObjectCommand({ Bucket: this.bucket, Key: path }))).ContentLength ?? null; } catch { return null; }
  }
  async signedPut(path: string, contentType: string, bytes: number): Promise<string> {
    return this.presign(this.client, new this.mod.PutObjectCommand({ Bucket: this.bucket, Key: path, ContentType: contentType, ContentLength: bytes }), { expiresIn: 3600 });
  }
}

const s3 = process.env.S3_BUCKET ? await new S3Storage(process.env.S3_BUCKET).init() : null;
export const storage: Storage = s3 ?? new LocalStorage(config.storageDir);
export const usingObjectStorage = !!s3;

/**
 * Where the browser sends the file bytes: a presigned PUT straight to object storage, so the
 * 1 GB server never handles file bytes (architecture decision 4). Without object storage
 * (development) the API stands in at /api/dev-upload/<token>.
 */
export async function uploadTarget(path: string, contentType: string, bytes: number, devToken: string): Promise<string> {
  if (s3) return s3.signedPut(path, contentType, bytes);
  return `${config.publicApiUrl}/api/dev-upload/${devToken}`;
}
export function mediaUrl(path: string): string {
  return `${config.mediaBaseUrl}/${path.replace(/^media\//, '')}`;
}
