# Drip

Drip is a mobile-first fashion resale marketplace built with Flutter. It pairs
editorial discovery, one-of-one listings, seller tools, an AI styling
concierge, verified accounts, and Stripe-hosted checkout in one branded
experience.

The repository contains a Flutter client and a Node.js service. Firebase
Authentication owns credentials, verification links, password recovery, and
native sessions. The service independently verifies Firebase ID tokens and is
the security boundary for AI, pricing, inventory reservations, payments,
webhooks, and seller payout readiness.

## Requirement status

| Requirement | Repository status | External activation still required |
| --- | --- | --- |
| Firebase accounts | Native iOS/Android Firebase email/password accounts, Google sign-in, verification links, token refresh, password recovery, and server token verification are connected to `dripproject-24882`. The Railway sandbox API verifies current Firebase accounts through the official Auth REST boundary. A separate Firebase-safe six-digit code path is implemented but off by default | Numeric codes require Firebase Admin plus a verified transactional-email sender; release signing and store-provider requirements still need owner completion |
| Firebase database | Firestore production-provider support for the catalog; local/test operation remains available | Owner-controlled Admin credentials are required only when Firestore is selected |
| Stripe payments | Stripe sandbox Checkout is online on Railway with a restricted test key, signed event destination, exact server pricing, inventory reservations, and resumable returns | Live mode remains blocked until tax, refunds, disputes, seller payouts, reconciliation, support, monitoring, and real inventory operations are complete |
| Profile, login, logout | Profile UI, Firebase signup, Google sign-in/sign-up, email-link or optional code verification, password reset, persistent sessions, sign-in, and sign-out | Register production Android/Play signing fingerprints before release; App Store submission may also require an equivalent Sign in with Apple option |
| Production website | Source and deployment package in [`website/`](website/) | Final hosted URL pending deployment, plus production API/domain configuration |
| No template data | Production catalog data is selected through the server provider boundary; demo mode is explicit | Real approved listings in the production Firestore project |
| README | This file | Nothing |
| Business Model Canvas | [`docs/BUSINESS_MODEL.md`](docs/BUSINESS_MODEL.md) | Validate assumptions with real customers |
| Technical documentation | [`docs/TECHNICAL_DOCUMENTATION.md`](docs/TECHNICAL_DOCUMENTATION.md) | Keep it current as infrastructure changes |
| Six-slide pitch deck | [`deliverables/drip_pitch_deck.pptx`](deliverables/drip_pitch_deck.pptx) | Presenter rehearsal |
| Two-minute demo video | [`deliverables/drip_demo_2min.mp4`](deliverables/drip_demo_2min.mp4) | Replace test-mode footage after production activation if desired |

“Implemented” does not mean “connected to every live owner provider.” This
repository contains no Firebase service-account credential, transactional
email key, Stripe secret, or OpenAI key. Server secrets must be supplied
through a deployment secret manager.

## Product capabilities

- Responsive discovery, market, saved, cart, messaging, selling, rankings,
  profile, and Seller Studio experiences.
- One-of-one inventory with live, paused, reserved, and sold states.
- Multi-seller carts with itemized buyer protection, per-seller shipping, and
  integer-cent totals.
- Stripe-hosted Checkout; Drip never renders card fields or handles raw card
  numbers.
- Server-created Checkout Sessions, 31-minute reservations, idempotent retries,
  signed webhook confirmation, and resumable checkout state.
- Stripe Connect recipient onboarding, capability synchronization, and
  short-lived Express Dashboard links.
- Firebase email/password signup with ownership verification, Google
  sign-in/sign-up, enumeration-safe login and password recovery, automatic
  ID-token refresh, secure logout, and encrypted device session storage.
- Optional six-digit Firebase email verification that binds codes to the
  current Firebase UID/email, stores only an HMAC digest, expires and
  rate-limits challenges, and requires Firebase Admin plus a verified sender.
- Drip Concierge for outfit building, fit, dress codes, garment care, unusual
  styling questions, and catalog-aware recommendations.
- Seller listings, fulfillment views, payouts readiness, promotions, Drip Pro,
  and clearly labeled planning metrics.
- Light and dark themes with adaptive phone, tablet, desktop, and web layouts.

## Project map

```text
drip/
├── lib/                 Flutter application
│   ├── auth/            Firebase signup, verification, recovery, sessions
│   ├── assistant/       AI request/response contracts
│   └── payments/        Checkout and Stripe Connect gateways
├── server/
│   ├── src/             Auth, data, AI, checkout, Connect, HTTP service
│   └── test/            Server acceptance and security tests
├── test/                Flutter unit and widget tests
├── docs/                Business, technical, and launch documentation
└── assets/              Product and editorial imagery
```

## Quick start: local product preview

Prerequisites:

- Flutter compatible with Dart `^3.12.2`
- Node.js `24.12.0` or newer for the service

Run the client:

```sh
flutter pub get
flutter run
```

The checked-in native Firebase configuration provides real account creation,
Google sign-in, verification links, email/password sign-in, and password
recovery. A build without a connected Drip API cannot use server-backed
catalog, AI, seller, or payment features. Demo mode appears only when
explicitly enabled with `DRIP_ENABLE_DEMO_MODE=true`.

## Run the connected local stack

Create the service configuration and install dependencies:

```sh
cd server
cp .env.example .env
npm install
npm start
```

In another terminal, point Flutter to that service:

```sh
flutter run \
  --dart-define=DRIP_API_URL=http://localhost:4242
```

For the iOS Simulator, `scripts/run_connected_ios.sh <device-id>` performs the
configuration check, starts the local API when needed, verifies that accounts
and Stripe are ready, and launches Flutter with the correct loopback API URL.
It never prints provider secrets. Run
`node scripts/check_connected_services.mjs` first when diagnosing a connection;
Firebase owns the account form in the app. The API health checks must pass
before authenticated catalog, AI, seller tools, and Checkout are enabled.

The server starts without third-party keys, but protected features report
themselves unavailable until their readiness requirements are met. That is an
intentional fail-closed state.

## Connect the Firebase catalog

SQLite remains the local/test provider and transactional payment ledger. To
use the server-only Firestore catalog in staging or production:

```text
MARKETPLACE_DATABASE_PROVIDER=firestore
FIREBASE_PROJECT_ID=your-project-id
FIREBASE_CREDENTIALS_MODE=application-default
FIREBASE_CONNECT_TIMEOUT_MS=10000
```

On Google-hosted infrastructure, attach a least-privilege workload identity.
Elsewhere, set `GOOGLE_APPLICATION_CREDENTIALS` to a secret-mounted
service-account file. Never commit that file or ship it with Flutter.

The provider reads validated documents from `marketplace_listings` and probes
`_drip_system/connectivity` during startup. Missing, denied, or unreachable
credentials stop startup; Drip does not silently show SQLite/demo data.
Repository Firestore rules deny all direct browser/mobile access because the
intended path is Flutter → Drip API → Firebase Admin.

## Connect signup, Google sign-in, and email verification

The Flutter app creates accounts with Firebase Authentication and sends
Firebase's secure verification link. Email/Password sign-in must be enabled in
Firebase for project `dripproject-24882`. Google sign-in is also enabled in
that project, and the checked-in iOS URL scheme plus Android debug signing
fingerprints match their native OAuth clients. Configure the API to trust only
verified Firebase ID tokens:

```text
AUTH_MODE=firebase
FIREBASE_PROJECT_ID=dripproject-24882
FIREBASE_CREDENTIALS_MODE=application-default
ACCOUNT_AUTH_ENABLED=false
```

On Google-managed hosting, attach a least-privilege runtime service identity.
For local or other hosting, set `GOOGLE_APPLICATION_CREDENTIALS` to a
secret-mounted service-account file. Never commit that file or ship it in the
Flutter app. The app remains signed out until Firebase reports the email as
verified, and the API checks verification, expiry, revocation, and disabled
account state before serving protected routes.

Firebase verification links remain the default and work without the Drip API.
The optional six-digit flow uses the same Firebase account—not the legacy JWT
account system—and is enabled only when all server-side delivery and Admin
requirements are present:

```text
FIREBASE_AUTH_VERIFIER_MODE=application-default
FIREBASE_EMAIL_CODE_ENABLED=true
FIREBASE_EMAIL_CODE_SECRET=<random 32+ byte server secret>
EMAIL_PROVIDER=resend
RESEND_API_KEY=<secret>
WELCOME_EMAIL_FROM=Drip <accounts@your-verified-domain.example>
```

The deployed Flutter build must also opt into that server capability with
`--dart-define=DRIP_FIREBASE_EMAIL_CODE_ENABLED=true` and an HTTPS
`DRIP_API_URL`. The current local configuration intentionally leaves numeric
codes off because no verified sender or Firebase Admin deployment identity has
been supplied. Gmail and Yahoo are supported recipient domains; they do not
need special client integrations. Inbox shortcuts are available on both link
and code screens.

Before an Android release, replace debug signing and register both upload and
Play App Signing SHA fingerprints in Firebase, then refresh
`android/app/google-services.json`. Before App Store submission, review
Apple’s login-services rule and add Sign in with Apple if the app does not
qualify for an exception.

## Connect Stripe Checkout

Configure Stripe in `server/.env`:

```text
STRIPE_SECRET_KEY=sk_test_...
STRIPE_WEBHOOK_SECRET=whsec_...
CHECKOUT_SUCCESS_URL=https://app.example.com/?stripe_session_id={CHECKOUT_SESSION_ID}
CHECKOUT_CANCEL_URL=https://app.example.com/cart
```

For local testing, forward Stripe events:

```sh
stripe listen --forward-to localhost:4242/v1/stripe/webhook
```

Use the CLI-provided webhook secret, restart the server, and complete Checkout
with a Stripe test card. The browser return alone never creates an order; only
a verified webhook can confirm payment.

Seller onboarding additionally requires:

```text
STRIPE_CONNECT_ENABLED=true
STRIPE_CONNECT_WEBHOOK_SECRET=whsec_...
CONNECT_ONBOARDING_RETURN_URL=https://app.example.com/connect/return
CONNECT_ONBOARDING_REFRESH_URL=https://api.example.com/connect/onboarding/refresh
```

Checkout and Connect use separate webhook signing secrets.

## Connect Drip Concierge

OpenAI credentials remain server-side:

```text
AI_ENABLED=true
OPENAI_API_KEY=<restricted project key>
OPENAI_MODEL=gpt-5.6-terra
OPENAI_MODERATION_MODEL=omni-moderation-latest
```

The server moderates requests, supplies trusted catalog and policy context,
requests structured output, and validates returned listings and totals. It
sets `store: false` and rejects likely payment-card or credential data before a
model request.

## Build for production

Release builds require an explicit HTTPS API:

```sh
flutter build web --release \
  --dart-define=DRIP_API_URL=https://api.your-domain.example
```

Do not enable `DRIP_ENABLE_DEMO_MODE` in a production build. Configure the
production data provider, load approved catalog records, use exact CORS
origins, and verify `/healthz` before deployment.

## Quality checks

```sh
flutter analyze
flutter test
cd server && npm test
flutter build web --release
flutter build macos --release
flutter build ios --release --no-codesign
```

## Launch truth

Drip has production-oriented boundaries, not an unattended permission to
accept live money. Before a public launch, the owner must deploy the API over
HTTPS; activate and test OpenAI, Stripe Checkout, and Stripe Connect in
accounts they control; complete tax, refunds, disputes, shipping, support,
monitoring, privacy, and legal operations; and run an end-to-end test-mode
purchase.

Read next:

- [`docs/TECHNICAL_DOCUMENTATION.md`](docs/TECHNICAL_DOCUMENTATION.md)
- [`docs/BUSINESS_MODEL.md`](docs/BUSINESS_MODEL.md)
- [`docs/REQUIREMENTS_CHECKLIST.md`](docs/REQUIREMENTS_CHECKLIST.md)
- [`docs/PRODUCTION_ROADMAP.md`](docs/PRODUCTION_ROADMAP.md)
- [`server/README.md`](server/README.md)
# Drip
