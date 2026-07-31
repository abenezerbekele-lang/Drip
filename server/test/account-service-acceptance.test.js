import assert from 'node:assert/strict';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { DatabaseSync } from 'node:sqlite';
import test from 'node:test';

import { AccountService, normalizeEmail } from '../src/account-service.js';
import { loadConfig } from '../src/config.js';
import { createDatabase } from '../src/database.js';
import { AppError } from '../src/errors.js';
import { FakeEmailClient } from '../test_support/fake-email.js';

const strongPassword = 'Correct-Horse-9!Battery';

function authConfig(overrides = {}) {
  return loadConfig({
    NODE_ENV: 'test',
    AUTH_MODE: 'jwt',
    JWT_HS256_SECRET: 'test-auth-secret-that-is-at-least-32-bytes-long',
    JWT_ISSUER: 'https://identity.drip.test',
    JWT_AUDIENCE: 'drip-app',
    ACCOUNT_AUTH_ENABLED: 'true',
    AUTH_RATE_LIMIT_SECRET: 'test-rate-limit-secret-that-is-at-least-32-bytes',
    AUTH_SIGNUP_RATE_LIMIT_PER_HOUR: '100',
    AUTH_LOGIN_RATE_LIMIT_PER_15_MINUTES: '100',
    AUTH_VERIFICATION_ATTEMPT_RATE_LIMIT_PER_15_MINUTES: '100',
    EMAIL_PROVIDER: 'resend',
    RESEND_API_KEY: 're_test_server_only',
    WELCOME_EMAIL_FROM: 'Drip <welcome@drip.test>',
    DATABASE_PATH: ':memory:',
    ...overrides,
  });
}

function context() {
  const database = createDatabase(':memory:');
  const config = authConfig();
  const emailClient = new FakeEmailClient();
  let now = 1_900_000_000_000;
  const service = new AccountService({
    database,
    emailClient,
    config,
    clock: () => now,
  });
  return {
    database,
    config,
    emailClient,
    service,
    advance(milliseconds) {
      now += milliseconds;
    },
  };
}

async function registerAndVerify(setup, email = 'alice@example.com') {
  const pending = await setup.service.register(
    { name: 'Alice', email, password: strongPassword },
    '198.51.100.1',
  );
  return setup.service.verifyEmail(
    {
      challengeToken: pending.verification.challengeToken,
      code: setup.emailClient.verificationCalls.at(-1).code,
    },
    '198.51.100.1',
  );
}

test('email normalization is canonical and rejects ambiguous input', () => {
  assert.equal(normalizeEmail('  Alice@Example.COM  '), 'alice@example.com');
  assert.equal(
    normalizeEmail(' Ａｌｉｃｅ＠Ｅｘａｍｐｌｅ．ＣＯＭ '),
    'alice@example.com',
  );
  for (const invalid of [
    'alice',
    '.alice@example.com',
    'alice..shop@example.com',
    'alice@example..com',
    'alice@example.com\nbcc:attacker@example.com',
    `a@${'x'.repeat(64)}.com`,
  ]) {
    assert.throws(
      () => normalizeEmail(invalid),
      (error) => error.status === 422 && error.code === 'invalid_email',
      invalid,
    );
  }
});

test('unknown email, malformed email, wrong password, and pending account login are indistinguishable', async () => {
  const setup = context();
  try {
    await setup.service.register(
      { name: 'Alice', email: 'alice@example.com', password: strongPassword },
      '198.51.100.20',
    );
    const credentials = [
      { email: 'missing@example.com', password: strongPassword },
      { email: 'alice@example.com', password: 'Wrong-Password-9!' },
      { email: 'not-an-email', password: strongPassword },
      { email: 'alice@example.com', password: strongPassword },
    ];
    const failures = [];
    for (const item of credentials) {
      await assert.rejects(
        setup.service.login(item, '198.51.100.21'),
        (error) => {
          failures.push({ status: error.status, code: error.code, message: error.message });
          return true;
        },
      );
    }
    assert.ok(failures.every((failure) => JSON.stringify(failure) === JSON.stringify(failures[0])));
  } finally {
    setup.database.close();
  }
});

test('welcome acceptance is reported only after verification and provider acceptance', async () => {
  const setup = context();
  setup.emailClient.welcomeError = new AppError(
    503,
    'email_provider_unavailable',
    'Email unavailable.',
    undefined,
    true,
  );
  try {
    const verified = await registerAndVerify(setup, 'delayed@example.com');
    assert.equal(verified.welcomeEmailSent, false);
    assert.deepEqual(verified.welcomeEmail, { status: 'pending' });
    assert.ok(verified.session.accessToken);
    assert.equal(setup.emailClient.verificationCalls.length, 1);
    assert.equal(setup.emailClient.welcomeCalls.length, 1);

    setup.emailClient.welcomeError = null;
    setup.advance(61_000);
    const drained = await setup.service.drainWelcomeEmails({
      accountId: verified.user.id,
      limit: 1,
    });
    assert.equal(drained.sent, 1);
    assert.equal(setup.emailClient.welcomeCalls.length, 2);
    assert.equal(
      new Set(setup.emailClient.welcomeCalls.map((call) => call.idempotencyKey)).size,
      1,
    );
  } finally {
    setup.database.close();
  }
});

test('email verification migration atomically backfills legacy and partially migrated databases', () => {
  for (const partiallyMigrated of [false, true]) {
    const directory = mkdtempSync(path.join(tmpdir(), 'drip-auth-migration-'));
    const databasePath = path.join(directory, 'drip.sqlite');
    try {
      const legacy = new DatabaseSync(databasePath);
      legacy.exec(`
        CREATE TABLE accounts (
          id TEXT PRIMARY KEY,
          display_name TEXT NOT NULL,
          email TEXT NOT NULL UNIQUE,
          password_hash TEXT NOT NULL,
          status TEXT NOT NULL,
          ${partiallyMigrated ? 'email_verified_at INTEGER,' : ''}
          created_at INTEGER NOT NULL,
          updated_at INTEGER NOT NULL
        ) STRICT;
        INSERT INTO accounts (
          id, display_name, email, password_hash, status, created_at, updated_at
        ) VALUES ('usr_legacy', 'Legacy User', 'legacy@example.com', 'legacy-hash',
                  'active', 1700000000, 1700000000);
      `);
      legacy.close();

      const migrated = createDatabase(databasePath);
      const row = migrated
        .prepare('SELECT email_verified_at AS verifiedAt FROM accounts WHERE id = ?')
        .get('usr_legacy');
      assert.equal(row.verifiedAt, 1_700_000_000);
      assert.equal(
        migrated
          .prepare('SELECT count(*) AS count FROM schema_migrations WHERE name = ?')
          .get('accounts_email_verification_v1').count,
        1,
      );
      migrated.close();

      const reopened = createDatabase(databasePath);
      assert.equal(
        reopened
          .prepare('SELECT email_verified_at AS verifiedAt FROM accounts WHERE id = ?')
          .get('usr_legacy').verifiedAt,
        1_700_000_000,
      );
      reopened.close();
    } finally {
      rmSync(directory, { recursive: true, force: true });
    }
  }
});
