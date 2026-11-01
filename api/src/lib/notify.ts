// Outgoing email/SMS. Development logs to the console. Production plugs in a real
// provider (an email API on a free tier; SMS only for phone OTP and receipts).
export interface Outbox { email(to: string, subject: string, text: string): Promise<void>; sms(to: string, text: string): Promise<void> }

export const sent: { channel: string; to: string; text: string }[] = [];

export const outbox: Outbox = {
  async email(to, subject, text) {
    sent.push({ channel: 'email', to, text: `${subject}\n${text}` });
    if (process.env.NODE_ENV !== 'test') console.log(`[email] to=${to} subject=${subject}\n${text}`);
  },
  async sms(to, text) {
    sent.push({ channel: 'sms', to, text });
    if (process.env.NODE_ENV !== 'test') console.log(`[sms] to=${to} ${text}`);
  },
};
