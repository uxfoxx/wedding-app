// All settings come from environment variables. Defaults suit local development.
const env = process.env;

export const config = {
  env: env.NODE_ENV ?? 'development',
  port: Number(env.PORT ?? 8080),
  databaseUrl: env.DATABASE_URL ?? 'postgres://wed:wed@localhost:5432/wedding',
  // Where the API is reachable (used in links sent to users).
  publicApiUrl: env.PUBLIC_API_URL ?? 'http://localhost:8080',
  // Where published guest pages are served from (a CDN in production).
  guestBaseUrl: env.GUEST_BASE_URL ?? 'http://localhost:8080/site',
  // Local folder standing in for object storage + CDN in development.
  storageDir: env.STORAGE_DIR ?? new URL('../../storage', import.meta.url).pathname,
  webPanelUrl: env.WEB_PANEL_URL ?? 'http://localhost:8080/panel',
  // Public URL of uploaded photos, videos and voice notes (object storage + CDN in production).
  mediaBaseUrl: env.MEDIA_BASE_URL ?? 'http://localhost:8080/media',
  // Comma-separated emails that get the admin staff role on sign-in.
  adminEmails: (env.ADMIN_EMAILS ?? '').split(',').map((s) => s.trim().toLowerCase()).filter(Boolean),
  googleClientIds: (env.GOOGLE_CLIENT_IDS ?? '').split(',').filter(Boolean),
  appleClientIds: (env.APPLE_CLIENT_IDS ?? '').split(',').filter(Boolean),
  // Shared secret for the payment gateway's webhook signature.
  gatewaySecret: env.GATEWAY_SECRET ?? 'dev-gateway-secret',
  // Signs short-lived preview links so apps can open the preview in a browser view.
  previewSecret: env.PREVIEW_SECRET ?? 'dev-preview-secret',
  // In development, sign-in codes are returned in the API response instead of being sent.
  exposeDevCodes: (env.EXPOSE_DEV_CODES ?? (env.NODE_ENV === 'production' ? 'false' : 'true')) === 'true',
  runJobs: (env.RUN_JOBS ?? 'true') === 'true',
} as const;

// Phase 1 prices and free-plan limits (proposals from the feature document).
export const pricing = {
  passWebLkr: Number(env.PASS_WEB_LKR ?? 7900),
  // In-app purchase price covers the store's commission.
  passAppLkr: Number(env.PASS_APP_LKR ?? 9900),
  designForMeLkr: Number(env.DESIGN_FOR_ME_LKR ?? 5000),
  freeGuestLimit: Number(env.FREE_GUEST_LIMIT ?? 50),
  freeEventLimit: 1,
  refundWindowDays: 7,
  passAccessMonthsAfterLastEvent: 12,
  purgeContactsMonthsAfterLastEvent: 12,
  followUpAfterDays: 7,
  // Guest uploads (per file, and per wedding in total). Storage is paid per GB.
  maxPhotoBytes: 12 * 1024 * 1024,
  maxVideoBytes: 150 * 1024 * 1024,
  maxVoiceBytes: 6 * 1024 * 1024,
  weddingStorageMb: Number(env.WEDDING_STORAGE_MB ?? 3000),
} as const;
