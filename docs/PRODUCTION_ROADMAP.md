# Production roadmap

## Current platform architecture

Flutter sends only listing IDs, selected sizes, and a stable attempt ID to the
checkout service. The service owns inventory, prices, fees, shipping, order
state, and Stripe credentials. It reserves one-of-one listings in the
transactional database, creates a Stripe-hosted Checkout Session, and fulfills
only after a signed webhook confirms payment. The browser return screen polls
the server; a redirect alone can never create an order.

The app persists a resumable Session reference before opening Stripe and keeps
the cart locked until payment is confirmed, canceled, failed, or expired. Paid
orders are cached locally only after server confirmation. Signed-in sellers can
create an Accounts v2 recipient, complete Stripe-hosted onboarding, see current
transfer/payout capability status, and open a short-lived Express Dashboard
link. Displayed local earnings are not presented as a Stripe balance or payout.

The API has an explicit marketplace provider boundary. SQLite supplies
deterministic local/test catalog data; the production Firestore option uses the
Firebase Admin SDK, validates every catalog document, performs a bounded
startup connectivity check, and fails closed when its project or credentials
are absent.

The native iOS and Android app is connected to Firebase project
`dripproject-24882`. Firebase Authentication owns email/password and Google
sign-in, default verification-link delivery, password reset, persistent
sign-in, and ID-token refresh. A separate optional six-digit code service now
binds each code to the current Firebase UID/email and can mark that exact email
verified through Firebase Admin; it remains off until a verified sender,
secret-managed email key, Admin runtime identity, and HTTPS deployment exist.
The Drip API accepts only a current, email-verified Firebase bearer token for
every other protected route. Local/self-hosted Auth-only verification can use
Firebase's official `accounts:lookup` endpoint with the matching Web API key.
Reservations, orders, webhook idempotency, and payables remain in SQL. The
SQL-backed JWT account service remains optional legacy compatibility, not a
requirement for the app.

## Production gates

### Platform foundation

- Connect every remaining client-owned seller mutation and marketplace screen
  to authenticated server repositories. The authoritative catalog read and
  checkout inventory boundaries are in place.
- Attach least-privilege Firebase Admin Application Default Credentials to the
  production API runtime, populate reviewed Firestore records, and exercise
  both Firebase token verification and the Firestore provider in staging.
- Keep `AUTH_MODE=firebase` and `ACCOUNT_AUTH_ENABLED=false` for the app.
  Add explicit admin/support authorization claims and policies before those
  tools exist.
- Verify an owned transactional-email domain with SPF/DKIM and DMARC, deploy
  the API with Firebase Admin plus a secret-managed provider key/code secret,
  and only then opt the Flutter build into numeric codes.
- Replace Android debug release signing, register the upload and Play
  App Signing SHA fingerprints with Firebase, and run a physical-device Google
  login. Review Apple’s login-services rule before App Store submission.
- Use server-generated IDs, timestamps, fee-policy versions, and idempotency
  keys.
- Move seller-created listing publication into an authenticated server API.
- Store product media in object storage with moderation and transformation.
- Remove demo-mode defines from production builds and test empty/unavailable
  states so missing provider data never falls back to a fabricated catalog.

### Money movement

- Configure and deploy the implemented Stripe-hosted Checkout and signed
  webhook endpoints with test-mode keys first, then complete live-mode review.
- Add Stripe Tax (or an explicit tax policy), refund/dispute handlers, transfer
  reversals, and a full double-entry general ledger.
- Validate the implemented Stripe Connect onboarding and capability checks
  against real test-mode recipient accounts, then add settlement holds and the
  idempotent separate-transfer worker. Current seller payables are held in the
  ledger and are not automatically transferred.
- Make Pro and boost entitlements server-authoritative and restorable.
- Reconcile the internal payable ledger against Stripe balances and events
  before any automated transfer.

### Marketplace operations

- Add shipping labels, tracking events, seller deadlines, delivery confirmation,
  and claim windows.
- Add persistent offers, reservations, messaging, push notifications, and abuse
  controls.
- Add explicit authenticity states and only show verification after a completed
  operational process.
- Add content moderation, prohibited-goods policy, seller enforcement, and
  customer-support tooling.

### Acquisition diligence

- Configure production-owned bundle IDs, signing teams, store accounts, domains,
  privacy policy, terms, and support contacts.
- Add analytics consent, event definitions, retention cohorts, and auditable KPI
  dashboards.
- Add repository CI, dependency scanning, secret management, backups, restore
  drills, incident response, and service-level objectives.
- Load-test concurrent checkout, inventory reservation, payout reconciliation,
  Firestore catalog reads, and webhook replay.

### Product proof

- Complete one real staging journey: Google login/logout, Firebase
  email/password signup, verification-link open or sender-backed code entry,
  ID-token refresh, password reset, session restore, Firestore catalog, AI
  outfit, Stripe test checkout, webhook-confirmed order, logout, and an
  independently revoked-token rejection.
- Define the first narrow seller/buyer cohort and recruit enough quality supply
  to make discovery useful without generic template inventory.
- Instrument funnel and issue-free-order metrics before claiming traction.
- Validate the fee model and support workload with reconciled transactions.

## Release rule

Firebase Authentication is connected for the native app; the repository is
ready for staging integration across the deployed Drip API, Firestore, OpenAI,
and Stripe test mode. It is not automatically connected to Stripe/OpenAI
production accounts or production hosting. Do not enable live Stripe keys
until HTTPS deployment, Firebase server verification, Firestore acceptance
testing, real-account Connect testing, authenticated seller publication,
tax/refund/dispute operations, observability, and the remaining money-movement
gates above are complete.
