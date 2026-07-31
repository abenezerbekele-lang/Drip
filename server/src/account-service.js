import {
  createHash,
  createHmac,
  randomBytes,
  randomInt,
  scrypt,
  timingSafeEqual,
} from 'node:crypto';

import { signAccessToken } from './auth.js';
import { immediateTransaction } from './database.js';
import { AppError } from './errors.js';

const SCRYPT_N = 32_768;
const SCRYPT_R = 8;
const SCRYPT_P = 3;
const SCRYPT_KEY_LENGTH = 64;
const SCRYPT_MAX_MEMORY = 64 * 1024 * 1024;
const DUMMY_SALT = Buffer.from('d9b1e375d8c34fc6a7b8ea2114b12f91', 'hex');
const MAX_WELCOME_ATTEMPTS = 5;
const WELCOME_IDEMPOTENCY_WINDOW_SECONDS = 23 * 60 * 60;
const WELCOME_CLAIM_LEASE_SECONDS = 5 * 60;
const WELCOME_RETRY_DELAYS_SECONDS = Object.freeze([60, 5 * 60, 15 * 60, 60 * 60]);
const MAX_VERIFICATION_ATTEMPTS = 5;
const VERIFICATION_RESEND_WINDOW_SECONDS = 60 * 60;
const COMMON_PASSWORDS = new Set([
  '123456789012',
  'password1234',
  'password123!',
  'qwertyuiop12',
  'letmein12345',
  'welcome12345',
  'iloveyou1234',
  'adminadmin12',
  'dripdrip1234',
]);

function exactObject(value, allowed, name) {
  if (value === null || typeof value !== 'object' || Array.isArray(value)) {
    throw new AppError(422, 'invalid_request', `${name} must be an object.`);
  }
  for (const key of Object.keys(value)) {
    if (!allowed.has(key)) {
      throw new AppError(
        422,
        'invalid_request',
        `${name} contains an unsupported field.`,
      );
    }
  }
  for (const key of allowed) {
    if (!Object.prototype.hasOwnProperty.call(value, key)) {
      throw new AppError(422, 'invalid_request', `${key} is required.`);
    }
  }
}

export function normalizeEmail(value) {
  if (typeof value !== 'string') {
    throw new AppError(422, 'invalid_email', 'Enter a valid email address.');
  }
  const email = value.normalize('NFKC').trim().toLowerCase();
  if (
    email.length < 3 ||
    email.length > 254 ||
    !/^[a-z0-9.!#$%&'*+/=?^_`{|}~-]+@[a-z0-9-]+(?:\.[a-z0-9-]+)+$/.test(
      email,
    )
  ) {
    throw new AppError(422, 'invalid_email', 'Enter a valid email address.');
  }
  const [local, ...domainParts] = email.split('@');
  const domain = domainParts.join('@');
  if (
    local.length > 64 ||
    local.startsWith('.') ||
    local.endsWith('.') ||
    local.includes('..') ||
    domainParts.length !== 1 ||
    domain.split('.').some(
      (label) =>
        !label ||
        label.length > 63 ||
        label.startsWith('-') ||
        label.endsWith('-'),
    )
  ) {
    throw new AppError(422, 'invalid_email', 'Enter a valid email address.');
  }
  return email;
}

export function normalizeDisplayName(value) {
  if (typeof value !== 'string') {
    throw new AppError(422, 'invalid_name', 'Enter your name.');
  }
  const name = value.normalize('NFKC').trim().replace(/\s+/gu, ' ');
  if (
    [...name].length < 1 ||
    [...name].length > 80 ||
    Buffer.byteLength(name) > 240 ||
    /\p{Cc}/u.test(name)
  ) {
    throw new AppError(
      422,
      'invalid_name',
      'Use a name between 1 and 80 characters.',
    );
  }
  return name;
}

function validateStrongPassword(password, email) {
  if (typeof password !== 'string') {
    throw new AppError(422, 'weak_password', 'Choose a stronger password.');
  }
  const characters = [...password];
  if (
    characters.length < 12 ||
    characters.length > 128 ||
    Buffer.byteLength(password) > 512 ||
    /\p{Cc}/u.test(password)
  ) {
    throw new AppError(
      422,
      'weak_password',
      'Use 12 to 128 characters with no control characters.',
    );
  }
  const categories = [
    /\p{Ll}/u.test(password),
    /\p{Lu}/u.test(password),
    /\p{N}/u.test(password),
    /[^\p{L}\p{N}\s]/u.test(password),
  ].filter(Boolean).length;
  const simplified = password.trim().toLowerCase();
  const localPart = email.split('@')[0];
  if (
    categories < 3 ||
    COMMON_PASSWORDS.has(simplified) ||
    (localPart.length >= 4 && simplified.includes(localPart))
  ) {
    throw new AppError(
      422,
      'weak_password',
      'Use a longer, uncommon password with at least three of: lowercase, uppercase, numbers, and symbols.',
    );
  }
}

function derivePassword(password, salt, options = {}) {
  return new Promise((resolve, reject) => {
    scrypt(
      password,
      salt,
      SCRYPT_KEY_LENGTH,
      {
        N: options.N ?? SCRYPT_N,
        r: options.r ?? SCRYPT_R,
        p: options.p ?? SCRYPT_P,
        maxmem: SCRYPT_MAX_MEMORY,
      },
      (error, key) => {
        if (error) reject(error);
        else resolve(key);
      },
    );
  });
}

async function hashPassword(password) {
  const salt = randomBytes(16);
  const key = await derivePassword(password, salt);
  return [
    'scrypt',
    SCRYPT_N,
    SCRYPT_R,
    SCRYPT_P,
    salt.toString('base64url'),
    key.toString('base64url'),
  ].join('$');
}

async function verifyPassword(password, encoded) {
  const parts = typeof encoded === 'string' ? encoded.split('$') : [];
  if (
    parts.length !== 6 ||
    parts[0] !== 'scrypt' ||
    Number(parts[1]) !== SCRYPT_N ||
    Number(parts[2]) !== SCRYPT_R ||
    Number(parts[3]) !== SCRYPT_P
  ) {
    await derivePassword(password, DUMMY_SALT);
    return false;
  }
  let salt;
  let expected;
  try {
    salt = Buffer.from(parts[4], 'base64url');
    expected = Buffer.from(parts[5], 'base64url');
  } catch {
    await derivePassword(password, DUMMY_SALT);
    return false;
  }
  if (salt.length !== 16 || expected.length !== SCRYPT_KEY_LENGTH) {
    await derivePassword(password, DUMMY_SALT);
    return false;
  }
  const actual = await derivePassword(password, salt);
  return timingSafeEqual(actual, expected);
}

async function burnPasswordCheck(password) {
  await derivePassword(password, DUMMY_SALT);
}

function invalidCredentials() {
  return new AppError(
    401,
    'invalid_credentials',
    'Email or password is incorrect.',
  );
}

function invalidVerificationCode() {
  return new AppError(
    422,
    'invalid_verification_code',
    'That confirmation code is invalid or expired. Request a new code and try again.',
  );
}

function invalidVerificationChallenge() {
  return new AppError(
    422,
    'invalid_verification_challenge',
    'This signup confirmation is no longer valid. Start creating your account again.',
  );
}

function verificationCode() {
  return randomInt(0, 1_000_000).toString().padStart(6, '0');
}

function challengeDigest(secret, challengeToken) {
  return createHmac('sha256', secret)
    .update(`drip-email-challenge:v1:${challengeToken}`)
    .digest('hex');
}

function verificationDigest(secret, accountId, challengeHash, idempotencyKey, code) {
  return createHmac('sha256', secret)
    .update(
      `drip-email-verification:v1:${accountId}:${challengeHash}:${idempotencyKey}:${code}`,
    )
    .digest('hex');
}

function verificationResponse(
  email,
  expiresAt,
  resendAvailableAt,
  challengeToken,
) {
  return Object.freeze({
    verification: Object.freeze({
      email,
      expiresAt: new Date(expiresAt * 1000).toISOString(),
      resendAvailableAt: new Date(resendAvailableAt * 1000).toISOString(),
      challengeToken,
    }),
  });
}

function validChallengeToken(value) {
  return (
    typeof value === 'string' &&
    value.length >= 43 &&
    value.length <= 200 &&
    /^[A-Za-z0-9_-]+$/.test(value)
  );
}

function assertProviderDelivery(delivery) {
  if (
    typeof delivery?.providerMessageId !== 'string' ||
    delivery.providerMessageId.length < 1 ||
    delivery.providerMessageId.length > 200
  ) {
    throw new AppError(
      503,
      'email_provider_unavailable',
      'Email delivery is temporarily unavailable. Try again shortly.',
      undefined,
      true,
    );
  }
}

function publicUser(row) {
  return Object.freeze({
    id: row.id,
    name: row.name,
    email: row.email,
    sellerHandle: row.sellerHandle,
  });
}

function sellerHandleFor(accountId, name) {
  const base = name
    .normalize('NFKD')
    .replace(/\p{M}/gu, '')
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-|-$/g, '')
    .slice(0, 24) || 'member';
  const suffix = createHash('sha256').update(accountId).digest('hex').slice(0, 10);
  return `@${base}-${suffix}`;
}

function sessionResponse(accessToken, expiresAt) {
  return Object.freeze({
    accessToken,
    tokenType: 'Bearer',
    expiresAt: new Date(expiresAt * 1000).toISOString(),
  });
}

function sqliteUniqueEmail(error) {
  return String(error?.message || '').includes(
    'UNIQUE constraint failed: accounts.email',
  );
}

export class AccountService {
  #database;
  #emailClient;
  #config;
  #clock;

  constructor({ database, emailClient, config, clock = () => Date.now() }) {
    this.#database = database;
    this.#emailClient = emailClient;
    this.#config = config;
    this.#clock = clock;
  }

  async register(body, requester = 'unknown') {
    this.#assertAvailable();
    exactObject(
      body,
      new Set(['name', 'email', 'password']),
      'Signup request',
    );
    const name = normalizeDisplayName(body.name);
    const email = normalizeEmail(body.email);
    validateStrongPassword(body.password, email);
    this.#consumeRateLimit('signup', requester, email);
    const now = this.#now();
    const existing = this.#database
      .prepare(`
        SELECT accounts.id, accounts.display_name AS name, accounts.email,
               accounts.password_hash AS passwordHash, accounts.status,
               accounts.email_verified_at AS emailVerifiedAt,
               accounts.created_at AS createdAt,
               verification.last_sent_at AS lastSentAt,
               verification.resend_window_start AS resendWindowStart,
               verification.resend_count AS resendCount,
               verification.consumed_at AS consumedAt
          FROM accounts
          LEFT JOIN email_verifications AS verification
            ON verification.account_id = accounts.id
         WHERE accounts.email = ?
      `)
      .get(email);
    if (existing) {
      const pending =
        existing.status === 'active' &&
        existing.emailVerifiedAt === null &&
        existing.consumedAt === null;
      const abandoned =
        pending &&
        existing.createdAt + this.#config.authPendingAccountTtlSeconds <= now;
      if (abandoned) {
        immediateTransaction(this.#database, () => {
          this.#database
            .prepare('DELETE FROM email_verifications WHERE account_id = ?')
            .run(existing.id);
          this.#database
            .prepare(`
              DELETE FROM accounts
               WHERE id = ? AND email_verified_at IS NULL
                 AND created_at = ?
            `)
            .run(existing.id, existing.createdAt);
        });
      } else {
        const passwordMatches = await verifyPassword(
          body.password,
          existing.passwordHash,
        );
        if (passwordMatches && pending) {
          return this.#rotateVerification(existing);
        }
        throw new AppError(
          409,
          'account_exists',
          'An account with that email already exists.',
        );
      }
    }
    const passwordHash = await hashPassword(body.password);
    const account = {
      id: `usr_${randomBytes(18).toString('base64url')}`,
      name,
      email,
    };
    const challengeToken = randomBytes(32).toString('base64url');
    const challengeHash = challengeDigest(
      this.#config.authRateLimitSecret,
      challengeToken,
    );
    const code = verificationCode();
    const idempotencyKey = `verify-${randomBytes(18).toString('base64url')}`;
    const expiresAt = now + this.#config.authVerificationCodeTtlSeconds;
    const resendAvailableAt =
      now + this.#config.authVerificationResendCooldownSeconds;
    const codeDigest = verificationDigest(
      this.#config.authRateLimitSecret,
      account.id,
      challengeHash,
      idempotencyKey,
      code,
    );
    try {
      immediateTransaction(this.#database, () => {
        this.#database
          .prepare(`
            INSERT INTO accounts (
              id, display_name, email, password_hash, status,
              created_at, updated_at
            ) VALUES (?, ?, ?, ?, 'active', ?, ?)
          `)
          .run(account.id, name, email, passwordHash, now, now);
        this.#database
          .prepare(`
            INSERT INTO email_verifications (
              account_id, challenge_digest, code_digest, idempotency_key, expires_at,
              attempt_count, resend_window_start, resend_count,
              last_sent_at, created_at, updated_at
            ) VALUES (?, ?, ?, ?, ?, 0, ?, 0, ?, ?, ?)
          `)
          .run(
            account.id,
            challengeHash,
            codeDigest,
            idempotencyKey,
            expiresAt,
            now,
            now,
            now,
            now,
          );
      });
    } catch (error) {
      if (sqliteUniqueEmail(error)) {
        throw new AppError(
          409,
          'account_exists',
          'An account with that email already exists.',
        );
      }
      throw error;
    }
    let delivery;
    try {
      delivery = await this.#emailClient.sendVerification({
        to: email,
        name,
        code,
        expiresInMinutes: Math.ceil(
          this.#config.authVerificationCodeTtlSeconds / 60,
        ),
        idempotencyKey,
      });
      assertProviderDelivery(delivery);
    } catch (error) {
      if (error instanceof AppError) throw error;
      throw new AppError(
        503,
        'email_provider_unavailable',
        'Email delivery is temporarily unavailable. Try again shortly.',
        undefined,
        true,
      );
    }
    this.#database
      .prepare(`
        UPDATE email_verifications
           SET provider_message_id = ?, updated_at = ?
         WHERE account_id = ? AND idempotency_key = ? AND consumed_at IS NULL
      `)
      .run(delivery.providerMessageId, this.#now(), account.id, idempotencyKey);
    return verificationResponse(
      email,
      expiresAt,
      resendAvailableAt,
      challengeToken,
    );
  }

  async verifyEmail(body, requester = 'unknown') {
    this.#assertAvailable();
    exactObject(
      body,
      new Set(['challengeToken', 'code']),
      'Email verification request',
    );
    const challengeToken = validChallengeToken(body.challengeToken)
      ? body.challengeToken
      : '';
    const code = typeof body.code === 'string' ? body.code : '';
    const challengeHash = challengeDigest(
      this.#config.authRateLimitSecret,
      challengeToken,
    );
    this.#consumeVerificationRateLimit('verify', requester, challengeHash);
    const now = this.#now();
    const row = this.#database
      .prepare(`
        SELECT accounts.id, accounts.display_name AS name, accounts.email,
               accounts.status, accounts.email_verified_at AS emailVerifiedAt,
               verification.code_digest AS codeDigest,
               verification.challenge_digest AS challengeDigest,
               verification.idempotency_key AS idempotencyKey,
               verification.expires_at AS verificationExpiresAt,
               verification.attempt_count AS attemptCount,
               verification.consumed_at AS consumedAt
          FROM accounts
          LEFT JOIN email_verifications AS verification
            ON verification.account_id = accounts.id
         WHERE verification.challenge_digest = ?
      `)
      .get(challengeHash);
    if (
      !challengeToken ||
      !/^[0-9]{6}$/.test(code) ||
      !row ||
      row.status !== 'active' ||
      row.emailVerifiedAt !== null ||
      row.consumedAt !== null ||
      row.verificationExpiresAt <= now ||
      row.attemptCount >= MAX_VERIFICATION_ATTEMPTS
    ) {
      throw invalidVerificationCode();
    }
    const actualDigest = verificationDigest(
      this.#config.authRateLimitSecret,
      row.id,
      row.challengeDigest,
      row.idempotencyKey,
      code,
    );
    const matches = timingSafeEqual(
      Buffer.from(actualDigest, 'hex'),
      Buffer.from(row.codeDigest, 'hex'),
    );
    if (!matches) {
      this.#database
        .prepare(`
          UPDATE email_verifications
             SET attempt_count = attempt_count + 1, updated_at = ?
           WHERE account_id = ? AND consumed_at IS NULL
             AND expires_at > ? AND attempt_count < ${MAX_VERIFICATION_ATTEMPTS}
        `)
        .run(now, row.id, now);
      throw invalidVerificationCode();
    }

    const sellerHandle = sellerHandleFor(row.id, row.name);
    const sessionId = `ses_${randomBytes(24).toString('base64url')}`;
    const sessionExpiresAt = now + this.#config.authSessionTtlSeconds;
    immediateTransaction(this.#database, () => {
      const consumed = this.#database
        .prepare(`
          UPDATE email_verifications
             SET consumed_at = ?, updated_at = ?
           WHERE account_id = ? AND code_digest = ? AND consumed_at IS NULL
             AND expires_at > ? AND attempt_count < ${MAX_VERIFICATION_ATTEMPTS}
        `)
        .run(now, now, row.id, actualDigest, now);
      if (consumed.changes !== 1) throw invalidVerificationCode();
      const verified = this.#database
        .prepare(`
          UPDATE accounts
             SET email_verified_at = ?, updated_at = ?
           WHERE id = ? AND status = 'active' AND email_verified_at IS NULL
        `)
        .run(now, now, row.id);
      if (verified.changes !== 1) throw invalidVerificationCode();
      this.#database
        .prepare(`
          INSERT INTO seller_accounts (
            seller_handle, seller_name, owner_account_id, is_pro,
            transfers_ready, updated_at
          ) VALUES (?, ?, ?, 0, 0, ?)
        `)
        .run(sellerHandle, row.name, row.id, now);
      this.#database
        .prepare(`
          INSERT INTO welcome_email_outbox (
            account_id, idempotency_key, status, attempt_count,
            next_attempt_at, created_at, updated_at
          ) VALUES (?, ?, 'pending', 0, ?, ?, ?)
        `)
        .run(row.id, `welcome-${row.id}`, now, now, now);
      this.#database
        .prepare(`
          INSERT INTO account_sessions (
            id, account_id, expires_at, created_at
          ) VALUES (?, ?, ?, ?)
        `)
        .run(sessionId, row.id, sessionExpiresAt, now);
    });
    const accessToken = signAccessToken(this.#config, {
      accountId: row.id,
      sessionId,
      issuedAt: now,
      expiresAt: sessionExpiresAt,
      sellerHandle,
    });
    await this.drainWelcomeEmails({ accountId: row.id, limit: 1 });
    const welcomeStatus = this.#welcomeEmailStatus(row.id);
    return Object.freeze({
      user: publicUser({ ...row, sellerHandle }),
      session: sessionResponse(accessToken, sessionExpiresAt),
      welcomeEmailSent: welcomeStatus === 'sent',
      welcomeEmail: Object.freeze({ status: welcomeStatus }),
    });
  }

  async resendVerification(body, requester = 'unknown') {
    this.#assertAvailable();
    exactObject(
      body,
      new Set(['challengeToken']),
      'Verification resend request',
    );
    const usableChallenge = validChallengeToken(body.challengeToken)
      ? body.challengeToken
      : '';
    const challengeHash = challengeDigest(
      this.#config.authRateLimitSecret,
      usableChallenge,
    );
    this.#consumeVerificationRateLimit('resend', requester, challengeHash);
    if (!usableChallenge) throw invalidVerificationChallenge();
    const now = this.#now();
    const row = this.#database
      .prepare(`
        SELECT accounts.id, accounts.display_name AS name, accounts.email,
               accounts.status,
               accounts.email_verified_at AS emailVerifiedAt,
               verification.challenge_digest AS challengeDigest,
               verification.last_sent_at AS lastSentAt,
               verification.resend_window_start AS resendWindowStart,
               verification.resend_count AS resendCount,
               verification.consumed_at AS consumedAt
          FROM accounts
          LEFT JOIN email_verifications AS verification
            ON verification.account_id = accounts.id
         WHERE verification.challenge_digest = ?
      `)
      .get(challengeHash);
    if (
      !row ||
      row.status !== 'active' ||
      row.emailVerifiedAt !== null ||
      row.consumedAt !== null
    ) {
      throw invalidVerificationChallenge();
    }
    const cooldownUntil =
      row.lastSentAt + this.#config.authVerificationResendCooldownSeconds;
    if (cooldownUntil > now) {
      throw this.#verificationRateLimit(
        'Wait before requesting another confirmation code.',
        cooldownUntil - now,
      );
    }
    const inCurrentWindow =
      row.resendWindowStart + VERIFICATION_RESEND_WINDOW_SECONDS > now;
    if (
      inCurrentWindow &&
      row.resendCount >= this.#config.authVerificationResendLimitPerHour
    ) {
      throw this.#verificationRateLimit(
        'Too many confirmation emails. Try again later.',
        row.resendWindowStart + VERIFICATION_RESEND_WINDOW_SECONDS - now,
      );
    }

    const code = verificationCode();
    const idempotencyKey = `verify-${randomBytes(18).toString('base64url')}`;
    const expiresAt = now + this.#config.authVerificationCodeTtlSeconds;
    const resendAvailableAt =
      now + this.#config.authVerificationResendCooldownSeconds;
    const codeDigest = verificationDigest(
      this.#config.authRateLimitSecret,
      row.id,
      row.challengeDigest,
      idempotencyKey,
      code,
    );
    const resendWindowStart = inCurrentWindow ? row.resendWindowStart : now;
    const resendCount = inCurrentWindow ? row.resendCount + 1 : 1;
    const rotated = this.#database
      .prepare(`
        UPDATE email_verifications
           SET code_digest = ?, idempotency_key = ?, expires_at = ?,
               attempt_count = 0, resend_window_start = ?, resend_count = ?,
               last_sent_at = ?, provider_message_id = NULL, updated_at = ?
         WHERE account_id = ? AND consumed_at IS NULL AND last_sent_at = ?
      `)
      .run(
        codeDigest,
        idempotencyKey,
        expiresAt,
        resendWindowStart,
        resendCount,
        now,
        now,
        row.id,
        row.lastSentAt,
      );
    if (rotated.changes !== 1) {
      throw this.#verificationRateLimit(
        'Wait before requesting another confirmation code.',
        this.#config.authVerificationResendCooldownSeconds,
      );
    }
    let delivery;
    try {
      delivery = await this.#emailClient.sendVerification({
        to: row.email,
        name: row.name,
        code,
        expiresInMinutes: Math.ceil(
          this.#config.authVerificationCodeTtlSeconds / 60,
        ),
        idempotencyKey,
      });
      assertProviderDelivery(delivery);
    } catch (error) {
      if (error instanceof AppError) throw error;
      throw new AppError(
        503,
        'email_provider_unavailable',
        'Email delivery is temporarily unavailable. Try again shortly.',
        undefined,
        true,
      );
    }
    this.#database
      .prepare(`
        UPDATE email_verifications
           SET provider_message_id = ?, updated_at = ?
         WHERE account_id = ? AND idempotency_key = ? AND consumed_at IS NULL
      `)
      .run(delivery.providerMessageId, this.#now(), row.id, idempotencyKey);
    return verificationResponse(
      row.email,
      expiresAt,
      resendAvailableAt,
      body.challengeToken,
    );
  }

  async login(body, requester = 'unknown') {
    this.#assertAvailable();
    exactObject(body, new Set(['email', 'password']), 'Login request');
    let email = null;
    try {
      email = normalizeEmail(body.email);
    } catch {
      // Invalid credentials deliberately share one public error below.
    }
    const usablePassword =
      typeof body.password === 'string' &&
      [...body.password].length <= 128 &&
      Buffer.byteLength(body.password) <= 512 &&
      !/\p{Cc}/u.test(body.password);
    const password = usablePassword ? body.password : '';
    this.#consumeRateLimit(
      'login',
      requester,
      email ??
        (typeof body.email === 'string'
          ? body.email.slice(0, 254)
          : 'invalid-email'),
    );
    const row = email
      ? this.#database
          .prepare(`
            SELECT id, display_name AS name, email,
                   password_hash AS passwordHash, accounts.status,
                   accounts.email_verified_at AS emailVerifiedAt,
                   sellers.seller_handle AS sellerHandle
              FROM accounts
              LEFT JOIN seller_accounts AS sellers
                ON sellers.owner_account_id = accounts.id
             WHERE accounts.email = ?
          `)
          .get(email)
      : null;
    const passwordMatches = row
      ? await verifyPassword(password, row.passwordHash)
      : (await burnPasswordCheck(password), false);
    if (
      !usablePassword ||
      !row ||
      !passwordMatches ||
      row.status !== 'active' ||
      row.emailVerifiedAt === null
    ) {
      throw invalidCredentials();
    }
    if (!row.sellerHandle) {
      row.sellerHandle = this.#ensureSeller(row.id, row.name);
    }

    const now = this.#now();
    const sessionId = `ses_${randomBytes(24).toString('base64url')}`;
    const expiresAt = now + this.#config.authSessionTtlSeconds;
    const accessToken = signAccessToken(this.#config, {
      accountId: row.id,
      sessionId,
      issuedAt: now,
      expiresAt,
      sellerHandle: row.sellerHandle,
    });
    this.#database
      .prepare(`
        INSERT INTO account_sessions (
          id, account_id, expires_at, created_at
        ) VALUES (?, ?, ?, ?)
      `)
      .run(sessionId, row.id, expiresAt, now);
    return Object.freeze({
      user: publicUser(row),
      session: sessionResponse(accessToken, expiresAt),
    });
  }

  getSession(actor) {
    this.#assertAvailable();
    const row = this.#database
      .prepare(`
        SELECT id, display_name AS name, email, status,
               email_verified_at AS emailVerifiedAt
          FROM accounts
         WHERE id = ?
      `)
      .get(actor.id);
    if (
      !row ||
      row.status !== 'active' ||
      row.emailVerifiedAt === null ||
      !actor.sessionId
    ) {
      throw invalidCredentials();
    }
    const sellerHandle = this.#ensureSeller(row.id, row.name);
    return Object.freeze({
      authenticated: true,
      user: publicUser({ ...row, sellerHandle }),
      expiresAt: new Date(actor.sessionExpiresAt * 1000).toISOString(),
    });
  }

  logout(actor, body) {
    this.#assertAvailable();
    exactObject(body, new Set(), 'Logout request');
    if (!actor.sessionId) throw invalidCredentials();
    const result = this.#database
      .prepare(`
        UPDATE account_sessions
           SET revoked_at = ?
         WHERE id = ? AND account_id = ? AND revoked_at IS NULL
      `)
      .run(this.#now(), actor.sessionId, actor.id);
    if (result.changes !== 1) throw invalidCredentials();
    return Object.freeze({ loggedOut: true });
  }

  async drainWelcomeEmails({ accountId = null, limit = 10 } = {}) {
    this.#assertAvailable();
    const boundedLimit = Number.isSafeInteger(limit)
      ? Math.max(1, Math.min(limit, 25))
      : 10;
    const now = this.#now();
    const oldestSafeCreatedAt = now - WELCOME_IDEMPOTENCY_WINDOW_SECONDS;
    const staleClaimedAt = now - WELCOME_CLAIM_LEASE_SECONDS;
    this.#database
      .prepare(`
        UPDATE welcome_email_outbox
           SET status = 'failed', next_attempt_at = NULL,
               claimed_at = NULL, updated_at = ?
         WHERE status <> 'sent' AND created_at < ?
      `)
      .run(now, oldestSafeCreatedAt);

    const accountFilter = accountId ? 'AND outbox.account_id = ?' : '';
    const parameters = [oldestSafeCreatedAt, now, staleClaimedAt];
    if (accountId) parameters.push(accountId);
    parameters.push(boundedLimit);
    const candidates = this.#database
      .prepare(`
        SELECT outbox.account_id AS accountId,
               outbox.idempotency_key AS idempotencyKey,
               outbox.attempt_count AS attemptCount,
               outbox.created_at AS createdAt,
               accounts.display_name AS name,
               accounts.email
          FROM welcome_email_outbox AS outbox
          JOIN accounts ON accounts.id = outbox.account_id
         WHERE accounts.status = 'active'
           AND outbox.created_at >= ?
           AND outbox.attempt_count < ${MAX_WELCOME_ATTEMPTS}
           AND (
             (outbox.status IN ('pending', 'failed')
              AND outbox.next_attempt_at IS NOT NULL
              AND outbox.next_attempt_at <= ?)
             OR
             (outbox.status = 'sending' AND outbox.claimed_at <= ?)
           )
           ${accountFilter}
         ORDER BY COALESCE(outbox.next_attempt_at, outbox.claimed_at),
                  outbox.created_at, outbox.account_id
         LIMIT ?
      `)
      .all(...parameters);

    const results = [];
    for (const candidate of candidates) {
      const claimed = immediateTransaction(this.#database, () =>
        this.#database
          .prepare(`
            UPDATE welcome_email_outbox
               SET status = 'sending',
                   attempt_count = attempt_count + 1,
                   next_attempt_at = NULL,
                   claimed_at = ?,
                   updated_at = ?
             WHERE account_id = ?
               AND created_at >= ?
               AND attempt_count < ${MAX_WELCOME_ATTEMPTS}
               AND (
                 (status IN ('pending', 'failed')
                  AND next_attempt_at IS NOT NULL
                  AND next_attempt_at <= ?)
                 OR
                 (status = 'sending' AND claimed_at <= ?)
               )
          `)
          .run(
            now,
            now,
            candidate.accountId,
            oldestSafeCreatedAt,
            now,
            staleClaimedAt,
          ),
      );
      if (claimed.changes !== 1) continue;
      const attemptCount = candidate.attemptCount + 1;
      try {
        const delivery = await this.#emailClient.sendWelcome({
          to: candidate.email,
          name: candidate.name,
          idempotencyKey: candidate.idempotencyKey,
        });
        if (
          typeof delivery?.providerMessageId !== 'string' ||
          delivery.providerMessageId.length < 1 ||
          delivery.providerMessageId.length > 200
        ) {
          throw new AppError(
            503,
            'email_provider_unavailable',
            'Welcome email delivery is temporarily unavailable.',
          );
        }
        const completedAt = this.#now();
        const update = this.#database
          .prepare(`
            UPDATE welcome_email_outbox
               SET status = 'sent', provider_message_id = ?, sent_at = ?,
                   next_attempt_at = NULL, claimed_at = NULL, updated_at = ?
             WHERE account_id = ? AND status = 'sending' AND claimed_at = ?
          `)
          .run(
            delivery.providerMessageId,
            completedAt,
            completedAt,
            candidate.accountId,
            now,
          );
        results.push(Object.freeze({
          accountId: candidate.accountId,
          status: update.changes === 1 ? 'sent' : 'failed',
        }));
      } catch {
        const failedAt = this.#now();
        const deliveryDeadline =
          candidate.createdAt + WELCOME_IDEMPOTENCY_WINDOW_SECONDS;
        const delay = WELCOME_RETRY_DELAYS_SECONDS[
          Math.min(
            attemptCount - 1,
            WELCOME_RETRY_DELAYS_SECONDS.length - 1,
          )
        ];
        const nextAttemptAt =
          attemptCount < MAX_WELCOME_ATTEMPTS && failedAt + delay < deliveryDeadline
            ? failedAt + delay
            : null;
        this.#database
          .prepare(`
            UPDATE welcome_email_outbox
               SET status = 'failed', next_attempt_at = ?,
                   claimed_at = NULL, updated_at = ?
             WHERE account_id = ? AND status = 'sending' AND claimed_at = ?
          `)
          .run(nextAttemptAt, failedAt, candidate.accountId, now);
        results.push(Object.freeze({
          accountId: candidate.accountId,
          status: nextAttemptAt === null ? 'failed' : 'pending',
        }));
      }
    }
    return Object.freeze({
      processed: results.length,
      sent: results.filter((result) => result.status === 'sent').length,
      pending: results.filter((result) => result.status === 'pending').length,
      failed: results.filter((result) => result.status === 'failed').length,
      results: Object.freeze(results),
    });
  }

  startWelcomeEmailWorker() {
    this.#assertAvailable();
    let stopped = false;
    let active = null;
    const tick = () => {
      if (stopped || active) return;
      active = this.drainWelcomeEmails()
        .catch(() => undefined)
        .finally(() => {
          active = null;
        });
    };
    tick();
    const timer = setInterval(tick, this.#config.emailRetryIntervalMs);
    timer.unref?.();
    return Object.freeze({
      stop: async () => {
        if (stopped) return;
        stopped = true;
        clearInterval(timer);
        if (active) await active;
      },
    });
  }

  async #rotateVerification(row) {
    const now = this.#now();
    const cooldownUntil =
      row.lastSentAt + this.#config.authVerificationResendCooldownSeconds;
    if (cooldownUntil > now) {
      throw this.#verificationRateLimit(
        'Wait before requesting another confirmation code.',
        cooldownUntil - now,
      );
    }
    const inCurrentWindow =
      row.resendWindowStart + VERIFICATION_RESEND_WINDOW_SECONDS > now;
    if (
      inCurrentWindow &&
      row.resendCount >= this.#config.authVerificationResendLimitPerHour
    ) {
      throw this.#verificationRateLimit(
        'Too many confirmation emails. Try again later.',
        row.resendWindowStart + VERIFICATION_RESEND_WINDOW_SECONDS - now,
      );
    }
    const challengeToken = randomBytes(32).toString('base64url');
    const challengeHash = challengeDigest(
      this.#config.authRateLimitSecret,
      challengeToken,
    );
    const code = verificationCode();
    const idempotencyKey = `verify-${randomBytes(18).toString('base64url')}`;
    const expiresAt = now + this.#config.authVerificationCodeTtlSeconds;
    const resendAvailableAt =
      now + this.#config.authVerificationResendCooldownSeconds;
    const codeDigest = verificationDigest(
      this.#config.authRateLimitSecret,
      row.id,
      challengeHash,
      idempotencyKey,
      code,
    );
    const resendWindowStart = inCurrentWindow ? row.resendWindowStart : now;
    const resendCount = inCurrentWindow ? row.resendCount + 1 : 1;
    const rotated = this.#database
      .prepare(`
        UPDATE email_verifications
           SET challenge_digest = ?, code_digest = ?, idempotency_key = ?,
               expires_at = ?, attempt_count = 0, resend_window_start = ?,
               resend_count = ?, last_sent_at = ?, provider_message_id = NULL,
               updated_at = ?
         WHERE account_id = ? AND consumed_at IS NULL AND last_sent_at = ?
      `)
      .run(
        challengeHash,
        codeDigest,
        idempotencyKey,
        expiresAt,
        resendWindowStart,
        resendCount,
        now,
        now,
        row.id,
        row.lastSentAt,
      );
    if (rotated.changes !== 1) {
      throw this.#verificationRateLimit(
        'Wait before requesting another confirmation code.',
        this.#config.authVerificationResendCooldownSeconds,
      );
    }
    let delivery;
    try {
      delivery = await this.#emailClient.sendVerification({
        to: row.email,
        name: row.name,
        code,
        expiresInMinutes: Math.ceil(
          this.#config.authVerificationCodeTtlSeconds / 60,
        ),
        idempotencyKey,
      });
      assertProviderDelivery(delivery);
    } catch (error) {
      if (error instanceof AppError) throw error;
      throw new AppError(
        503,
        'email_provider_unavailable',
        'Email delivery is temporarily unavailable. Try again shortly.',
        undefined,
        true,
      );
    }
    this.#database
      .prepare(`
        UPDATE email_verifications
           SET provider_message_id = ?, updated_at = ?
         WHERE account_id = ? AND challenge_digest = ? AND consumed_at IS NULL
      `)
      .run(delivery.providerMessageId, this.#now(), row.id, challengeHash);
    return verificationResponse(
      row.email,
      expiresAt,
      resendAvailableAt,
      challengeToken,
    );
  }

  #assertAvailable() {
    if (!this.#config.accountAuthEnabled || !this.#emailClient) {
      throw new AppError(
        503,
        'account_auth_unavailable',
        'Account sign-in is not configured on this server.',
        undefined,
        true,
      );
    }
  }

  #ensureSeller(accountId, name) {
    const existing = this.#database
      .prepare('SELECT seller_handle AS sellerHandle FROM seller_accounts WHERE owner_account_id = ?')
      .get(accountId);
    if (existing) return existing.sellerHandle;
    const sellerHandle = sellerHandleFor(accountId, name);
    this.#database
      .prepare(`
        INSERT OR IGNORE INTO seller_accounts (
          seller_handle, seller_name, owner_account_id, is_pro,
          transfers_ready, updated_at
        ) VALUES (?, ?, ?, 0, 0, ?)
      `)
      .run(sellerHandle, name, accountId, this.#now());
    const created = this.#database
      .prepare('SELECT seller_handle AS sellerHandle FROM seller_accounts WHERE owner_account_id = ?')
      .get(accountId);
    if (!created) {
      throw new AppError(500, 'seller_identity_error', 'Seller identity could not be created.');
    }
    return created.sellerHandle;
  }

  #now() {
    return Math.floor(this.#clock() / 1000);
  }

  #consumeRateLimit(action, requester, email) {
    const now = this.#now();
    const windowSeconds = action === 'signup' ? 60 * 60 : 15 * 60;
    const limit = action === 'signup'
      ? this.#config.authSignupRateLimitPerHour
      : this.#config.authLoginRateLimitPer15Minutes;
    const windowStart = Math.floor(now / windowSeconds) * windowSeconds;
    const entries = [
      [`${action}_ip`, String(requester).slice(0, 256)],
      [`${action}_email`, String(email).slice(0, 254)],
    ].map(([kind, scope]) => ({
      kind,
      hash: createHmac('sha256', this.#config.authRateLimitSecret)
        .update(`drip-auth:${kind}:${scope}`)
        .digest('hex'),
    }));
    immediateTransaction(this.#database, () => {
      const read = this.#database.prepare(`
        SELECT request_count AS requestCount
          FROM auth_usage_windows
         WHERE scope_hash = ? AND action = ? AND window_start = ?
      `);
      for (const entry of entries) {
        const count =
          read.get(entry.hash, entry.kind, windowStart)?.requestCount ?? 0;
        if (count >= limit) {
          throw new AppError(
            429,
            'auth_rate_limited',
            action === 'signup'
              ? 'Too many account creation attempts. Try again later.'
              : 'Too many sign-in attempts. Try again later.',
            {
              retryAfterSeconds: Math.max(
                1,
                windowStart + windowSeconds - now,
              ),
            },
            true,
          );
        }
      }
      const upsert = this.#database.prepare(`
        INSERT INTO auth_usage_windows (
          scope_hash, action, window_start, request_count, updated_at
        ) VALUES (?, ?, ?, 1, ?)
        ON CONFLICT (scope_hash, action, window_start)
        DO UPDATE SET
          request_count = request_count + 1,
          updated_at = excluded.updated_at
      `);
      for (const entry of entries) {
        upsert.run(entry.hash, entry.kind, windowStart, now);
      }
      this.#database
        .prepare('DELETE FROM auth_usage_windows WHERE window_start < ?')
        .run(now - 2 * 24 * 60 * 60);
    });
  }

  #consumeVerificationRateLimit(action, requester, challengeHash) {
    const now = this.#now();
    const windowSeconds =
      action === 'verify' ? 15 * 60 : VERIFICATION_RESEND_WINDOW_SECONDS;
    const limit =
      action === 'verify'
        ? this.#config.authVerificationAttemptRateLimitPer15Minutes
        : this.#config.authVerificationResendLimitPerHour;
    const windowStart = Math.floor(now / windowSeconds) * windowSeconds;
    const entries = [
      [`${action}_ip`, String(requester).slice(0, 256)],
      [`${action}_email`, String(challengeHash).slice(0, 64)],
    ].map(([kind, scope]) => ({
      kind,
      hash: createHmac('sha256', this.#config.authRateLimitSecret)
        .update(`drip-email-verification-rate:v1:${kind}:${scope}`)
        .digest('hex'),
    }));
    immediateTransaction(this.#database, () => {
      const read = this.#database.prepare(`
        SELECT request_count AS requestCount
          FROM email_verification_usage
         WHERE scope_hash = ? AND action = ? AND window_start = ?
      `);
      for (const entry of entries) {
        const count =
          read.get(entry.hash, entry.kind, windowStart)?.requestCount ?? 0;
        if (count >= limit) {
          throw this.#verificationRateLimit(
            action === 'verify'
              ? 'Too many confirmation attempts. Try again later.'
              : 'Too many confirmation emails. Try again later.',
            Math.max(1, windowStart + windowSeconds - now),
          );
        }
      }
      const upsert = this.#database.prepare(`
        INSERT INTO email_verification_usage (
          scope_hash, action, window_start, request_count, updated_at
        ) VALUES (?, ?, ?, 1, ?)
        ON CONFLICT (scope_hash, action, window_start)
        DO UPDATE SET
          request_count = request_count + 1,
          updated_at = excluded.updated_at
      `);
      for (const entry of entries) {
        upsert.run(entry.hash, entry.kind, windowStart, now);
      }
      this.#database
        .prepare('DELETE FROM email_verification_usage WHERE window_start < ?')
        .run(now - 2 * 24 * 60 * 60);
    });
  }

  #verificationRateLimit(message, retryAfterSeconds) {
    return new AppError(
      429,
      'verification_rate_limited',
      message,
      { retryAfterSeconds: Math.max(1, Math.floor(retryAfterSeconds)) },
      true,
    );
  }

  #welcomeEmailStatus(accountId) {
    const row = this.#database
      .prepare(`
        SELECT status, next_attempt_at AS nextAttemptAt
          FROM welcome_email_outbox
         WHERE account_id = ?
      `)
      .get(accountId);
    if (row?.status === 'sent') return 'sent';
    if (
      row?.status === 'pending' ||
      row?.status === 'sending' ||
      (row?.status === 'failed' && row.nextAttemptAt !== null)
    ) {
      return 'pending';
    }
    return 'failed';
  }
}
