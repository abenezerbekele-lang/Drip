import assert from 'node:assert/strict';
import test from 'node:test';

import { authenticateRequest } from '../src/auth.js';
import { loadConfig } from '../src/config.js';
import {
  createFirebaseAuthVerifier,
  FirebaseRestAuthVerifier,
} from '../src/firebase-auth.js';

const REST_API_KEY = 'AIzaSyDripTestOnlyKey_123456789012345678';
const NOW_SECONDS = 2_000_000_000;

function firebaseConfig(overrides = {}) {
  return loadConfig({
    NODE_ENV: 'test',
    AUTH_MODE: 'firebase',
    DATABASE_PATH: ':memory:',
    FIREBASE_PROJECT_ID: 'dripproject-24882',
    FIREBASE_CREDENTIALS_MODE: 'application-default',
    ...overrides,
  });
}

function firebaseRestConfig(overrides = {}) {
  return loadConfig({
    NODE_ENV: 'test',
    AUTH_MODE: 'firebase',
    DATABASE_PATH: ':memory:',
    FIREBASE_PROJECT_ID: 'dripproject-24882',
    FIREBASE_AUTH_VERIFIER_MODE: 'rest-api-key',
    FIREBASE_WEB_API_KEY: REST_API_KEY,
    ...overrides,
  });
}

function request(token = 'firebase-id-token') {
  return { headers: { authorization: `Bearer ${token}` } };
}

function verifiedClaims(overrides = {}) {
  return {
    uid: 'firebase-customer-123',
    sub: 'firebase-customer-123',
    email: 'customer@example.com',
    email_verified: true,
    name: 'Jordan Lee',
    exp: 2_000_000_100,
    ...overrides,
  };
}

function firebaseIdToken(overrides = {}) {
  const header = Buffer.from(
    JSON.stringify({ alg: 'RS256', kid: 'test-key' }),
  ).toString('base64url');
  const payload = Buffer.from(
    JSON.stringify({
      sub: 'firebase-customer-123',
      user_id: 'firebase-customer-123',
      aud: 'dripproject-24882',
      iss: 'https://securetoken.google.com/dripproject-24882',
      exp: NOW_SECONDS + 100,
      iat: NOW_SECONDS - 100,
      auth_time: NOW_SECONDS - 200,
      seller_handle: '@jordan.closet',
      ...overrides,
    }),
  ).toString('base64url');
  return `${header}.${payload}.test-signature`;
}

function lookupResponse(overrides = {}, init = {}) {
  return new Response(
    JSON.stringify({
      users: [
        {
          localId: 'firebase-customer-123',
          email: 'current@example.com',
          emailVerified: true,
          disabled: false,
          displayName: 'Current Firebase Name',
          validSince: String(NOW_SECONDS - 300),
          ...overrides,
        },
      ],
    }),
    {
      status: 200,
      headers: { 'Content-Type': 'application/json' },
      ...init,
    },
  );
}

test('Firebase auth configuration requires an explicit project and ADC', () => {
  assert.throws(
    () =>
      loadConfig({
        NODE_ENV: 'test',
        AUTH_MODE: 'firebase',
        DATABASE_PATH: ':memory:',
      }),
    (error) => error.code === 'invalid_configuration',
  );
  assert.throws(
    () =>
      loadConfig({
        NODE_ENV: 'test',
        AUTH_MODE: 'firebase',
        DATABASE_PATH: ':memory:',
        FIREBASE_PROJECT_ID: 'dripproject-24882',
      }),
    (error) => error.code === 'invalid_configuration',
  );

  const config = firebaseConfig();
  assert.equal(config.authMode, 'firebase');
  assert.equal(config.firebaseProjectId, 'dripproject-24882');
  assert.equal(config.firebaseCredentialsMode, 'application-default');
  assert.equal(config.firebaseAuthVerifierMode, 'application-default');
});

test('Firebase REST auth requires an explicit Web API key without ADC', () => {
  assert.throws(
    () =>
      firebaseRestConfig({
        FIREBASE_WEB_API_KEY: '',
      }),
    (error) => error.code === 'invalid_configuration',
  );
  assert.throws(
    () =>
      firebaseRestConfig({
        FIREBASE_WEB_API_KEY: 'not-a-firebase-api-key',
      }),
    (error) => error.code === 'invalid_configuration',
  );
  assert.throws(
    () =>
      firebaseRestConfig({
        FIREBASE_CREDENTIALS_MODE: 'application-default',
      }),
    (error) => error.code === 'invalid_configuration',
  );

  const config = firebaseRestConfig();
  assert.equal(config.firebaseAuthVerifierMode, 'rest-api-key');
  assert.equal(config.firebaseCredentialsMode, '');
  assert.equal(config.firebaseWebApiKey, REST_API_KEY);
});

test('Firebase Admin initializes with ADC and the configured project', async () => {
  const initialized = [];
  const deleted = [];
  const verified = [];
  const updated = [];
  const auth = {
    async listUsers(limit) {
      assert.equal(limit, 1);
      return { users: [] };
    },
    async verifyIdToken(token, checkRevoked) {
      verified.push({ token, checkRevoked });
      return verifiedClaims();
    },
    async getUser(uid) {
      return {
        uid,
        email: 'Current@Example.com',
        emailVerified: false,
        disabled: false,
      };
    },
    async updateUser(uid, properties) {
      updated.push({ uid, properties });
      return {
        uid,
        email: properties.email,
        emailVerified: properties.emailVerified,
        disabled: false,
      };
    },
  };
  const verifier = await createFirebaseAuthVerifier(firebaseConfig(), {
    sdk: {
      app: {
        applicationDefault: () => ({ kind: 'adc' }),
        initializeApp: (options, name) => {
          initialized.push({ options, name });
          return { name };
        },
        deleteApp: async (app) => deleted.push(app),
      },
      auth: {
        getAuth: () => auth,
      },
    },
  });

  assert.equal(initialized.length, 1);
  assert.equal(initialized[0].options.projectId, 'dripproject-24882');
  assert.deepEqual(initialized[0].options.credential, { kind: 'adc' });
  await verifier.verifyIdToken('token-to-check', true);
  assert.deepEqual(verified, [
    { token: 'token-to-check', checkRevoked: true },
  ]);
  const current = await verifier.getUserForEmailVerification(
    'firebase-customer-123',
  );
  assert.equal(current.email, 'Current@Example.com');
  const marked = await verifier.markEmailVerified(
    'firebase-customer-123',
    'current@example.com',
  );
  assert.equal(marked.emailVerified, true);
  assert.deepEqual(updated, [
    {
      uid: 'firebase-customer-123',
      properties: {
        email: 'current@example.com',
        emailVerified: true,
      },
    },
  ]);
  await assert.rejects(
    () =>
      verifier.markEmailVerified(
        'firebase-customer-123',
        'different@example.com',
      ),
    (error) =>
      error.status === 409 &&
      error.code === 'verification_email_changed',
  );
  assert.equal(updated.length, 1);
  await verifier.close();
  await verifier.close();
  assert.equal(deleted.length, 1);
});

test('Firebase Admin startup fails closed when ADC cannot read Auth users', async () => {
  const deleted = [];
  await assert.rejects(
    () =>
      createFirebaseAuthVerifier(firebaseConfig(), {
        sdk: {
          app: {
            applicationDefault: () => ({ kind: 'adc' }),
            initializeApp: () => ({ name: 'unready-auth-app' }),
            deleteApp: async (app) => deleted.push(app),
          },
          auth: {
            getAuth: () => ({
              async listUsers() {
                throw new Error('permission denied');
              },
              async verifyIdToken() {
                throw new Error('must not be called');
              },
            }),
          },
        },
      }),
    (error) =>
      error.status === 503 &&
      error.code === 'authentication_unavailable' &&
      error.retryable === true,
  );
  assert.equal(deleted.length, 1);
});

test('Firebase REST verifier uses accounts:lookup before trusting token claims', async () => {
  const calls = [];
  const token = firebaseIdToken();
  const verifier = await createFirebaseAuthVerifier(firebaseRestConfig(), {
    fetchImpl: async (url, options) => {
      calls.push({ url, options });
      return lookupResponse();
    },
    now: () => NOW_SECONDS * 1000,
  });

  const claims = await verifier.verifyIdToken(token, true);
  assert.deepEqual(claims, {
    uid: 'firebase-customer-123',
    sub: 'firebase-customer-123',
    email: 'current@example.com',
    email_verified: true,
    exp: NOW_SECONDS + 100,
    name: 'Current Firebase Name',
    seller_handle: '@jordan.closet',
  });
  assert.equal(calls.length, 1);
  assert.equal(calls[0].url.origin, 'https://identitytoolkit.googleapis.com');
  assert.equal(calls[0].url.pathname, '/v1/accounts:lookup');
  assert.equal(calls[0].url.searchParams.get('key'), REST_API_KEY);
  assert.equal(calls[0].options.method, 'POST');
  assert.deepEqual(JSON.parse(calls[0].options.body), { idToken: token });
  assert.equal(calls[0].options.redirect, 'error');

  let malformedLookupCalls = 0;
  const malformedTokenVerifier = new FirebaseRestAuthVerifier({
    projectId: 'dripproject-24882',
    apiKey: REST_API_KEY,
    fetchImpl: async () => {
      malformedLookupCalls += 1;
      return lookupResponse();
    },
    now: () => NOW_SECONDS * 1000,
  });
  await assert.rejects(
    () => malformedTokenVerifier.verifyIdToken('not-a-jwt', true),
    (error) => error.status === 401 && error.code === 'invalid_token',
  );
  assert.equal(malformedLookupCalls, 1);
});

test('Firebase REST verifier enforces current account state and revocation', async () => {
  async function rejected({ tokenOverrides, accountOverrides }, expectedStatus) {
    const verifier = new FirebaseRestAuthVerifier({
      projectId: 'dripproject-24882',
      apiKey: REST_API_KEY,
      fetchImpl: async () => lookupResponse(accountOverrides),
      now: () => NOW_SECONDS * 1000,
    });
    await assert.rejects(
      () => verifier.verifyIdToken(firebaseIdToken(tokenOverrides), true),
      (error) =>
        error.status === expectedStatus &&
        (expectedStatus === 401
          ? error.code === 'invalid_token'
          : error.code === 'authentication_unavailable'),
    );
  }

  await rejected(
    { tokenOverrides: { exp: NOW_SECONDS }, accountOverrides: {} },
    401,
  );
  await rejected(
    {
      tokenOverrides: { auth_time: NOW_SECONDS - 301 },
      accountOverrides: { validSince: String(NOW_SECONDS - 300) },
    },
    401,
  );
  await rejected(
    { tokenOverrides: {}, accountOverrides: { disabled: true } },
    401,
  );
  await rejected(
    {
      tokenOverrides: { sub: 'different-user' },
      accountOverrides: {},
    },
    401,
  );
  await rejected(
    {
      tokenOverrides: {},
      accountOverrides: { validSince: 'not-a-timestamp' },
    },
    503,
  );
  await rejected(
    {
      tokenOverrides: {},
      accountOverrides: { emailVerified: 'true' },
    },
    503,
  );
});

test('Firebase REST verifier preserves the verified-email authorization gate', async () => {
  const verifier = new FirebaseRestAuthVerifier({
    projectId: 'dripproject-24882',
    apiKey: REST_API_KEY,
    fetchImpl: async () => lookupResponse({ emailVerified: false }),
    now: () => NOW_SECONDS * 1000,
  });

  await assert.rejects(
    () =>
      authenticateRequest(
        request(firebaseIdToken()),
        firebaseRestConfig(),
        NOW_SECONDS,
        null,
        verifier,
      ),
    (error) =>
      error.status === 403 && error.code === 'email_verification_required',
  );
});

test('Firebase REST verifier maps token failures separately from provider failures', async () => {
  async function verifyWithResponse(status, payload) {
    const verifier = new FirebaseRestAuthVerifier({
      projectId: 'dripproject-24882',
      apiKey: REST_API_KEY,
      fetchImpl: async () =>
        new Response(JSON.stringify(payload), {
          status,
          headers: { 'Content-Type': 'application/json' },
        }),
      now: () => NOW_SECONDS * 1000,
    });
    return verifier.verifyIdToken(firebaseIdToken(), true);
  }

  await assert.rejects(
    () =>
      verifyWithResponse(400, {
        error: { message: 'INVALID_ID_TOKEN' },
      }),
    (error) => error.status === 401 && error.code === 'invalid_token',
  );
  await assert.rejects(
    () =>
      verifyWithResponse(400, {
        error: { message: 'API_KEY_INVALID' },
      }),
    (error) =>
      error.status === 503 &&
      error.code === 'authentication_unavailable' &&
      error.retryable === true,
  );
  await assert.rejects(
    () =>
      verifyWithResponse(503, {
        error: { message: 'BACKEND_ERROR' },
      }),
    (error) =>
      error.status === 503 && error.code === 'authentication_unavailable',
  );
});

test('Firebase REST verifier bounds response size and total lookup time', async () => {
  const oversized = new FirebaseRestAuthVerifier({
    projectId: 'dripproject-24882',
    apiKey: REST_API_KEY,
    fetchImpl: async () =>
      new Response(JSON.stringify({ users: [], padding: 'x'.repeat(256) })),
    responseLimitBytes: 64,
    now: () => NOW_SECONDS * 1000,
  });
  await assert.rejects(
    () => oversized.verifyIdToken(firebaseIdToken(), true),
    (error) =>
      error.status === 503 && error.code === 'authentication_unavailable',
  );

  const timedOut = new FirebaseRestAuthVerifier({
    projectId: 'dripproject-24882',
    apiKey: REST_API_KEY,
    fetchImpl: async () => new Promise(() => {}),
    timeoutMs: 5,
    now: () => NOW_SECONDS * 1000,
  });
  await assert.rejects(
    () => timedOut.verifyIdToken(firebaseIdToken(), true),
    (error) =>
      error.status === 503 &&
      error.code === 'authentication_unavailable' &&
      error.retryable === true,
  );
});

test('Firebase bearer tokens produce verified, stable server actors', async () => {
  const calls = [];
  const actor = await authenticateRequest(
    request(),
    firebaseConfig(),
    2_000_000_000,
    null,
    {
      async verifyIdToken(token, checkRevoked) {
        calls.push({ token, checkRevoked });
        return verifiedClaims({ seller_handle: '@jordan.closet' });
      },
    },
  );

  assert.deepEqual(actor, {
    id: 'firebase-customer-123',
    sellerHandle: '@jordan.closet',
    authProvider: 'firebase',
    sessionExpiresAt: 2_000_000_100,
    email: 'customer@example.com',
    displayName: 'Jordan Lee',
  });
  assert.deepEqual(calls, [
    { token: 'firebase-id-token', checkRevoked: true },
  ]);
});

test('Firebase authentication fails closed for unsafe account states', async () => {
  const config = firebaseConfig();

  await assert.rejects(
    () =>
      authenticateRequest(request(), config, 2_000_000_000, null, {
        async verifyIdToken() {
          return verifiedClaims({ email_verified: false });
        },
      }),
    (error) =>
      error.status === 403 && error.code === 'email_verification_required',
  );
  await assert.rejects(
    () =>
      authenticateRequest(request(), config, 2_000_000_000, null, {
        async verifyIdToken() {
          const error = new Error('expired');
          error.code = 'auth/id-token-expired';
          throw error;
        },
      }),
    (error) => error.status === 401 && error.code === 'invalid_token',
  );
  await assert.rejects(
    () =>
      authenticateRequest(request(), config, 2_000_000_000, null, {
        async verifyIdToken() {
          const error = new Error('credential outage');
          error.code = 'app/invalid-credential';
          throw error;
        },
      }),
    (error) =>
      error.status === 503 &&
      error.code === 'authentication_unavailable' &&
      error.retryable === true,
  );
  await assert.rejects(
    () => authenticateRequest(request(), config),
    (error) =>
      error.status === 503 && error.code === 'authentication_unavailable',
  );
});
