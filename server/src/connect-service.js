import { immediateTransaction } from './database.js';
import { AppError } from './errors.js';

const ACCOUNT_ID = /^acct_[A-Za-z0-9]{8,120}$/;
const EVENT_ID = /^evt_[A-Za-z0-9_]{8,180}$/;
const CAPABILITY_STATUSES = new Set([
  'pending',
  'active',
  'restricted',
  'unsupported',
]);
const SUPPORTED_EVENTS = new Set([
  'v2.core.account.updated',
  'v2.core.account.closed',
  'v2.core.account[configuration.recipient].capability_status_updated',
  'v2.core.account[configuration.recipient].updated',
  'v2.core.account[future_requirements].updated',
  'v2.core.account[requirements].updated',
]);

function exactEmptyObject(body) {
  if (
    body === null ||
    typeof body !== 'object' ||
    Array.isArray(body) ||
    Object.keys(body).length !== 0
  ) {
    throw new AppError(422, 'invalid_request', 'Request must be an empty object.');
  }
}

function safeCapabilityStatus(value) {
  return CAPABILITY_STATUSES.has(value) ? value : 'unrequested';
}

function requirementsDue(account) {
  const entries = Array.isArray(account?.requirements?.entries)
    ? account.requirements.entries
    : [];
  const dueEntries = entries.filter((entry) => {
    const status = entry?.minimum_deadline?.status;
    return (
      entry?.awaiting_action_from === 'user' &&
      (status === 'currently_due' || status === 'past_due')
    );
  });
  const summaryStatus = account?.requirements?.summary?.minimum_deadline?.status;
  return dueEntries.length ||
    (summaryStatus === 'currently_due' || summaryStatus === 'past_due' ? 1 : 0);
}

function firstRestriction(account, transferStatus, payoutStatus, dueCount) {
  const statusDetails = [
    ...(account?.configuration?.recipient?.capabilities?.stripe_balance
      ?.stripe_transfers?.status_details ?? []),
    ...(account?.configuration?.recipient?.capabilities?.stripe_balance
      ?.payouts?.status_details ?? []),
  ];
  const providerCode = statusDetails.find(
    (item) => typeof item?.code === 'string' && item.code.length <= 100,
  )?.code;
  if (providerCode) return providerCode;
  if (dueCount > 0) return 'requirements_due';
  if (transferStatus !== 'active') return `transfers_${transferStatus}`;
  if (payoutStatus !== 'active') return `payouts_${payoutStatus}`;
  return null;
}

function normalizeAccount(account, expectedLiveMode) {
  if (
    !account ||
    typeof account !== 'object' ||
    !ACCOUNT_ID.test(account.id || '') ||
    typeof account.livemode !== 'boolean'
  ) {
    throw new AppError(
      502,
      'invalid_provider_response',
      'Stripe returned an invalid connected account.',
      undefined,
      true,
    );
  }
  if (account.livemode !== expectedLiveMode) {
    throw new AppError(
      409,
      'stripe_mode_mismatch',
      'The connected account belongs to a different Stripe mode.',
    );
  }
  const balance =
    account.configuration?.recipient?.capabilities?.stripe_balance ?? {};
  const transfersStatus = safeCapabilityStatus(
    balance.stripe_transfers?.status,
  );
  const payoutsStatus = safeCapabilityStatus(balance.payouts?.status);
  const dueCount = requirementsDue(account);
  const closed = account.closed === true;
  const restricted =
    transfersStatus === 'restricted' ||
    transfersStatus === 'unsupported' ||
    payoutsStatus === 'restricted' ||
    payoutsStatus === 'unsupported' ||
    account.requirements?.summary?.minimum_deadline?.status === 'past_due';
  const ready =
    !closed &&
    transfersStatus === 'active' &&
    payoutsStatus === 'active' &&
    dueCount === 0;
  const status = closed
    ? 'closed'
    : ready
      ? 'ready'
      : restricted
        ? 'restricted'
        : 'pending';
  const country =
    typeof account.identity?.country === 'string' &&
    /^[A-Z]{2}$/i.test(account.identity.country)
      ? account.identity.country.toUpperCase()
      : null;
  return Object.freeze({
    id: account.id,
    livemode: account.livemode,
    dashboard: account.dashboard === 'express' ? 'express' : account.dashboard,
    transfersStatus,
    payoutsStatus,
    dueCount,
    status,
    ready,
    disabledReason: firstRestriction(
      account,
      transfersStatus,
      payoutsStatus,
      dueCount,
    ),
    country,
  });
}

function publicStatus(row) {
  const accountExists = typeof row.stripe_connect_account_id === 'string';
  const status = !accountExists
    ? 'not_started'
    : row.connect_status === 'ready'
      ? 'ready'
      : row.connect_status === 'restricted' || row.connect_status === 'closed'
        ? 'restricted'
        : row.requirements_due_count > 0 ||
            row.transfers_capability_status === 'unrequested' ||
            row.payouts_capability_status === 'unrequested'
          ? 'onboarding_incomplete'
          : 'verification_pending';
  return Object.freeze({
    status,
    onboardingRequired: status !== 'ready',
    transfersStatus: accountExists
      ? row.transfers_capability_status
      : 'unrequested',
    payoutsStatus: accountExists
      ? row.payouts_capability_status
      : 'unrequested',
    transfersReady:
      accountExists && row.transfers_capability_status === 'active',
    payoutsReady: accountExists && row.connect_status === 'ready',
    requirementsDue: accountExists ? row.requirements_due_count : 0,
    canOpenDashboard:
      accountExists && row.connect_status !== 'closed',
    livemode: accountExists ? row.connect_livemode === 1 : false,
    disabledReason: accountExists ? row.connect_disabled_reason : null,
    lastSyncedAt: row.connect_last_synced_at
      ? new Date(row.connect_last_synced_at * 1000).toISOString()
      : null,
  });
}

function providerError(error, message) {
  if (error instanceof AppError) return error;
  return new AppError(
    503,
    'stripe_connect_unavailable',
    message,
    undefined,
    true,
  );
}

export class ConnectService {
  #database;
  #stripe;
  #config;
  #clock;
  #inflightAccounts = new Map();
  #inflightEvents = new Map();

  constructor({ database, stripeClient, config, clock = () => Date.now() }) {
    this.#database = database;
    this.#stripe = stripeClient;
    this.#config = config;
    this.#clock = clock;
  }

  async getStatus(actor) {
    this.#assertAvailable();
    let seller = this.#sellerFor(actor.id);
    if (seller.stripe_connect_account_id) {
      let account;
      try {
        account = await this.#stripe.retrieveConnectedAccount(
          seller.stripe_connect_account_id,
        );
      } catch (error) {
        throw providerError(
          error,
          'Stripe could not refresh payout status. Try again shortly.',
        );
      }
      this.#syncAccount(account, seller.stripe_connect_account_id);
      seller = this.#sellerFor(actor.id);
    }
    return publicStatus(seller);
  }

  async createOnboarding(actor, body = {}) {
    this.#assertAvailable();
    exactEmptyObject(body);
    const seller = await this.#ensureConnectedAccount(actor.id);
    if (seller.connect_status === 'closed') {
      throw new AppError(
        409,
        'connect_account_closed',
        'This payout account is closed. Contact Drip support.',
      );
    }
    return this.#createAccountLink(seller);
  }

  async createDashboardLink(actor, body = {}) {
    this.#assertAvailable();
    exactEmptyObject(body);
    let seller = this.#sellerFor(actor.id);
    if (!seller.stripe_connect_account_id) {
      throw new AppError(
        409,
        'connect_onboarding_required',
        'Finish Stripe payout onboarding before opening the dashboard.',
      );
    }
    let account;
    try {
      account = await this.#stripe.retrieveConnectedAccount(
        seller.stripe_connect_account_id,
      );
    } catch (error) {
      throw providerError(error, 'Stripe Dashboard is temporarily unavailable.');
    }
    const normalized = this.#syncAccount(
      account,
      seller.stripe_connect_account_id,
    );
    seller = this.#sellerFor(actor.id);
    if (normalized.status === 'closed' || normalized.dashboard !== 'express') {
      throw new AppError(
        409,
        'connect_dashboard_unavailable',
        'Stripe Dashboard is not available for this payout account.',
      );
    }
    let link;
    try {
      link = await this.#stripe.createExpressDashboardLoginLink(
        seller.stripe_connect_account_id,
      );
    } catch (error) {
      throw providerError(error, 'Stripe Dashboard is temporarily unavailable.');
    }
    return Object.freeze({
      url: this.#safeProviderUrl(link?.url, 'dashboard'),
      expiresAt: new Date((this.#now() + 5 * 60) * 1000).toISOString(),
    });
  }

  async handleWebhook(rawBody, signature) {
    this.#assertAvailable();
    let event;
    try {
      event = this.#stripe.constructConnectEvent(rawBody, signature);
    } catch (error) {
      if (error instanceof AppError) throw error;
      throw new AppError(
        400,
        'invalid_connect_webhook_signature',
        'Stripe Connect signature is invalid.',
      );
    }
    if (
      !event ||
      event.object !== 'v2.core.event' ||
      !EVENT_ID.test(event.id || '') ||
      typeof event.type !== 'string' ||
      typeof event.livemode !== 'boolean'
    ) {
      throw new AppError(
        400,
        'invalid_connect_webhook_event',
        'Stripe Connect event is invalid.',
      );
    }
    if (!SUPPORTED_EVENTS.has(event.type)) {
      return Object.freeze({ received: true, ignored: true });
    }
    const accountId = event.related_object?.id;
    if (
      event.related_object?.type !== 'v2.core.account' ||
      !ACCOUNT_ID.test(accountId || '')
    ) {
      throw new AppError(
        400,
        'invalid_connect_webhook_event',
        'Stripe Connect event has no account.',
      );
    }
    if (this.#inflightEvents.has(event.id)) {
      return this.#inflightEvents.get(event.id);
    }
    const promise = this.#handleWebhookEvent(event, accountId).finally(() => {
      this.#inflightEvents.delete(event.id);
    });
    this.#inflightEvents.set(event.id, promise);
    return promise;
  }

  async #handleWebhookEvent(event, accountId) {
    const now = this.#now();
    this.#database
      .prepare(`
        INSERT OR IGNORE INTO stripe_connect_events (
          event_id, event_type, object_id, livemode, status, attempts,
          received_at
        ) VALUES (?, ?, ?, ?, 'received', 0, ?)
      `)
      .run(event.id, event.type, accountId, event.livemode ? 1 : 0, now);
    const inbox = this.#database
      .prepare('SELECT status FROM stripe_connect_events WHERE event_id = ?')
      .get(event.id);
    if (inbox.status === 'processed') {
      return Object.freeze({ received: true, duplicate: true });
    }
    if (event.livemode !== this.#config.stripeLiveMode) {
      this.#finishEvent(event.id, 'ignored_stripe_mode');
      return Object.freeze({ received: true, ignored: true });
    }
    const seller = this.#database
      .prepare('SELECT seller_handle FROM seller_accounts WHERE stripe_connect_account_id = ?')
      .get(accountId);
    if (!seller) {
      this.#finishEvent(event.id, 'ignored_external_account');
      return Object.freeze({ received: true, ignored: true });
    }
    try {
      const account = await this.#stripe.retrieveConnectedAccount(accountId);
      const normalized = normalizeAccount(account, this.#config.stripeLiveMode);
      immediateTransaction(this.#database, () => {
        this.#writeAccountSync(normalized, accountId);
        this.#database
          .prepare(`
            UPDATE stripe_connect_events
               SET status = 'processed', attempts = attempts + 1,
                   processed_at = ?, last_error = NULL
             WHERE event_id = ?
          `)
          .run(this.#now(), event.id);
      });
      return Object.freeze({ received: true, processed: true });
    } catch (error) {
      this.#database
        .prepare(`
          UPDATE stripe_connect_events
             SET status = 'failed', attempts = attempts + 1,
                 processed_at = NULL, last_error = ?
           WHERE event_id = ?
        `)
        .run(error instanceof AppError ? error.code : 'provider_error', event.id);
      throw providerError(error, 'Stripe Connect event processing will retry.');
    }
  }

  async #ensureConnectedAccount(accountId) {
    if (this.#inflightAccounts.has(accountId)) {
      return this.#inflightAccounts.get(accountId);
    }
    const promise = this.#ensureConnectedAccountInner(accountId).finally(() => {
      this.#inflightAccounts.delete(accountId);
    });
    this.#inflightAccounts.set(accountId, promise);
    return promise;
  }

  async #ensureConnectedAccountInner(accountId) {
    let seller = this.#sellerFor(accountId);
    let account;
    if (seller.stripe_connect_account_id) {
      try {
        account = await this.#stripe.retrieveConnectedAccount(
          seller.stripe_connect_account_id,
        );
      } catch (error) {
        throw providerError(error, 'Stripe payout onboarding is temporarily unavailable.');
      }
      this.#syncAccount(account, seller.stripe_connect_account_id);
      return this.#sellerFor(accountId);
    }
    try {
      account = await this.#stripe.createConnectedAccount(
        {
          displayName: seller.seller_name,
          email: seller.email,
          sellerHandle: seller.seller_handle,
        },
        `connect-account:${seller.seller_handle}:v2`,
      );
    } catch (error) {
      throw providerError(error, 'Stripe payout onboarding is temporarily unavailable.');
    }
    const normalized = normalizeAccount(account, this.#config.stripeLiveMode);
    immediateTransaction(this.#database, () => {
      const current = this.#database
        .prepare(`
          SELECT stripe_connect_account_id AS accountId
            FROM seller_accounts
           WHERE seller_handle = ?
        `)
        .get(seller.seller_handle);
      if (current.accountId && current.accountId !== normalized.id) {
        throw new AppError(
          409,
          'connect_account_conflict',
          'This seller already has another payout account.',
        );
      }
      this.#database
        .prepare(`
          UPDATE seller_accounts
             SET stripe_connect_account_id = COALESCE(stripe_connect_account_id, ?),
                 connect_created_at = COALESCE(connect_created_at, ?)
           WHERE seller_handle = ?
        `)
        .run(normalized.id, this.#now(), seller.seller_handle);
      this.#writeAccountSync(normalized, normalized.id);
    });
    return this.#sellerFor(accountId);
  }

  async #createAccountLink(seller) {
    let link;
    try {
      link = await this.#stripe.createConnectedAccountLink(
        seller.stripe_connect_account_id,
        {
          refreshUrl: this.#config.connectOnboardingRefreshUrl,
          returnUrl: this.#config.connectOnboardingReturnUrl,
        },
      );
    } catch (error) {
      throw providerError(error, 'Stripe payout onboarding is temporarily unavailable.');
    }
    const providerExpiry = Date.parse(link?.expires_at || '');
    return Object.freeze({
      url: this.#safeProviderUrl(link?.url, 'onboarding'),
      expiresAt: Number.isFinite(providerExpiry)
        ? new Date(providerExpiry).toISOString()
        : new Date((this.#now() + 5 * 60) * 1000).toISOString(),
      connect: publicStatus(this.#sellerByHandle(seller.seller_handle)),
    });
  }

  #syncAccount(account, expectedAccountId) {
    const normalized = normalizeAccount(account, this.#config.stripeLiveMode);
    if (normalized.id !== expectedAccountId) {
      throw new AppError(
        409,
        'connect_account_mismatch',
        'Stripe returned a different connected account.',
      );
    }
    const result = this.#writeAccountSync(normalized, expectedAccountId);
    if (result.changes !== 1) {
      throw new AppError(404, 'seller_not_found', 'Seller account was not found.');
    }
    return normalized;
  }

  #writeAccountSync(account, accountId) {
    return this.#database
      .prepare(`
        UPDATE seller_accounts
           SET connect_livemode = ?, connect_status = ?,
               transfers_capability_status = ?,
               payouts_capability_status = ?, requirements_due_count = ?,
               connect_disabled_reason = ?, connect_country = ?,
               transfers_ready = ?, connect_last_synced_at = ?, updated_at = ?
         WHERE stripe_connect_account_id = ?
      `)
      .run(
        account.livemode ? 1 : 0,
        account.status,
        account.transfersStatus,
        account.payoutsStatus,
        account.dueCount,
        account.disabledReason,
        account.country,
        account.ready ? 1 : 0,
        this.#now(),
        this.#now(),
        accountId,
      );
  }

  #finishEvent(eventId, reason) {
    this.#database
      .prepare(`
        UPDATE stripe_connect_events
           SET status = 'processed', attempts = attempts + 1,
               processed_at = ?, last_error = ?
         WHERE event_id = ?
      `)
      .run(this.#now(), reason, eventId);
  }

  #sellerFor(accountId) {
    const seller = this.#database
      .prepare(`
        SELECT sellers.*, accounts.email
          FROM seller_accounts AS sellers
          JOIN accounts ON accounts.id = sellers.owner_account_id
         WHERE sellers.owner_account_id = ? AND accounts.status = 'active'
      `)
      .get(accountId);
    if (!seller) {
      throw new AppError(404, 'seller_not_found', 'Seller account was not found.');
    }
    return seller;
  }

  #sellerByHandle(sellerHandle) {
    const seller = this.#database
      .prepare('SELECT * FROM seller_accounts WHERE seller_handle = ?')
      .get(sellerHandle);
    if (!seller) {
      throw new AppError(404, 'seller_not_found', 'Seller account was not found.');
    }
    return seller;
  }

  #safeProviderUrl(value, kind) {
    let decoded = null;
    try {
      decoded = typeof value === 'string' ? decodeURIComponent(value) : '';
    } catch {}
    if (
      typeof value !== 'string' ||
      value.length < 1 ||
      value.length > 4096 ||
      decoded === null ||
      /[\u0000-\u001F\u007F-\u009F]/u.test(value) ||
      /[\u0000-\u001F\u007F-\u009F]/u.test(decoded ?? '')
    ) {
      throw new AppError(
        502,
        'invalid_provider_response',
        'Stripe returned an invalid secure link.',
      );
    }
    let parsed;
    try {
      parsed = new URL(value);
    } catch {
      throw new AppError(
        502,
        'invalid_provider_response',
        'Stripe returned an invalid secure link.',
      );
    }
    const expectedHost =
      kind === 'onboarding' ? 'accounts.stripe.com' : 'connect.stripe.com';
    const fragmentAllowed = kind === 'onboarding';
    if (
      parsed.protocol !== 'https:' ||
      parsed.hostname !== expectedHost ||
      parsed.username ||
      parsed.password ||
      parsed.port ||
      (!fragmentAllowed && parsed.hash) ||
      !parsed.hostname
    ) {
      throw new AppError(
        502,
        'invalid_provider_response',
        'Stripe returned an invalid secure link.',
      );
    }
    return parsed.toString();
  }

  #assertAvailable() {
    if (!this.#config.stripeConnectConfigured) {
      throw new AppError(
        503,
        'stripe_connect_unavailable',
        'Stripe seller payouts are not configured on this server.',
        undefined,
        true,
      );
    }
  }

  #now() {
    return Math.floor(this.#clock() / 1000);
  }
}
