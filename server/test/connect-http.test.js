import assert from 'node:assert/strict';
import test from 'node:test';

import { signAccessToken } from '../src/auth.js';
import { ConnectService } from '../src/connect-service.js';
import { loadConfig } from '../src/config.js';
import { createDatabase } from '../src/database.js';
import { createHttpServer } from '../src/http-server.js';
import {
  connectedAccount,
  connectEvent,
  FakeConnectStripeClient,
} from '../test_support/fake-connect-stripe.js';

const JWT_SECRET = 'connect-http-secret-that-is-longer-than-thirty-two-bytes';

function config() {
  return loadConfig({
    NODE_ENV: 'test',
    AUTH_MODE: 'jwt',
    JWT_HS256_SECRET: JWT_SECRET,
    JWT_ISSUER: 'https://identity.drip.test',
    JWT_AUDIENCE: 'drip-app',
    ACCOUNT_AUTH_ENABLED: 'true',
    EMAIL_PROVIDER: 'resend',
    RESEND_API_KEY: 're_test_connect_http',
    WELCOME_EMAIL_FROM: 'Drip <welcome@drip.test>',
    STRIPE_SECRET_KEY: 'sk_test_connect_http',
    STRIPE_WEBHOOK_SECRET: 'whsec_checkout_http',
    STRIPE_CONNECT_ENABLED: 'true',
    STRIPE_CONNECT_WEBHOOK_SECRET: 'whsec_connect_http',
    CONNECT_ONBOARDING_RETURN_URL: 'https://app.drip.test/connect/return',
    CONNECT_ONBOARDING_REFRESH_URL:
      'https://api.drip.test/connect/onboarding/refresh',
    CORS_ALLOWED_ORIGINS: 'http://localhost:8080',
    DATABASE_PATH: ':memory:',
  });
}

function listen(server) {
  return new Promise((resolve, reject) => {
    server.once('error', reject);
    server.listen(0, '127.0.0.1', () => {
      server.off('error', reject);
      resolve(`http://127.0.0.1:${server.address().port}`);
    });
  });
}

function close(server) {
  return new Promise((resolve) => server.close(resolve));
}

test('HTTP Connect lifecycle is authenticated, refresh-safe, and webhook synchronized', async () => {
  const testConfig = config();
  const database = createDatabase(':memory:');
  const stripeClient = new FakeConnectStripeClient();
  const now = Math.floor(Date.now() / 1000);
  const accountId = 'usr_connect_http_owner_123';
  const sessionId = 'ses_connect_http_session_123456789';
  database
    .prepare(`
      INSERT INTO accounts (
        id, display_name, email, password_hash, status, email_verified_at,
        created_at, updated_at
      ) VALUES (?, 'HTTP Seller', 'http-seller@example.com', 'test-hash',
                'active', ?, ?, ?)
    `)
    .run(accountId, now, now, now);
  database
    .prepare(`
      INSERT INTO seller_accounts (
        seller_handle, seller_name, owner_account_id, is_pro,
        transfers_ready, updated_at
      ) VALUES ('@http-seller', 'HTTP Seller', ?, 0, 0, ?)
    `)
    .run(accountId, now);
  database
    .prepare(`
      INSERT INTO account_sessions (id, account_id, expires_at, created_at)
      VALUES (?, ?, ?, ?)
    `)
    .run(sessionId, accountId, now + 3600, now);
  const accessToken = signAccessToken(testConfig, {
    accountId,
    sessionId,
    issuedAt: now,
    expiresAt: now + 3600,
    sellerHandle: '@http-seller',
  });
  const connectService = new ConnectService({
    database,
    stripeClient,
    config: testConfig,
  });
  const checkoutService = {
    handleWebhook() {
      throw new Error('Checkout webhook is outside this test.');
    },
  };
  const server = createHttpServer({
    checkoutService,
    aiService: null,
    accountService: null,
    connectService,
    config: testConfig,
    database,
  });
  const base = await listen(server);
  const authorized = {
    authorization: `Bearer ${accessToken}`,
    'content-type': 'application/json',
  };
  try {
    const health = await fetch(`${base}/healthz`);
    assert.equal((await health.json()).stripeConnectConfigured, true);

    const anonymous = await fetch(`${base}/v1/seller/connect/status`);
    assert.equal(anonymous.status, 401);

    const initial = await fetch(`${base}/v1/seller/connect/status`, {
      headers: authorized,
    });
    assert.equal(initial.status, 200);
    assert.equal((await initial.json()).status, 'not_started');

    const onboarding = await fetch(`${base}/v1/seller/connect/onboarding`, {
      method: 'POST',
      headers: authorized,
      body: '{}',
    });
    assert.equal(onboarding.status, 201);
    assert.equal(
      (await onboarding.json()).url,
      'https://accounts.stripe.com/r/test-link#alu_opaque-state',
    );

    const dashboard = await fetch(`${base}/v1/seller/connect/dashboard`, {
      method: 'POST',
      headers: authorized,
      body: '{}',
    });
    assert.equal(dashboard.status, 200);
    const dashboardBody = await dashboard.json();
    assert.equal(
      dashboardBody.url,
      'https://connect.stripe.com/express/test-login',
    );
    assert.match(dashboardBody.expiresAt, /^\d{4}-/);

    const refresh = await fetch(`${base}/connect/onboarding/refresh`);
    assert.equal(refresh.status, 200);
    const refreshBody = await refresh.text();
    assert.match(refreshBody, /cannot create a new payout link/);
    assert.doesNotMatch(refreshBody, /connect\.stripe\.com/);

    stripeClient.account = connectedAccount({
      transfers: 'active',
      payouts: 'active',
    });
    const event = connectEvent();
    const invalidWebhook = await fetch(`${base}/v1/stripe/connect-webhook`, {
      method: 'POST',
      headers: { 'stripe-signature': 'bad' },
      body: JSON.stringify(event),
    });
    assert.equal(invalidWebhook.status, 400);

    const webhook = await fetch(`${base}/v1/stripe/connect-webhook`, {
      method: 'POST',
      headers: { 'stripe-signature': 'connect_test_signature' },
      body: JSON.stringify(event),
    });
    assert.equal(webhook.status, 200);
    assert.deepEqual(await webhook.json(), { received: true, processed: true });

    const ready = await fetch(`${base}/v1/seller/connect/status`, {
      headers: authorized,
    });
    assert.equal((await ready.json()).status, 'ready');
  } finally {
    await close(server);
    database.close();
  }
});
