import assert from 'node:assert/strict';
import test from 'node:test';

import { loadConfig } from '../src/config.js';
import { createRealEmailClient } from '../src/email-client.js';

function emailConfig() {
  return loadConfig({
    NODE_ENV: 'test',
    AUTH_MODE: 'jwt',
    JWT_HS256_SECRET: 'email-client-test-secret-longer-than-thirty-two-bytes',
    JWT_ISSUER: 'https://identity.drip.test',
    JWT_AUDIENCE: 'drip-app',
    ACCOUNT_AUTH_ENABLED: 'true',
    EMAIL_PROVIDER: 'resend',
    RESEND_API_KEY: 're_test_delivery',
    WELCOME_EMAIL_FROM: 'Drip <welcome@drip.test>',
    DATABASE_PATH: ':memory:',
  });
}

test('Resend boundary sends a fixed welcome message with provider idempotency', async () => {
  const calls = [];
  const client = createRealEmailClient(emailConfig(), async (url, options) => {
    calls.push({ url, options });
    return new Response(JSON.stringify({ id: 'email_provider_123' }), {
      status: 200,
      headers: { 'Content-Type': 'application/json' },
    });
  });
  const result = await client.sendWelcome({
    to: 'style.user@example.com',
    name: '<Style & Co>',
    idempotencyKey: 'welcome-acct_123',
  });
  assert.deepEqual(result, { providerMessageId: 'email_provider_123' });
  assert.equal(calls.length, 1);
  assert.equal(calls[0].url, 'https://api.resend.com/emails');
  assert.equal(calls[0].options.headers.Authorization, 'Bearer re_test_delivery');
  assert.equal(
    calls[0].options.headers['Idempotency-Key'],
    'welcome-acct_123',
  );
  assert.equal(calls[0].options.headers['User-Agent'], 'drip-server/1.0');
  const payload = JSON.parse(calls[0].options.body);
  assert.deepEqual(payload.to, ['style.user@example.com']);
  assert.equal(payload.subject, 'Welcome to Drip!');
  assert.match(payload.text, /Hi <Style & Co>/);
  assert.match(payload.html, /Hi &lt;Style &amp; Co&gt;/);
  assert.doesNotMatch(payload.html, /Hi <Style & Co>/);
  assert.doesNotMatch(calls[0].options.body, /password|accessToken/i);
});

test('Resend boundary sends a fixed six-digit confirmation message', async () => {
  const calls = [];
  const client = createRealEmailClient(emailConfig(), async (url, options) => {
    calls.push({ url, options });
    return new Response(JSON.stringify({ id: 'email_verification_123' }), {
      status: 200,
      headers: { 'Content-Type': 'application/json' },
    });
  });
  const result = await client.sendVerification({
    to: 'style.user@example.com',
    name: '<Style & Co>',
    code: '042917',
    expiresInMinutes: 10,
    idempotencyKey: 'verify-generation-123',
  });
  assert.deepEqual(result, { providerMessageId: 'email_verification_123' });
  const payload = JSON.parse(calls[0].options.body);
  assert.equal(payload.subject, '042917 is your Drip confirmation code');
  assert.match(payload.text, /042917/);
  assert.match(payload.text, /10 minutes/);
  assert.match(payload.html, /Hi &lt;Style &amp; Co&gt;/);
  assert.deepEqual(payload.tags, [
    { name: 'message_type', value: 'email_verification' },
  ]);
  assert.equal(calls[0].options.headers['Idempotency-Key'], 'verify-generation-123');
  assert.doesNotMatch(calls[0].options.body, /password|accessToken/i);
});

test('email boundary fails closed unless the provider confirms an id', async () => {
  for (const response of [
    new Response(JSON.stringify({ message: 'rejected' }), { status: 422 }),
    new Response(JSON.stringify({}), { status: 200 }),
    new Response('not-json', { status: 200 }),
  ]) {
    const client = createRealEmailClient(emailConfig(), async () => response);
    await assert.rejects(
      client.sendWelcome({
        to: 'style.user@example.com',
        name: 'Style User',
        idempotencyKey: 'welcome-acct_123',
      }),
      (error) =>
        error.code === 'email_provider_unavailable' && error.status === 503,
    );
  }
});
