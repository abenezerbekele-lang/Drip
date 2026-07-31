import { AppError } from './errors.js';

const MAX_PROVIDER_RESPONSE_BYTES = 64 * 1024;

function unavailable() {
  return new AppError(
    503,
    'email_provider_unavailable',
    'Email delivery is temporarily unavailable. Try again shortly.',
    undefined,
    true,
  );
}

function escapeHtml(value) {
  return value.replace(/[&<>"']/g, (character) => ({
    '&': '&amp;',
    '<': '&lt;',
    '>': '&gt;',
    '"': '&quot;',
    "'": '&#39;',
  })[character]);
}

class DisabledEmailClient {
  async sendVerification() {
    throw unavailable();
  }

  async sendWelcome() {
    throw unavailable();
  }
}

class ResendEmailClient {
  #apiKey;
  #from;
  #timeoutMs;
  #fetch;

  constructor({ apiKey, from, timeoutMs, fetchImpl }) {
    this.#apiKey = apiKey;
    this.#from = from;
    this.#timeoutMs = timeoutMs;
    this.#fetch = fetchImpl;
  }

  async sendWelcome({ to, name, idempotencyKey }) {
    const textName = String(name).replace(/[\r\n]/g, ' ').slice(0, 240);
    const htmlName = escapeHtml(textName);
    return this.#send({
      to,
      idempotencyKey,
      subject: 'Welcome to Drip!',
      text:
        `Hi ${textName},\n\nWelcome to Drip! Your account is ready. ` +
        'You can now save pieces, build fits, and check out securely.',
      html:
        `<p>Hi ${htmlName},</p>` +
        '<p>Welcome to Drip! Your account is ready. You can now save ' +
        'pieces, build fits, and check out securely.</p>',
      messageType: 'welcome',
    });
  }

  async sendVerification({
    to,
    name,
    code,
    expiresInMinutes,
    idempotencyKey,
  }) {
    if (!/^[0-9]{6}$/.test(code)) throw unavailable();
    const textName = String(name).replace(/[\r\n]/g, ' ').slice(0, 240);
    const htmlName = escapeHtml(textName);
    const minutes = Number.isSafeInteger(expiresInMinutes)
      ? Math.max(1, Math.min(expiresInMinutes, 60))
      : 10;
    return this.#send({
      to,
      idempotencyKey,
      subject: `${code} is your Drip confirmation code`,
      text:
        `Hi ${textName},\n\nYour Drip confirmation code is ${code}. ` +
        `It expires in ${minutes} minutes. Never share this code with anyone.`,
      html:
        `<p>Hi ${htmlName},</p>` +
        '<p>Use this confirmation code to finish creating your Drip account:</p>' +
        `<p style="font-size:28px;font-weight:700;letter-spacing:6px">${code}</p>` +
        `<p>It expires in ${minutes} minutes. Never share this code with anyone.</p>`,
      messageType: 'email_verification',
    });
  }

  async #send({ to, idempotencyKey, subject, text, html, messageType }) {
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), this.#timeoutMs);
    timeout.unref?.();
    try {
      const response = await this.#fetch('https://api.resend.com/emails', {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${this.#apiKey}`,
          'Content-Type': 'application/json',
          'Idempotency-Key': idempotencyKey,
          'User-Agent': 'drip-server/1.0',
        },
        body: JSON.stringify({
          from: this.#from,
          to: [to],
          subject,
          text,
          html,
          tags: [{ name: 'message_type', value: messageType }],
        }),
        signal: controller.signal,
      });
      const declaredLength = Number(response.headers?.get?.('content-length'));
      if (
        Number.isFinite(declaredLength) &&
        declaredLength > MAX_PROVIDER_RESPONSE_BYTES
      ) {
        throw unavailable();
      }
      const raw = await response.text();
      if (Buffer.byteLength(raw) > MAX_PROVIDER_RESPONSE_BYTES) {
        throw unavailable();
      }
      let payload;
      try {
        payload = JSON.parse(raw);
      } catch {
        throw unavailable();
      }
      if (
        !response.ok ||
        typeof payload?.id !== 'string' ||
        payload.id.length < 1 ||
        payload.id.length > 200
      ) {
        throw unavailable();
      }
      return Object.freeze({ providerMessageId: payload.id });
    } catch (error) {
      if (error instanceof AppError) throw error;
      throw unavailable();
    } finally {
      clearTimeout(timeout);
    }
  }
}

export function createRealEmailClient(config, fetchImpl = globalThis.fetch) {
  if (!config.emailConfigured) return new DisabledEmailClient();
  if (typeof fetchImpl !== 'function') {
    throw new AppError(
      500,
      'invalid_configuration',
      'The email provider requires fetch support.',
    );
  }
  return new ResendEmailClient({
    apiKey: config.resendApiKey,
    from: config.welcomeEmailFrom,
    timeoutMs: config.emailTimeoutMs,
    fetchImpl,
  });
}
