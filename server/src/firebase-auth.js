import { AppError } from './errors.js';

let firebaseAuthAppSequence = 0;
const FIREBASE_AUTH_LOOKUP_URL =
  'https://identitytoolkit.googleapis.com/v1/accounts:lookup';
const FIREBASE_AUTH_RESPONSE_LIMIT_BYTES = 64 * 1024;
const FIREBASE_CLOCK_SKEW_SECONDS = 30;

function authenticationUnavailable(message) {
  return new AppError(
    503,
    'authentication_unavailable',
    message,
    undefined,
    true,
  );
}

function invalidToken() {
  return new AppError(401, 'invalid_token', 'The access token is invalid.');
}

function withTimeout(promise, timeoutMs, message) {
  let timeout;
  const timeoutPromise = new Promise((_, reject) => {
    timeout = setTimeout(() => {
      reject(authenticationUnavailable(message));
    }, timeoutMs);
    timeout.unref?.();
  });
  return Promise.race([promise, timeoutPromise]).finally(() => {
    clearTimeout(timeout);
  });
}

async function firebaseSdk() {
  const [app, auth] = await Promise.all([
    import('firebase-admin/app'),
    import('firebase-admin/auth'),
  ]);
  return { app, auth };
}

function parseJsonObject(raw) {
  try {
    const parsed = JSON.parse(raw);
    if (
      parsed === null ||
      typeof parsed !== 'object' ||
      Array.isArray(parsed)
    ) {
      throw new TypeError('Expected a JSON object.');
    }
    return parsed;
  } catch {
    throw authenticationUnavailable(
      'Firebase Authentication returned an invalid response.',
    );
  }
}

async function readBoundedJson(response, limitBytes, abortController) {
  const declaredLength = response.headers?.get?.('content-length');
  if (declaredLength != null && declaredLength !== '') {
    const parsedLength = Number(declaredLength);
    if (
      !Number.isSafeInteger(parsedLength) ||
      parsedLength < 0 ||
      parsedLength > limitBytes
    ) {
      abortController.abort();
      throw authenticationUnavailable(
        'Firebase Authentication returned an invalid response.',
      );
    }
  }

  if (!response.body) {
    return parseJsonObject('');
  }

  const chunks = [];
  let totalBytes = 0;
  try {
    for await (const chunk of response.body) {
      const bytes = Buffer.from(chunk);
      totalBytes += bytes.length;
      if (totalBytes > limitBytes) {
        abortController.abort();
        throw authenticationUnavailable(
          'Firebase Authentication returned an invalid response.',
        );
      }
      chunks.push(bytes);
    }
  } catch (error) {
    if (error instanceof AppError) throw error;
    throw authenticationUnavailable(
      'Firebase Authentication could not complete account verification.',
    );
  }
  return parseJsonObject(Buffer.concat(chunks, totalBytes).toString('utf8'));
}

function firebaseRestErrorMessage(payload) {
  const message = payload?.error?.message;
  if (typeof message !== 'string') return '';
  return message.split(/[\s:]/, 1)[0].toUpperCase();
}

function mapLookupError(status, payload) {
  const code = firebaseRestErrorMessage(payload);
  if (
    code === 'INVALID_ID_TOKEN' ||
    code === 'TOKEN_EXPIRED' ||
    code === 'USER_NOT_FOUND' ||
    code === 'EMAIL_NOT_FOUND' ||
    code === 'USER_DISABLED' ||
    code === 'CREDENTIAL_TOO_OLD_LOGIN_AGAIN'
  ) {
    return invalidToken();
  }
  if (status === 429 || status >= 500) {
    return authenticationUnavailable(
      'Firebase Authentication is temporarily unavailable.',
    );
  }
  return authenticationUnavailable(
    'Firebase Authentication rejected the server configuration.',
  );
}

function validFirebaseEmail(value) {
  return (
    typeof value === 'string' &&
    value.length >= 3 &&
    value.length <= 254 &&
    !/[\s\r\n]/.test(value) &&
    /^[^@]+@[^@]+$/.test(value)
  );
}

function accountFromLookup(payload) {
  if (!Array.isArray(payload.users)) {
    throw authenticationUnavailable(
      'Firebase Authentication returned an invalid account response.',
    );
  }
  if (payload.users.length === 0) throw invalidToken();
  if (payload.users.length !== 1) {
    throw authenticationUnavailable(
      'Firebase Authentication returned an invalid account response.',
    );
  }

  const account = payload.users[0];
  if (
    account === null ||
    typeof account !== 'object' ||
    Array.isArray(account) ||
    typeof account.localId !== 'string' ||
    account.localId.length < 1 ||
    account.localId.length > 128 ||
    !validFirebaseEmail(account.email) ||
    (account.emailVerified != null &&
      typeof account.emailVerified !== 'boolean') ||
    (account.disabled != null && typeof account.disabled !== 'boolean') ||
    typeof account.validSince !== 'string' ||
    !/^(?:0|[1-9]\d{0,15})$/.test(account.validSince)
  ) {
    throw authenticationUnavailable(
      'Firebase Authentication returned an invalid account response.',
    );
  }
  const validSince = Number(account.validSince);
  if (!Number.isSafeInteger(validSince) || validSince < 0) {
    throw authenticationUnavailable(
      'Firebase Authentication returned an invalid account response.',
    );
  }
  if (account.disabled === true) throw invalidToken();

  return {
    uid: account.localId,
    email: account.email,
    emailVerified: account.emailVerified === true,
    displayName:
      typeof account.displayName === 'string' &&
      account.displayName.length >= 1 &&
      account.displayName.length <= 80 &&
      !/[\r\n]/.test(account.displayName)
        ? account.displayName
        : null,
    validSince,
  };
}

function parseVerifiedTokenPayload(token) {
  const parts = token.split('.');
  if (parts.length !== 3 || parts.some((part) => !part)) {
    throw invalidToken();
  }
  let payload;
  try {
    payload = JSON.parse(Buffer.from(parts[1], 'base64url').toString('utf8'));
  } catch {
    throw invalidToken();
  }
  if (
    payload === null ||
    typeof payload !== 'object' ||
    Array.isArray(payload)
  ) {
    throw invalidToken();
  }
  return payload;
}

function verifiedClaims({
  token,
  account,
  projectId,
  checkRevoked,
  nowSeconds,
}) {
  if (!Number.isSafeInteger(nowSeconds) || nowSeconds < 0) {
    throw authenticationUnavailable(
      'Firebase Authentication could not verify the server clock.',
    );
  }
  // The payload is deliberately decoded only after accounts:lookup has
  // accepted this exact ID token and returned its current Firebase user.
  const payload = parseVerifiedTokenPayload(token);
  if (
    payload.sub !== account.uid ||
    (payload.user_id != null && payload.user_id !== account.uid) ||
    payload.aud !== projectId ||
    payload.iss !== `https://securetoken.google.com/${projectId}` ||
    !Number.isSafeInteger(payload.exp) ||
    payload.exp <= nowSeconds ||
    !Number.isSafeInteger(payload.iat) ||
    payload.iat > nowSeconds + FIREBASE_CLOCK_SKEW_SECONDS ||
    !Number.isSafeInteger(payload.auth_time) ||
    payload.auth_time > nowSeconds + FIREBASE_CLOCK_SKEW_SECONDS ||
    payload.auth_time > payload.iat ||
    payload.iat >= payload.exp ||
    (checkRevoked && payload.auth_time < account.validSince)
  ) {
    throw invalidToken();
  }

  const claims = {
    uid: account.uid,
    sub: account.uid,
    email: account.email,
    email_verified: account.emailVerified,
    exp: payload.exp,
  };
  if (account.displayName) claims.name = account.displayName;
  if (typeof payload.seller_handle === 'string') {
    claims.seller_handle = payload.seller_handle;
  }
  return Object.freeze(claims);
}

export class FirebaseRestAuthVerifier {
  #apiKey;
  #fetch;
  #lookupUrl;
  #now;
  #projectId;
  #responseLimitBytes;
  #timeoutMs;

  constructor({
    projectId,
    apiKey,
    fetchImpl = globalThis.fetch,
    lookupUrl = FIREBASE_AUTH_LOOKUP_URL,
    now = Date.now,
    responseLimitBytes = FIREBASE_AUTH_RESPONSE_LIMIT_BYTES,
    timeoutMs = 10_000,
  }) {
    if (
      typeof projectId !== 'string' ||
      !projectId ||
      typeof apiKey !== 'string' ||
      !apiKey ||
      typeof fetchImpl !== 'function' ||
      typeof lookupUrl !== 'string' ||
      !lookupUrl ||
      typeof now !== 'function' ||
      !Number.isSafeInteger(responseLimitBytes) ||
      responseLimitBytes < 1 ||
      !Number.isSafeInteger(timeoutMs) ||
      timeoutMs < 1
    ) {
      throw new TypeError('Firebase REST Auth verifier configuration is invalid.');
    }
    this.#projectId = projectId;
    this.#apiKey = apiKey;
    this.#fetch = fetchImpl;
    this.#lookupUrl = lookupUrl;
    this.#now = now;
    this.#responseLimitBytes = responseLimitBytes;
    this.#timeoutMs = timeoutMs;
  }

  async assertReady() {
    // accounts:lookup requires a real user's ID token. Constructor validation
    // is the only non-destructive readiness check available for this mode.
  }

  async verifyIdToken(token, checkRevoked = true) {
    if (
      typeof token !== 'string' ||
      token.length < 1 ||
      token.length > 4096 ||
      /\s/.test(token)
    ) {
      throw invalidToken();
    }

    const abortController = new AbortController();
    let timeout;
    const timeoutFailure = new Promise((_, reject) => {
      timeout = setTimeout(() => {
        abortController.abort();
        reject(
          authenticationUnavailable(
            'Firebase Authentication did not respond before token verification timed out.',
          ),
        );
      }, this.#timeoutMs);
      timeout.unref?.();
    });
    try {
      const verification = (async () => {
        let response;
        try {
          const url = new URL(this.#lookupUrl);
          url.searchParams.set('key', this.#apiKey);
          response = await this.#fetch(url, {
            method: 'POST',
            headers: {
              Accept: 'application/json',
              'Content-Type': 'application/json',
            },
            body: JSON.stringify({ idToken: token }),
            redirect: 'error',
            signal: abortController.signal,
          });
        } catch {
          throw authenticationUnavailable(
            abortController.signal.aborted
              ? 'Firebase Authentication did not respond before token verification timed out.'
              : 'Firebase Authentication could not complete account verification.',
          );
        }

        if (
          !response ||
          typeof response.status !== 'number' ||
          typeof response.ok !== 'boolean'
        ) {
          throw authenticationUnavailable(
            'Firebase Authentication returned an invalid response.',
          );
        }
        const payload = await readBoundedJson(
          response,
          this.#responseLimitBytes,
          abortController,
        );
        if (!response.ok) throw mapLookupError(response.status, payload);

        const account = accountFromLookup(payload);
        return verifiedClaims({
          token,
          account,
          projectId: this.#projectId,
          checkRevoked: checkRevoked === true,
          nowSeconds: Math.floor(this.#now() / 1000),
        });
      })();
      return await Promise.race([verification, timeoutFailure]);
    } finally {
      clearTimeout(timeout);
    }
  }

  async close() {}
}

export class FirebaseAuthVerifier {
  #auth;
  #firebaseApp;
  #deleteApp;
  #timeoutMs;

  constructor({
    auth,
    firebaseApp = null,
    deleteApp = null,
    timeoutMs = 10_000,
  }) {
    if (!auth || typeof auth.verifyIdToken !== 'function') {
      throw new TypeError('Firebase Auth requires an ID-token verifier.');
    }
    this.#auth = auth;
    this.#firebaseApp = firebaseApp;
    this.#deleteApp = deleteApp;
    this.#timeoutMs = timeoutMs;
  }

  async assertReady() {
    if (typeof this.#auth.listUsers !== 'function') {
      throw new TypeError('Firebase Auth readiness requires listUsers.');
    }
    await withTimeout(
      this.#auth.listUsers(1),
      this.#timeoutMs,
      'Firebase Authentication did not respond before startup timed out.',
    );
  }

  verifyIdToken(token, checkRevoked = true) {
    return withTimeout(
      this.#auth.verifyIdToken(token, checkRevoked),
      this.#timeoutMs,
      'Firebase Authentication did not respond before token verification timed out.',
    );
  }

  getUserForEmailVerification(uid) {
    if (
      typeof uid !== 'string' ||
      uid.length < 1 ||
      uid.length > 128 ||
      typeof this.#auth.getUser !== 'function'
    ) {
      throw invalidToken();
    }
    return withTimeout(
      this.#auth.getUser(uid),
      this.#timeoutMs,
      'Firebase Authentication did not respond before account verification timed out.',
    );
  }

  async markEmailVerified(uid, expectedEmail) {
    if (
      typeof expectedEmail !== 'string' ||
      !validFirebaseEmail(expectedEmail) ||
      typeof this.#auth.updateUser !== 'function'
    ) {
      throw invalidToken();
    }
    const current = await this.getUserForEmailVerification(uid);
    if (current?.disabled === true) throw invalidToken();
    const currentEmail =
      typeof current?.email === 'string'
        ? current.email.normalize('NFKC').trim().toLowerCase()
        : '';
    if (currentEmail !== expectedEmail) {
      throw new AppError(
        409,
        'verification_email_changed',
        'Your email address changed. Request a new confirmation code.',
      );
    }
    if (current.emailVerified === true) return current;

    // Writing the expected address with the verified flag binds the update to
    // the exact address that received the code, even if a client races an
    // email-address change between the read and this Admin SDK operation.
    return withTimeout(
      this.#auth.updateUser(uid, {
        email: expectedEmail,
        emailVerified: true,
      }),
      this.#timeoutMs,
      'Firebase Authentication did not respond before email verification timed out.',
    );
  }

  async close() {
    if (this.#firebaseApp && typeof this.#deleteApp === 'function') {
      const app = this.#firebaseApp;
      this.#firebaseApp = null;
      await this.#deleteApp(app);
    }
  }
}

export async function createFirebaseAuthVerifier(
  config,
  {
    sdk,
    fetchImpl,
    now,
    responseLimitBytes,
  } = {},
) {
  if (config.authMode !== 'firebase') return null;

  if (config.firebaseAuthVerifierMode === 'rest-api-key') {
    const verifier = new FirebaseRestAuthVerifier({
      projectId: config.firebaseProjectId,
      apiKey: config.firebaseWebApiKey,
      fetchImpl,
      now,
      responseLimitBytes,
      timeoutMs: config.firebaseConnectTimeoutMs,
    });
    await verifier.assertReady();
    return verifier;
  }

  const firebase = sdk || (await firebaseSdk());
  let app;
  try {
    app = firebase.app.initializeApp(
      {
        credential: firebase.app.applicationDefault(),
        projectId: config.firebaseProjectId,
      },
      `drip-auth-${process.pid}-${firebaseAuthAppSequence++}`,
    );
    const verifier = new FirebaseAuthVerifier({
      auth: firebase.auth.getAuth(app),
      firebaseApp: app,
      deleteApp: firebase.app.deleteApp,
      timeoutMs: config.firebaseConnectTimeoutMs,
    });
    await verifier.assertReady();
    return verifier;
  } catch (error) {
    if (app && typeof firebase.app.deleteApp === 'function') {
      await firebase.app.deleteApp(app).catch(() => {});
    }
    throw new AppError(
      503,
      'authentication_unavailable',
      'Firebase Authentication could not start with the configured project and credentials.',
      undefined,
      true,
    );
  }
}
