import { randomUUID } from 'node:crypto';
import { createServer } from 'node:http';

import {
  authenticateFirebaseEmailCodeRequest,
  authenticateRequest,
} from './auth.js';
import { AppError } from './errors.js';
import { checkoutErrorResponse } from './checkout-service.js';
import { SqliteMarketplaceDatabase } from './marketplace-database.js';

const JSON_BODY_LIMIT = 64 * 1024;
const WEBHOOK_BODY_LIMIT = 256 * 1024;

function addVary(response, value) {
  const current = response.getHeader('Vary');
  if (!current) response.setHeader('Vary', value);
  else if (!String(current).split(',').map((item) => item.trim()).includes(value)) {
    response.setHeader('Vary', `${current}, ${value}`);
  }
}

function applyCors(request, response, config) {
  const origin = request.headers.origin;
  addVary(response, 'Origin');
  if (!origin) return;
  if (!config.corsAllowedOrigins.has(origin)) {
    throw new AppError(403, 'origin_not_allowed', 'This web origin is not allowed.');
  }
  response.setHeader('Access-Control-Allow-Origin', origin);
  response.setHeader(
    'Access-Control-Allow-Headers',
    'Authorization, Cache-Control, Content-Type, Idempotency-Key',
  );
  response.setHeader('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  response.setHeader('Access-Control-Max-Age', '600');
}

function securityHeaders(response) {
  response.setHeader('X-Content-Type-Options', 'nosniff');
  response.setHeader('Referrer-Policy', 'no-referrer');
  response.setHeader('Cross-Origin-Resource-Policy', 'same-site');
  response.setHeader('Cache-Control', 'no-store');
}

function sendJson(response, status, payload, requestId) {
  if (response.writableEnded) return;
  const body = JSON.stringify(payload);
  response.statusCode = status;
  response.setHeader('Content-Type', 'application/json; charset=utf-8');
  response.setHeader('Content-Length', Buffer.byteLength(body));
  response.setHeader('X-Request-Id', requestId);
  response.end(body);
}

function sendHtml(response, status, title, message, requestId) {
  if (response.writableEnded) return;
  const safeTitle = title.replace(/[<>&]/g, '');
  const safeMessage = message.replace(/[<>&]/g, '');
  const body = `<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width"><title>${safeTitle}</title><style>body{margin:0;background:#0c0d12;color:#f7f8ff;font:16px system-ui;display:grid;min-height:100vh;place-items:center}.card{max-width:32rem;padding:2rem;border:1px solid #2b2e3b;border-radius:1.5rem;background:#151722}h1{margin-top:0}p{color:#b7bac8;line-height:1.55}</style><main class="card"><h1>${safeTitle}</h1><p>${safeMessage}</p></main></html>`;
  response.statusCode = status;
  response.setHeader('Content-Type', 'text/html; charset=utf-8');
  response.setHeader('Content-Security-Policy', "default-src 'none'; style-src 'unsafe-inline'; base-uri 'none'; frame-ancestors 'none'");
  response.setHeader('Content-Length', Buffer.byteLength(body));
  response.setHeader('X-Request-Id', requestId);
  response.end(body);
}

function readRawBody(request, limit) {
  return new Promise((resolve, reject) => {
    const declared = Number(request.headers['content-length']);
    if (Number.isFinite(declared) && declared > limit) {
      request.resume();
      reject(new AppError(413, 'body_too_large', 'Request body is too large.'));
      return;
    }
    const chunks = [];
    let length = 0;
    let settled = false;
    const fail = (error) => {
      if (settled) return;
      settled = true;
      reject(error);
    };
    request.on('data', (chunk) => {
      if (settled) return;
      length += chunk.length;
      if (length > limit) {
        settled = true;
        request.resume();
        reject(new AppError(413, 'body_too_large', 'Request body is too large.'));
        return;
      }
      chunks.push(chunk);
    });
    request.on('end', () => {
      if (settled) return;
      settled = true;
      resolve(Buffer.concat(chunks, length));
    });
    request.on('aborted', () => fail(new AppError(400, 'request_aborted', 'Request was aborted.')));
    request.on('error', fail);
  });
}

async function readJson(request, { optional = false } = {}) {
  const contentType = String(request.headers['content-type'] || '')
    .split(';', 1)[0]
    .trim()
    .toLowerCase();
  const raw = await readRawBody(request, JSON_BODY_LIMIT);
  if (raw.length === 0 && optional) return {};
  if (contentType !== 'application/json') {
    throw new AppError(415, 'unsupported_media_type', 'Use application/json.');
  }
  try {
    return JSON.parse(raw.toString('utf8'));
  } catch {
    throw new AppError(400, 'invalid_json', 'Request body is not valid JSON.');
  }
}

function decodeSessionId(pathname) {
  const match = /^\/v1\/checkout\/sessions\/([^/]+)$/.exec(pathname);
  if (!match) return null;
  try {
    return decodeURIComponent(match[1]);
  } catch {
    throw new AppError(404, 'not_found', 'Route was not found.');
  }
}

export function createHttpServer({
  checkoutService,
  aiService,
  accountService,
  connectService,
  config,
  database,
  firebaseEmailCodeService,
  firebaseAuthVerifier,
  marketplaceDatabase,
}) {
  const catalogDatabase =
    marketplaceDatabase || new SqliteMarketplaceDatabase(database);
  const server = createServer(
    {
      insecureHTTPParser: false,
      maxHeaderSize: 16 * 1024,
      requireHostHeader: true,
    },
    (request, response) => {
      const requestId = randomUUID();
      securityHeaders(response);
      Promise.resolve()
        .then(async () => {
          applyCors(request, response, config);
          if (request.method === 'OPTIONS') {
            response.statusCode = 204;
            response.setHeader('X-Request-Id', requestId);
            response.end();
            return;
          }
          const url = new URL(request.url || '/', 'http://localhost');
          const pathname = url.pathname;

          if (request.method === 'GET' && pathname === '/healthz') {
            sendJson(
              response,
              200,
              {
                status: 'ok',
                service: 'drip-checkout',
                paymentsConfigured: config.paymentsConfigured,
                stripeConnectConfigured: config.stripeConnectConfigured,
                aiConfigured: config.aiConfigured,
                accountAuthConfigured:
                  config.accountAuthEnabled || config.authMode === 'firebase',
                firebaseEmailCodeConfigured:
                  Boolean(firebaseEmailCodeService),
                authProvider: config.authMode,
                databaseProvider: catalogDatabase.provider,
              },
              requestId,
            );
            return;
          }
          if (request.method === 'GET' && pathname === '/checkout/success') {
            sendHtml(
              response,
              200,
              'Payment submitted',
              'Return to Drip while the verified Stripe webhook confirms your order.',
              requestId,
            );
            return;
          }
          if (request.method === 'GET' && pathname === '/checkout/cancel') {
            sendHtml(
              response,
              200,
              'Checkout canceled',
              'No order is marked paid from this page. Return to Drip to review your bag.',
              requestId,
            );
            return;
          }
          if (request.method === 'POST' && pathname === '/v1/stripe/webhook') {
            const signature = request.headers['stripe-signature'];
            if (typeof signature !== 'string' || signature.length > 2048) {
              throw new AppError(400, 'missing_webhook_signature', 'Stripe signature is required.');
            }
            const raw = await readRawBody(request, WEBHOOK_BODY_LIMIT);
            const result = await checkoutService.handleWebhook(raw, signature);
            sendJson(response, 200, result, requestId);
            return;
          }
          if (
            request.method === 'POST' &&
            new Set([
              '/v1/auth/firebase/email-code/request',
              '/v1/auth/firebase/email-code/verify',
            ]).has(pathname)
          ) {
            if (!firebaseEmailCodeService) {
              throw new AppError(
                503,
                'firebase_email_code_unavailable',
                'Email confirmation codes are not configured on this server.',
                undefined,
                true,
              );
            }
            const firebaseActor =
              await authenticateFirebaseEmailCodeRequest(
                request,
                config,
                firebaseAuthVerifier,
              );
            const body = await readJson(request);
            const requester = request.socket.remoteAddress || 'unknown';
            const requesting =
              pathname === '/v1/auth/firebase/email-code/request';
            const result = requesting
              ? await firebaseEmailCodeService.requestCode(
                  firebaseActor,
                  body,
                  requester,
                )
              : await firebaseEmailCodeService.verifyCode(
                  firebaseActor,
                  body,
                  requester,
                );
            sendJson(response, requesting ? 202 : 200, result, requestId);
            return;
          }

          if (
            request.method === 'POST' &&
            pathname === '/v1/stripe/connect-webhook'
          ) {
            if (!connectService) {
              throw new AppError(
                503,
                'stripe_connect_unavailable',
                'Stripe seller payouts are not configured on this server.',
                undefined,
                true,
              );
            }
            const signature = request.headers['stripe-signature'];
            if (typeof signature !== 'string' || signature.length > 2048) {
              throw new AppError(
                400,
                'missing_connect_webhook_signature',
                'Stripe Connect signature is required.',
              );
            }
            const raw = await readRawBody(request, WEBHOOK_BODY_LIMIT);
            const result = await connectService.handleWebhook(raw, signature);
            sendJson(response, 200, result, requestId);
            return;
          }
          if (
            request.method === 'GET' &&
            pathname === '/connect/onboarding/refresh'
          ) {
            sendHtml(
              response,
              200,
              'Stripe link expired',
              'Return to Drip and tap Continue onboarding again. For your security, this page cannot create a new payout link.',
              requestId,
            );
            return;
          }

          if (
            request.method === 'POST' &&
            new Set([
              '/v1/auth/signup',
              '/v1/auth/login',
              '/v1/auth/verify-email',
              '/v1/auth/resend-verification',
            ]).has(pathname)
          ) {
            if (!accountService) {
              throw new AppError(
                503,
                'account_auth_unavailable',
                'Account sign-in is not configured on this server.',
                undefined,
                true,
              );
            }
            const body = await readJson(request);
            const requester = request.socket.remoteAddress || 'unknown';
            let result;
            let status = 200;
            if (pathname === '/v1/auth/signup') {
              result = await accountService.register(body, requester);
              status = 202;
            } else if (pathname === '/v1/auth/verify-email') {
              result = await accountService.verifyEmail(body, requester);
            } else if (pathname === '/v1/auth/resend-verification') {
              result = await accountService.resendVerification(body, requester);
              status = 202;
            } else {
              result = await accountService.login(body, requester);
            }
            sendJson(
              response,
              status,
              result,
              requestId,
            );
            return;
          }

          const buyer = await authenticateRequest(
            request,
            config,
            Date.now() / 1000,
            database,
            firebaseAuthVerifier,
          );
          if (request.method === 'GET' && pathname === '/v1/auth/session') {
            if (config.authMode === 'firebase') {
              sendJson(
                response,
                200,
                {
                  authenticated: true,
                  user: {
                    id: buyer.id,
                    name: buyer.displayName || 'Drip member',
                    email: buyer.email || '',
                    sellerHandle: buyer.sellerHandle,
                  },
                  expiresAt: new Date(
                    buyer.sessionExpiresAt * 1000,
                  ).toISOString(),
                },
                requestId,
              );
              return;
            }
            if (!accountService) {
              throw new AppError(
                503,
                'account_auth_unavailable',
                'Account sign-in is not configured on this server.',
                undefined,
                true,
              );
            }
            sendJson(response, 200, accountService.getSession(buyer), requestId);
            return;
          }
          if (request.method === 'POST' && pathname === '/v1/auth/logout') {
            if (!accountService) {
              throw new AppError(
                503,
                'account_auth_unavailable',
                'Account sign-in is not configured on this server.',
                undefined,
                true,
              );
            }
            const body = await readJson(request, { optional: true });
            sendJson(
              response,
              200,
              accountService.logout(buyer, body),
              requestId,
            );
            return;
          }
          if (request.method === 'POST' && pathname === '/v1/ai/chat') {
            if (!aiService) {
              throw new AppError(
                503,
                'ai_unavailable',
                'Drip AI is not connected on this server.',
                undefined,
                true,
              );
            }
            const body = await readJson(request);
            const result = await aiService.chat(buyer, body);
            sendJson(response, 200, result, requestId);
            return;
          }
          if (
            request.method === 'GET' &&
            pathname === '/v1/seller/connect/status'
          ) {
            if (!connectService) {
              throw new AppError(
                503,
                'stripe_connect_unavailable',
                'Stripe seller payouts are not configured on this server.',
                undefined,
                true,
              );
            }
            sendJson(
              response,
              200,
              await connectService.getStatus(buyer),
              requestId,
            );
            return;
          }
          if (
            request.method === 'POST' &&
            pathname === '/v1/seller/connect/onboarding'
          ) {
            if (!connectService) {
              throw new AppError(
                503,
                'stripe_connect_unavailable',
                'Stripe seller payouts are not configured on this server.',
                undefined,
                true,
              );
            }
            const body = await readJson(request, { optional: true });
            sendJson(
              response,
              201,
              await connectService.createOnboarding(buyer, body),
              requestId,
            );
            return;
          }
          if (
            request.method === 'POST' &&
            pathname === '/v1/seller/connect/dashboard'
          ) {
            if (!connectService) {
              throw new AppError(
                503,
                'stripe_connect_unavailable',
                'Stripe seller payouts are not configured on this server.',
                undefined,
                true,
              );
            }
            const body = await readJson(request, { optional: true });
            sendJson(
              response,
              200,
              await connectService.createDashboardLink(buyer, body),
              requestId,
            );
            return;
          }
          if (request.method === 'GET' && pathname === '/v1/catalog') {
            sendJson(
              response,
              200,
              { items: await catalogDatabase.listCatalog() },
              requestId,
            );
            return;
          }
          if (request.method === 'POST' && pathname === '/v1/checkout/sessions') {
            const body = await readJson(request);
            const idempotency = request.headers['idempotency-key'];
            if (Array.isArray(idempotency) || (idempotency && idempotency.length > 128)) {
              throw new AppError(422, 'invalid_attempt_id', 'Idempotency-Key is invalid.');
            }
            const result = await checkoutService.createCheckout(
              buyer,
              body,
              idempotency || '',
            );
            sendJson(response, 201, result, requestId);
            return;
          }
          const sessionId = decodeSessionId(pathname);
          if (sessionId && request.method === 'GET') {
            sendJson(
              response,
              200,
              checkoutService.getCheckout(buyer, sessionId),
              requestId,
            );
            return;
          }
          const expireMatch = /^\/v1\/checkout\/sessions\/([^/]+)\/expire$/.exec(pathname);
          if (expireMatch && request.method === 'POST') {
            const expireSessionId = decodeURIComponent(expireMatch[1]);
            const body = await readJson(request, { optional: true });
            const result = await checkoutService.expireCheckout(
              buyer,
              expireSessionId,
              body,
            );
            sendJson(response, 200, result, requestId);
            return;
          }
          throw new AppError(404, 'not_found', 'Route was not found.');
        })
        .catch((error) => {
          if (response.writableEnded) return;
          const result = checkoutErrorResponse(error);
          if (result.status === 401) {
            response.setHeader('WWW-Authenticate', 'Bearer');
          }
          const retryAfter = result.payload.error.details?.retryAfterSeconds;
          if (result.status === 429 && Number.isSafeInteger(retryAfter)) {
            response.setHeader('Retry-After', String(retryAfter));
          }
          sendJson(response, result.status, result.payload, requestId);
        });
    },
  );
  server.requestTimeout = 15_000;
  server.headersTimeout = 10_000;
  server.keepAliveTimeout = 5_000;
  server.maxHeadersCount = 64;
  server.on('clientError', (_error, socket) => {
    if (socket.writable) socket.end('HTTP/1.1 400 Bad Request\r\nConnection: close\r\n\r\n');
  });
  return server;
}
