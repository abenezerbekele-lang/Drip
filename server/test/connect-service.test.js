import assert from 'node:assert/strict';
import test from 'node:test';

import { ConnectService } from '../src/connect-service.js';
import { loadConfig } from '../src/config.js';
import { createDatabase } from '../src/database.js';
import {
  connectedAccount,
  connectEvent,
  FakeConnectStripeClient,
} from '../test_support/fake-connect-stripe.js';

const NOW = 1_800_000_000_000;
const OWNER = Object.freeze({ id: 'usr_connect_owner_123456789' });

function connectConfig(overrides = {}) {
  return loadConfig({
    NODE_ENV: 'test',
    AUTH_MODE: 'jwt',
    JWT_HS256_SECRET: 'connect-test-secret-that-is-longer-than-thirty-two-bytes',
    JWT_ISSUER: 'https://identity.drip.test',
    JWT_AUDIENCE: 'drip-app',
    ACCOUNT_AUTH_ENABLED: 'true',
    EMAIL_PROVIDER: 'resend',
    RESEND_API_KEY: 're_test_connect',
    WELCOME_EMAIL_FROM: 'Drip <welcome@drip.test>',
    STRIPE_SECRET_KEY: 'sk_test_connect',
    STRIPE_WEBHOOK_SECRET: 'whsec_checkout_test',
    STRIPE_CONNECT_ENABLED: 'true',
    STRIPE_CONNECT_WEBHOOK_SECRET: 'whsec_connect_test',
    CONNECT_ONBOARDING_RETURN_URL: 'https://app.drip.test/connect/return',
    CONNECT_ONBOARDING_REFRESH_URL:
      'https://api.drip.test/connect/onboarding/refresh',
    DATABASE_PATH: ':memory:',
    ...overrides,
  });
}

function insertOwner(database, {
  id = OWNER.id,
  email = 'seller@example.com',
  name = 'Seller One',
  handle = '@seller-one',
} = {}) {
  const now = NOW / 1000;
  database
    .prepare(`
      INSERT INTO accounts (
        id, display_name, email, password_hash, status, email_verified_at,
        created_at, updated_at
      ) VALUES (?, ?, ?, 'test-hash', 'active', ?, ?, ?)
    `)
    .run(id, name, email, now, now, now);
  database
    .prepare(`
      INSERT INTO seller_accounts (
        seller_handle, seller_name, owner_account_id, is_pro,
        transfers_ready, updated_at
      ) VALUES (?, ?, ?, 0, 0, ?)
    `)
    .run(handle, name, id, now);
  return { id };
}

function context({ account, config = connectConfig() } = {}) {
  const database = createDatabase(':memory:');
  insertOwner(database);
  const stripeClient = new FakeConnectStripeClient({ account });
  const service = new ConnectService({
    database,
    stripeClient,
    config,
    clock: () => NOW,
  });
  return { database, stripeClient, service, config };
}

test('onboarding creates one recipient account with a static non-minting refresh page', async () => {
  const testContext = context();
  try {
    assert.deepEqual(await testContext.service.getStatus(OWNER), {
      status: 'not_started',
      onboardingRequired: true,
      transfersStatus: 'unrequested',
      payoutsStatus: 'unrequested',
      transfersReady: false,
      payoutsReady: false,
      requirementsDue: 0,
      canOpenDashboard: false,
      livemode: false,
      disabledReason: null,
      lastSyncedAt: null,
    });

    const result = await testContext.service.createOnboarding(OWNER, {});
    assert.equal(
      result.url,
      'https://accounts.stripe.com/r/test-link#alu_opaque-state',
    );
    assert.equal(result.expiresAt, '2027-01-15T08:05:00.000Z');
    assert.equal(result.connect.status, 'verification_pending');
    assert.equal(result.connect.livemode, false);
    assert.equal(testContext.stripeClient.createCalls.length, 1);
    assert.deepEqual(testContext.stripeClient.createCalls[0], {
      details: {
        displayName: 'Seller One',
        email: 'seller@example.com',
        sellerHandle: '@seller-one',
      },
      idempotencyKey: 'connect-account:@seller-one:v2',
    });

    assert.equal(
      testContext.stripeClient.accountLinkCalls[0].options.refreshUrl,
      'https://api.drip.test/connect/onboarding/refresh',
    );
    assert.equal(
      testContext.stripeClient.accountLinkCalls[0].options.returnUrl,
      'https://app.drip.test/connect/return',
    );
  } finally {
    testContext.database.close();
  }
});

test('concurrent onboarding uses one stable connected-account creation', async () => {
  const testContext = context();
  let release;
  testContext.stripeClient.createDelay = new Promise((resolve) => {
    release = resolve;
  });
  try {
    const first = testContext.service.createOnboarding(OWNER, {});
    const second = testContext.service.createOnboarding(OWNER, {});
    release();
    await Promise.all([first, second]);
    assert.equal(testContext.stripeClient.createCalls.length, 1);
    assert.equal(testContext.stripeClient.accountLinkCalls.length, 2);
    const row = testContext.database
      .prepare(`
        SELECT stripe_connect_account_id AS accountId
          FROM seller_accounts
         WHERE owner_account_id = ?
      `)
      .get(OWNER.id);
    assert.equal(row.accountId, 'acct_ConnectTest123456789');
  } finally {
    testContext.database.close();
  }
});

test('status derives readiness from transfers, payouts, and current requirements', async () => {
  const testContext = context({
    account: connectedAccount({ transfers: 'active', payouts: 'active' }),
  });
  try {
    await testContext.service.createOnboarding(OWNER, {});
    const ready = await testContext.service.getStatus(OWNER);
    assert.equal(ready.status, 'ready');
    assert.equal(ready.transfersReady, true);
    assert.equal(ready.payoutsReady, true);
    assert.equal(ready.canOpenDashboard, true);
    assert.equal(ready.livemode, false);
    assert.equal(
      testContext.database
        .prepare('SELECT transfers_ready FROM seller_accounts WHERE owner_account_id = ?')
        .get(OWNER.id).transfers_ready,
      1,
    );

    testContext.stripeClient.account = connectedAccount({
      transfers: 'active',
      payouts: 'active',
      requirementStatus: 'currently_due',
    });
    const incomplete = await testContext.service.getStatus(OWNER);
    assert.equal(incomplete.status, 'onboarding_incomplete');
    assert.equal(incomplete.payoutsReady, false);
    assert.equal(incomplete.requirementsDue, 1);
    assert.equal(incomplete.disabledReason, 'requirements_due');
  } finally {
    testContext.database.close();
  }
});

test('dashboard link is owner-scoped, Stripe-hosted, and explicitly expires', async () => {
  const testContext = context({
    account: connectedAccount({ transfers: 'active', payouts: 'active' }),
  });
  try {
    await assert.rejects(
      testContext.service.createDashboardLink(OWNER, {}),
      (error) => error.code === 'connect_onboarding_required',
    );
    await testContext.service.createOnboarding(OWNER, {});
    const dashboard = await testContext.service.createDashboardLink(OWNER, {});
    assert.deepEqual(dashboard, {
      url: 'https://connect.stripe.com/express/test-login',
      expiresAt: '2027-01-15T08:05:00.000Z',
    });
    assert.deepEqual(testContext.stripeClient.dashboardCalls, [
      'acct_ConnectTest123456789',
    ]);

    testContext.stripeClient.createExpressDashboardLoginLink = async () => ({
      url: 'https://connect.stripe.com/express/test-login#unexpected',
    });
    await assert.rejects(
      testContext.service.createDashboardLink(OWNER, {}),
      (error) => error.code === 'invalid_provider_response',
    );

    insertOwner(testContext.database, {
      id: 'usr_connect_other_123456789',
      email: 'other@example.com',
      name: 'Other Seller',
      handle: '@other-seller',
    });
    await assert.rejects(
      testContext.service.createDashboardLink(
        { id: 'usr_connect_other_123456789' },
        {},
      ),
      (error) => error.code === 'connect_onboarding_required',
    );
  } finally {
    testContext.database.close();
  }
});

test('Connect webhook is signature checked, mode checked, latest-state synced, and replay safe', async () => {
  const testContext = context();
  try {
    await testContext.service.createOnboarding(OWNER, {});
    testContext.stripeClient.account = connectedAccount({
      transfers: 'active',
      payouts: 'active',
    });
    const event = connectEvent();
    const raw = Buffer.from(JSON.stringify(event));
    await assert.rejects(
      testContext.service.handleWebhook(raw, 'bad'),
      (error) => error.code === 'invalid_connect_webhook_signature',
    );
    assert.deepEqual(
      await testContext.service.handleWebhook(raw, 'connect_test_signature'),
      { received: true, processed: true },
    );
    assert.deepEqual(
      await testContext.service.handleWebhook(raw, 'connect_test_signature'),
      { received: true, duplicate: true },
    );
    assert.equal((await testContext.service.getStatus(OWNER)).status, 'ready');
    assert.equal(
      testContext.database
        .prepare('SELECT attempts, status FROM stripe_connect_events WHERE event_id = ?')
        .get(event.id).attempts,
      1,
    );

    const liveEvent = connectEvent({
      id: 'evt_connect_live_123456789',
      livemode: true,
    });
    assert.deepEqual(
      await testContext.service.handleWebhook(
        Buffer.from(JSON.stringify(liveEvent)),
        'connect_test_signature',
      ),
      { received: true, ignored: true },
    );
  } finally {
    testContext.database.close();
  }
});

test('provider URLs, request bodies, and account modes fail closed', async () => {
  const testContext = context();
  try {
    await assert.rejects(
      testContext.service.createOnboarding(OWNER, { accountId: 'acct_attacker' }),
      (error) => error.code === 'invalid_request',
    );
  } finally {
    testContext.database.close();
  }

  for (const unsafeUrl of [
    'https://evil.example/connect',
    'https://accounts.stripe.com.evil.example/r/setup',
    'https://accounts.stripe.com:8443/r/setup',
    'https://user:password@accounts.stripe.com/r/setup',
    'https://accounts.stripe.com/r/setup?next=%0Aheader',
    'https://connect.stripe.com/setup',
  ]) {
    const unsafe = context();
    try {
      unsafe.stripeClient.createConnectedAccountLink = async () => ({
        url: unsafeUrl,
        expires_at: '2027-01-15T08:05:00.000Z',
      });
      await assert.rejects(
        unsafe.service.createOnboarding(OWNER, {}),
        (error) => error.code === 'invalid_provider_response',
      );
    } finally {
      unsafe.database.close();
    }
  }

  const liveMismatch = context({ account: connectedAccount({ livemode: true }) });
  try {
    await assert.rejects(
      liveMismatch.service.createOnboarding(OWNER, {}),
      (error) => error.code === 'stripe_mode_mismatch',
    );
  } finally {
    liveMismatch.database.close();
  }
});
