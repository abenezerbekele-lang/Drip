import assert from 'node:assert/strict';
import test from 'node:test';

import { loadConfig } from '../src/config.js';
import { createDatabase } from '../src/database.js';
import { FirebaseEmailCodeService } from '../src/firebase-email-code-service.js';
import { AppError } from '../src/errors.js';
import { FakeEmailClient } from '../test_support/fake-email.js';

const SECRET = 'firebase-email-code-test-secret-more-than-32-bytes';
const START_MS = 2_100_000_000_000;

function config(overrides = {}) {
  return loadConfig({
    NODE_ENV: 'test',
    AUTH_MODE: 'firebase',
    DATABASE_PATH: ':memory:',
    FIREBASE_PROJECT_ID: 'dripproject-24882',
    FIREBASE_CREDENTIALS_MODE: 'application-default',
    FIREBASE_EMAIL_CODE_ENABLED: 'true',
    FIREBASE_EMAIL_CODE_SECRET: SECRET,
    EMAIL_PROVIDER: 'resend',
    RESEND_API_KEY: 're_firebase_email_code_test',
    WELCOME_EMAIL_FROM: 'Drip <accounts@drip.test>',
    ...overrides,
  });
}

function actor(uid = 'firebase-user-123') {
  return Object.freeze({
    id: uid,
    authProvider: 'firebase',
    emailVerified: false,
  });
}

class FakeFirebaseAuth {
  constructor(users = [
    {
      uid: 'firebase-user-123',
      email: 'Member@Example.com',
      emailVerified: false,
      disabled: false,
      displayName: 'Jordan Lee',
    },
  ]) {
    this.users = new Map(users.map((user) => [user.uid, { ...user }]));
    this.getCalls = [];
    this.markCalls = [];
    this.markError = null;
  }

  async getUserForEmailVerification(uid) {
    this.getCalls.push(uid);
    const user = this.users.get(uid);
    if (!user) {
      const error = new Error('not found');
      error.code = 'auth/user-not-found';
      throw error;
    }
    return { ...user };
  }

  async markEmailVerified(uid, expectedEmail) {
    this.markCalls.push({ uid, expectedEmail });
    if (this.markError) throw this.markError;
    const user = this.users.get(uid);
    if (!user || user.disabled) {
      const error = new Error('not found');
      error.code = 'auth/user-not-found';
      throw error;
    }
    if (user.email.trim().toLowerCase() !== expectedEmail) {
      throw new AppError(
        409,
        'verification_email_changed',
        'Your email address changed. Request a new confirmation code.',
      );
    }
    user.email = expectedEmail;
    user.emailVerified = true;
    return { ...user };
  }
}

function context({
  configOverrides = {},
  firebaseAuth = new FakeFirebaseAuth(),
} = {}) {
  const database = createDatabase(':memory:');
  const emailClient = new FakeEmailClient();
  let now = START_MS;
  const service = new FirebaseEmailCodeService({
    database,
    emailClient,
    firebaseAuth,
    config: config(configOverrides),
    clock: () => now,
  });
  return {
    database,
    emailClient,
    firebaseAuth,
    service,
    advance(seconds) {
      now += seconds * 1000;
    },
  };
}

test('Firebase code request binds the current UID/email and stores only an HMAC digest', async () => {
  const testContext = context();
  try {
    const result = await testContext.service.requestCode(
      actor(),
      {},
      '203.0.113.10',
    );
    assert.equal(result.verification.status, 'code_sent');
    assert.equal(result.verification.email, 'member@example.com');
    assert.equal(testContext.emailClient.verificationCalls.length, 1);
    const message = testContext.emailClient.verificationCalls[0];
    assert.equal(message.to, 'member@example.com');
    assert.equal(message.name, 'Jordan Lee');
    assert.match(message.code, /^[0-9]{6}$/);
    assert.doesNotMatch(JSON.stringify(result), new RegExp(message.code));

    const row = testContext.database
      .prepare(`
        SELECT firebase_uid AS uid, email, challenge_id AS challengeId,
               code_digest AS codeDigest, status, provider_message_id AS providerId
          FROM firebase_email_verifications
         WHERE firebase_uid = ?
      `)
      .get(actor().id);
    assert.equal(row.uid, actor().id);
    assert.equal(row.email, 'member@example.com');
    assert.equal(row.status, 'sent');
    assert.equal(row.providerId, 'email_verification_test_1');
    assert.match(row.challengeId, /^[A-Za-z0-9_-]{20,100}$/);
    assert.match(row.codeDigest, /^[a-f0-9]{64}$/);
    assert.notEqual(row.codeDigest, message.code);
    assert.doesNotMatch(JSON.stringify(row), new RegExp(`"${message.code}"`));
  } finally {
    testContext.database.close();
  }
});

test('a correct code marks that exact Firebase email verified and consumes the challenge', async () => {
  const testContext = context();
  try {
    await testContext.service.requestCode(actor(), {}, '203.0.113.11');
    const code = testContext.emailClient.verificationCalls[0].code;
    const result = await testContext.service.verifyCode(
      actor(),
      { code },
      '203.0.113.11',
    );
    assert.deepEqual(result, {
      verified: true,
      email: 'member@example.com',
      refreshIdToken: true,
    });
    assert.deepEqual(testContext.firebaseAuth.markCalls, [
      {
        uid: 'firebase-user-123',
        expectedEmail: 'member@example.com',
      },
    ]);
    const row = testContext.database
      .prepare(`
        SELECT status, consumed_at AS consumedAt
          FROM firebase_email_verifications
         WHERE firebase_uid = ?
      `)
      .get(actor().id);
    assert.equal(row.status, 'consumed');
    assert.ok(Number.isSafeInteger(row.consumedAt));
  } finally {
    testContext.database.close();
  }
});

test('wrong codes are attempt-limited and never call Firebase Admin', async () => {
  const testContext = context({
    configOverrides: {
      FIREBASE_EMAIL_CODE_MAX_ATTEMPTS: '3',
      FIREBASE_EMAIL_CODE_ATTEMPT_LIMIT_PER_15_MINUTES: '10',
    },
  });
  try {
    await testContext.service.requestCode(actor(), {}, '203.0.113.12');
    const correct = testContext.emailClient.verificationCalls[0].code;
    const wrong = correct === '999999' ? '999998' : '999999';
    for (let index = 0; index < 3; index += 1) {
      await assert.rejects(
        () =>
          testContext.service.verifyCode(
            actor(),
            { code: wrong },
            '203.0.113.12',
          ),
        (error) =>
          error.status === 422 &&
          error.code === 'invalid_verification_code',
      );
    }
    await assert.rejects(
      () =>
        testContext.service.verifyCode(
          actor(),
          { code: correct },
          '203.0.113.12',
        ),
      (error) => error.code === 'invalid_verification_code',
    );
    assert.equal(testContext.firebaseAuth.markCalls.length, 0);
    const row = testContext.database
      .prepare(`
        SELECT status, attempt_count AS attemptCount
          FROM firebase_email_verifications
         WHERE firebase_uid = ?
      `)
      .get(actor().id);
    assert.equal(row.status, 'consumed');
    assert.equal(row.attemptCount, 3);
  } finally {
    testContext.database.close();
  }
});

test('request cooldown and UID/IP windows are enforced without storing raw scopes', async () => {
  const testContext = context({
    configOverrides: {
      FIREBASE_EMAIL_CODE_RESEND_LIMIT_PER_HOUR: '1',
      FIREBASE_EMAIL_CODE_IP_REQUEST_LIMIT_PER_HOUR: '1',
    },
  });
  try {
    await testContext.service.requestCode(actor(), {}, '198.51.100.7');
    await assert.rejects(
      () =>
        testContext.service.requestCode(actor(), {}, '198.51.100.7'),
      (error) =>
        error.status === 429 &&
        error.code === 'verification_rate_limited' &&
        error.details.retryAfterSeconds > 0,
    );
    testContext.advance(61);
    await assert.rejects(
      () =>
        testContext.service.requestCode(actor(), {}, '198.51.100.8'),
      (error) =>
        error.status === 429 &&
        error.code === 'verification_rate_limited',
    );
    const scopes = testContext.database
      .prepare(`
        SELECT scope_hash AS scopeHash
          FROM firebase_email_verification_usage
      `)
      .all();
    assert.ok(scopes.length >= 2);
    assert.ok(scopes.every((row) => /^[a-f0-9]{64}$/.test(row.scopeHash)));
    assert.doesNotMatch(JSON.stringify(scopes), /198\.51\.100|firebase-user/);
  } finally {
    testContext.database.close();
  }
});

test('email changes, expiry, disabled users, and provider failures fail closed', async () => {
  const testContext = context();
  try {
    await testContext.service.requestCode(actor(), {}, '203.0.113.13');
    const code = testContext.emailClient.verificationCalls[0].code;
    testContext.firebaseAuth.users.get(actor().id).email = 'other@example.com';
    await assert.rejects(
      () =>
        testContext.service.verifyCode(
          actor(),
          { code },
          '203.0.113.13',
        ),
      (error) => error.code === 'invalid_verification_code',
    );
    assert.equal(testContext.firebaseAuth.markCalls.length, 0);

    const expiring = context();
    try {
      await expiring.service.requestCode(actor(), {}, '203.0.113.14');
      const expiringCode = expiring.emailClient.verificationCalls[0].code;
      expiring.advance(601);
      await assert.rejects(
        () =>
          expiring.service.verifyCode(
            actor(),
            { code: expiringCode },
            '203.0.113.14',
          ),
        (error) => error.code === 'invalid_verification_code',
      );
      assert.equal(expiring.firebaseAuth.markCalls.length, 0);
    } finally {
      expiring.database.close();
    }

    const disabledAuth = new FakeFirebaseAuth();
    disabledAuth.users.get(actor().id).disabled = true;
    const disabled = context({ firebaseAuth: disabledAuth });
    try {
      await assert.rejects(
        () => disabled.service.requestCode(actor(), {}, '203.0.113.15'),
        (error) => error.code === 'invalid_token',
      );
      assert.equal(disabled.emailClient.verificationCalls.length, 0);
    } finally {
      disabled.database.close();
    }

    const deliveryFailure = context();
    deliveryFailure.emailClient.verificationError = new AppError(
      503,
      'email_provider_unavailable',
      'Email unavailable.',
      undefined,
      true,
    );
    try {
      await assert.rejects(
        () =>
          deliveryFailure.service.requestCode(
            actor(),
            {},
            '203.0.113.16',
          ),
        (error) =>
          error.status === 503 &&
          error.code === 'email_provider_unavailable',
      );
      assert.equal(
        deliveryFailure.database
          .prepare(`
            SELECT COUNT(*) AS count
              FROM firebase_email_verifications
          `)
          .get().count,
        0,
      );
    } finally {
      deliveryFailure.database.close();
    }
  } finally {
    testContext.database.close();
  }
});

test('already-verified Firebase identities do not trigger another email', async () => {
  const firebaseAuth = new FakeFirebaseAuth();
  firebaseAuth.users.get(actor().id).emailVerified = true;
  const testContext = context({ firebaseAuth });
  try {
    const result = await testContext.service.requestCode(
      actor(),
      {},
      '203.0.113.17',
    );
    assert.deepEqual(result, {
      verification: {
        status: 'already_verified',
        email: 'member@example.com',
      },
    });
    assert.equal(testContext.emailClient.verificationCalls.length, 0);
  } finally {
    testContext.database.close();
  }
});
