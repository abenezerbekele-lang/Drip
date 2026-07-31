import assert from 'node:assert/strict';
import test from 'node:test';

import { AccountService } from '../src/account-service.js';
import { CheckoutService } from '../src/checkout-service.js';
import { loadConfig } from '../src/config.js';
import { createDatabase } from '../src/database.js';
import { createHttpServer } from '../src/http-server.js';
import { FakeEmailClient } from '../test_support/fake-email.js';
import { FakeStripeClient } from '../test_support/fake-stripe.js';

function config(overrides = {}) {
  return loadConfig({
    NODE_ENV: 'test',
    AUTH_MODE: 'jwt',
    JWT_HS256_SECRET: 'account-http-test-secret-longer-than-thirty-two-bytes',
    JWT_ISSUER: 'https://identity.drip.test',
    JWT_AUDIENCE: 'drip-app',
    ACCOUNT_AUTH_ENABLED: 'true',
    EMAIL_PROVIDER: 'resend',
    RESEND_API_KEY: 're_test_http',
    WELCOME_EMAIL_FROM: 'Drip <welcome@drip.test>',
    DATABASE_PATH: ':memory:',
    CORS_ALLOWED_ORIGINS: 'http://localhost:8080',
    ...overrides,
  });
}

function context(overrides = {}) {
  const appConfig = config(overrides);
  const database = createDatabase(':memory:');
  const emailClient = new FakeEmailClient();
  const checkoutService = new CheckoutService({
    database,
    stripeClient: new FakeStripeClient(),
    config: appConfig,
  });
  const accountService = new AccountService({
    database,
    emailClient,
    config: appConfig,
  });
  const server = createHttpServer({
    checkoutService,
    accountService,
    config: appConfig,
    database,
  });
  return { config: appConfig, database, emailClient, accountService, server };
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

const credentials = Object.freeze({
  name: 'Jordan Lee',
  email: 'Member@Example.com',
  password: 'Gallery-Fit!2026',
});
const loginCredentials = Object.freeze({
  email: credentials.email,
  password: credentials.password,
});

test('HTTP signup, session, protected API, logout, and login share one revocable token', async () => {
  const testContext = context();
  const base = await listen(testContext.server);
  try {
    const signup = await fetch(`${base}/v1/auth/signup`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(credentials),
    });
    assert.equal(signup.status, 202);
    assert.equal(signup.headers.get('cache-control'), 'no-store');
    const pending = await signup.json();
    assert.equal(pending.verification.email, 'member@example.com');
    assert.ok(pending.verification.challengeToken);
    assert.equal(Object.hasOwn(pending, 'session'), false);
    const tooSoon = await fetch(`${base}/v1/auth/resend-verification`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        challengeToken: pending.verification.challengeToken,
      }),
    });
    assert.equal(tooSoon.status, 429);
    assert.equal(
      (await tooSoon.json()).error.code,
      'verification_rate_limited',
    );
    assert.ok(Number(tooSoon.headers.get('retry-after')) > 0);
    const wrongCode = await fetch(`${base}/v1/auth/verify-email`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        challengeToken: pending.verification.challengeToken,
        code: '999999' === testContext.emailClient.verificationCalls.at(-1).code
          ? '999998'
          : '999999',
      }),
    });
    assert.equal(wrongCode.status, 422);
    assert.equal(
      (await wrongCode.json()).error.code,
      'invalid_verification_code',
    );
    const verification = await fetch(`${base}/v1/auth/verify-email`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        challengeToken: pending.verification.challengeToken,
        code: testContext.emailClient.verificationCalls.at(-1).code,
      }),
    });
    assert.equal(verification.status, 200);
    const created = await verification.json();
    assert.equal(created.user.email, 'member@example.com');
    assert.equal(created.user.name, 'Jordan Lee');
    assert.equal(created.welcomeEmailSent, true);
    assert.deepEqual(created.welcomeEmail, { status: 'sent' });
    assert.doesNotMatch(JSON.stringify(created), /Gallery-Fit|passwordHash/);
    const authorization = `Bearer ${created.session.accessToken}`;

    const session = await fetch(`${base}/v1/auth/session`, {
      headers: { Authorization: authorization },
    });
    assert.equal(session.status, 200);
    assert.equal((await session.json()).authenticated, true);

    const catalog = await fetch(`${base}/v1/catalog`, {
      headers: { Authorization: authorization },
    });
    assert.equal(catalog.status, 200);
    assert.ok((await catalog.json()).items.length > 0);

    const logout = await fetch(`${base}/v1/auth/logout`, {
      method: 'POST',
      headers: { Authorization: authorization },
    });
    assert.equal(logout.status, 200);
    assert.deepEqual(await logout.json(), { loggedOut: true });

    const revoked = await fetch(`${base}/v1/auth/session`, {
      headers: { Authorization: authorization },
    });
    assert.equal(revoked.status, 401);
    assert.equal((await revoked.json()).error.code, 'invalid_token');

    const login = await fetch(`${base}/v1/auth/login`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(loginCredentials),
    });
    assert.equal(login.status, 200);
    const loggedIn = await login.json();
    assert.equal(loggedIn.user.id, created.user.id);
    assert.notEqual(loggedIn.session.accessToken, created.session.accessToken);
    assert.equal(testContext.emailClient.welcomeCalls.length, 1);
  } finally {
    await close(testContext.server);
    testContext.database.close();
  }
});

test('HTTP auth schemas and rate limits fail closed with Retry-After', async () => {
  const testContext = context({
    AUTH_LOGIN_RATE_LIMIT_PER_15_MINUTES: '1',
  });
  const base = await listen(testContext.server);
  try {
    const unknownField = await fetch(`${base}/v1/auth/signup`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ ...credentials, isAdmin: true }),
    });
    assert.equal(unknownField.status, 422);
    assert.equal((await unknownField.json()).error.code, 'invalid_request');

    const signup = await fetch(`${base}/v1/auth/signup`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(credentials),
    });
    assert.equal(signup.status, 202);

    const wrong = await fetch(`${base}/v1/auth/login`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        ...loginCredentials,
        password: 'Wrong-Gallery!2026',
      }),
    });
    assert.equal(wrong.status, 401);
    assert.equal((await wrong.json()).error.code, 'invalid_credentials');

    const limited = await fetch(`${base}/v1/auth/login`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(loginCredentials),
    });
    assert.equal(limited.status, 429);
    assert.equal((await limited.json()).error.code, 'auth_rate_limited');
    assert.ok(Number(limited.headers.get('retry-after')) > 0);
  } finally {
    await close(testContext.server);
    testContext.database.close();
  }
});
