import {
  createHmac,
  timingSafeEqual,
} from 'node:crypto';

import { AppError } from './errors.js';

const SESSION_ID = /^ses_[A-Za-z0-9_-]{20,120}$/;
const SELLER_HANDLE = /^@[A-Za-z0-9._]{1,39}$/;

function invalidToken() {
  return new AppError(401, 'invalid_token', 'The access token is invalid.');
}

function parseJsonPart(part) {
  try {
    const result = JSON.parse(Buffer.from(part, 'base64url').toString('utf8'));
    if (result === null || typeof result !== 'object' || Array.isArray(result)) {
      throw invalidToken();
    }
    return result;
  } catch (error) {
    if (error instanceof AppError) throw error;
    throw invalidToken();
  }
}

function includesAudience(value, expected) {
  return value === expected ||
    (Array.isArray(value) && value.includes(expected));
}

function bearerToken(request) {
  const authorization = request.headers.authorization || '';
  if (!authorization.startsWith('Bearer ')) {
    throw new AppError(401, 'authentication_required', 'Sign in to continue.');
  }
  const token = authorization.slice(7);
  if (!token || token.length > 4096 || /\s/.test(token)) throw invalidToken();
  return token;
}

function firebaseVerificationError(error) {
  const code = typeof error?.code === 'string' ? error.code : '';
  if (
    code === 'app/invalid-credential' ||
    code === 'auth/internal-error' ||
    code === 'auth/insufficient-permission' ||
    code === 'auth/network-request-failed' ||
    code === 'auth/project-not-found'
  ) {
    return new AppError(
      503,
      'authentication_unavailable',
      'Account verification is temporarily unavailable.',
      undefined,
      true,
    );
  }
  return invalidToken();
}

async function authenticateFirebaseRequest(
  request,
  firebaseAuthVerifier,
  { requireVerifiedEmail = true } = {},
) {
  if (
    !firebaseAuthVerifier ||
    typeof firebaseAuthVerifier.verifyIdToken !== 'function'
  ) {
    throw new AppError(
      503,
      'authentication_unavailable',
      'Firebase Authentication is not configured on this server.',
      undefined,
      true,
    );
  }

  let payload;
  try {
    payload = await firebaseAuthVerifier.verifyIdToken(
      bearerToken(request),
      true,
    );
  } catch (error) {
    if (error instanceof AppError) throw error;
    throw firebaseVerificationError(error);
  }
  const uid = payload?.uid ?? payload?.sub;
  if (
    payload === null ||
    typeof payload !== 'object' ||
    typeof uid !== 'string' ||
    uid.length < 1 ||
    uid.length > 128 ||
    !Number.isSafeInteger(payload.exp) ||
    (payload.uid != null && payload.sub != null && payload.uid !== payload.sub)
  ) {
    throw invalidToken();
  }
  if (
    typeof payload.email_verified !== 'boolean' ||
    (requireVerifiedEmail && payload.email_verified !== true)
  ) {
    throw new AppError(
      403,
      'email_verification_required',
      'Verify your email address before continuing.',
    );
  }

  const actor = {
    id: uid,
    sellerHandle: SELLER_HANDLE.test(payload.seller_handle || '')
      ? payload.seller_handle
      : null,
    authProvider: 'firebase',
    sessionExpiresAt: payload.exp,
  };
  if (
    typeof payload.email === 'string' &&
    payload.email.length >= 3 &&
    payload.email.length <= 254 &&
    !/[\r\n]/.test(payload.email)
  ) {
    actor.email = payload.email;
  }
  if (
    typeof payload.name === 'string' &&
    payload.name.length >= 1 &&
    payload.name.length <= 80 &&
    !/[\r\n]/.test(payload.name)
  ) {
    actor.displayName = payload.name;
  }
  if (!requireVerifiedEmail) {
    actor.emailVerified = payload.email_verified;
  }
  return Object.freeze(actor);
}

function verifyToken(token, config, nowSeconds) {
  const parts = token.split('.');
  if (parts.length !== 3 || parts.some((part) => !part)) throw invalidToken();
  const header = parseJsonPart(parts[0]);
  const payload = parseJsonPart(parts[1]);
  if (header.alg !== 'HS256' || (header.typ && header.typ !== 'JWT')) {
    throw invalidToken();
  }
  const expected = createHmac('sha256', config.jwtSecret)
    .update(`${parts[0]}.${parts[1]}`)
    .digest();
  let actual;
  try {
    actual = Buffer.from(parts[2], 'base64url');
  } catch {
    throw invalidToken();
  }
  if (actual.length !== expected.length || !timingSafeEqual(actual, expected)) {
    throw invalidToken();
  }
  if (
    payload.iss !== config.jwtIssuer ||
    !includesAudience(payload.aud, config.jwtAudience) ||
    typeof payload.sub !== 'string' ||
    payload.sub.length < 1 ||
    payload.sub.length > 128 ||
    !Number.isSafeInteger(payload.exp) ||
    payload.exp <= nowSeconds - 30 ||
    (payload.nbf != null &&
      (!Number.isSafeInteger(payload.nbf) || payload.nbf > nowSeconds + 30)) ||
    (payload.iat != null &&
      (!Number.isSafeInteger(payload.iat) || payload.iat > nowSeconds + 30))
  ) {
    throw invalidToken();
  }
  if (
    payload.sid != null &&
    (!SESSION_ID.test(payload.sid) || payload.jti !== payload.sid)
  ) {
    throw invalidToken();
  }
  if (
    payload.sid == null &&
    payload.jti != null &&
    (typeof payload.jti !== 'string' ||
      payload.jti.length < 1 ||
      payload.jti.length > 200)
  ) {
    throw invalidToken();
  }
  return payload;
}

function verifyDatabaseSession(database, payload, nowSeconds) {
  if (!database) throw invalidToken();
  const row = database
    .prepare(`
      SELECT sessions.expires_at AS expiresAt,
             sessions.revoked_at AS revokedAt,
             accounts.status AS accountStatus,
             accounts.email_verified_at AS emailVerifiedAt,
             sellers.seller_handle AS sellerHandle
        FROM account_sessions AS sessions
        JOIN accounts ON accounts.id = sessions.account_id
        LEFT JOIN seller_accounts AS sellers
          ON sellers.owner_account_id = accounts.id
       WHERE sessions.id = ? AND sessions.account_id = ?
    `)
    .get(payload.sid, payload.sub);
  if (
    !row ||
    row.accountStatus !== 'active' ||
    row.emailVerifiedAt === null ||
    row.revokedAt !== null ||
    row.expiresAt !== payload.exp ||
    row.expiresAt <= nowSeconds
  ) {
    throw invalidToken();
  }
  return row;
}

export function signAccessToken(
  config,
  { accountId, sessionId, issuedAt, expiresAt, sellerHandle = null },
) {
  if (
    config.authMode !== 'jwt' ||
    typeof accountId !== 'string' ||
    accountId.length < 1 ||
    accountId.length > 128 ||
    !SESSION_ID.test(sessionId) ||
    !Number.isSafeInteger(issuedAt) ||
    !Number.isSafeInteger(expiresAt) ||
    expiresAt <= issuedAt
  ) {
    throw new AppError(
      500,
      'invalid_configuration',
      'An access token could not be issued.',
    );
  }
  const header = Buffer.from(
    JSON.stringify({ alg: 'HS256', typ: 'JWT' }),
  ).toString('base64url');
  const claims = {
    sub: accountId,
    iss: config.jwtIssuer,
    aud: config.jwtAudience,
    iat: issuedAt,
    exp: expiresAt,
    sid: sessionId,
    jti: sessionId,
  };
  if (sellerHandle) claims.seller_handle = sellerHandle;
  const payload = Buffer.from(JSON.stringify(claims)).toString('base64url');
  const signature = createHmac('sha256', config.jwtSecret)
    .update(`${header}.${payload}`)
    .digest('base64url');
  return `${header}.${payload}.${signature}`;
}

export function authenticateRequest(
  request,
  config,
  nowSeconds = Date.now() / 1000,
  database = null,
  firebaseAuthVerifier = null,
) {
  if (config.authMode === 'development') {
    return Object.freeze({
      id: config.devBuyerId,
      sellerHandle: config.devBuyerSellerHandle,
    });
  }
  if (config.authMode === 'firebase') {
    return authenticateFirebaseRequest(request, firebaseAuthVerifier);
  }

  const payload = verifyToken(bearerToken(request), config, nowSeconds);
  const databaseSession = payload.sid
    ? verifyDatabaseSession(database, payload, nowSeconds)
    : null;
  const sellerHandle = databaseSession?.sellerHandle ??
    (typeof payload.seller_handle === 'string' ? payload.seller_handle : null);
  const actor = { id: payload.sub, sellerHandle };
  if (payload.sid) {
    actor.sessionId = payload.sid;
    actor.sessionExpiresAt = payload.exp;
  }
  return Object.freeze(actor);
}

export function authenticateFirebaseEmailCodeRequest(
  request,
  config,
  firebaseAuthVerifier,
) {
  if (
    config.authMode !== 'firebase' ||
    config.firebaseEmailCodeConfigured !== true
  ) {
    throw new AppError(
      503,
      'firebase_email_code_unavailable',
      'Email confirmation codes are not configured on this server.',
      undefined,
      true,
    );
  }
  return authenticateFirebaseRequest(request, firebaseAuthVerifier, {
    requireVerifiedEmail: false,
  });
}
