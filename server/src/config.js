import path from 'node:path';

import { AppError } from './errors.js';

function integer(value, fallback, name, { min, max }) {
  const parsed = value == null || value === '' ? fallback : Number(value);
  if (!Number.isSafeInteger(parsed) || parsed < min || parsed > max) {
    throw new AppError(500, 'invalid_configuration', `${name} is invalid.`);
  }
  return parsed;
}

function boolean(value, fallback = false) {
  if (value == null || value === '') return fallback;
  if (value === 'true') return true;
  if (value === 'false') return false;
  throw new AppError(
    500,
    'invalid_configuration',
    'Boolean environment values must be true or false.',
  );
}

function url(value, name, { production, checkoutPlaceholder = false }) {
  let parsed;
  try {
    parsed = new URL(value);
  } catch {
    throw new AppError(500, 'invalid_configuration', `${name} must be a URL.`);
  }
  if (production && parsed.protocol !== 'https:') {
    throw new AppError(
      500,
      'invalid_configuration',
      `${name} must use HTTPS in production.`,
    );
  }
  if (
    checkoutPlaceholder &&
    !value.includes('{CHECKOUT_SESSION_ID}')
  ) {
    throw new AppError(
      500,
      'invalid_configuration',
      `${name} must include {CHECKOUT_SESSION_ID}.`,
    );
  }
  return value;
}

function origins(value) {
  if (!value) return new Set();
  const result = new Set();
  for (const candidate of value.split(',').map((item) => item.trim())) {
    if (!candidate) continue;
    if (candidate === '*') {
      throw new AppError(
        500,
        'invalid_configuration',
        'CORS_ALLOWED_ORIGINS cannot contain a wildcard.',
      );
    }
    const parsed = new URL(candidate);
    if (parsed.origin !== candidate || parsed.pathname !== '/') {
      throw new AppError(
        500,
        'invalid_configuration',
        'CORS origins must be exact scheme/host/port origins.',
      );
    }
    result.add(candidate);
  }
  return result;
}

function checkoutCountries(value) {
  const countries = value
    .split(',')
    .map((country) => country.trim().toUpperCase());
  if (
    countries.length === 0 ||
    countries.some((country) => !/^[A-Z]{2}$/.test(country))
  ) {
    throw new AppError(
      500,
      'invalid_configuration',
      'CHECKOUT_ALLOWED_COUNTRIES must contain two-letter country codes.',
    );
  }
  return Object.freeze([...new Set(countries)]);
}

function identifier(value, fallback, name) {
  const result = value || fallback;
  if (!/^[A-Za-z0-9][A-Za-z0-9._:-]{1,79}$/.test(result)) {
    throw new AppError(500, 'invalid_configuration', `${name} is invalid.`);
  }
  return result;
}

function firebaseProjectId(value) {
  const result = (value || '').trim();
  if (
    !/^[a-z][a-z0-9-]{4,28}[a-z0-9]$/.test(result) ||
    result.includes('--')
  ) {
    throw new AppError(
      500,
      'invalid_configuration',
      'FIREBASE_PROJECT_ID must be a valid Firebase project ID.',
    );
  }
  return result;
}

function firebaseWebApiKey(value) {
  const result = (value || '').trim();
  if (!/^AIza[A-Za-z0-9_-]{20,100}$/.test(result)) {
    throw new AppError(
      500,
      'invalid_configuration',
      'FIREBASE_WEB_API_KEY must be a valid Firebase Web API key.',
    );
  }
  return result;
}

function emailSender(value, name) {
  if (
    typeof value !== 'string' ||
    value.length < 3 ||
    value.length > 254 ||
    /[\r\n]/.test(value)
  ) {
    throw new AppError(500, 'invalid_configuration', `${name} is invalid.`);
  }
  const address = value.includes('<')
    ? /^.{1,100}<([^<>]+)>$/.exec(value)?.[1]
    : value;
  if (
    !address ||
    !/^[A-Za-z0-9.!#$%&'*+/=?^_`{|}~-]+@[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+$/.test(
      address,
    )
  ) {
    throw new AppError(500, 'invalid_configuration', `${name} is invalid.`);
  }
  return value;
}

export function loadConfig(env = process.env) {
  const nodeEnv = env.NODE_ENV || 'development';
  const deploymentStage =
    env.DEPLOYMENT_STAGE ||
    (nodeEnv === 'production' ? 'production' : 'development');
  if (!['development', 'staging', 'production'].includes(deploymentStage)) {
    throw new AppError(
      500,
      'invalid_configuration',
      'DEPLOYMENT_STAGE must be development, staging, or production.',
    );
  }
  const production = deploymentStage === 'production';
  const publicDeployment = deploymentStage !== 'development';
  if (publicDeployment && nodeEnv !== 'production') {
    throw new AppError(
      500,
      'invalid_configuration',
      'Staging and production deployments require NODE_ENV=production.',
    );
  }
  const authMode =
    env.AUTH_MODE || (publicDeployment ? '' : 'development');
  if (!['development', 'jwt', 'firebase'].includes(authMode)) {
    throw new AppError(
      500,
      'invalid_configuration',
      'AUTH_MODE must be development, jwt, or firebase.',
    );
  }
  if (publicDeployment && authMode === 'development') {
    throw new AppError(
      500,
      'invalid_configuration',
      'Public deployments require JWT or Firebase authentication.',
    );
  }

  const stripeSecretKey = env.STRIPE_SECRET_KEY || '';
  const stripeWebhookSecret = env.STRIPE_WEBHOOK_SECRET || '';
  const stripeConnectWebhookSecret = env.STRIPE_CONNECT_WEBHOOK_SECRET || '';
  if (
    stripeSecretKey &&
    !/^(?:sk|rk)_(?:test|live)_[^\s]{4,}$/.test(stripeSecretKey)
  ) {
    throw new AppError(
      500,
      'invalid_configuration',
      'STRIPE_SECRET_KEY must be a Stripe test or live server key.',
    );
  }
  if (
    stripeWebhookSecret &&
    !/^whsec_[^\s]{4,}$/.test(stripeWebhookSecret)
  ) {
    throw new AppError(
      500,
      'invalid_configuration',
      'STRIPE_WEBHOOK_SECRET must be a webhook signing secret.',
    );
  }
  if (
    stripeConnectWebhookSecret &&
    !/^whsec_[^\s]{4,}$/.test(stripeConnectWebhookSecret)
  ) {
    throw new AppError(
      500,
      'invalid_configuration',
      'STRIPE_CONNECT_WEBHOOK_SECRET must be a webhook signing secret.',
    );
  }
  const stripeLiveMode = /^(?:sk|rk)_live_/.test(stripeSecretKey);
  if (production && !stripeLiveMode) {
    throw new AppError(
      500,
      'invalid_configuration',
      'Production requires a Stripe live server key.',
    );
  }
  if (production && !stripeWebhookSecret.startsWith('whsec_')) {
    throw new AppError(
      500,
      'invalid_configuration',
      'Production requires a Stripe webhook signing secret.',
    );
  }
  if (!production && stripeLiveMode) {
    throw new AppError(
      500,
      'invalid_configuration',
      'Live Stripe keys are forbidden outside production.',
    );
  }
  if (
    publicDeployment &&
    Boolean(stripeSecretKey) !== Boolean(stripeWebhookSecret)
  ) {
    throw new AppError(
      500,
      'invalid_configuration',
      'Public deployments require both the Stripe server key and Checkout webhook secret, or neither.',
    );
  }

  const openaiApiKey = (env.OPENAI_API_KEY || '').trim();
  const aiEnabled = boolean(env.AI_ENABLED, Boolean(openaiApiKey));
  if (aiEnabled && !openaiApiKey.startsWith('sk-')) {
    throw new AppError(
      500,
      'invalid_configuration',
      'AI_ENABLED requires an OpenAI server API key.',
    );
  }

  const jwtSecret = env.JWT_HS256_SECRET || '';
  const jwtIssuer = env.JWT_ISSUER || '';
  const jwtAudience = env.JWT_AUDIENCE || '';
  if (
    authMode === 'jwt' &&
    (Buffer.byteLength(jwtSecret) < 32 || !jwtIssuer || !jwtAudience)
  ) {
    throw new AppError(
      500,
      'invalid_configuration',
      'JWT auth requires a 32+ byte secret, issuer, and audience.',
    );
  }

  const accountAuthEnabled = boolean(env.ACCOUNT_AUTH_ENABLED, false);
  const emailProvider = env.EMAIL_PROVIDER || 'disabled';
  if (!['disabled', 'resend'].includes(emailProvider)) {
    throw new AppError(
      500,
      'invalid_configuration',
      'EMAIL_PROVIDER must be disabled or resend.',
    );
  }
  const resendApiKey = (env.RESEND_API_KEY || '').trim();
  const welcomeEmailFrom = (env.WELCOME_EMAIL_FROM || '').trim();
  const emailConfigured =
    emailProvider === 'resend' &&
    resendApiKey.startsWith('re_') &&
    Boolean(welcomeEmailFrom);
  if (emailProvider === 'resend') {
    if (!resendApiKey.startsWith('re_')) {
      throw new AppError(
        500,
        'invalid_configuration',
        'Resend email requires a server API key.',
      );
    }
    emailSender(welcomeEmailFrom, 'WELCOME_EMAIL_FROM');
  }
  if (
    accountAuthEnabled &&
    (authMode !== 'jwt' || !emailConfigured)
  ) {
    throw new AppError(
      500,
      'invalid_configuration',
      'Account authentication requires JWT auth and a configured email provider.',
    );
  }
  const firebaseEmailCodeEnabled = boolean(
    env.FIREBASE_EMAIL_CODE_ENABLED,
    false,
  );
  const firebaseEmailCodeSecret =
    (env.FIREBASE_EMAIL_CODE_SECRET || '').trim();
  if (
    firebaseEmailCodeEnabled &&
    (
      authMode !== 'firebase' ||
      (env.FIREBASE_AUTH_VERIFIER_MODE || 'application-default')
        .trim()
        .toLowerCase() !== 'application-default' ||
      !emailConfigured ||
      Buffer.byteLength(firebaseEmailCodeSecret) < 32
    )
  ) {
    throw new AppError(
      500,
      'invalid_configuration',
      'Firebase email codes require Firebase Admin authentication, a configured email provider, and a 32+ byte dedicated secret.',
    );
  }
  const authRateLimitSecret = env.AUTH_RATE_LIMIT_SECRET || jwtSecret;
  if (
    accountAuthEnabled &&
    Buffer.byteLength(authRateLimitSecret) < 32
  ) {
    throw new AppError(
      500,
      'invalid_configuration',
      'Account authentication requires a 32+ byte rate-limit secret.',
    );
  }

  const stripeConnectEnabled = production
    ? true
    : boolean(env.STRIPE_CONNECT_ENABLED, false);
  const connectDefaultCountry =
    (env.CONNECT_DEFAULT_COUNTRY || 'US').trim().toUpperCase();
  const connectDefaultCurrency =
    (env.CONNECT_DEFAULT_CURRENCY || 'usd').trim().toLowerCase();
  if (!/^[A-Z]{2}$/.test(connectDefaultCountry)) {
    throw new AppError(
      500,
      'invalid_configuration',
      'CONNECT_DEFAULT_COUNTRY must be a two-letter country code.',
    );
  }
  if (!/^[a-z]{3}$/.test(connectDefaultCurrency)) {
    throw new AppError(
      500,
      'invalid_configuration',
      'CONNECT_DEFAULT_CURRENCY must be a three-letter currency code.',
    );
  }
  let connectOnboardingReturnUrl = '';
  let connectOnboardingRefreshUrl = '';
  if (stripeConnectEnabled) {
    const accountIdentityConfigured =
      (authMode === 'jwt' && accountAuthEnabled) ||
      authMode === 'firebase';
    if (
      !accountIdentityConfigured ||
      !stripeSecretKey ||
      !stripeWebhookSecret ||
      !stripeConnectWebhookSecret
    ) {
      throw new AppError(
        500,
        'invalid_configuration',
        'Stripe Connect requires verified accounts, Stripe Checkout, and a separate Connect webhook secret.',
      );
    }
    connectOnboardingReturnUrl = url(
      env.CONNECT_ONBOARDING_RETURN_URL || '',
      'CONNECT_ONBOARDING_RETURN_URL',
      { production: true },
    );
    connectOnboardingRefreshUrl = url(
      env.CONNECT_ONBOARDING_REFRESH_URL || '',
      'CONNECT_ONBOARDING_REFRESH_URL',
      { production: true },
    );
  }

  const databasePath = env.DATABASE_PATH || './data/drip.sqlite';
  if (publicDeployment && databasePath === ':memory:') {
    throw new AppError(
      500,
      'invalid_configuration',
      'Public deployments require a durable database path.',
    );
  }
  const marketplaceDatabaseProvider =
    (env.MARKETPLACE_DATABASE_PROVIDER || 'sqlite').trim().toLowerCase();
  if (!['sqlite', 'firestore'].includes(marketplaceDatabaseProvider)) {
    throw new AppError(
      500,
      'invalid_configuration',
      'MARKETPLACE_DATABASE_PROVIDER must be sqlite or firestore.',
    );
  }
  const firebaseCredentialsMode =
    (env.FIREBASE_CREDENTIALS_MODE || '').trim().toLowerCase();
  const firebaseAuthVerifierMode =
    (env.FIREBASE_AUTH_VERIFIER_MODE || 'application-default')
      .trim()
      .toLowerCase();
  if (
    authMode === 'firebase' &&
    !['application-default', 'rest-api-key'].includes(
      firebaseAuthVerifierMode,
    )
  ) {
    throw new AppError(
      500,
      'invalid_configuration',
      'FIREBASE_AUTH_VERIFIER_MODE must be application-default or rest-api-key.',
    );
  }
  let configuredFirebaseProjectId = '';
  let configuredFirebaseWebApiKey = '';
  const firebaseRequired =
    marketplaceDatabaseProvider === 'firestore' || authMode === 'firebase';
  if (firebaseRequired) {
    configuredFirebaseProjectId = firebaseProjectId(env.FIREBASE_PROJECT_ID);
  }
  const firebaseAdminRequired =
    marketplaceDatabaseProvider === 'firestore' ||
    (authMode === 'firebase' &&
      firebaseAuthVerifierMode === 'application-default');
  if (firebaseAdminRequired) {
    if (firebaseCredentialsMode !== 'application-default') {
      throw new AppError(
        500,
        'invalid_configuration',
        'Firebase Admin services require FIREBASE_CREDENTIALS_MODE=application-default.',
      );
    }
  } else if (firebaseCredentialsMode) {
    throw new AppError(
      500,
      'invalid_configuration',
      'FIREBASE_CREDENTIALS_MODE is only valid with Firebase authentication or Firestore.',
    );
  }
  if (
    authMode === 'firebase' &&
    firebaseAuthVerifierMode === 'rest-api-key'
  ) {
    configuredFirebaseWebApiKey = firebaseWebApiKey(env.FIREBASE_WEB_API_KEY);
  } else if ((env.FIREBASE_WEB_API_KEY || '').trim()) {
    throw new AppError(
      500,
      'invalid_configuration',
      'FIREBASE_WEB_API_KEY is only valid with Firebase REST API-key verification.',
    );
  }
  if (
    authMode !== 'firebase' &&
    env.FIREBASE_AUTH_VERIFIER_MODE != null &&
    env.FIREBASE_AUTH_VERIFIER_MODE !== ''
  ) {
    throw new AppError(
      500,
      'invalid_configuration',
      'FIREBASE_AUTH_VERIFIER_MODE is only valid with Firebase authentication.',
    );
  }

  const aiRateLimitPerMinute = integer(
    env.AI_RATE_LIMIT_PER_MINUTE,
    12,
    'AI_RATE_LIMIT_PER_MINUTE',
    { min: 1, max: 120 },
  );
  const aiRateLimitPerDay = integer(
    env.AI_RATE_LIMIT_PER_DAY,
    200,
    'AI_RATE_LIMIT_PER_DAY',
    { min: 1, max: 10_000 },
  );
  if (aiRateLimitPerDay < aiRateLimitPerMinute) {
    throw new AppError(
      500,
      'invalid_configuration',
      'AI_RATE_LIMIT_PER_DAY cannot be lower than the minute limit.',
    );
  }

  return Object.freeze({
    nodeEnv,
    deploymentStage,
    production,
    publicDeployment,
    host: env.HOST || '127.0.0.1',
    port: integer(env.PORT, 4242, 'PORT', { min: 1, max: 65535 }),
    databasePath:
      databasePath === ':memory:' ? databasePath : path.resolve(databasePath),
    marketplaceDatabaseProvider,
    firebaseProjectId: configuredFirebaseProjectId,
    firebaseCredentialsMode,
    firebaseAuthVerifierMode:
      authMode === 'firebase' ? firebaseAuthVerifierMode : '',
    firebaseWebApiKey: configuredFirebaseWebApiKey,
    firebaseEmailCodeEnabled,
    firebaseEmailCodeConfigured: firebaseEmailCodeEnabled,
    firebaseEmailCodeSecret,
    firebaseEmailCodeTtlSeconds: integer(
      env.FIREBASE_EMAIL_CODE_TTL_SECONDS,
      10 * 60,
      'FIREBASE_EMAIL_CODE_TTL_SECONDS',
      { min: 5 * 60, max: 30 * 60 },
    ),
    firebaseEmailCodeResendCooldownSeconds: integer(
      env.FIREBASE_EMAIL_CODE_RESEND_COOLDOWN_SECONDS,
      60,
      'FIREBASE_EMAIL_CODE_RESEND_COOLDOWN_SECONDS',
      { min: 30, max: 15 * 60 },
    ),
    firebaseEmailCodeResendLimitPerHour: integer(
      env.FIREBASE_EMAIL_CODE_RESEND_LIMIT_PER_HOUR,
      5,
      'FIREBASE_EMAIL_CODE_RESEND_LIMIT_PER_HOUR',
      { min: 1, max: 20 },
    ),
    firebaseEmailCodeIpRequestLimitPerHour: integer(
      env.FIREBASE_EMAIL_CODE_IP_REQUEST_LIMIT_PER_HOUR,
      20,
      'FIREBASE_EMAIL_CODE_IP_REQUEST_LIMIT_PER_HOUR',
      { min: 1, max: 200 },
    ),
    firebaseEmailCodeAttemptLimitPer15Minutes: integer(
      env.FIREBASE_EMAIL_CODE_ATTEMPT_LIMIT_PER_15_MINUTES,
      20,
      'FIREBASE_EMAIL_CODE_ATTEMPT_LIMIT_PER_15_MINUTES',
      { min: 5, max: 100 },
    ),
    firebaseEmailCodeMaxAttempts: integer(
      env.FIREBASE_EMAIL_CODE_MAX_ATTEMPTS,
      5,
      'FIREBASE_EMAIL_CODE_MAX_ATTEMPTS',
      { min: 3, max: 10 },
    ),
    firebaseConnectTimeoutMs: integer(
      env.FIREBASE_CONNECT_TIMEOUT_MS,
      10_000,
      'FIREBASE_CONNECT_TIMEOUT_MS',
      { min: 1_000, max: 60_000 },
    ),
    stripeSecretKey,
    stripeWebhookSecret,
    stripeConnectWebhookSecret,
    paymentsConfigured: Boolean(stripeSecretKey && stripeWebhookSecret),
    stripeLiveMode,
    stripeConnectEnabled,
    stripeConnectConfigured: stripeConnectEnabled,
    connectOnboardingReturnUrl,
    connectOnboardingRefreshUrl,
    connectDefaultCountry,
    connectDefaultCurrency,
    aiEnabled,
    aiConfigured: Boolean(aiEnabled && openaiApiKey),
    openaiApiKey,
    openaiModel: identifier(
      env.OPENAI_MODEL,
      'gpt-5.6-terra',
      'OPENAI_MODEL',
    ),
    openaiModerationModel: identifier(
      env.OPENAI_MODERATION_MODEL,
      'omni-moderation-latest',
      'OPENAI_MODERATION_MODEL',
    ),
    aiTimeoutMs: integer(env.AI_TIMEOUT_MS, 20_000, 'AI_TIMEOUT_MS', {
      min: 1_000,
      max: 60_000,
    }),
    aiMaxOutputTokens: integer(
      env.AI_MAX_OUTPUT_TOKENS,
      900,
      'AI_MAX_OUTPUT_TOKENS',
      { min: 256, max: 4_096 },
    ),
    aiRateLimitPerMinute,
    aiRateLimitPerDay,
    checkoutSuccessUrl: url(
      env.CHECKOUT_SUCCESS_URL ||
        'http://localhost:4242/checkout/success?session_id={CHECKOUT_SESSION_ID}',
      'CHECKOUT_SUCCESS_URL',
      { production: publicDeployment, checkoutPlaceholder: true },
    ),
    checkoutCancelUrl: url(
      env.CHECKOUT_CANCEL_URL || 'http://localhost:4242/checkout/cancel',
      'CHECKOUT_CANCEL_URL',
      { production: publicDeployment },
    ),
    checkoutAllowedCountries: checkoutCountries(
      env.CHECKOUT_ALLOWED_COUNTRIES || 'US',
    ),
    reservationMinutes: integer(
      env.CHECKOUT_RESERVATION_MINUTES,
      31,
      'CHECKOUT_RESERVATION_MINUTES',
      { min: 31, max: 1440 },
    ),
    corsAllowedOrigins: origins(env.CORS_ALLOWED_ORIGINS || ''),
    authMode,
    devBuyerId: env.DEV_BUYER_ID || 'dev-alex',
    devBuyerSellerHandle:
      env.DEV_BUYER_SELLER_HANDLE || '@alexwears',
    jwtSecret,
    jwtIssuer,
    jwtAudience,
    accountAuthEnabled,
    authSessionTtlSeconds: integer(
      env.AUTH_SESSION_TTL_SECONDS,
      7 * 24 * 60 * 60,
      'AUTH_SESSION_TTL_SECONDS',
      { min: 15 * 60, max: 30 * 24 * 60 * 60 },
    ),
    authSignupRateLimitPerHour: integer(
      env.AUTH_SIGNUP_RATE_LIMIT_PER_HOUR,
      5,
      'AUTH_SIGNUP_RATE_LIMIT_PER_HOUR',
      { min: 1, max: 100 },
    ),
    authLoginRateLimitPer15Minutes: integer(
      env.AUTH_LOGIN_RATE_LIMIT_PER_15_MINUTES,
      10,
      'AUTH_LOGIN_RATE_LIMIT_PER_15_MINUTES',
      { min: 1, max: 500 },
    ),
    authVerificationCodeTtlSeconds: integer(
      env.AUTH_VERIFICATION_CODE_TTL_SECONDS,
      10 * 60,
      'AUTH_VERIFICATION_CODE_TTL_SECONDS',
      { min: 5 * 60, max: 30 * 60 },
    ),
    authVerificationResendCooldownSeconds: integer(
      env.AUTH_VERIFICATION_RESEND_COOLDOWN_SECONDS,
      60,
      'AUTH_VERIFICATION_RESEND_COOLDOWN_SECONDS',
      { min: 30, max: 15 * 60 },
    ),
    authVerificationResendLimitPerHour: integer(
      env.AUTH_VERIFICATION_RESEND_LIMIT_PER_HOUR,
      5,
      'AUTH_VERIFICATION_RESEND_LIMIT_PER_HOUR',
      { min: 1, max: 20 },
    ),
    authVerificationAttemptRateLimitPer15Minutes: integer(
      env.AUTH_VERIFICATION_ATTEMPT_RATE_LIMIT_PER_15_MINUTES,
      20,
      'AUTH_VERIFICATION_ATTEMPT_RATE_LIMIT_PER_15_MINUTES',
      { min: 5, max: 100 },
    ),
    authPendingAccountTtlSeconds: integer(
      env.AUTH_PENDING_ACCOUNT_TTL_SECONDS,
      24 * 60 * 60,
      'AUTH_PENDING_ACCOUNT_TTL_SECONDS',
      { min: 60 * 60, max: 7 * 24 * 60 * 60 },
    ),
    authRateLimitSecret,
    emailProvider,
    emailConfigured,
    resendApiKey,
    welcomeEmailFrom,
    emailTimeoutMs: integer(
      env.EMAIL_TIMEOUT_MS,
      10_000,
      'EMAIL_TIMEOUT_MS',
      { min: 1_000, max: 30_000 },
    ),
    emailRetryIntervalMs: integer(
      env.WELCOME_EMAIL_RETRY_INTERVAL_MS,
      60_000,
      'WELCOME_EMAIL_RETRY_INTERVAL_MS',
      { min: 1_000, max: 15 * 60 * 1_000 },
    ),
    requireConnectPayouts: production
      ? true
      : boolean(env.REQUIRE_CONNECT_PAYOUTS, false),
  });
}
