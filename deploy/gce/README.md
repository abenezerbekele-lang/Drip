# Drip API staging host

This is a deliberately single-writer deployment for the current SQLite
transaction ledger. It targets one Compute Engine VM in Firebase project
`dripproject-24882`, one container, and one attached Persistent Disk mounted at
`/var/lib/drip`.

```text
Internet -> HTTPS proxy -> 127.0.0.1:4242 -> one Node container
                                             |
                                             +-> /var/lib/drip/drip.sqlite
                                                 on one block-storage disk
```

Do not run this manifest with multiple replicas, a process cluster, NFS,
Cloud Storage FUSE, or an autoscaler. SQLite WAL, inventory reservations,
Stripe event idempotency, and the seller ledger all require the same durable
database file and one application writer. Cloud Run's normal writable layer is
ephemeral and is not a safe home for this database. Cloud Run becomes a good
target only after the transaction ledger is migrated to a shared database such
as PostgreSQL.

## Host requirements

- A single Linux VM with Docker Engine and the Compose plugin.
- A separate encrypted Persistent Disk mounted at `/var/lib/drip` before the
  container starts. The directory must be mode `0700` and owned by UID/GID
  `1000:1000`, which is the unprivileged `node` user in the image.
- A reserved IP, DNS name, and valid HTTPS termination. The example Caddy file
  keeps Node bound to host loopback and lets Caddy manage TLS.
- A dedicated user-managed VM service account. Grant
  `roles/firebaseauth.viewer` for Firebase token verification. Grant the
  broader Authentication write permission only if the separately reviewed
  Firebase six-digit-code service is enabled later.
- Access to only the specific Secret Manager secrets needed at runtime. Do not
  download or mount a Firebase service-account JSON key on a Google-hosted VM;
  the Admin SDK uses the VM service identity through Application Default
  Credentials.

The image is pinned to Node 24.13.1 because the service requires Node 24.12+
and uses the built-in `node:sqlite` defensive mode. The image never copies
`server/.env`, `node_modules`, tests, or any local SQLite file.

## Staging configuration

1. Copy `staging.env.example` to `/etc/drip/staging.env` on the VM and replace
   the two example hostnames with the real staging web/API domains.
2. Keep that file root-readable only. Supply `STRIPE_SECRET_KEY` and
   `STRIPE_WEBHOOK_SECRET` from Secret Manager; use sandbox/test values.
3. Keep `MARKETPLACE_DATABASE_PROVIDER=sqlite`,
   `STRIPE_CONNECT_ENABLED=false`, and `REQUIRE_CONNECT_PAYOUTS=false` for this
   first Checkout test. The checked-in seed is demonstration inventory, so do
   not describe it as real seller stock.
4. Start exactly one service from this directory:

   ```sh
   docker compose -f compose.staging.yaml up --build -d
   ```

5. Verify `https://YOUR_API_HOST/healthz` reports
   `authProvider: "firebase"`, `accountAuthConfigured: true`, and
   `paymentsConfigured: true`.

`DEPLOYMENT_STAGE=staging` keeps `NODE_ENV=production` hardening, rejects local
HTTP return URLs, development authentication, in-memory storage, live Stripe
keys, and a half-configured Stripe key/webhook pair. Unlike the live production
stage, it does not force Stripe Connect or seller payout readiness.

## Stripe event destination

Create one sandbox/test event destination with this stable URL:

```text
https://YOUR_API_HOST/v1/stripe/webhook
```

Subscribe only to:

- `checkout.session.completed`
- `checkout.session.async_payment_succeeded`
- `checkout.session.async_payment_failed`
- `checkout.session.expired`

Put that destination's `whsec_...` signing secret in Secret Manager. It is not
the Stripe API key and must not be reused for Connect. The server verifies the
raw request body, retrieves the Checkout Session from Stripe again, checks the
server-owned total and metadata, and stores event IDs transactionally before
changing order state.

The browser success page never marks an order paid. A signed webhook must
confirm it. After configuring the destination, complete one test checkout,
replay its event, and verify the order is paid once and inventory is sold once.

## Backups and updates

- Schedule Persistent Disk snapshots and keep at least one copy outside the
  VM lifecycle.
- Before an application update, stop the one container, take an
  application-consistent snapshot, deploy the new image, and verify
  `/healthz` before reopening traffic. Never start an old and new writer
  against the same file during a rolling deployment.
- Add an online SQLite backup job before storing real transactions; it should
  use SQLite's backup API, upload the completed backup to versioned encrypted
  storage, run an integrity check, and be restore-tested. Do not copy only
  `drip.sqlite` while its WAL may contain committed data.

## Live-production blockers

This manifest is for an online Stripe sandbox, not live money. Before changing
`DEPLOYMENT_STAGE` to `production`, Drip still needs real seller inventory,
completed Connect onboarding, tax handling, refunds/disputes, shipping and
claim operations, idempotent transfer/settlement work, reconciliation,
monitoring and alerts, a tested backup/restore plan, and legal/support approval.
The current checkout code records seller payables as held but intentionally
does not transfer funds to sellers.
