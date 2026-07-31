import assert from 'node:assert/strict';
import test from 'node:test';

import { createHttpServer } from '../src/http-server.js';
import { testConfig, testContext } from '../test_support/setup.js';

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

test('HTTP surface exposes health, exact CORS, and canonical checkout contract', async () => {
  const context = testContext();
  const server = createHttpServer({
    checkoutService: context.service,
    config: context.config,
    database: context.database,
  });
  const base = await listen(server);
  try {
    const health = await fetch(`${base}/healthz`);
    assert.equal(health.status, 200);
    const healthPayload = await health.json();
    assert.equal(healthPayload.service, 'drip-checkout');
    assert.equal(healthPayload.databaseProvider, 'sqlite');
    assert.equal(health.headers.get('cache-control'), 'no-store');

    const rejectedOrigin = await fetch(`${base}/healthz`, {
      headers: { Origin: 'https://evil.example' },
    });
    assert.equal(rejectedOrigin.status, 403);

    const authPreflight = await fetch(`${base}/v1/auth/signup`, {
      method: 'OPTIONS',
      headers: {
        Origin: 'http://localhost:8080',
        'Access-Control-Request-Method': 'POST',
        'Access-Control-Request-Headers': 'cache-control,content-type',
      },
    });
    assert.equal(authPreflight.status, 204);
    assert.match(
      authPreflight.headers.get('access-control-allow-headers') || '',
      /(?:^|,\s*)Cache-Control(?:,|$)/,
    );

    const body = {
      attemptId: 'attempt_http_checkout_001',
      items: [{ listingId: 'nike-red-court', selectedSize: '9' }],
    };
    const checkout = await fetch(`${base}/v1/checkout/sessions`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Idempotency-Key': body.attemptId,
        Origin: 'http://localhost:8080',
      },
      body: JSON.stringify(body),
    });
    assert.equal(checkout.status, 201);
    assert.equal(
      checkout.headers.get('access-control-allow-origin'),
      'http://localhost:8080',
    );
    const created = await checkout.json();
    assert.equal(created.sessionId, 'cs_test_1');
    assert.equal(created.checkoutSessionId, created.sessionId);
    assert.equal(created.url, created.checkoutUrl);
    assert.equal(created.quote.totalCents, 10_366);

    const status = await fetch(
      `${base}/v1/checkout/sessions/${created.sessionId}`,
    );
    assert.equal(status.status, 200);
    assert.equal((await status.json()).orderId, created.orderId);

    const canceled = await fetch(
      `${base}/v1/checkout/sessions/${created.sessionId}/expire`,
      {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ attemptId: body.attemptId }),
      },
    );
    assert.equal(canceled.status, 200);
    assert.equal((await canceled.json()).status, 'canceled');
  } finally {
    await close(server);
    context.database.close();
  }
});

test('HTTP validation rejects client prices and invalid webhook signatures', async () => {
  const context = testContext();
  const server = createHttpServer({
    checkoutService: context.service,
    config: context.config,
    database: context.database,
  });
  const base = await listen(server);
  try {
    const badCheckout = await fetch(`${base}/v1/checkout/sessions`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        attemptId: 'attempt_http_tamper_0001',
        items: [
          {
            listingId: 'nike-red-court',
            selectedSize: '9',
            priceCents: 1,
          },
        ],
      }),
    });
    assert.equal(badCheckout.status, 422);
    assert.equal((await badCheckout.json()).error.code, 'invalid_request');

    const webhook = await fetch(`${base}/v1/stripe/webhook`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Stripe-Signature': 'wrong',
      },
      body: JSON.stringify({ id: 'evt_fake', type: 'checkout.session.completed' }),
    });
    assert.equal(webhook.status, 400);
    assert.equal(
      (await webhook.json()).error.code,
      'invalid_webhook_signature',
    );
  } finally {
    await close(server);
    context.database.close();
  }
});

test('HTTP checkout accepts only verified Firebase ID tokens in Firebase mode', async () => {
  const config = testConfig({
    AUTH_MODE: 'firebase',
    FIREBASE_PROJECT_ID: 'dripproject-24882',
    FIREBASE_CREDENTIALS_MODE: 'application-default',
  });
  const context = testContext({ config });
  const verificationCalls = [];
  const firebaseAuthVerifier = {
    async verifyIdToken(token, checkRevoked) {
      verificationCalls.push({ token, checkRevoked });
      if (token === 'unverified-token') {
        return {
          uid: 'firebase-unverified',
          sub: 'firebase-unverified',
          email: 'pending@example.com',
          email_verified: false,
          exp: 2_000_000_100,
        };
      }
      if (token !== 'verified-token') {
        const error = new Error('invalid');
        error.code = 'auth/invalid-id-token';
        throw error;
      }
      return {
        uid: 'firebase-buyer-123',
        sub: 'firebase-buyer-123',
        email: 'buyer@example.com',
        email_verified: true,
        name: 'Verified Buyer',
        exp: 2_000_000_100,
      };
    },
  };
  const server = createHttpServer({
    checkoutService: context.service,
    config,
    database: context.database,
    firebaseAuthVerifier,
  });
  const base = await listen(server);
  try {
    const health = await fetch(`${base}/healthz`);
    const healthPayload = await health.json();
    assert.equal(healthPayload.accountAuthConfigured, true);
    assert.equal(healthPayload.authProvider, 'firebase');

    const anonymous = await fetch(`${base}/v1/catalog`);
    assert.equal(anonymous.status, 401);
    assert.equal(
      (await anonymous.json()).error.code,
      'authentication_required',
    );

    const unverified = await fetch(`${base}/v1/catalog`, {
      headers: { Authorization: 'Bearer unverified-token' },
    });
    assert.equal(unverified.status, 403);
    assert.equal(
      (await unverified.json()).error.code,
      'email_verification_required',
    );

    const session = await fetch(`${base}/v1/auth/session`, {
      headers: { Authorization: 'Bearer verified-token' },
    });
    assert.equal(session.status, 200);
    const sessionPayload = await session.json();
    assert.equal(sessionPayload.authenticated, true);
    assert.equal(sessionPayload.user.id, 'firebase-buyer-123');
    assert.equal(sessionPayload.user.email, 'buyer@example.com');

    const body = {
      attemptId: 'attempt_firebase_checkout_001',
      items: [{ listingId: 'nike-red-court', selectedSize: '9' }],
    };
    const checkout = await fetch(`${base}/v1/checkout/sessions`, {
      method: 'POST',
      headers: {
        Authorization: 'Bearer verified-token',
        'Content-Type': 'application/json',
        'Idempotency-Key': body.attemptId,
      },
      body: JSON.stringify(body),
    });
    assert.equal(checkout.status, 201);
    assert.equal((await checkout.json()).sessionId, 'cs_test_1');
    assert.ok(
      verificationCalls.every((call) => call.checkRevoked === true),
    );
  } finally {
    await close(server);
    context.database.close();
  }
});
