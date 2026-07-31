import { chmodSync, mkdirSync, readFileSync } from 'node:fs';
import path from 'node:path';
import { DatabaseSync } from 'node:sqlite';

const catalog = JSON.parse(
  readFileSync(new URL('../data/catalog.json', import.meta.url), 'utf8'),
);

const schema = `
  PRAGMA journal_mode = WAL;
  PRAGMA synchronous = FULL;
  PRAGMA busy_timeout = 5000;

  CREATE TABLE IF NOT EXISTS schema_migrations (
    name TEXT PRIMARY KEY,
    applied_at INTEGER NOT NULL
  ) STRICT;

  CREATE TABLE IF NOT EXISTS accounts (
    id TEXT PRIMARY KEY,
    display_name TEXT NOT NULL CHECK (length(display_name) BETWEEN 1 AND 80),
    email TEXT NOT NULL UNIQUE COLLATE BINARY CHECK (
      length(email) BETWEEN 3 AND 254 AND email = lower(email)
    ),
    password_hash TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'disabled')),
    email_verified_at INTEGER,
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL
  ) STRICT;

  CREATE TABLE IF NOT EXISTS email_verifications (
    account_id TEXT PRIMARY KEY REFERENCES accounts(id) ON DELETE RESTRICT,
    challenge_digest TEXT NOT NULL UNIQUE CHECK (length(challenge_digest) = 64),
    code_digest TEXT NOT NULL CHECK (length(code_digest) = 64),
    idempotency_key TEXT NOT NULL UNIQUE,
    expires_at INTEGER NOT NULL,
    attempt_count INTEGER NOT NULL DEFAULT 0 CHECK (attempt_count BETWEEN 0 AND 5),
    resend_window_start INTEGER NOT NULL,
    resend_count INTEGER NOT NULL DEFAULT 0 CHECK (resend_count BETWEEN 0 AND 100),
    last_sent_at INTEGER NOT NULL,
    provider_message_id TEXT,
    consumed_at INTEGER,
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL,
    CHECK (expires_at > created_at),
    CHECK (consumed_at IS NULL OR consumed_at >= created_at)
  ) STRICT;

  CREATE TABLE IF NOT EXISTS email_verification_usage (
    scope_hash TEXT NOT NULL,
    action TEXT NOT NULL CHECK (action IN (
      'verify_ip', 'verify_email', 'resend_ip', 'resend_email'
    )),
    window_start INTEGER NOT NULL,
    request_count INTEGER NOT NULL CHECK (request_count >= 0),
    updated_at INTEGER NOT NULL,
    PRIMARY KEY (scope_hash, action, window_start)
  ) STRICT;

  CREATE TABLE IF NOT EXISTS firebase_email_verifications (
    firebase_uid TEXT PRIMARY KEY CHECK (length(firebase_uid) BETWEEN 1 AND 128),
    email TEXT NOT NULL CHECK (
      length(email) BETWEEN 3 AND 254 AND email = lower(email)
    ),
    challenge_id TEXT NOT NULL UNIQUE CHECK (
      length(challenge_id) BETWEEN 20 AND 100
    ),
    code_digest TEXT NOT NULL CHECK (length(code_digest) = 64),
    idempotency_key TEXT NOT NULL UNIQUE CHECK (
      length(idempotency_key) BETWEEN 20 AND 200
    ),
    status TEXT NOT NULL CHECK (status IN ('pending', 'sent', 'consumed')),
    expires_at INTEGER NOT NULL,
    attempt_count INTEGER NOT NULL DEFAULT 0 CHECK (
      attempt_count BETWEEN 0 AND 10
    ),
    last_sent_at INTEGER NOT NULL,
    provider_message_id TEXT UNIQUE,
    consumed_at INTEGER,
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL,
    CHECK (expires_at > created_at),
    CHECK (
      (status = 'pending' AND provider_message_id IS NULL
       AND consumed_at IS NULL)
      OR
      (status = 'sent' AND provider_message_id IS NOT NULL
       AND consumed_at IS NULL)
      OR
      (status = 'consumed' AND consumed_at IS NOT NULL)
    )
  ) STRICT;

  CREATE TABLE IF NOT EXISTS firebase_email_verification_usage (
    scope_hash TEXT NOT NULL CHECK (length(scope_hash) = 64),
    action TEXT NOT NULL CHECK (action IN (
      'request_uid', 'request_ip', 'verify_uid', 'verify_ip'
    )),
    window_start INTEGER NOT NULL,
    request_count INTEGER NOT NULL CHECK (request_count >= 0),
    updated_at INTEGER NOT NULL,
    PRIMARY KEY (scope_hash, action, window_start)
  ) STRICT;

  CREATE TABLE IF NOT EXISTS welcome_email_outbox (
    account_id TEXT PRIMARY KEY REFERENCES accounts(id) ON DELETE RESTRICT,
    idempotency_key TEXT NOT NULL UNIQUE,
    status TEXT NOT NULL CHECK (status IN ('pending', 'sending', 'sent', 'failed')),
    attempt_count INTEGER NOT NULL DEFAULT 0 CHECK (attempt_count BETWEEN 0 AND 5),
    next_attempt_at INTEGER,
    claimed_at INTEGER,
    provider_message_id TEXT UNIQUE,
    sent_at INTEGER,
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL,
    CHECK (
      (status = 'pending' AND next_attempt_at IS NOT NULL AND claimed_at IS NULL
       AND provider_message_id IS NULL AND sent_at IS NULL)
      OR
      (status = 'sending' AND next_attempt_at IS NULL AND claimed_at IS NOT NULL
       AND provider_message_id IS NULL AND sent_at IS NULL)
      OR
      (status = 'failed' AND claimed_at IS NULL
       AND provider_message_id IS NULL AND sent_at IS NULL)
      OR
      (status = 'sent' AND next_attempt_at IS NULL AND claimed_at IS NULL
       AND provider_message_id IS NOT NULL AND sent_at IS NOT NULL)
    )
  ) STRICT;

  CREATE TABLE IF NOT EXISTS account_sessions (
    id TEXT PRIMARY KEY,
    account_id TEXT NOT NULL REFERENCES accounts(id) ON DELETE RESTRICT,
    expires_at INTEGER NOT NULL,
    revoked_at INTEGER,
    created_at INTEGER NOT NULL,
    CHECK (expires_at > created_at),
    CHECK (revoked_at IS NULL OR revoked_at >= created_at)
  ) STRICT;

  CREATE TABLE IF NOT EXISTS auth_usage_windows (
    scope_hash TEXT NOT NULL,
    action TEXT NOT NULL CHECK (action IN (
      'signup_ip', 'signup_email', 'login_ip', 'login_email'
    )),
    window_start INTEGER NOT NULL,
    request_count INTEGER NOT NULL CHECK (request_count >= 0),
    updated_at INTEGER NOT NULL,
    PRIMARY KEY (scope_hash, action, window_start)
  ) STRICT;

  CREATE TABLE IF NOT EXISTS seller_accounts (
    seller_handle TEXT PRIMARY KEY,
    seller_name TEXT NOT NULL,
    owner_account_id TEXT REFERENCES accounts(id) ON DELETE RESTRICT,
    is_pro INTEGER NOT NULL DEFAULT 0 CHECK (is_pro IN (0, 1)),
    stripe_connect_account_id TEXT UNIQUE,
    transfers_ready INTEGER NOT NULL DEFAULT 0 CHECK (transfers_ready IN (0, 1)),
    connect_livemode INTEGER CHECK (connect_livemode IN (0, 1)),
    connect_status TEXT NOT NULL DEFAULT 'not_started' CHECK (connect_status IN (
      'not_started', 'pending', 'ready', 'restricted', 'closed'
    )),
    transfers_capability_status TEXT NOT NULL DEFAULT 'unrequested' CHECK (
      transfers_capability_status IN (
        'unrequested', 'pending', 'active', 'restricted', 'unsupported'
      )
    ),
    payouts_capability_status TEXT NOT NULL DEFAULT 'unrequested' CHECK (
      payouts_capability_status IN (
        'unrequested', 'pending', 'active', 'restricted', 'unsupported'
      )
    ),
    requirements_due_count INTEGER NOT NULL DEFAULT 0 CHECK (requirements_due_count >= 0),
    connect_disabled_reason TEXT,
    connect_country TEXT,
    connect_created_at INTEGER,
    connect_last_synced_at INTEGER,
    updated_at INTEGER NOT NULL
  ) STRICT;

  CREATE TABLE IF NOT EXISTS stripe_connect_events (
    event_id TEXT PRIMARY KEY,
    event_type TEXT NOT NULL,
    object_id TEXT,
    livemode INTEGER NOT NULL CHECK (livemode IN (0, 1)),
    status TEXT NOT NULL CHECK (status IN ('received', 'processed', 'failed')),
    attempts INTEGER NOT NULL DEFAULT 0 CHECK (attempts >= 0),
    received_at INTEGER NOT NULL,
    processed_at INTEGER,
    last_error TEXT
  ) STRICT;

  CREATE TABLE IF NOT EXISTS orders (
    id TEXT PRIMARY KEY,
    buyer_id TEXT NOT NULL,
    buyer_seller_handle TEXT,
    attempt_id TEXT NOT NULL,
    request_fingerprint TEXT NOT NULL,
    stripe_idempotency_key TEXT NOT NULL UNIQUE,
    status TEXT NOT NULL CHECK (status IN (
      'creating', 'open', 'processing', 'paid', 'expired', 'canceled',
      'payment_failed', 'payment_review'
    )),
    status_reason TEXT,
    policy_version TEXT NOT NULL,
    currency TEXT NOT NULL CHECK (length(currency) = 3),
    merchandise_subtotal_cents INTEGER NOT NULL CHECK (merchandise_subtotal_cents >= 0),
    buyer_protection_cents INTEGER NOT NULL CHECK (buyer_protection_cents >= 0),
    shipping_cents INTEGER NOT NULL CHECK (shipping_cents >= 0),
    tax_cents INTEGER NOT NULL CHECK (tax_cents >= 0),
    total_cents INTEGER NOT NULL CHECK (total_cents >= 0),
    platform_revenue_cents INTEGER NOT NULL CHECK (platform_revenue_cents >= 0),
    stripe_session_id TEXT UNIQUE,
    stripe_checkout_url TEXT,
    stripe_payment_intent_id TEXT UNIQUE,
    expires_at INTEGER NOT NULL,
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL,
    paid_at INTEGER,
    UNIQUE (buyer_id, attempt_id),
    CHECK (
      total_cents = merchandise_subtotal_cents + buyer_protection_cents +
                    shipping_cents + tax_cents
    ),
    CHECK (platform_revenue_cents <= total_cents)
  ) STRICT;

  CREATE TABLE IF NOT EXISTS listings (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    brand TEXT NOT NULL,
    seller_handle TEXT NOT NULL REFERENCES seller_accounts(seller_handle),
    price_cents INTEGER NOT NULL CHECK (price_cents >= 1000),
    currency TEXT NOT NULL DEFAULT 'usd' CHECK (length(currency) = 3),
    sizes_json TEXT NOT NULL CHECK (
      json_valid(sizes_json) AND json_type(sizes_json) = 'array'
    ),
    status TEXT NOT NULL CHECK (status IN ('live', 'reserved', 'sold', 'paused')),
    reserved_order_id TEXT REFERENCES orders(id),
    reserved_until INTEGER,
    version INTEGER NOT NULL DEFAULT 1 CHECK (version > 0),
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL,
    CHECK (
      (status = 'reserved' AND reserved_order_id IS NOT NULL AND reserved_until IS NOT NULL)
      OR
      (status <> 'reserved' AND reserved_order_id IS NULL AND reserved_until IS NULL)
    )
  ) STRICT;

  CREATE TABLE IF NOT EXISTS order_items (
    order_id TEXT NOT NULL REFERENCES orders(id) ON DELETE RESTRICT,
    listing_id TEXT NOT NULL REFERENCES listings(id) ON DELETE RESTRICT,
    listing_name TEXT NOT NULL,
    brand TEXT NOT NULL,
    seller_handle TEXT NOT NULL REFERENCES seller_accounts(seller_handle),
    selected_size TEXT NOT NULL,
    price_cents INTEGER NOT NULL CHECK (price_cents >= 0),
    seller_fee_cents INTEGER NOT NULL CHECK (seller_fee_cents >= 0),
    seller_payable_merchandise_cents INTEGER NOT NULL CHECK (seller_payable_merchandise_cents >= 0),
    listing_version INTEGER NOT NULL CHECK (listing_version > 0),
    PRIMARY KEY (order_id, listing_id),
    CHECK (seller_fee_cents <= price_cents),
    CHECK (seller_payable_merchandise_cents = price_cents - seller_fee_cents)
  ) STRICT;

  CREATE TABLE IF NOT EXISTS seller_ledger (
    order_id TEXT NOT NULL REFERENCES orders(id) ON DELETE RESTRICT,
    seller_handle TEXT NOT NULL REFERENCES seller_accounts(seller_handle),
    merchandise_cents INTEGER NOT NULL CHECK (merchandise_cents >= 0),
    seller_fee_cents INTEGER NOT NULL CHECK (seller_fee_cents >= 0),
    shipping_cents INTEGER NOT NULL CHECK (shipping_cents >= 0),
    payable_cents INTEGER NOT NULL CHECK (payable_cents >= 0),
    connect_account_id TEXT,
    status TEXT NOT NULL CHECK (status IN (
      'awaiting_payment', 'awaiting_connect', 'held', 'transferred', 'reversed'
    )),
    stripe_transfer_id TEXT UNIQUE,
    updated_at INTEGER NOT NULL,
    PRIMARY KEY (order_id, seller_handle),
    CHECK (seller_fee_cents <= merchandise_cents),
    CHECK (payable_cents = merchandise_cents - seller_fee_cents + shipping_cents)
  ) STRICT;

  CREATE TABLE IF NOT EXISTS stripe_events (
    event_id TEXT PRIMARY KEY,
    event_type TEXT NOT NULL,
    object_id TEXT,
    status TEXT NOT NULL CHECK (status IN ('received', 'processed', 'failed')),
    attempts INTEGER NOT NULL DEFAULT 0 CHECK (attempts >= 0),
    received_at INTEGER NOT NULL,
    processed_at INTEGER,
    last_error TEXT
  ) STRICT;

  CREATE TABLE IF NOT EXISTS ai_usage_windows (
    actor_hash TEXT NOT NULL,
    window_kind TEXT NOT NULL CHECK (window_kind IN ('minute', 'day')),
    window_start INTEGER NOT NULL,
    request_count INTEGER NOT NULL CHECK (request_count >= 0),
    updated_at INTEGER NOT NULL,
    PRIMARY KEY (actor_hash, window_kind, window_start)
  ) STRICT;

  CREATE INDEX IF NOT EXISTS listings_status_index
    ON listings(status, reserved_until);
  CREATE INDEX IF NOT EXISTS orders_buyer_index
    ON orders(buyer_id, created_at DESC);
  CREATE INDEX IF NOT EXISTS orders_session_index
    ON orders(stripe_session_id);
  CREATE INDEX IF NOT EXISTS ai_usage_window_cleanup_index
    ON ai_usage_windows(window_start);
  CREATE INDEX IF NOT EXISTS account_sessions_account_index
    ON account_sessions(account_id, created_at DESC);
  CREATE INDEX IF NOT EXISTS account_sessions_expiry_index
    ON account_sessions(expires_at, revoked_at);
  CREATE INDEX IF NOT EXISTS auth_usage_window_cleanup_index
    ON auth_usage_windows(window_start);
  CREATE INDEX IF NOT EXISTS email_verifications_expiry_index
    ON email_verifications(expires_at, consumed_at);
  CREATE INDEX IF NOT EXISTS email_verification_usage_cleanup_index
    ON email_verification_usage(window_start);
  CREATE INDEX IF NOT EXISTS firebase_email_verifications_expiry_index
    ON firebase_email_verifications(expires_at, status);
  CREATE INDEX IF NOT EXISTS firebase_email_verification_usage_cleanup_index
    ON firebase_email_verification_usage(window_start);
  CREATE INDEX IF NOT EXISTS welcome_email_outbox_due_index
    ON welcome_email_outbox(status, next_attempt_at, claimed_at);
`;

export function createDatabase(databasePath = ':memory:') {
  if (databasePath !== ':memory:') {
    mkdirSync(path.dirname(databasePath), { recursive: true, mode: 0o700 });
  }
  const database = new DatabaseSync(databasePath, {
    timeout: 5000,
    enableForeignKeyConstraints: true,
    enableDoubleQuotedStringLiterals: false,
    allowExtension: false,
    defensive: true,
  });
  if (databasePath !== ':memory:') chmodSync(databasePath, 0o600);
  database.exec(schema);
  migrateAccountVerificationSchema(database);
  migrateSellerConnectSchema(database);
  seedCatalog(database);
  return database;
}

function migrateAccountVerificationSchema(database) {
  const migration = 'accounts_email_verification_v1';
  if (
    database
      .prepare('SELECT 1 FROM schema_migrations WHERE name = ?')
      .get(migration)
  ) {
    return;
  }
  immediateTransaction(database, () => {
    const columns = new Set(
      database.prepare('PRAGMA table_info(accounts)').all().map((row) => row.name),
    );
    if (!columns.has('email_verified_at')) {
      database.exec('ALTER TABLE accounts ADD COLUMN email_verified_at INTEGER');
    }
    // The marker is committed with the backfill. If a process previously added
    // the column but crashed before finishing, the missing marker safely resumes
    // this legacy-only migration on the next boot. Future pending accounts are
    // created only after the marker exists and therefore remain unverified.
    database.exec(`
      UPDATE accounts
         SET email_verified_at = created_at
       WHERE email_verified_at IS NULL
    `);
    database
      .prepare('INSERT INTO schema_migrations (name, applied_at) VALUES (?, ?)')
      .run(migration, Math.floor(Date.now() / 1000));
  });
}

function migrateSellerConnectSchema(database) {
  const columns = new Set(
    database.prepare('PRAGMA table_info(seller_accounts)').all().map((row) => row.name),
  );
  const additions = [
    ['owner_account_id', 'TEXT REFERENCES accounts(id) ON DELETE RESTRICT'],
    ['connect_livemode', 'INTEGER'],
    ['connect_status', "TEXT NOT NULL DEFAULT 'not_started'"],
    ['transfers_capability_status', "TEXT NOT NULL DEFAULT 'unrequested'"],
    ['payouts_capability_status', "TEXT NOT NULL DEFAULT 'unrequested'"],
    ['requirements_due_count', 'INTEGER NOT NULL DEFAULT 0'],
    ['connect_disabled_reason', 'TEXT'],
    ['connect_country', 'TEXT'],
    ['connect_created_at', 'INTEGER'],
    ['connect_last_synced_at', 'INTEGER'],
  ];
  for (const [name, definition] of additions) {
    if (!columns.has(name)) {
      database.exec(`ALTER TABLE seller_accounts ADD COLUMN ${name} ${definition}`);
    }
  }
  database.exec(`
    CREATE UNIQUE INDEX IF NOT EXISTS seller_accounts_owner_index
      ON seller_accounts(owner_account_id)
      WHERE owner_account_id IS NOT NULL;
  `);
}

export function immediateTransaction(database, callback) {
  database.exec('BEGIN IMMEDIATE');
  try {
    const result = callback();
    if (result && typeof result.then === 'function') {
      throw new TypeError('SQLite transaction callbacks must be synchronous.');
    }
    database.exec('COMMIT');
    return result;
  } catch (error) {
    database.exec('ROLLBACK');
    throw error;
  }
}

function seedCatalog(database) {
  const now = Math.floor(Date.now() / 1000);
  const insertSeller = database.prepare(`
    INSERT OR IGNORE INTO seller_accounts (
      seller_handle, seller_name, is_pro, transfers_ready, updated_at
    ) VALUES (?, ?, 0, 0, ?)
  `);
  const insertListing = database.prepare(`
    INSERT OR IGNORE INTO listings (
      id, name, brand, seller_handle, price_cents, currency, sizes_json,
      status, created_at, updated_at
    ) VALUES (?, ?, ?, ?, ?, 'usd', ?, ?, ?, ?)
  `);
  immediateTransaction(database, () => {
    for (const item of catalog) {
      insertSeller.run(item.sellerHandle, item.sellerName, now);
      insertListing.run(
        item.id,
        item.name,
        item.brand,
        item.sellerHandle,
        item.priceCents,
        JSON.stringify(item.sizes),
        item.status,
        now,
        now,
      );
    }
  });
}

export function listCatalog(database) {
  return database
    .prepare(`
      SELECT id, name, brand, seller_handle AS sellerHandle,
             price_cents AS priceCents, currency, sizes_json AS sizesJson,
             status
        FROM listings
       ORDER BY created_at, id
    `)
    .all()
    .map((row) => ({ ...row, sizes: JSON.parse(row.sizesJson), sizesJson: undefined }));
}
