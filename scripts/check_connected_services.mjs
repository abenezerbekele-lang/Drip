import { existsSync } from 'node:fs';
import { readFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.resolve(
  path.dirname(fileURLToPath(import.meta.url)),
  '..',
);
const envPath = path.join(root, 'server', '.env');
const configOnly = process.argv.includes('--config-only');

function parseEnv(source) {
  const values = new Map();
  for (const rawLine of source.split(/\r?\n/)) {
    const line = rawLine.trim();
    if (!line || line.startsWith('#')) continue;
    const separator = line.indexOf('=');
    if (separator < 1) continue;
    const key = line.slice(0, separator).trim();
    let value = line.slice(separator + 1).trim();
    if (
      (value.startsWith('"') && value.endsWith('"')) ||
      (value.startsWith("'") && value.endsWith("'"))
    ) {
      value = value.slice(1, -1);
    }
    values.set(key, value);
  }
  return values;
}

function fail(message) {
  console.error(`✗ ${message}`);
  process.exitCode = 1;
}

if (!existsSync(envPath)) {
  fail('server/.env is missing. Copy server/.env.example and add owner credentials.');
} else {
  const values = parseEnv(await readFile(envPath, 'utf8'));

  if (values.get('AUTH_MODE') !== 'firebase') {
    fail('AUTH_MODE must be firebase for the Flutter account flow.');
  }
  if (values.get('FIREBASE_PROJECT_ID') !== 'dripproject-24882') {
    fail('FIREBASE_PROJECT_ID must be dripproject-24882.');
  }
  const firebaseVerifierMode =
    values.get('FIREBASE_AUTH_VERIFIER_MODE') || 'application-default';
  if (firebaseVerifierMode === 'application-default') {
    if (values.get('FIREBASE_CREDENTIALS_MODE') !== 'application-default') {
      fail(
        'Firebase Admin verification requires FIREBASE_CREDENTIALS_MODE=application-default.',
      );
    }
  } else if (firebaseVerifierMode === 'rest-api-key') {
    if (
      !/^AIza[A-Za-z0-9_-]{20,100}$/.test(
        values.get('FIREBASE_WEB_API_KEY') || '',
      )
    ) {
      fail('Firebase REST verification requires the project Web API key.');
    }
  } else {
    fail(
      'FIREBASE_AUTH_VERIFIER_MODE must be application-default or rest-api-key.',
    );
  }
  if (values.get('ACCOUNT_AUTH_ENABLED') !== 'false') {
    fail('ACCOUNT_AUTH_ENABLED must be false because Firebase owns sign-up.');
  }

  if (!/^(?:sk|rk)_test_/.test(values.get('STRIPE_SECRET_KEY') || '')) {
    fail('A Stripe test server key is required.');
  }
  if (!(values.get('STRIPE_WEBHOOK_SECRET') || '').startsWith('whsec_')) {
    fail('A Stripe webhook signing secret is required.');
  }

  if (process.exitCode !== 1) {
    console.log('✓ Firebase account and Stripe test configuration are present.');
  }
}

if (!configOnly && process.exitCode !== 1) {
  try {
    const response = await fetch('http://127.0.0.1:4242/healthz', {
      signal: AbortSignal.timeout(2_500),
      headers: { Accept: 'application/json' },
    });
    const health = await response.json();
    if (
      !response.ok ||
      health.status !== 'ok' ||
      health.service !== 'drip-checkout'
    ) {
      fail('The Drip API returned an invalid health response.');
    } else {
      if (health.accountAuthConfigured !== true) {
        fail('The API is online but Firebase token verification is not ready.');
      }
      if (health.authProvider !== 'firebase') {
        fail('The API is online but is not using Firebase authentication.');
      }
      if (health.paymentsConfigured !== true) {
        fail('The API is online but Stripe Checkout is not ready.');
      }
      if (process.exitCode !== 1) {
        console.log('✓ Drip API, accounts, and Stripe Checkout are ready.');
      }
    }
  } catch {
    fail('The Drip API is not reachable at http://127.0.0.1:4242.');
  }
}
