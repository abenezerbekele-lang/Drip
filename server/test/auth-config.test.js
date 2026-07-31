import assert from 'node:assert/strict';
import { createHmac } from 'node:crypto';
import test from 'node:test';

import { authenticateRequest } from '../src/auth.js';
import { loadConfig } from '../src/config.js';

function token(secret, payload) {
  const header = Buffer.from(JSON.stringify({ alg: 'HS256', typ: 'JWT' })).toString(
    'base64url',
  );
  const claims = Buffer.from(JSON.stringify(payload)).toString('base64url');
  const signature = createHmac('sha256', secret)
    .update(`${header}.${claims}`)
    .digest('base64url');
  return `${header}.${claims}.${signature}`;
}

test('production-style JWT auth verifies signature, issuer, audience, and time', () => {
  const secret = 'a-secure-test-secret-that-is-longer-than-32-bytes';
  const config = loadConfig({
    NODE_ENV: 'test',
    AUTH_MODE: 'jwt',
    JWT_HS256_SECRET: secret,
    JWT_ISSUER: 'https://identity.drip.test',
    JWT_AUDIENCE: 'drip-checkout',
    DATABASE_PATH: ':memory:',
  });
  const accessToken = token(secret, {
    sub: 'buyer-123',
    seller_handle: '@buyercloset',
    iss: config.jwtIssuer,
    aud: config.jwtAudience,
    exp: 2_000_000_100,
    jti: 'external-identity-token-123',
  });
  assert.deepEqual(
    authenticateRequest(
      { headers: { authorization: `Bearer ${accessToken}` } },
      config,
      2_000_000_000,
    ),
    { id: 'buyer-123', sellerHandle: '@buyercloset' },
  );
  assert.throws(
    () =>
      authenticateRequest(
        { headers: { authorization: `Bearer ${accessToken}tampered` } },
        config,
        2_000_000_000,
      ),
    (error) => error.code === 'invalid_token',
  );
  assert.throws(
    () =>
      authenticateRequest(
        { headers: { authorization: `Bearer ${accessToken}` } },
        config,
        2_000_000_200,
      ),
    (error) => error.code === 'invalid_token',
  );
});

test('production configuration fails closed without payment and auth secrets', () => {
  assert.throws(
    () => loadConfig({ NODE_ENV: 'production' }),
    (error) => error.code === 'invalid_configuration',
  );
  assert.throws(
    () =>
      loadConfig({
        NODE_ENV: 'test',
        AUTH_MODE: 'development',
        DATABASE_PATH: ':memory:',
        CORS_ALLOWED_ORIGINS: '*',
      }),
    (error) => error.code === 'invalid_configuration',
  );
  assert.throws(
    () =>
      loadConfig({
        NODE_ENV: 'development',
        AUTH_MODE: 'development',
        DATABASE_PATH: ':memory:',
        STRIPE_SECRET_KEY: 'sk_live_must_not_run_in_development',
        STRIPE_WEBHOOK_SECRET: 'whsec_live_mismatch',
      }),
    (error) => error.code === 'invalid_configuration',
  );
});

test('public staging keeps production hardening while allowing Stripe sandbox checkout without Connect', () => {
  const staging = loadConfig({
    NODE_ENV: 'production',
    DEPLOYMENT_STAGE: 'staging',
    AUTH_MODE: 'firebase',
    ACCOUNT_AUTH_ENABLED: 'false',
    DATABASE_PATH: '/var/lib/drip/drip.sqlite',
    MARKETPLACE_DATABASE_PROVIDER: 'sqlite',
    FIREBASE_PROJECT_ID: 'dripproject-24882',
    FIREBASE_AUTH_VERIFIER_MODE: 'application-default',
    FIREBASE_CREDENTIALS_MODE: 'application-default',
    STRIPE_SECRET_KEY: 'rk_test_checkout_permissions_only',
    STRIPE_WEBHOOK_SECRET: 'whsec_staging_checkout',
    STRIPE_CONNECT_ENABLED: 'false',
    CHECKOUT_SUCCESS_URL:
      'https://api-staging.drip.example/checkout/success?session_id={CHECKOUT_SESSION_ID}',
    CHECKOUT_CANCEL_URL:
      'https://api-staging.drip.example/checkout/cancel',
  });
  assert.equal(staging.deploymentStage, 'staging');
  assert.equal(staging.publicDeployment, true);
  assert.equal(staging.production, false);
  assert.equal(staging.paymentsConfigured, true);
  assert.equal(staging.stripeLiveMode, false);
  assert.equal(staging.stripeConnectConfigured, false);
  assert.equal(staging.requireConnectPayouts, false);

  for (const unsafe of [
    { NODE_ENV: 'development' },
    { AUTH_MODE: 'development' },
    { DATABASE_PATH: ':memory:' },
    { STRIPE_SECRET_KEY: 'sk_live_not_for_staging' },
    { CHECKOUT_CANCEL_URL: 'http://api-staging.drip.example/checkout/cancel' },
  ]) {
    assert.throws(
      () => loadConfig({
        NODE_ENV: 'production',
        DEPLOYMENT_STAGE: 'staging',
        AUTH_MODE: 'firebase',
        ACCOUNT_AUTH_ENABLED: 'false',
        DATABASE_PATH: '/var/lib/drip/drip.sqlite',
        MARKETPLACE_DATABASE_PROVIDER: 'sqlite',
        FIREBASE_PROJECT_ID: 'dripproject-24882',
        FIREBASE_AUTH_VERIFIER_MODE: 'application-default',
        FIREBASE_CREDENTIALS_MODE: 'application-default',
        CHECKOUT_SUCCESS_URL:
          'https://api-staging.drip.example/checkout/success?session_id={CHECKOUT_SESSION_ID}',
        CHECKOUT_CANCEL_URL:
          'https://api-staging.drip.example/checkout/cancel',
        ...unsafe,
      }),
      (error) => error.code === 'invalid_configuration',
    );
  }
});

test('Firestore marketplace selection requires an explicit project and ADC mode', () => {
  const base = {
    NODE_ENV: 'test',
    AUTH_MODE: 'development',
    DATABASE_PATH: ':memory:',
    MARKETPLACE_DATABASE_PROVIDER: 'firestore',
  };
  assert.throws(
    () => loadConfig(base),
    (error) => error.code === 'invalid_configuration',
  );
  assert.throws(
    () =>
      loadConfig({
        ...base,
        FIREBASE_PROJECT_ID: 'drip-marketplace-test',
      }),
    (error) => error.code === 'invalid_configuration',
  );
  const config = loadConfig({
    ...base,
    FIREBASE_PROJECT_ID: 'drip-marketplace-test',
    FIREBASE_CREDENTIALS_MODE: 'application-default',
  });
  assert.equal(config.marketplaceDatabaseProvider, 'firestore');
  assert.equal(config.firebaseProjectId, 'drip-marketplace-test');

  assert.throws(
    () =>
      loadConfig({
        NODE_ENV: 'test',
        AUTH_MODE: 'development',
        DATABASE_PATH: ':memory:',
        FIREBASE_CREDENTIALS_MODE: 'application-default',
      }),
    (error) => error.code === 'invalid_configuration',
  );
});

test('Stripe accepts least-privilege sandbox server keys and rejects live keys in development', () => {
  const restricted = loadConfig({
    NODE_ENV: 'development',
    AUTH_MODE: 'development',
    DATABASE_PATH: ':memory:',
    STRIPE_SECRET_KEY: 'rk_test_checkout_permissions_only',
    STRIPE_WEBHOOK_SECRET: 'whsec_restricted_key_test',
  });
  assert.equal(restricted.paymentsConfigured, true);
  assert.equal(restricted.stripeLiveMode, false);

  assert.throws(
    () =>
      loadConfig({
        NODE_ENV: 'development',
        AUTH_MODE: 'development',
        DATABASE_PATH: ':memory:',
        STRIPE_SECRET_KEY: 'rk_live_must_not_run_in_development',
        STRIPE_WEBHOOK_SECRET: 'whsec_live_restricted_mismatch',
      }),
    (error) => error.code === 'invalid_configuration',
  );
  assert.throws(
    () =>
      loadConfig({
        NODE_ENV: 'development',
        AUTH_MODE: 'development',
        DATABASE_PATH: ':memory:',
        STRIPE_SECRET_KEY: 'pk_test_publishable_is_not_a_server_key',
        STRIPE_WEBHOOK_SECRET: 'whsec_publishable_key_mismatch',
      }),
    (error) => error.code === 'invalid_configuration',
  );

  const productionRestricted = loadConfig({
    NODE_ENV: 'production',
    AUTH_MODE: 'jwt',
    JWT_HS256_SECRET: 'production-jwt-secret-longer-than-thirty-two-bytes',
    JWT_ISSUER: 'https://identity.drip.example',
    JWT_AUDIENCE: 'drip-app',
    DATABASE_PATH: './data/production.sqlite',
    ACCOUNT_AUTH_ENABLED: 'true',
    AUTH_RATE_LIMIT_SECRET:
      'production-rate-limit-secret-longer-than-thirty-two-bytes',
    EMAIL_PROVIDER: 'resend',
    RESEND_API_KEY: 're_production_config_test',
    WELCOME_EMAIL_FROM: 'Drip <welcome@drip.example>',
    STRIPE_SECRET_KEY: 'rk_live_checkout_permissions_only',
    STRIPE_WEBHOOK_SECRET: 'whsec_production_checkout',
    STRIPE_CONNECT_WEBHOOK_SECRET: 'whsec_production_connect',
    CONNECT_ONBOARDING_RETURN_URL:
      'https://app.drip.example/connect/return',
    CONNECT_ONBOARDING_REFRESH_URL:
      'https://api.drip.example/connect/onboarding/refresh',
    CHECKOUT_SUCCESS_URL:
      'https://app.drip.example/checkout/return?session_id={CHECKOUT_SESSION_ID}',
    CHECKOUT_CANCEL_URL: 'https://app.drip.example/cart',
  });
  assert.equal(productionRestricted.paymentsConfigured, true);
  assert.equal(productionRestricted.stripeLiveMode, true);
});

test('Stripe readiness rejects placeholder credentials and malformed shipping countries', () => {
  const base = {
    NODE_ENV: 'development',
    AUTH_MODE: 'development',
    DATABASE_PATH: ':memory:',
  };
  assert.throws(
    () =>
      loadConfig({
        ...base,
        STRIPE_SECRET_KEY: 'sk_test_',
        STRIPE_WEBHOOK_SECRET: 'whsec_checkout_test',
      }),
    (error) => error.code === 'invalid_configuration',
  );
  assert.throws(
    () =>
      loadConfig({
        ...base,
        STRIPE_SECRET_KEY: 'sk_test_checkout_test',
        STRIPE_WEBHOOK_SECRET: 'whsec_',
      }),
    (error) => error.code === 'invalid_configuration',
  );
  assert.throws(
    () =>
      loadConfig({
        ...base,
        CHECKOUT_ALLOWED_COUNTRIES: 'US,',
      }),
    (error) => error.code === 'invalid_configuration',
  );
  assert.throws(
    () =>
      loadConfig({
        ...base,
        CHECKOUT_ALLOWED_COUNTRIES: 'US,USA',
      }),
    (error) => error.code === 'invalid_configuration',
  );

  const configured = loadConfig({
    ...base,
    CHECKOUT_ALLOWED_COUNTRIES: 'us, CA,US',
  });
  assert.deepEqual(configured.checkoutAllowedCountries, ['US', 'CA']);
});

test('Stripe Connect configuration requires separate secrets and static HTTPS redirects', () => {
  const base = {
    NODE_ENV: 'test',
    AUTH_MODE: 'jwt',
    JWT_HS256_SECRET: 'connect-config-secret-longer-than-thirty-two-bytes',
    JWT_ISSUER: 'https://identity.drip.test',
    JWT_AUDIENCE: 'drip-app',
    DATABASE_PATH: ':memory:',
    ACCOUNT_AUTH_ENABLED: 'true',
    EMAIL_PROVIDER: 'resend',
    RESEND_API_KEY: 're_test_connect_config',
    WELCOME_EMAIL_FROM: 'Drip <welcome@drip.test>',
    STRIPE_SECRET_KEY: 'sk_test_connect_config',
    STRIPE_WEBHOOK_SECRET: 'whsec_checkout_config',
    STRIPE_CONNECT_ENABLED: 'true',
  };
  assert.throws(
    () => loadConfig(base),
    (error) => error.code === 'invalid_configuration',
  );
  assert.throws(
    () =>
      loadConfig({
        ...base,
        STRIPE_CONNECT_WEBHOOK_SECRET: 'whsec_connect_config',
        CONNECT_ONBOARDING_RETURN_URL: 'http://localhost/connect/return',
        CONNECT_ONBOARDING_REFRESH_URL:
          'https://api.drip.test/connect/onboarding/refresh',
      }),
    (error) => error.code === 'invalid_configuration',
  );
  const configured = loadConfig({
    ...base,
    STRIPE_CONNECT_WEBHOOK_SECRET: 'whsec_connect_config',
    CONNECT_ONBOARDING_RETURN_URL: 'https://app.drip.test/connect/return',
    CONNECT_ONBOARDING_REFRESH_URL:
      'https://api.drip.test/connect/onboarding/refresh',
  });
  assert.equal(configured.stripeConnectConfigured, true);
  assert.equal(configured.stripeLiveMode, false);
});

test('AI configuration is explicit, secret-backed, and bounded', () => {
  const disabled = loadConfig({
    NODE_ENV: 'test',
    AUTH_MODE: 'development',
    DATABASE_PATH: ':memory:',
  });
  assert.equal(disabled.aiConfigured, false);
  assert.equal(disabled.openaiModel, 'gpt-5.6-terra');

  assert.throws(
    () =>
      loadConfig({
        NODE_ENV: 'test',
        AUTH_MODE: 'development',
        DATABASE_PATH: ':memory:',
        AI_ENABLED: 'true',
      }),
    (error) => error.code === 'invalid_configuration',
  );
  assert.throws(
    () =>
      loadConfig({
        NODE_ENV: 'test',
        AUTH_MODE: 'development',
        DATABASE_PATH: ':memory:',
        AI_RATE_LIMIT_PER_MINUTE: '20',
        AI_RATE_LIMIT_PER_DAY: '10',
      }),
    (error) => error.code === 'invalid_configuration',
  );

  const enabled = loadConfig({
    NODE_ENV: 'test',
    AUTH_MODE: 'development',
    DATABASE_PATH: ':memory:',
    AI_ENABLED: 'true',
    OPENAI_API_KEY: 'sk-test-configured',
    OPENAI_MODEL: 'gpt-5.6-terra',
  });
  assert.equal(enabled.aiConfigured, true);
  assert.equal(enabled.openaiApiKey, 'sk-test-configured');
});

test('account auth requires JWT sessions and a real server email provider', () => {
  const base = {
    NODE_ENV: 'test',
    AUTH_MODE: 'jwt',
    JWT_HS256_SECRET: 'account-config-secret-longer-than-thirty-two-bytes',
    JWT_ISSUER: 'https://identity.drip.test',
    JWT_AUDIENCE: 'drip-app',
    DATABASE_PATH: ':memory:',
    ACCOUNT_AUTH_ENABLED: 'true',
  };
  assert.throws(
    () => loadConfig(base),
    (error) => error.code === 'invalid_configuration',
  );
  assert.throws(
    () =>
      loadConfig({
        ...base,
        EMAIL_PROVIDER: 'resend',
        RESEND_API_KEY: 'not-a-resend-key',
        WELCOME_EMAIL_FROM: 'Drip <welcome@drip.test>',
      }),
    (error) => error.code === 'invalid_configuration',
  );
  assert.throws(
    () =>
      loadConfig({
        ...base,
        EMAIL_PROVIDER: 'resend',
        RESEND_API_KEY: 're_test_configured',
        WELCOME_EMAIL_FROM: 'bad\nheader@example.com',
      }),
    (error) => error.code === 'invalid_configuration',
  );

  const configured = loadConfig({
    ...base,
    EMAIL_PROVIDER: 'resend',
    RESEND_API_KEY: 're_test_configured',
    WELCOME_EMAIL_FROM: 'Drip <welcome@drip.test>',
    AUTH_SESSION_TTL_SECONDS: '3600',
    AUTH_SIGNUP_RATE_LIMIT_PER_HOUR: '4',
    AUTH_LOGIN_RATE_LIMIT_PER_15_MINUTES: '8',
    AUTH_VERIFICATION_CODE_TTL_SECONDS: '900',
    AUTH_VERIFICATION_RESEND_COOLDOWN_SECONDS: '90',
    AUTH_VERIFICATION_RESEND_LIMIT_PER_HOUR: '4',
    AUTH_VERIFICATION_ATTEMPT_RATE_LIMIT_PER_15_MINUTES: '12',
    AUTH_PENDING_ACCOUNT_TTL_SECONDS: '7200',
  });
  assert.equal(configured.accountAuthEnabled, true);
  assert.equal(configured.emailConfigured, true);
  assert.equal(configured.authSessionTtlSeconds, 3600);
  assert.equal(configured.authSignupRateLimitPerHour, 4);
  assert.equal(configured.authLoginRateLimitPer15Minutes, 8);
  assert.equal(configured.authVerificationCodeTtlSeconds, 900);
  assert.equal(configured.authVerificationResendCooldownSeconds, 90);
  assert.equal(configured.authVerificationResendLimitPerHour, 4);
  assert.equal(configured.authVerificationAttemptRateLimitPer15Minutes, 12);
  assert.equal(configured.authPendingAccountTtlSeconds, 7200);
  assert.equal(configured.authRateLimitSecret, base.JWT_HS256_SECRET);
});

test('Firebase email codes are optional and fail closed without every server capability', () => {
  const base = {
    NODE_ENV: 'test',
    AUTH_MODE: 'firebase',
    DATABASE_PATH: ':memory:',
    FIREBASE_PROJECT_ID: 'dripproject-24882',
    FIREBASE_CREDENTIALS_MODE: 'application-default',
    FIREBASE_EMAIL_CODE_ENABLED: 'true',
  };
  assert.throws(
    () => loadConfig(base),
    (error) => error.code === 'invalid_configuration',
  );
  assert.throws(
    () =>
      loadConfig({
        ...base,
        EMAIL_PROVIDER: 'resend',
        RESEND_API_KEY: 're_firebase_code_config',
        WELCOME_EMAIL_FROM: 'Drip <accounts@drip.test>',
        FIREBASE_EMAIL_CODE_SECRET: 'too-short',
      }),
    (error) => error.code === 'invalid_configuration',
  );
  assert.throws(
    () =>
      loadConfig({
        ...base,
        FIREBASE_CREDENTIALS_MODE: '',
        FIREBASE_AUTH_VERIFIER_MODE: 'rest-api-key',
        FIREBASE_WEB_API_KEY:
          'AIzaSyDripTestOnlyKey_123456789012345678',
        EMAIL_PROVIDER: 'resend',
        RESEND_API_KEY: 're_firebase_code_config',
        WELCOME_EMAIL_FROM: 'Drip <accounts@drip.test>',
        FIREBASE_EMAIL_CODE_SECRET:
          'firebase-code-config-secret-longer-than-32-bytes',
      }),
    (error) => error.code === 'invalid_configuration',
  );

  const configured = loadConfig({
    ...base,
    EMAIL_PROVIDER: 'resend',
    RESEND_API_KEY: 're_firebase_code_config',
    WELCOME_EMAIL_FROM: 'Drip <accounts@drip.test>',
    FIREBASE_EMAIL_CODE_SECRET:
      'firebase-code-config-secret-longer-than-32-bytes',
    FIREBASE_EMAIL_CODE_TTL_SECONDS: '900',
    FIREBASE_EMAIL_CODE_RESEND_COOLDOWN_SECONDS: '90',
    FIREBASE_EMAIL_CODE_RESEND_LIMIT_PER_HOUR: '4',
    FIREBASE_EMAIL_CODE_IP_REQUEST_LIMIT_PER_HOUR: '12',
    FIREBASE_EMAIL_CODE_ATTEMPT_LIMIT_PER_15_MINUTES: '15',
    FIREBASE_EMAIL_CODE_MAX_ATTEMPTS: '4',
  });
  assert.equal(configured.firebaseEmailCodeConfigured, true);
  assert.equal(configured.firebaseEmailCodeTtlSeconds, 900);
  assert.equal(configured.firebaseEmailCodeResendCooldownSeconds, 90);
  assert.equal(configured.firebaseEmailCodeResendLimitPerHour, 4);
  assert.equal(configured.firebaseEmailCodeIpRequestLimitPerHour, 12);
  assert.equal(configured.firebaseEmailCodeAttemptLimitPer15Minutes, 15);
  assert.equal(configured.firebaseEmailCodeMaxAttempts, 4);

  const disabled = loadConfig({
    NODE_ENV: 'test',
    AUTH_MODE: 'firebase',
    DATABASE_PATH: ':memory:',
    FIREBASE_PROJECT_ID: 'dripproject-24882',
    FIREBASE_CREDENTIALS_MODE: 'application-default',
  });
  assert.equal(disabled.firebaseEmailCodeConfigured, false);
});
