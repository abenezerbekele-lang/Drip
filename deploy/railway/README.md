# Railway Stripe sandbox deployment

Railway is the quickest safe target for an online Drip **staging** API with the
current code. The checked-in `railway.json` selects the Node 24 Docker image,
waits for `/healthz`, drains on `SIGTERM`, and prevents deployment overlap.

This remains a single-writer SQLite service. Keep exactly one replica in one
region and attach exactly one Railway Volume at `/data` before making any test
purchase. Set `DATABASE_PATH=/data/drip.sqlite`. Railway prevents two
deployments with an attached volume from being active simultaneously, so
updates have a short downtime instead of two SQLite writers.

## Required service setup

1. Create one persistent Railway service from this repository.
2. Attach a Volume to that service with mount path `/data`.
3. Keep the replica count at **1** and do not enable multi-region scaling.
4. Add the variables from `staging.env.example` in Railway Variables. Railway
   supplies `PORT`; do not hard-code it.
5. Generate a stable public Railway HTTPS domain.
6. Replace `YOUR_RAILWAY_DOMAIN` and `YOUR_WEB_APP_DOMAIN` in the variables
   with the exact real hosts.
7. Add the current Firebase Web API key for project `dripproject-24882` as
   `FIREBASE_WEB_API_KEY`. This Auth-only deployment uses Firebase's official
   account lookup verifier and does not need a service-account private key.
8. Add a Stripe **sandbox/test** restricted or secret server key as
   `STRIPE_SECRET_KEY` and the sandbox event destination's separate signing
   secret as `STRIPE_WEBHOOK_SECRET`.

The volume is mounted as root. `Dockerfile.railway` starts a minimal bootstrap
as root only long enough to secure `/data`, then permanently drops to UID/GID
1000 before loading the HTTP server. The service refuses to continue as root.
No local `.env`, SQLite file, Flutter asset, or credential is copied into the
image.

## Stripe event destination

Create one sandbox event destination at:

```text
https://YOUR_RAILWAY_DOMAIN/v1/stripe/webhook
```

Subscribe only to:

- `checkout.session.completed`
- `checkout.session.async_payment_succeeded`
- `checkout.session.async_payment_failed`
- `checkout.session.expired`

The `whsec_...` value belongs only in Railway Variables. Do not confuse it
with the `sk_test_...`/`rk_test_...` API key and do not reuse it for Stripe
Connect.

After deployment, `/healthz` must show:

```json
{
  "status": "ok",
  "paymentsConfigured": true,
  "accountAuthConfigured": true,
  "authProvider": "firebase",
  "databaseProvider": "sqlite"
}
```

## Current approved test deployment

The connected Stripe sandbox service is available at:

```text
https://drip-api-production.up.railway.app
```

Railway calls its default environment `production`, but Drip runs it with
`DEPLOYMENT_STAGE=staging`, Stripe test credentials, Connect disabled, and no
live-charge capability. Launch the connected iOS build with:

```sh
flutter run -d <simulator-id> \
  --dart-define=DRIP_API_URL=https://drip-api-production.up.railway.app
```

For an owner-controlled verification pass, sign in to a verified Firebase
test account on that simulator, then run:

```sh
flutter test integration_test/stripe_staging_smoke_test.dart \
  -d <simulator-id> \
  --dart-define=DRIP_API_URL=https://drip-api-production.up.railway.app
```

The smoke test creates a Stripe-hosted sandbox Session, validates its
server-priced quote, and immediately expires it to release the one-of-one
inventory reservation. Confirm `checkout.session.expired` is delivered with
HTTP `200` in Stripe Workbench.

Then complete one Stripe test checkout and confirm the signed webhook changes
the order to `paid`. Replay the same event to prove it remains one order and
one inventory sale. A browser redirect by itself is never payment proof.

## Important limits

- This configuration intentionally disables Connect and seller payouts so the
  existing demonstration sellers do not block a sandbox checkout.
- Keep the Firebase six-digit email-code service disabled here. The REST
  verifier cannot update `emailVerified`; normal Firebase verification links
  and Google sign-in continue to work.
- Enable Railway volume backups and perform a restore test. Never download or
  copy only `drip.sqlite` while its WAL may contain committed transactions.
- Railway's deployment healthcheck runs during deployment, not as continuous
  monitoring. Add an independent uptime check and alerts before wider testing.
- Do not switch this service to live Stripe keys. Tax, refunds, disputes,
  shipping, transfers, reconciliation, real seller inventory, support, and
  operational monitoring remain launch blockers.
