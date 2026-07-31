# Drip Checkout Service

This directory is the server-authoritative foundation for Stripe-hosted
Checkout. Flutter sends listing IDs and selected sizes; this service owns
inventory, prices, fees, shipping, order state, and the Stripe secret.

It is intentionally separate from the device-only marketplace snapshot. A
redirect from Checkout never marks an order paid. Only a verified Stripe
webhook can do that.

The same server also owns Drip Concierge, the app's AI style and marketplace
assistant. Flutter never calls OpenAI directly and never receives the OpenAI
API key. The server authenticates the buyer, validates a bounded transcript,
moderates the request, supplies server-owned catalog and policy facts, asks the
Responses API for strict structured output, and verifies every returned
listing and money value again before responding.

## Safety properties

- All money uses integer cents.
- The complete 44-item checkout catalog is seeded into SQLite. Seed inserts
  never overwrite later inventory state. The authenticated catalog API can
  instead read production marketplace documents from server-only Firestore.
- One-of-one listings are reserved transactionally before Stripe is called.
- `UNIQUE (buyer_id, attempt_id)` and a request fingerprint make retries safe
  while rejecting a changed cart under the same key.
- The Stripe idempotency key, exact quote, inventory snapshot, and 31-minute
  expiry are persisted before the network call. A retry recovers the same
  Checkout Session if the first response was lost.
- Signed webhooks retrieve the Session from Stripe again, verify order metadata,
  currency, and total, and apply monotonic state changes.
- Event IDs, Session IDs, PaymentIntent IDs, and order attempts are unique.
- A paid order cannot be reverted by a late expiration event.
- A captured payment whose inventory was already released enters
  `payment_review` with `captured_after_inventory_release_refund_required`; it
  does not oversell the listing.
- Checkout URLs and API responses use `Cache-Control: no-store`.
- Production refuses development auth, in-memory storage, non-HTTPS redirects,
  missing live Stripe secrets, and sellers without Connect transfer readiness.
- Built-in accounts normalize email before a unique database insert, hash
  passwords with a random 16-byte salt and memory-hard scrypt, issue short-lived
  HS256 tokens backed by revocable database sessions only after email
  confirmation, and rate-limit signup, confirmation, resend, and login by
  separately hashed network and account/challenge scopes.
- Confirmation uses a CSPRNG six-digit code that expires after ten minutes and
  an independent 32-byte opaque signup challenge. The database stores only
  keyed HMAC digests of both values. Codes are single-use, allow five failed
  attempts, rotate on resend, and have cooldown and hourly limits. A pending
  signup creates neither a session nor a seller identity.
- Login failures use the same status, code, and message whether the account is
  missing, disabled, or the password is wrong. Passwords and password hashes
  are never included in responses, email payloads, or normal server logs.
- Welcome delivery uses a database outbox with one persisted provider
  idempotency key. Transient failures retry at most five times with backoff,
  stale claims are reclaimed, and retries stop after 23 hours—inside Resend's
  documented 24-hour idempotency window. The response says
  `welcomeEmailSent: true` only after the provider accepts the message and
  returns an ID; a pending retry is never presented as a successful send. This
  means accepted for delivery—not proven inbox delivery. Inbox delivery would
  require separately verified Resend delivery webhooks.
- Drip AI uses the Responses API with `store: false`, a hashed safety
  identifier, a versioned developer prompt, strict Structured Outputs, and no
  client-supplied price or marketplace status as authority.
- AI requests have server-side per-buyer minute and daily limits. Moderation is
  required before generation; a moderation outage fails closed.
- General style, color, dress-code, weather-layering, proportion, cultural or
  religious clothing, and garment-care questions can be answered without
  forcing a catalog recommendation. Unusual ideas are treated respectfully,
  and proportion guidance stays body-neutral and inclusive.
- Care guidance treats the sewn-in label and manufacturer instructions as the
  authority, describes fabric behavior as a tendency rather than a guarantee,
  and recommends a qualified cleaner when an unknown or high-risk item makes
  home treatment unsafe to predict. It does not make medical claims.
- The AI response contract permits at most one focused follow-up question, and
  only when a missing detail materially changes the recommendation, compliance
  guidance, or safe-care advice.
- A pre-provider privacy guard blocks likely payment-card numbers, CVC/CVV
  values, passwords, API keys, secrets, and tokens found in either the current
  message or supplied history. The warning never echoes the value, and neither
  moderation nor generation receives the sensitive text.
- AI-disabled deployments return `ai_unavailable`; there is no fabricated or
  keyword-based production fallback.
- Outfit validation is deterministic after generation: a complete fit normally
  needs exactly one top, one bottom, and one footwear choice. Explicit
  pre-styled bundles are the only exception. An outfit budget covers the
  estimated checkout total before tax, including buyer protection and shipping
  for every unique seller package.

## What this does not pretend to provide

The service creates Stripe Accounts v2 recipient accounts, provides
Stripe-hosted onboarding and Express Dashboard links to the authenticated
seller, and synchronizes transfer/payout capability status from a separate
signed Connect event destination. It does **not** create Transfers or bank
payouts. A paid order with no ready connected account is marked
`awaiting_connect`; a ready connected account is only marked `held`. Nothing
becomes `transferred` until a separately reviewed settlement worker is
implemented.

The PaymentIntent gets a `transfer_group` so later separate charges and
transfers can be reconciled across a multi-seller order. It deliberately does
not set `transfer_data` or claim that money reached a seller.

Refunds, disputes, tax calculation, shipping labels, settlement, and a
double-entry accounting export remain launch gates. Tax is currently explicitly
snapshotted as $0. Do not accept live money until the business's tax obligations
and Stripe Tax/product tax codes have been configured and tested.

Cloud Firestore is an optional production source for `/v1/catalog`; it is not
misrepresented as a drop-in relational payment ledger. SQLite remains
authoritative for authentication, one-of-one inventory reservation, orders,
Stripe event idempotency, seller payout readiness, outboxes, and rate limits.
Those paths depend on SQL uniqueness, foreign keys, and immediate
multi-table transactions. SQLite is suitable for one service instance and this
product stage. Horizontal scaling requires moving those same constraints and
transactions to a shared transactional database such as PostgreSQL.

## Requirements

- Node.js 24.12 or newer (`node:sqlite` defensive mode is required).
- A Stripe account in test mode for real hosted Checkout testing.
- Stripe CLI for local webhook forwarding.
- A Firebase project when `AUTH_MODE=firebase`. Production should use a
  least-privilege server service identity with Firebase Admin. Local or
  self-hosted Auth-only deployments can instead use the project's Web API key
  with Firebase's official account-lookup endpoint. A server identity and
  Cloud Firestore database are still required when
  `MARKETPLACE_DATABASE_PROVIDER=firestore`.

## Local setup

From this directory:

```sh
cp .env.example .env
npm install
npm test
npm start
```

The server anchors its working directory here at startup. Launching
`npm --prefix server start` from the repository root therefore reads the same
`server/.env` and `server/data/drip.sqlite` paths instead of silently selecting
different files.

The repository does not include or generate any Stripe server key. Without
both Stripe environment values the server still starts and `/healthz` works,
but checkout returns `payments_unavailable`. A least-privilege `rk_test_…`
restricted key is preferred when it grants every Checkout operation used by
this service; `sk_test_…` is also accepted.

## Firebase / Cloud Firestore catalog

Local development and tests keep using the SQLite catalog:

```text
MARKETPLACE_DATABASE_PROVIDER=sqlite
DATABASE_PATH=./data/drip.sqlite
```

For a production marketplace catalog, create a Firebase project and Cloud
Firestore database, deploy the repository's deny-all `firestore.rules`, and
grant the server service identity only the IAM access it needs. Then configure:

```text
MARKETPLACE_DATABASE_PROVIDER=firestore
FIREBASE_PROJECT_ID=your-firebase-project-id
FIREBASE_CREDENTIALS_MODE=application-default
FIREBASE_CONNECT_TIMEOUT_MS=10000
GOOGLE_APPLICATION_CREDENTIALS=/run/secrets/drip-firebase-service-account.json
```

`GOOGLE_APPLICATION_CREDENTIALS` is needed for a secret-mounted service-account
file on a non-Google host. On Google-managed infrastructure, Application
Default Credentials can come from the runtime service identity instead. Never
commit a service-account JSON key, paste it into Flutter, or expose it to a
browser.

The server performs a real Firestore read before it starts listening. A missing
project, missing explicit ADC mode, unavailable credentials, denied IAM access,
or unreachable Firestore endpoint stops startup; the service never silently
falls back to seeded data after Firestore has been selected. Runtime catalog
failures return a retryable `database_unavailable` response.

Catalog documents live at `marketplace_listings/{listingId}`:

```json
{
  "name": "Future Runner",
  "brand": "Drip Lab",
  "sellerHandle": "@futurecloset",
  "priceCents": 18500,
  "currency": "usd",
  "sizes": ["9", "10"],
  "status": "live",
  "sortOrder": 20
}
```

The server bounds a catalog read to 500 documents, validates every field, and
returns only the public catalog contract. It does not auto-seed Firestore, so a
production project cannot accidentally publish template records. The default
security rules deny every mobile/web client read and write because the Admin
SDK bypasses Firestore rules; protect Admin access with Google Cloud IAM.

Official setup references:

- [Initialize the Firebase Admin SDK](https://firebase.google.com/docs/admin/setup)
- [Cloud Firestore server quickstart](https://firebase.google.com/docs/firestore/quickstart-server)
- [Secure server access with IAM](https://firebase.google.com/docs/firestore/security/overview)

Deploy only the database configuration from the repository root:

```sh
firebase deploy --only firestore --project your-firebase-project-id
```

Put test secrets only in `server/.env`:

```text
STRIPE_SECRET_KEY=sk_test_...
STRIPE_WEBHOOK_SECRET=whsec_...
STRIPE_CONNECT_ENABLED=true
STRIPE_CONNECT_WEBHOOK_SECRET=whsec_...
CONNECT_ONBOARDING_RETURN_URL=https://app.example.com/connect/return
CONNECT_ONBOARDING_REFRESH_URL=https://api.example.com/connect/onboarding/refresh
```

Never put either value in Flutter, a Dart define, source control, logs, or an
HTTP response.

The Checkout and Connect event destinations must use their own signing
secrets. The Connect refresh URL is deliberately informational: it tells the
seller to return to Drip. It never mints a replacement Account Link. Only an
authenticated `POST /v1/seller/connect/onboarding` request creates a new
single-use link. New seller accounts use Stripe's recipient configuration with
an Express Dashboard; Drip remains responsible for platform fees and losses.

## Drip AI setup

Drip AI can be implemented, tested, and deployed disabled without any OpenAI
credential. To enable actual model calls, create a restricted project key and
put it only in `server/.env` or the deployment secret manager:

```text
AI_ENABLED=true
OPENAI_API_KEY=sk-...
OPENAI_MODEL=gpt-5.6-terra
OPENAI_MODERATION_MODEL=omni-moderation-latest
```

`gpt-5.6-terra` is the configurable default because it is the current balanced
GPT-5.6 model. Pin `OPENAI_MODEL` to a dated model snapshot after the prompt
evaluation set is approved if production behavior must remain fixed across
model updates.

The server manually supplies the bounded recent transcript and sets
`store: false` on every Responses API call. It does not use an OpenAI
Conversation object or `previous_response_id`, so Drip retains control of what
history is sent and can add an application-level deletion/retention policy
before persistent chat history is introduced.

Relevant official guidance:

- [Responses API and instruction hierarchy](https://developers.openai.com/api/docs/guides/text)
- [Structured Outputs](https://developers.openai.com/api/docs/guides/structured-outputs)
- [Conversation state and retention](https://developers.openai.com/api/docs/guides/conversation-state)
- [Safety best practices](https://developers.openai.com/api/docs/guides/safety-best-practices)
- [Production best practices](https://developers.openai.com/api/docs/guides/production-best-practices)

Forward Stripe events locally:

```sh
stripe listen --forward-to localhost:4242/v1/stripe/webhook
```

Copy the CLI's temporary `whsec_...` value into `.env`, restart the server, and
complete hosted Checkout with Stripe test card `4242 4242 4242 4242`, any
future expiration date, and any three-digit CVC.

## Authentication

Development mode intentionally represents the current fixed demo user:

```text
buyer ID: dev-alex
seller handle: @alexwears
```

That makes the server reject `nike-noir-runner`, `black-street-sneakers`, and
the sold `black-backpack` for this buyer.

For the Flutter app's Firebase Authentication accounts, configure the server
to verify the Firebase ID token attached to every protected API request.
Firebase Admin with Application Default Credentials is the preferred
production mode:

```text
AUTH_MODE=firebase
FIREBASE_PROJECT_ID=dripproject-24882
FIREBASE_AUTH_VERIFIER_MODE=application-default
FIREBASE_CREDENTIALS_MODE=application-default
ACCOUNT_AUTH_ENABLED=false
```

On Google-managed infrastructure, attach a least-privilege runtime service
identity. For local development or another host, set
`GOOGLE_APPLICATION_CREDENTIALS` to a secret-mounted service-account file.
The identity must be allowed to read Firebase Authentication users because the
server asks Firebase Admin to check token revocation and disabled-user state.
Never commit that file, copy it into Flutter, or paste it into an environment
value that is exposed to the client.

For local development or a self-hosted Auth-only server where a service-account
file is not available, use Firebase's documented `accounts:lookup` endpoint:

```text
AUTH_MODE=firebase
FIREBASE_PROJECT_ID=dripproject-24882
FIREBASE_AUTH_VERIFIER_MODE=rest-api-key
FIREBASE_WEB_API_KEY=<Web API key for the same Firebase project>
ACCOUNT_AUTH_ENABLED=false
```

This mode sends the exact bearer token to Firebase over HTTPS and accepts its
claims only after Firebase returns the current account. The server then
validates the response shape, stable UID, current email and verification
state, disabled state, project audience/issuer, expiry, and the account's
`validSince` revocation boundary against the token's `auth_time`. Responses are
time- and size-bounded, redirect following is disabled, and provider/network
failures fail closed. The Web API key is not a service-account credential:
never put a service-account private key in `FIREBASE_WEB_API_KEY`, and avoid
printing the configured key in logs or support output.

If Cloud Firestore is also selected, it still needs
`FIREBASE_CREDENTIALS_MODE=application-default` even when Authentication uses
`rest-api-key`.

Flutter signs up and signs in through the Firebase SDK, then sends the current
ID token as `Authorization: Bearer <Firebase ID token>`. The server verifies
the signature, project issuer/audience, expiry, revocation, disabled-user
state, stable Firebase UID, and `email_verified=true` before allowing catalog,
AI, seller, or Checkout access. An unverified account receives
`email_verification_required`; an expired, revoked, malformed, or wrong-project
token receives `invalid_token`.

Official Firebase references:

- [Firebase Auth REST API: get user data (`accounts:lookup`)](https://firebase.google.com/docs/reference/rest/auth#section-get-account-info)
- [Firebase ID-token claim validation](https://firebase.google.com/docs/auth/admin/verify-id-tokens)
- [Manage sessions and token revocation](https://firebase.google.com/docs/auth/admin/manage-sessions)

Firebase's normal verification-link flow remains the default. An optional
server-issued six-digit code can be enabled without turning on Drip's legacy
JWT/SQLite accounts:

```text
AUTH_MODE=firebase
ACCOUNT_AUTH_ENABLED=false
FIREBASE_AUTH_VERIFIER_MODE=application-default
FIREBASE_CREDENTIALS_MODE=application-default
FIREBASE_EMAIL_CODE_ENABLED=true
FIREBASE_EMAIL_CODE_SECRET=<dedicated random secret of at least 32 bytes>
EMAIL_PROVIDER=resend
RESEND_API_KEY=re_...
WELCOME_EMAIL_FROM=Drip <accounts@verified-sender.example>
GOOGLE_APPLICATION_CREDENTIALS=/run/secrets/drip-firebase-service-account.json
```

The Resend account must have the sender domain verified. Its DNS should have
the SPF and DKIM records Resend supplies, plus an appropriate DMARC policy.
`WELCOME_EMAIL_FROM` is the existing shared transactional-email sender setting;
it is also used for confirmation-code messages. Keep the API key, Firebase
credential, and code secret in the deployment secret manager—not in Flutter,
source control, or support messages.

This feature is deliberately unavailable with REST API-key token verification:
the server must have Firebase Admin `getUser` and `updateUser` access so it can
re-read the current UID/email and set `emailVerified: true`. Startup fails if
the feature is enabled without Firebase Admin, Resend, a valid sender, or the
dedicated HMAC secret.

Only these narrow endpoints accept a current unverified Firebase ID token:

```text
POST /v1/auth/firebase/email-code/request   body: {}
POST /v1/auth/firebase/email-code/verify    body: {"code":"123456"}
```

Both require `Authorization: Bearer <Firebase ID token>`. UID and email are
never accepted from the request body; they are reloaded from Firebase Admin.
The database stores only a keyed HMAC digest of the code. Codes expire after
ten minutes, rotate on resend, allow five guesses, and are protected by a
per-UID cooldown plus UID/IP request and attempt windows. On a correct code,
the Admin update writes the exact email that received the code together with
`emailVerified: true`; the client must then force-refresh its ID token.
Catalog, AI, seller, and Checkout routes still require
`email_verified=true` at all times.

Optional bounds can be adjusted with
`FIREBASE_EMAIL_CODE_TTL_SECONDS`,
`FIREBASE_EMAIL_CODE_RESEND_COOLDOWN_SECONDS`,
`FIREBASE_EMAIL_CODE_RESEND_LIMIT_PER_HOUR`,
`FIREBASE_EMAIL_CODE_IP_REQUEST_LIMIT_PER_HOUR`,
`FIREBASE_EMAIL_CODE_ATTEMPT_LIMIT_PER_15_MINUTES`, and
`FIREBASE_EMAIL_CODE_MAX_ATTEMPTS`.

In Firebase mode, `/v1/auth/signup`, `/v1/auth/login`, and the built-in
challenge-token verification endpoints remain intentionally unused.
Email/password creation, password reset, token refresh, and sign-out are owned
by Firebase Authentication in Flutter. `GET /v1/auth/session` remains
available as a server-side check for a current verified Firebase bearer token.

The built-in signup/login service is opt-in. Enabling it requires JWT mode and
a real server-side email provider:

```text
AUTH_MODE=jwt
JWT_HS256_SECRET=<32+ byte secret>
JWT_ISSUER=https://identity.example.com
JWT_AUDIENCE=drip-app
ACCOUNT_AUTH_ENABLED=true
AUTH_VERIFICATION_CODE_TTL_SECONDS=600
AUTH_VERIFICATION_RESEND_COOLDOWN_SECONDS=60
AUTH_VERIFICATION_RESEND_LIMIT_PER_HOUR=5
AUTH_VERIFICATION_ATTEMPT_RATE_LIMIT_PER_15_MINUTES=20
AUTH_PENDING_ACCOUNT_TTL_SECONDS=86400
EMAIL_PROVIDER=resend
RESEND_API_KEY=re_...
WELCOME_EMAIL_FROM=Drip <welcome@your-verified-domain.example>
```

Resend requires a verified sending domain. Its API key and the JWT/rate-limit
secrets belong only in `server/.env` or the deployment secret manager. See the
[Resend send-email API](https://resend.com/docs/api-reference/emails/send-email)
for provider setup.

Signup requires a display name, email, and password. Names are Unicode
normalized, whitespace-trimmed/collapsed, and limited to 80 characters. Email
is normalized before the unique insert. Passwords must contain 12–128
characters, avoid common/account-derived values and control characters, and use
at least three of lowercase, uppercase, numbers, and symbols. The password
itself is not normalized or trimmed.

Signup first creates an unverified pending record and asks Resend to accept a
confirmation email. Provider acceptance does not prove inbox delivery. The
client receives a high-entropy `challengeToken` only in memory and submits it
with the emailed code; it receives no user or bearer session before successful
confirmation. Repeating the same pending signup rotates the challenge only
after the submitted password matches the pending password hash. Unverified
records older than 24 hours are replaceable so an abandoned request cannot
reserve an address forever.

Passwords use Node's stable asynchronous scrypt with a random 16-byte salt and
`N=2^15`, `r=8`, `p=3`. This is one of the minimum-equivalent configurations in
the current [OWASP Password Storage Cheat
Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Password_Storage_Cheat_Sheet.html).
Node 24 includes Argon2id, but its API is still marked release-candidate; the
service deliberately uses the stable built-in scrypt primitive until Argon2id
stabilizes, then hashes can be version-migrated on successful login.

Built-in account tokens contain a random `sid`/`jti`. Every protected request,
including checkout and Drip AI, verifies the signature, issuer, audience,
expiry, active account, unexpired session, and revocation state. Logout revokes
that session immediately.

The verifier also remains compatible with an external HS256 identity service.
Such a bearer token has:

- `sub`: stable buyer ID
- `iss`: configured issuer
- `aud`: configured audience
- `exp`: future expiration
- optional `seller_handle`: used to block buying one's own listing

An external token without `sid` is signature/claim verified as before, but it
cannot use the built-in session/logout endpoints. Replace the interim HS256
adapter with the provider's asymmetric JWKS verifier when an external identity
provider is selected.

## API

### Health

```http
GET /healthz
```

### Create an account

```http
POST /v1/auth/signup
Content-Type: application/json

{"name":"Jordan Lee","email":"member@example.com","password":"A-strong-passphrase!2026"}
```

An accepted request returns `202` with no user or session:

```json
{"verification":{"email":"member@example.com","expiresAt":"2026-07-20T19:10:00.000Z","resendAvailableAt":"2026-07-20T19:01:00.000Z","challengeToken":"<opaque one-time signup challenge>"}}
```

The response means the email provider accepted the request, not that the email
was delivered to the inbox. Unknown fields are rejected. A repeated pending
signup must prove the same password before it can rotate the challenge.

### Confirm an email

```http
POST /v1/auth/verify-email
Content-Type: application/json

{"challengeToken":"<opaque signup challenge>","code":"042917"}
```

Successful confirmation returns the public user, bearer session and expiry,
plus the welcome outbox status. A wrong, expired, exhausted, or already-used
code returns the same `invalid_verification_code` response.

```http
POST /v1/auth/resend-verification
Content-Type: application/json

{"challengeToken":"<opaque signup challenge>"}
```

Resend returns `202` with the same verification envelope and a rotated code.
Cooldown and hourly limits return `429` with `Retry-After`.

### Log in

```http
POST /v1/auth/login
Content-Type: application/json

{"email":"member@example.com","password":"A-strong-passphrase!2026"}
```

Bad credentials always return the same `invalid_credentials` response. Signup
and login limits return `429` with `Retry-After`.

### Verify or end a session

```http
GET /v1/auth/session
Authorization: Bearer <access token>
```

```http
POST /v1/auth/logout
Authorization: Bearer <access token>
```

Logout accepts an empty body and revokes only the presented session. The old
token is rejected immediately by account, catalog, checkout, and AI routes.

### Authoritative catalog

```http
GET /v1/catalog
Authorization: Bearer <token in production>
```

The response comes from SQLite by default or `marketplace_listings` in
Firestore when that provider is explicitly selected. `/healthz` reports the
active `databaseProvider`.

### Create Checkout

```http
POST /v1/checkout/sessions
Content-Type: application/json
Idempotency-Key: attempt_92f3c09a50f14114
Authorization: Bearer <token in production>

{
  "attemptId": "attempt_92f3c09a50f14114",
  "items": [
    {"listingId": "nike-red-court", "selectedSize": "9"},
    {"listingId": "white-heavy-tee", "selectedSize": "M"}
  ]
}
```

Do not send price, quantity, seller, shipping, fee, currency, or redirect URL.
Unknown item fields are rejected.

Response:

```json
{
  "orderId": "ord_...",
  "sessionId": "cs_test_...",
  "url": "https://checkout.stripe.com/...",
  "expiresAt": "2027-01-15T08:31:00.000Z",
  "status": "open",
  "quote": {
    "currency": "usd",
    "merchandiseSubtotalCents": 13000,
    "buyerProtectionCents": 499,
    "shippingCents": 1398,
    "taxCents": 0,
    "totalCents": 14897
  }
}
```

`checkoutSessionId` and `checkoutUrl` compatibility aliases are also returned.

### Read status

```http
GET /v1/checkout/sessions/{sessionId}
Authorization: Bearer <token in production>
```

Status values are `creating`, `open`, `processing`, `paid`, `expired`,
`canceled`, `payment_failed`, and `payment_review`.

### Explicitly expire

```http
POST /v1/checkout/sessions/{sessionId}/expire
Content-Type: application/json
Authorization: Bearer <token in production>

{"attemptId":"attempt_92f3c09a50f14114"}
```

Stripe must confirm expiration before the reservation is released. An empty JSON
body is accepted, but Flutter sends the attempt ID as an additional guard.

### Seller Stripe Connect

All seller routes require the built-in bearer session. Seller identity and the
connected-account ID are resolved from the database; clients cannot submit an
account ID or seller handle.

```http
GET /v1/seller/connect/status
Authorization: Bearer <token>
```

The response reports `not_started`, `onboarding_incomplete`,
`verification_pending`, `restricted`, or `ready`, plus the current recipient
transfer and payout capability states. `ready` requires both capabilities to be
active and no currently-due or past-due user requirements.

```http
POST /v1/seller/connect/onboarding
Authorization: Bearer <token>
Content-Type: application/json

{}
```

This creates or retrieves the seller's one recipient account and returns a
short-lived `https://accounts.stripe.com/...` Account Link and `expiresAt`.
Open the URL in the system browser, never an embedded WebView. If Stripe sends
the browser to the configured refresh page, the seller must return to Drip and
request another link while authenticated.

```http
POST /v1/seller/connect/dashboard
Authorization: Bearer <token>
Content-Type: application/json

{}
```

This returns a validated Express Dashboard login URL and a conservative local
expiry. Drip never stores either Stripe-hosted URL.

### Stripe Connect webhook

```http
POST /v1/stripe/connect-webhook
Stripe-Signature: ...
```

Configure this as a separate v2 thin-event destination for recipient
capability, requirements, account update, and account closure events. The
service verifies the separate signing secret, rejects live/test mixing,
retrieves the latest Account from Stripe, and applies replay-safe database
updates. The ordinary Checkout webhook secret must not be reused.

### Stripe webhook

```http
POST /v1/stripe/webhook
Stripe-Signature: ...
```

The configured Stripe destination should send only:

- `checkout.session.completed`
- `checkout.session.async_payment_succeeded`
- `checkout.session.async_payment_failed`
- `checkout.session.expired`

The raw body limit is 256 KiB. The official Stripe SDK verifies its signature
before JSON is trusted. Failed processing returns a retryable non-2xx response;
replayed event IDs are safe.

### Drip AI chat

```http
POST /v1/ai/chat
Content-Type: application/json
Authorization: Bearer <token in production>
```

```json
{
  "message": "Build me a clean basketball fit under $150.",
  "history": [
    {"role":"user","content":"I prefer a simple palette."},
    {"role":"assistant","content":"I’ll keep the colors focused."}
  ],
  "context": {
    "entryPoint": "home",
    "focusProductId": "nike-red-court",
    "cart": [{"listingId":"nike-red-court","selectedSize":"9"}],
    "savedListingIds": ["white-heavy-tee"],
    "cartSubtotalCents": 9200,
    "cartTotalCents": 10366,
    "checkoutStatus": null,
    "sellerPro": false
  }
}
```

The context prices, checkout status, and Pro flag are accepted only for a
stable Flutter contract; they are never trusted. The server rehydrates catalog
prices, availability, the buyer's latest order status, and seller state from
SQLite.

Response:

```json
{
  "reply": "Start with the court shoe and keep the rest of the palette clean.",
  "intent": "outfit",
  "followUps": ["Would you like a lightweight or heavyweight layer?"],
  "productIds": ["vans-black-canvas", "cloud-practice-tee", "blue-denim-jeans"],
  "outfit": {
    "title": "Clean Everyday Rotation",
    "rationale": "The canvas footwear, clean tee, and relaxed denim create a balanced everyday silhouette.",
    "productIds": ["vans-black-canvas", "cloud-practice-tee", "blue-denim-jeans"],
    "subtotalCents": 11000,
    "budgetCents": 15000
  },
  "needsHumanSupport": false
}
```

Intents are `outfit`, `discovery`, `sizing`, `checkout`, `orders`, `seller`,
`general`, and `safety`. The server recomputes outfit subtotal and budget,
rejects unknown or unavailable listing IDs, and returns `429` with
`Retry-After` when a buyer reaches the configured limit.

`budgetCents` means the user's maximum estimated checkout total before tax,
not merely merchandise. In the example above, the server also verifies the
$4.99 protection amount and two $6.99 seller packages, producing a $128.97
estimated total before accepting the $150 outfit budget. The response keeps
`subtotalCents` as merchandise so Flutter can show it alongside its own
server-backed fee breakdown.

## Production runbook

Before enabling live mode:

1. Put the SQLite transaction ledger on an encrypted, backed-up persistent
   volume and test restore. If Firestore supplies the marketplace catalog,
   deploy the deny-all rules, set least-privilege IAM, enable backups/PITR as
   appropriate, and verify the startup credential probe.
2. Configure exact HTTPS success/cancel URLs and exact CORS origins.
3. Configure Firebase token verification for the production project. Prefer
   Firebase Admin with a least-privilege runtime identity; use the documented
   REST verifier only for an Auth-only deployment without Admin credentials.
   Confirm that unverified, disabled, expired, and revoked accounts all fail
   closed before exposing protected routes.
4. Enable Accounts v2 for the Connect platform, configure the authenticated
   recipient onboarding flow, and test incomplete, restricted, and ready
   seller states. The server persists readiness only after retrieving Stripe's
   current transfer, payout, and requirements state.
5. Keep `REQUIRE_CONNECT_PAYOUTS=true` in production. The service forces this
   setting even if the environment says otherwise.
6. Configure tax, refunds, disputes, shipping, prohibited-item controls, and
   customer support before accepting money.
7. Create separate Checkout and Connect event destinations, select only the
   documented events, and keep both signing secrets in a secret manager.
8. Add a settlement worker with idempotent Transfers, delivery/claim holds,
   refund transfer reversals, and reconciliation before paying sellers.
9. Alert on `payment_review`, failed webhook rows, stale reservations, and any
   seller ledger held beyond policy.
10. Exercise duplicate webhook delivery, an API timeout after Session creation,
    payment at the expiration boundary, refunds, restore, and incident rollback
    in Stripe test mode.

If Session creation fails ambiguously, its reservation remains protected until
the persisted expiry. A later checkout sweep expires only a stale `creating`
order with no stored Session. If Stripe subsequently reports a captured payment,
the inventory guard routes it to refund-required review instead of overselling.

## Tests

```sh
npm test
npm run test:coverage
```

Tests use injected fake Stripe, AI, email, and Firestore clients and make no
external network calls or payments. They cover Firestore configuration,
credential/readiness failure, catalog field validation and allowlisting,
normalized unique accounts, salted
password hashes, hashed confirmation challenges/codes, expiry, replay, five
attempt exhaustion, resend rotation/cooldown/rate limits, provider failure,
abandoned pending-account recovery, crash-safe legacy migration, generic login
failures, revocable sessions, honest one-time welcome acceptance, fee math, the
whole catalog seed, multi-seller
shipping/payables, tampered client prices, ownership, sold inventory,
idempotent retries, webhook replay, expiration, late events, captured-payment
review, CORS, and the HTTP contract.
