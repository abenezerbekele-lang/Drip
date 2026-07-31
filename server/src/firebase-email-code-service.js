import {
  createHmac,
  randomBytes,
  randomInt,
  timingSafeEqual,
} from 'node:crypto';

import { immediateTransaction } from './database.js';
import { AppError } from './errors.js';

const HOUR_SECONDS = 60 * 60;
const FIFTEEN_MINUTES_SECONDS = 15 * 60;

function invalidCode() {
  return new AppError(
    422,
    'invalid_verification_code',
    'That confirmation code is invalid or expired. Request a new code and try again.',
  );
}

function unavailable() {
  return new AppError(
    503,
    'firebase_email_code_unavailable',
    'Email confirmation codes are temporarily unavailable.',
    undefined,
    true,
  );
}

function invalidToken() {
  return new AppError(401, 'invalid_token', 'The access token is invalid.');
}

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

function normalizeFirebaseEmail(value) {
  if (typeof value !== 'string') throw invalidToken();
  const email = value.normalize('NFKC').trim().toLowerCase();
  if (
    email.length < 3 ||
    email.length > 254 ||
    /[\s\r\n]/.test(email) ||
    !/^[^@]+@[^@]+\.[^@]+$/.test(email)
  ) {
    throw invalidToken();
  }
  return email;
}

function currentFirebaseUser(record, expectedUid) {
  if (
    record === null ||
    typeof record !== 'object' ||
    record.uid !== expectedUid ||
    typeof record.uid !== 'string' ||
    record.uid.length < 1 ||
    record.uid.length > 128 ||
    typeof record.emailVerified !== 'boolean' ||
    (record.disabled != null && typeof record.disabled !== 'boolean')
  ) {
    throw unavailable();
  }
  if (record.disabled === true) throw invalidToken();
  return Object.freeze({
    uid: record.uid,
    email: normalizeFirebaseEmail(record.email),
    emailVerified: record.emailVerified,
    displayName:
      typeof record.displayName === 'string' &&
      record.displayName.length >= 1 &&
      record.displayName.length <= 80 &&
      !/[\r\n]/.test(record.displayName)
        ? record.displayName
        : 'Drip member',
  });
}

function validateActor(actor) {
  if (
    actor === null ||
    typeof actor !== 'object' ||
    typeof actor.id !== 'string' ||
    actor.id.length < 1 ||
    actor.id.length > 128 ||
    actor.authProvider !== 'firebase'
  ) {
    throw invalidToken();
  }
  return actor.id;
}

function providerError(error) {
  if (error instanceof AppError) return error;
  const code = typeof error?.code === 'string' ? error.code : '';
  if (
    code === 'auth/user-not-found' ||
    code === 'auth/user-disabled' ||
    code === 'auth/id-token-revoked'
  ) {
    return invalidToken();
  }
  return unavailable();
}

function assertDelivery(delivery) {
  if (
    typeof delivery?.providerMessageId !== 'string' ||
    delivery.providerMessageId.length < 1 ||
    delivery.providerMessageId.length > 200
  ) {
    throw unavailable();
  }
}

function codeDigest(secret, uid, email, challengeId, code) {
  return createHmac('sha256', secret)
    .update(
      `drip-firebase-email-code:v1:${uid}:${email}:${challengeId}:${code}`,
    )
    .digest('hex');
}

function safeDigestMatch(actualHex, expectedHex) {
  if (
    typeof actualHex !== 'string' ||
    typeof expectedHex !== 'string' ||
    !/^[a-f0-9]{64}$/.test(actualHex) ||
    !/^[a-f0-9]{64}$/.test(expectedHex)
  ) {
    return false;
  }
  return timingSafeEqual(
    Buffer.from(actualHex, 'hex'),
    Buffer.from(expectedHex, 'hex'),
  );
}

function response(email, expiresAt, resendAvailableAt) {
  return Object.freeze({
    verification: Object.freeze({
      status: 'code_sent',
      email,
      expiresAt: new Date(expiresAt * 1000).toISOString(),
      resendAvailableAt: new Date(
        resendAvailableAt * 1000,
      ).toISOString(),
    }),
  });
}

export class FirebaseEmailCodeService {
  #clock;
  #config;
  #database;
  #emailClient;
  #firebaseAuth;

  constructor({
    database,
    emailClient,
    firebaseAuth,
    config,
    clock = () => Date.now(),
  }) {
    if (
      !database ||
      !emailClient ||
      !firebaseAuth ||
      typeof clock !== 'function'
    ) {
      throw new TypeError('Firebase email code service configuration is invalid.');
    }
    this.#database = database;
    this.#emailClient = emailClient;
    this.#firebaseAuth = firebaseAuth;
    this.#config = config;
    this.#clock = clock;
    this.#assertAvailable();
  }

  async requestCode(actor, body, requester = 'unknown') {
    this.#assertAvailable();
    exactObject(body, new Set(), 'Email code request');
    const uid = validateActor(actor);
    const user = await this.#getCurrentUser(uid);
    if (user.emailVerified) {
      return Object.freeze({
        verification: Object.freeze({
          status: 'already_verified',
          email: user.email,
        }),
      });
    }

    const now = this.#now();
    const expiresAt = now + this.#config.firebaseEmailCodeTtlSeconds;
    const resendAvailableAt =
      now + this.#config.firebaseEmailCodeResendCooldownSeconds;
    const challengeId = randomBytes(18).toString('base64url');
    const idempotencyKey = `firebase-email-code-${challengeId}`;
    const code = randomInt(0, 1_000_000).toString().padStart(6, '0');
    const digest = codeDigest(
      this.#config.firebaseEmailCodeSecret,
      uid,
      user.email,
      challengeId,
      code,
    );

    // Count every authenticated request, including cooldown failures and
    // provider failures. This keeps repeated button mashing or scripted calls
    // from bypassing the hourly window through transaction rollback.
    immediateTransaction(this.#database, () => {
      this.#consumeUsageInTransaction('request', uid, requester, now);
    });
    immediateTransaction(this.#database, () => {
      const previous = this.#database
        .prepare(`
          SELECT last_sent_at AS lastSentAt
            FROM firebase_email_verifications
           WHERE firebase_uid = ?
        `)
        .get(uid);
      if (
        previous &&
        previous.lastSentAt +
          this.#config.firebaseEmailCodeResendCooldownSeconds >
          now
      ) {
        throw this.#rateLimited(
          'Wait before requesting another confirmation email.',
          previous.lastSentAt +
            this.#config.firebaseEmailCodeResendCooldownSeconds -
            now,
        );
      }
      this.#database
        .prepare(`
          INSERT INTO firebase_email_verifications (
            firebase_uid, email, challenge_id, code_digest,
            idempotency_key, status, expires_at, attempt_count,
            last_sent_at, provider_message_id, consumed_at,
            created_at, updated_at
          ) VALUES (?, ?, ?, ?, ?, 'pending', ?, 0, ?, NULL, NULL, ?, ?)
          ON CONFLICT (firebase_uid) DO UPDATE SET
            email = excluded.email,
            challenge_id = excluded.challenge_id,
            code_digest = excluded.code_digest,
            idempotency_key = excluded.idempotency_key,
            status = 'pending',
            expires_at = excluded.expires_at,
            attempt_count = 0,
            last_sent_at = excluded.last_sent_at,
            provider_message_id = NULL,
            consumed_at = NULL,
            created_at = excluded.created_at,
            updated_at = excluded.updated_at
        `)
        .run(
          uid,
          user.email,
          challengeId,
          digest,
          idempotencyKey,
          expiresAt,
          now,
          now,
          now,
        );
    });

    let delivery;
    try {
      delivery = await this.#emailClient.sendVerification({
        to: user.email,
        name: user.displayName,
        code,
        expiresInMinutes: Math.ceil(
          this.#config.firebaseEmailCodeTtlSeconds / 60,
        ),
        idempotencyKey,
      });
      assertDelivery(delivery);
    } catch (error) {
      this.#database
        .prepare(`
          DELETE FROM firebase_email_verifications
           WHERE firebase_uid = ? AND challenge_id = ? AND status = 'pending'
        `)
        .run(uid, challengeId);
      throw providerError(error);
    }

    const sentAt = this.#now();
    const markedSent = this.#database
      .prepare(`
        UPDATE firebase_email_verifications
           SET status = 'sent', provider_message_id = ?, updated_at = ?
         WHERE firebase_uid = ? AND challenge_id = ? AND status = 'pending'
      `)
      .run(
        delivery.providerMessageId,
        sentAt,
        uid,
        challengeId,
      );
    if (markedSent.changes !== 1) throw unavailable();
    return response(user.email, expiresAt, resendAvailableAt);
  }

  async verifyCode(actor, body, requester = 'unknown') {
    this.#assertAvailable();
    exactObject(body, new Set(['code']), 'Email code verification');
    const uid = validateActor(actor);
    const code = body.code;
    if (typeof code !== 'string' || !/^[0-9]{6}$/.test(code)) {
      throw invalidCode();
    }

    const user = await this.#getCurrentUser(uid);
    if (user.emailVerified) {
      return Object.freeze({
        verified: true,
        email: user.email,
        refreshIdToken: true,
      });
    }

    const now = this.#now();
    const result = immediateTransaction(this.#database, () => {
      this.#consumeUsageInTransaction('verify', uid, requester, now);
      const row = this.#database
        .prepare(`
          SELECT email, challenge_id AS challengeId,
                 code_digest AS codeDigest, status, expires_at AS expiresAt,
                 attempt_count AS attemptCount
            FROM firebase_email_verifications
           WHERE firebase_uid = ?
        `)
        .get(uid);
      if (
        !row ||
        row.status !== 'sent' ||
        row.email !== user.email ||
        row.expiresAt <= now ||
        row.attemptCount >= this.#config.firebaseEmailCodeMaxAttempts
      ) {
        if (row && row.status === 'sent') {
          this.#database
            .prepare(`
              UPDATE firebase_email_verifications
                 SET status = 'consumed', consumed_at = ?, updated_at = ?
               WHERE firebase_uid = ? AND status = 'sent'
            `)
            .run(now, now, uid);
        }
        return Object.freeze({ valid: false });
      }
      const expected = codeDigest(
        this.#config.firebaseEmailCodeSecret,
        uid,
        row.email,
        row.challengeId,
        code,
      );
      if (!safeDigestMatch(row.codeDigest, expected)) {
        const nextAttempt = row.attemptCount + 1;
        this.#database
          .prepare(`
            UPDATE firebase_email_verifications
               SET attempt_count = ?,
                   status = CASE WHEN ? >= ? THEN 'consumed' ELSE status END,
                   consumed_at = CASE WHEN ? >= ? THEN ? ELSE consumed_at END,
                   updated_at = ?
             WHERE firebase_uid = ? AND status = 'sent'
          `)
          .run(
            nextAttempt,
            nextAttempt,
            this.#config.firebaseEmailCodeMaxAttempts,
            nextAttempt,
            this.#config.firebaseEmailCodeMaxAttempts,
            now,
            now,
            uid,
          );
        return Object.freeze({ valid: false });
      }
      return Object.freeze({
        valid: true,
        email: row.email,
        challengeId: row.challengeId,
      });
    });
    if (!result.valid) throw invalidCode();

    let verified;
    try {
      verified = await this.#firebaseAuth.markEmailVerified(
        uid,
        result.email,
      );
    } catch (error) {
      throw providerError(error);
    }
    const verifiedUser = currentFirebaseUser(verified, uid);
    if (
      !verifiedUser.emailVerified ||
      verifiedUser.email !== result.email
    ) {
      throw unavailable();
    }

    const consumedAt = this.#now();
    this.#database
      .prepare(`
        UPDATE firebase_email_verifications
           SET status = 'consumed', consumed_at = ?, updated_at = ?
         WHERE firebase_uid = ? AND challenge_id = ? AND status = 'sent'
      `)
      .run(consumedAt, consumedAt, uid, result.challengeId);
    return Object.freeze({
      verified: true,
      email: verifiedUser.email,
      refreshIdToken: true,
    });
  }

  async #getCurrentUser(uid) {
    if (typeof this.#firebaseAuth.getUserForEmailVerification !== 'function') {
      throw unavailable();
    }
    try {
      return currentFirebaseUser(
        await this.#firebaseAuth.getUserForEmailVerification(uid),
        uid,
      );
    } catch (error) {
      throw providerError(error);
    }
  }

  #consumeUsageInTransaction(action, uid, requester, now) {
    const request = action === 'request';
    const windowSeconds = request ? HOUR_SECONDS : FIFTEEN_MINUTES_SECONDS;
    const windowStart = Math.floor(now / windowSeconds) * windowSeconds;
    const entries = [
      {
        kind: `${action}_uid`,
        scope: uid,
        limit: request
          ? this.#config.firebaseEmailCodeResendLimitPerHour
          : this.#config.firebaseEmailCodeAttemptLimitPer15Minutes,
      },
      {
        kind: `${action}_ip`,
        scope: String(requester).slice(0, 256),
        limit: request
          ? this.#config.firebaseEmailCodeIpRequestLimitPerHour
          : this.#config.firebaseEmailCodeAttemptLimitPer15Minutes,
      },
    ].map((entry) => ({
      ...entry,
      hash: createHmac(
        'sha256',
        this.#config.firebaseEmailCodeSecret,
      )
        .update(
          `drip-firebase-email-code-rate:v1:${entry.kind}:${entry.scope}`,
        )
        .digest('hex'),
    }));
    const read = this.#database.prepare(`
      SELECT request_count AS requestCount
        FROM firebase_email_verification_usage
       WHERE scope_hash = ? AND action = ? AND window_start = ?
    `);
    for (const entry of entries) {
      const count =
        read.get(entry.hash, entry.kind, windowStart)?.requestCount ?? 0;
      if (count >= entry.limit) {
        throw this.#rateLimited(
          request
            ? 'Too many confirmation emails. Try again later.'
            : 'Too many confirmation attempts. Try again later.',
          windowStart + windowSeconds - now,
        );
      }
    }
    const upsert = this.#database.prepare(`
      INSERT INTO firebase_email_verification_usage (
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
      .prepare(`
        DELETE FROM firebase_email_verification_usage
         WHERE window_start < ?
      `)
      .run(now - 2 * 24 * HOUR_SECONDS);
  }

  #rateLimited(message, retryAfterSeconds) {
    return new AppError(
      429,
      'verification_rate_limited',
      message,
      { retryAfterSeconds: Math.max(1, Math.floor(retryAfterSeconds)) },
      true,
    );
  }

  #assertAvailable() {
    if (
      !this.#config?.firebaseEmailCodeConfigured ||
      this.#config.authMode !== 'firebase' ||
      this.#config.firebaseAuthVerifierMode !== 'application-default' ||
      !this.#config.emailConfigured ||
      Buffer.byteLength(this.#config.firebaseEmailCodeSecret || '') < 32 ||
      typeof this.#emailClient?.sendVerification !== 'function' ||
      typeof this.#firebaseAuth?.getUserForEmailVerification !== 'function' ||
      typeof this.#firebaseAuth?.markEmailVerified !== 'function'
    ) {
      throw unavailable();
    }
  }

  #now() {
    return Math.floor(this.#clock() / 1000);
  }
}
