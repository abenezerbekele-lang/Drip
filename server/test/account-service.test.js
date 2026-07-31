import assert from 'node:assert/strict';
import test from 'node:test';

import { AccountService } from '../src/account-service.js';
import { authenticateRequest } from '../src/auth.js';
import { loadConfig } from '../src/config.js';
import { createDatabase } from '../src/database.js';
import {
  FakeEmailClient,
  failingEmailClient,
} from '../test_support/fake-email.js';

const START = 1_800_000_000_000;
const JWT_SECRET = 'account-test-secret-that-is-longer-than-thirty-two-bytes';
const signup = Object.freeze({
  name: 'Avery Stone',
  email: 'Style.User@example.com',
  password: 'Archive-Look!2026',
});

function accountConfig(overrides = {}) {
  return loadConfig({
    NODE_ENV: 'test',
    AUTH_MODE: 'jwt',
    JWT_HS256_SECRET: JWT_SECRET,
    JWT_ISSUER: 'https://identity.drip.test',
    JWT_AUDIENCE: 'drip-app',
    ACCOUNT_AUTH_ENABLED: 'true',
    AUTH_SIGNUP_RATE_LIMIT_PER_HOUR: '100',
    AUTH_LOGIN_RATE_LIMIT_PER_15_MINUTES: '100',
    AUTH_VERIFICATION_ATTEMPT_RATE_LIMIT_PER_15_MINUTES: '100',
    EMAIL_PROVIDER: 'resend',
    RESEND_API_KEY: 're_test_accounts',
    WELCOME_EMAIL_FROM: 'Drip <welcome@drip.test>',
    DATABASE_PATH: ':memory:',
    ...overrides,
  });
}

function context({ config = accountConfig(), emailClient, start = START } = {}) {
  const database = createDatabase(':memory:');
  const client = emailClient ?? new FakeEmailClient();
  let now = start;
  const service = new AccountService({
    database,
    emailClient: client,
    config,
    clock: () => now,
  });
  return {
    database,
    emailClient: client,
    service,
    config,
    now: () => now,
    advance(milliseconds) {
      now += milliseconds;
    },
    close() {
      database.close();
    },
  };
}

function latestCode(setup) {
  return setup.emailClient.verificationCalls.at(-1).code;
}

async function createAndVerify(setup, body = signup, requester = '203.0.113.8') {
  const pending = await setup.service.register(body, requester);
  const verified = await setup.service.verifyEmail(
    {
      challengeToken: pending.verification.challengeToken,
      code: latestCode(setup),
    },
    requester,
  );
  return { pending, verified };
}

test('signup stores only password/code/challenge hashes and creates no session', async () => {
  const setup = context();
  try {
    const pending = await setup.service.register(
      {
        name: '  Avery   Stone  ',
        email: '  STYLE.User@Example.COM ',
        password: signup.password,
      },
      '203.0.113.8',
    );
    assert.equal(pending.verification.email, 'style.user@example.com');
    assert.match(pending.verification.challengeToken, /^[A-Za-z0-9_-]{43}$/);
    assert.equal(Object.hasOwn(pending, 'user'), false);
    assert.equal(Object.hasOwn(pending, 'session'), false);
    assert.equal(setup.emailClient.verificationCalls.length, 1);
    assert.match(latestCode(setup), /^[0-9]{6}$/);
    assert.equal(setup.emailClient.welcomeCalls.length, 0);

    const row = setup.database.prepare(`
      SELECT accounts.display_name AS name, accounts.email,
             accounts.password_hash AS passwordHash,
             accounts.email_verified_at AS emailVerifiedAt,
             verification.code_digest AS codeDigest,
             verification.challenge_digest AS challengeDigest,
             verification.provider_message_id AS providerId
        FROM accounts
        JOIN email_verifications AS verification
          ON verification.account_id = accounts.id
    `).get();
    assert.equal(row.name, 'Avery Stone');
    assert.equal(row.email, 'style.user@example.com');
    assert.equal(row.emailVerifiedAt, null);
    assert.match(row.passwordHash, /^scrypt\$32768\$8\$3\$/);
    assert.match(row.codeDigest, /^[a-f0-9]{64}$/);
    assert.match(row.challengeDigest, /^[a-f0-9]{64}$/);
    assert.equal(row.providerId, 'email_verification_test_1');
    assert.doesNotMatch(
      JSON.stringify(row),
      new RegExp(`${latestCode(setup)}|${pending.verification.challengeToken}|Archive-Look`),
    );
    assert.equal(
      setup.database.prepare('SELECT count(*) AS count FROM account_sessions').get().count,
      0,
    );
    assert.equal(
      setup.database.prepare('SELECT count(*) AS count FROM seller_accounts WHERE owner_account_id IS NOT NULL').get().count,
      0,
    );
  } finally {
    setup.close();
  }
});

test('correct code verifies once, issues a revocable session, and only then sends welcome', async () => {
  const setup = context();
  try {
    const { pending, verified } = await createAndVerify(setup);
    assert.equal(verified.user.email, 'style.user@example.com');
    assert.match(verified.user.sellerHandle, /^@avery-stone-[a-f0-9]{10}$/);
    assert.equal(verified.session.tokenType, 'Bearer');
    assert.equal(verified.welcomeEmailSent, true);
    assert.deepEqual(verified.welcomeEmail, { status: 'sent' });
    assert.equal(setup.emailClient.welcomeCalls.length, 1);
    assert.equal(
      setup.database.prepare('SELECT email_verified_at AS at FROM accounts').get().at,
      START / 1000,
    );

    const request = {
      headers: { authorization: `Bearer ${verified.session.accessToken}` },
    };
    const actor = authenticateRequest(
      request,
      setup.config,
      setup.now() / 1000,
      setup.database,
    );
    assert.deepEqual(setup.service.getSession(actor), {
      authenticated: true,
      user: verified.user,
      expiresAt: verified.session.expiresAt,
    });
    assert.deepEqual(setup.service.logout(actor, {}), { loggedOut: true });
    assert.throws(
      () => authenticateRequest(request, setup.config, setup.now() / 1000, setup.database),
      (error) => error.code === 'invalid_token',
    );

    await assert.rejects(
      setup.service.verifyEmail(
        {
          challengeToken: pending.verification.challengeToken,
          code: latestCode(setup),
        },
        '203.0.113.8',
      ),
      (error) => error.code === 'invalid_verification_code' && error.status === 422,
    );
    assert.equal(setup.emailClient.welcomeCalls.length, 1);
    assert.equal(
      setup.database.prepare('SELECT count(*) AS count FROM account_sessions').get().count,
      1,
    );
  } finally {
    setup.close();
  }
});

test('five wrong codes exhaust the challenge without leaking which part was wrong', async () => {
  const setup = context();
  try {
    const pending = await setup.service.register(signup, '198.51.100.2');
    const failures = [];
    for (let attempt = 0; attempt < 5; attempt += 1) {
      await assert.rejects(
        setup.service.verifyEmail(
          {
            challengeToken: pending.verification.challengeToken,
            code: latestCode(setup) === '000000' ? '000001' : '000000',
          },
          `198.51.100.${attempt + 3}`,
        ),
        (error) => {
          failures.push({ status: error.status, code: error.code, message: error.message });
          return true;
        },
      );
    }
    assert.ok(failures.every((failure) => JSON.stringify(failure) === JSON.stringify(failures[0])));
    await assert.rejects(
      setup.service.verifyEmail(
        {
          challengeToken: pending.verification.challengeToken,
          code: latestCode(setup),
        },
        '198.51.100.9',
      ),
      (error) => error.code === 'invalid_verification_code',
    );
    assert.equal(
      setup.database.prepare('SELECT attempt_count AS count FROM email_verifications').get().count,
      5,
    );
    assert.equal(
      setup.database.prepare('SELECT count(*) AS count FROM account_sessions').get().count,
      0,
    );
  } finally {
    setup.close();
  }
});

test('expired codes fail and resend rotates the code while preserving the opaque challenge', async () => {
  const setup = context();
  try {
    const pending = await setup.service.register(signup, '192.0.2.10');
    const firstCode = latestCode(setup);
    setup.advance(10 * 60 * 1000 + 1000);
    await assert.rejects(
      setup.service.verifyEmail(
        { challengeToken: pending.verification.challengeToken, code: firstCode },
        '192.0.2.10',
      ),
      (error) => error.code === 'invalid_verification_code',
    );
    const resent = await setup.service.resendVerification(
      { challengeToken: pending.verification.challengeToken },
      '192.0.2.10',
    );
    const secondCode = latestCode(setup);
    assert.equal(resent.verification.challengeToken, pending.verification.challengeToken);
    assert.equal(setup.emailClient.verificationCalls.length, 2);
    await assert.rejects(
      setup.service.verifyEmail(
        { challengeToken: pending.verification.challengeToken, code: firstCode },
        '192.0.2.10',
      ),
      (error) => error.code === 'invalid_verification_code',
    );
    const verified = await setup.service.verifyEmail(
      { challengeToken: pending.verification.challengeToken, code: secondCode },
      '192.0.2.10',
    );
    assert.equal(verified.user.email, 'style.user@example.com');
  } finally {
    setup.close();
  }
});

test('resend enforces cooldown and persistent hourly rate limits', async () => {
  const setup = context({
    config: accountConfig({
      AUTH_VERIFICATION_RESEND_LIMIT_PER_HOUR: '3',
    }),
  });
  try {
    const pending = await setup.service.register(signup, '192.0.2.20');
    await assert.rejects(
      setup.service.resendVerification(
        { challengeToken: pending.verification.challengeToken },
        '192.0.2.20',
      ),
      (error) =>
        error.status === 429 &&
        error.code === 'verification_rate_limited' &&
        error.details.retryAfterSeconds > 0,
    );
    setup.advance(61_000);
    await setup.service.resendVerification(
      { challengeToken: pending.verification.challengeToken },
      '192.0.2.20',
    );
    setup.advance(61_000);
    await setup.service.resendVerification(
      { challengeToken: pending.verification.challengeToken },
      '192.0.2.20',
    );
    setup.advance(61_000);
    await assert.rejects(
      setup.service.resendVerification(
        { challengeToken: pending.verification.challengeToken },
        '192.0.2.20',
      ),
      (error) => error.status === 429 && error.code === 'verification_rate_limited',
    );
    assert.equal(setup.emailClient.verificationCalls.length, 3);
  } finally {
    setup.close();
  }
});

test('pending login is denied; a repeated signup rotates only after the same password', async () => {
  const setup = context();
  try {
    const first = await setup.service.register(signup, '192.0.2.30');
    await assert.rejects(
      setup.service.login({ email: signup.email, password: signup.password }, '192.0.2.31'),
      (error) => error.code === 'invalid_credentials',
    );
    setup.advance(61_000);
    await assert.rejects(
      setup.service.register(
        { ...signup, password: 'Different-Fit!2027' },
        '192.0.2.32',
      ),
      (error) => error.status === 409 && error.code === 'account_exists',
    );
    const restarted = await setup.service.register(signup, '192.0.2.33');
    assert.notEqual(
      restarted.verification.challengeToken,
      first.verification.challengeToken,
    );
    await assert.rejects(
      setup.service.verifyEmail(
        { challengeToken: first.verification.challengeToken, code: setup.emailClient.verificationCalls[0].code },
        '192.0.2.34',
      ),
      (error) => error.code === 'invalid_verification_code',
    );
    const verified = await setup.service.verifyEmail(
      { challengeToken: restarted.verification.challengeToken, code: latestCode(setup) },
      '192.0.2.35',
    );
    const loggedIn = await setup.service.login(
      { email: signup.email, password: signup.password },
      '192.0.2.36',
    );
    assert.equal(loggedIn.user.id, verified.user.id);
  } finally {
    setup.close();
  }
});

test('provider failure is truthful and leaves no authenticated session', async () => {
  const emailClient = failingEmailClient();
  const setup = context({ emailClient });
  try {
    await assert.rejects(
      setup.service.register(signup, '192.0.2.40'),
      (error) => error.status === 503 && error.code === 'email_provider_unavailable',
    );
    assert.equal(
      setup.database.prepare('SELECT count(*) AS count FROM accounts').get().count,
      1,
    );
    assert.equal(
      setup.database.prepare('SELECT count(*) AS count FROM account_sessions').get().count,
      0,
    );
    assert.equal(setup.emailClient.welcomeCalls.length, 0);
    setup.advance(61_000);
    emailClient.error = null;
    const recovered = await setup.service.register(signup, '192.0.2.40');
    assert.ok(recovered.verification.challengeToken);
    assert.equal(emailClient.verificationCalls.length, 2);
  } finally {
    setup.close();
  }
});

test('abandoned unverified signup expires so the address can be safely reclaimed', async () => {
  const setup = context({
    config: accountConfig({ AUTH_PENDING_ACCOUNT_TTL_SECONDS: '3600' }),
  });
  try {
    const first = await setup.service.register(signup, '192.0.2.50');
    setup.advance(60 * 60 * 1000 + 1000);
    const replacement = await setup.service.register(
      {
        name: 'New Owner',
        email: signup.email,
        password: 'Entirely-New!2028',
      },
      '192.0.2.51',
    );
    assert.notEqual(replacement.verification.challengeToken, first.verification.challengeToken);
    assert.equal(
      setup.database.prepare('SELECT count(*) AS count FROM accounts').get().count,
      1,
    );
    assert.equal(
      setup.database.prepare('SELECT display_name AS name FROM accounts').get().name,
      'New Owner',
    );
  } finally {
    setup.close();
  }
});

test('concurrent normalized signup inserts only one pending account', async () => {
  const setup = context();
  try {
    const attempts = await Promise.allSettled([
      setup.service.register(signup, '203.0.113.20'),
      setup.service.register(
        { ...signup, name: 'Second Name', email: ' STYLE.USER@EXAMPLE.COM ' },
        '203.0.113.21',
      ),
    ]);
    assert.equal(attempts.filter((result) => result.status === 'fulfilled').length, 1);
    assert.equal(attempts.filter((result) => result.status === 'rejected').length, 1);
    assert.equal(
      setup.database.prepare('SELECT count(*) AS count FROM accounts').get().count,
      1,
    );
    assert.equal(setup.emailClient.verificationCalls.length, 1);
  } finally {
    setup.close();
  }
});

test('strict validation and signup rate limits run before account side effects', async () => {
  const setup = context({
    config: accountConfig({ AUTH_SIGNUP_RATE_LIMIT_PER_HOUR: '1' }),
  });
  try {
    await assert.rejects(
      setup.service.register({ ...signup, admin: true }, '192.0.2.60'),
      (error) => error.code === 'invalid_request',
    );
    await setup.service.register(signup, '192.0.2.60');
    await assert.rejects(
      setup.service.register(
        { name: 'Second', email: 'second@example.com', password: 'Gallery-Fit!2027' },
        '192.0.2.60',
      ),
      (error) => error.status === 429 && error.code === 'auth_rate_limited',
    );
    assert.equal(
      setup.database.prepare('SELECT count(*) AS count FROM accounts').get().count,
      1,
    );
  } finally {
    setup.close();
  }
});
