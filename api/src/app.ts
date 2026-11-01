import Fastify, { type FastifyInstance } from 'fastify';
import cors from '@fastify/cors';
import fastifyStatic from '@fastify/static';
import { existsSync, mkdirSync } from 'node:fs';
import { join } from 'node:path';
import { config } from './config.ts';
import { HttpError } from './lib/util.ts';
import authRoutes from './routes/auth.ts';
import weddingRoutes from './routes/weddings.ts';
import guestRoutes from './routes/guests.ts';
import publicRoutes from './routes/public.ts';
import paymentRoutes from './routes/payments.ts';
import adminRoutes from './routes/admin.ts';
import plannerRoutes from './routes/planners.ts';
import planningRoutes from './routes/planning.ts';
import experienceRoutes from './routes/experience.ts';

// Tiny per-IP, per-route rate limiter (requests per minute) for public and sign-in endpoints.
function rateLimiter(app: FastifyInstance) {
  const hits = new Map<string, { n: number; reset: number }>();
  setInterval(() => { const now = Date.now(); for (const [k, v] of hits) if (v.reset < now) hits.delete(k); }, 60_000).unref();
  app.addHook('onRequest', async (req) => {
    const limit = (req.routeOptions.config as any)?.rateLimit as number | undefined;
    if (!limit || config.env === 'test') return;
    const key = `${req.ip}:${req.routeOptions.url}`;
    const now = Date.now();
    const h = hits.get(key);
    if (!h || h.reset < now) { hits.set(key, { n: 1, reset: now + 60_000 }); return; }
    if (++h.n > limit) throw new HttpError(429, 'rate_limited', 'Too many requests. Please wait a minute.');
  });
}

export async function buildApp(): Promise<FastifyInstance> {
  for (const d of ['site', 'media']) mkdirSync(join(config.storageDir, d), { recursive: true });
  const app = Fastify({
    logger: config.env === 'test' ? false : { level: 'info' },
    bodyLimit: 2 * 1024 * 1024,
    trustProxy: true,
  });

  // Keep the raw body so payment webhooks can be signature-checked.
  app.addContentTypeParser('application/json', { parseAs: 'string' }, (req, body, done) => {
    (req as any).rawBody = body;
    if (!body) return done(null, {});
    try { done(null, JSON.parse(body as string)); } catch (e: any) { e.statusCode = 400; done(e, undefined); }
  });

  // Bearer tokens (no cookies), so any origin may call the API: the web panel, the guest pages on the CDN.
  await app.register(cors, { origin: true, methods: ['GET', 'POST', 'PATCH', 'PUT', 'DELETE'] });

  app.setErrorHandler((err: any, req, reply) => {
    if (err instanceof HttpError) {
      return reply.code(err.status).send({ error: err.code, message: err.message, ...err.extra });
    }
    if (err.statusCode && err.statusCode < 500) return reply.code(err.statusCode).send({ error: 'bad_request', message: err.message });
    if (err.code === '22P02') return reply.code(404).send({ error: 'not_found' }); // malformed uuid
    req.log.error(err);
    return reply.code(500).send({ error: 'server_error', message: 'Something went wrong on our side.' });
  });

  await app.register(async (api) => {
    rateLimiter(api);
    api.get('/health', async () => ({ ok: true }));
    await api.register(authRoutes);
    await api.register(weddingRoutes);
    await api.register(guestRoutes);
    await api.register(publicRoutes);
    await api.register(paymentRoutes);
    await api.register(adminRoutes);
    await api.register(plannerRoutes);
    await api.register(planningRoutes);
    await api.register(experienceRoutes);
  }, { prefix: '/api' });

  // Development: serve published guest pages (stand-in for the CDN) and the Flutter web panel.
  await app.register(fastifyStatic, { root: join(config.storageDir, 'site'), prefix: '/site/', decorateReply: false, cacheControl: false,
    setHeaders: (res) => { res.setHeader('cache-control', 'no-cache'); res.setHeader('x-content-type-options', 'nosniff'); } });
  await app.register(fastifyStatic, { root: join(config.storageDir, 'media'), prefix: '/media/', decorateReply: false,
    setHeaders: (res) => { res.setHeader('x-content-type-options', 'nosniff'); res.setHeader('content-security-policy', "default-src 'none'"); } });
  const panel = new URL('../../app/build/web', import.meta.url).pathname;
  if (existsSync(panel)) {
    await app.register(fastifyStatic, { root: panel, prefix: '/panel/', decorateReply: false });
  }
  app.get('/', async (_req, reply) => reply.redirect('/panel/'));
  return app;
}
