-- Staff two-factor sign-in with an authenticator app. The secret is encrypted by the API;
-- totp_last_step stops a code being used twice. A session counts as verified for 12 hours.
ALTER TABLE users ADD COLUMN totp_secret text, ADD COLUMN totp_enabled_at timestamptz, ADD COLUMN totp_last_step bigint;
ALTER TABLE sessions ADD COLUMN mfa_at timestamptz;
