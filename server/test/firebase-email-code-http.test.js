import assert from 'node:assert/strict';
import test from 'node:test';

import { CheckoutService } from '../src/checkout-service.js';
import { loadConfig } from '../src/config.js';
import { createDatabase } from '../src/database.js';
import { FirebaseEmailCodeService } from '../src/firebase-email-code-service.js';
import { createHttpServer } from '../src/http-server.js';
import { FakeEmailClient } from '../test_support/fake-email.js';
import { FakeStripeClient } from '../test_support/fake-stripe.js';

function config() {
  return loadConfig({
    NODE_ENV: 'test',
    AUTH_MODE: 'firebase',
    DATABASE_PATH: ':memory:',
    FIREBASE_PROJECT_ID: 'dripproject-24882',
    FIREBASE_CREDENTIALS_MODE: 'application-default',
    FIREBASE_EMAIL_CODE_ENABLED: 'true',
    FIREBASE_EMAIL_CODE_SECRET:
      'firebase-http-email-code-secret-longer-than-32-bytes',
    EMAIL_PROVIDER: 'resend',
    RESEND_API_KEY: 're_firebase_http_test',
    WELCOME_EMAIL_FROM: 'Drip <accounts@drip.test>',
  });
}

class FirebaseIdentity {
  constructor() {
    this.user = {
      uid: 'firebase-pending-123',
      email: 'pending@example.com',
      emailVerified: false,
      disabled: false,
      displayName: 'Pending Member',
    };
    this.verifyCalls = [];
    this.markCalls = [];
  }

  async verifyIdToken(token, checkRevoked) {
    this.verifyCalls.push({ token, checkRevoked });
    if (token !== 'pending-id-token') {
      const error = new Error('invalid');
      error.code = 'auth/invalid-id-token';
      throw error;
    }
    return {
      uid: this.user.uid,
      sub: this.user.uid,
      email: this.user.email,
      email_verified: this.user.emailVerified,
      name: this.user.displayName,
      exp: 2_200_000_100,
    };
  }

  async getUserForEmailVerification(uid) {
    assert.equal(uid, this.user.uid);
    return { ...this.user };
  }

  async markEmailVerified(uid, expectedEmail) {
    this.markCalls.push({ uid, expectedEmail });
    assert.equal(uid, this.user.uid);
    assert.equal(expectedEmail, this.user.email);
    this.user.emailVerified = true;
    return { ...this.user };
  }
}

async function listen(server) {
  await new Promise((resolve, reject) => {
    server.once('error', reject);
    server.listen(0, '127.0.0.1', resolve);
  });
  const address = server.address();
  return `http://127.0.0.1:${address.port}`;
}

async function close(server) {
  await new Promise((resolve) => server.close(resolve));
}

function context({ includeService = true } = {}) {
  const appConfig = config();
  const database = createDatabase(':memory:');
  const emailClient = new FakeEmailClient();
  const firebaseAuthVerifier = new FirebaseIdentity();
  const checkoutService = new CheckoutService({
    database,
    stripeClient: new FakeStripeClient(),
    config: appConfig,
  });
  const firebaseEmailCodeService = includeService
    ? new FirebaseEmailCodeService({
        database,
        emailClient,
        firebaseAuth: firebaseAuthVerifier,
        config: appConfig,
        clock: () => 2_200_000_000_000,
      })
    : null;
  const server = createHttpServer({
    checkoutService,
    config: appConfig,
    database,
    firebaseAuthVerifier,
    firebaseEmailCodeService,
  });
  return {
    database,
    emailClient,
    firebaseAuthVerifier,
    server,
  };
}

test('Firebase code HTTP flow alone accepts unverified tokens and preserves every other verified-email gate', async () => {
  const testContext = context();
  const base = await listen(testContext.server);
  const authorization = { Authorization: 'Bearer pending-id-token' };
  try {
    const health = await fetch(`${base}/healthz`);
    assert.equal((await health.json()).firebaseEmailCodeConfigured, true);

    const stillProtected = await fetch(`${base}/v1/catalog`, {
      headers: authorization,
    });
    assert.equal(stillProtected.status, 403);
    assert.equal(
      (await stillProtected.json()).error.code,
      'email_verification_required',
    );

    const anonymous = await fetch(
      `${base}/v1/auth/firebase/email-code/request`,
      {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: '{}',
      },
    );
    assert.equal(anonymous.status, 401);

    const injectedIdentity = await fetch(
      `${base}/v1/auth/firebase/email-code/request`,
      {
        method: 'POST',
        headers: {
          ...authorization,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          email: 'attacker@example.com',
          uid: 'attacker',
        }),
      },
    );
    assert.equal(injectedIdentity.status, 422);
    assert.equal(
      (await injectedIdentity.json()).error.code,
      'invalid_request',
    );

    const requested = await fetch(
      `${base}/v1/auth/firebase/email-code/request`,
      {
        method: 'POST',
        headers: {
          ...authorization,
          'Content-Type': 'application/json',
        },
        body: '{}',
      },
    );
    assert.equal(requested.status, 202);
    const pending = await requested.json();
    assert.equal(pending.verification.status, 'code_sent');
    assert.equal(pending.verification.email, 'pending@example.com');
    assert.equal(testContext.emailClient.verificationCalls.length, 1);

    const code = testContext.emailClient.verificationCalls[0].code;
    const verified = await fetch(
      `${base}/v1/auth/firebase/email-code/verify`,
      {
        method: 'POST',
        headers: {
          ...authorization,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({ code }),
      },
    );
    assert.equal(verified.status, 200);
    assert.deepEqual(await verified.json(), {
      verified: true,
      email: 'pending@example.com',
      refreshIdToken: true,
    });
    assert.deepEqual(testContext.firebaseAuthVerifier.markCalls, [
      {
        uid: 'firebase-pending-123',
        expectedEmail: 'pending@example.com',
      },
    ]);

    const nowAllowed = await fetch(`${base}/v1/catalog`, {
      headers: authorization,
    });
    assert.equal(nowAllowed.status, 200);
    assert.ok((await nowAllowed.json()).items.length > 0);
    assert.ok(
      testContext.firebaseAuthVerifier.verifyCalls.every(
        (call) => call.checkRevoked === true,
      ),
    );
  } finally {
    await close(testContext.server);
    testContext.database.close();
  }
});

test('Firebase code routes fail closed when the service is not installed', async () => {
  const testContext = context({ includeService: false });
  const base = await listen(testContext.server);
  try {
    const response = await fetch(
      `${base}/v1/auth/firebase/email-code/request`,
      {
        method: 'POST',
        headers: {
          Authorization: 'Bearer pending-id-token',
          'Content-Type': 'application/json',
        },
        body: '{}',
      },
    );
    assert.equal(response.status, 503);
    assert.equal(
      (await response.json()).error.code,
      'firebase_email_code_unavailable',
    );
    assert.equal(testContext.emailClient.verificationCalls.length, 0);
  } finally {
    await close(testContext.server);
    testContext.database.close();
  }
});
