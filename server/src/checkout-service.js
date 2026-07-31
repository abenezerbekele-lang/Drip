import { createHash, randomUUID } from 'node:crypto';

import { immediateTransaction } from './database.js';
import { AppError, asAppError } from './errors.js';
import {
  calculateQuote,
  CURRENCY,
  POLICY_VERSION,
  sellerFeeCents,
  SHIPPING_PER_SELLER_CENTS,
} from './policy.js';

const MAX_ITEMS = 20;
const IDENTIFIER = /^[A-Za-z0-9][A-Za-z0-9._:-]{1,127}$/;
const ATTEMPT = /^[A-Za-z0-9][A-Za-z0-9._:-]{15,127}$/;
const SUPPORTED_EVENTS = new Set([
  'checkout.session.completed',
  'checkout.session.async_payment_succeeded',
  'checkout.session.async_payment_failed',
  'checkout.session.expired',
]);

function own(object, key) {
  return Object.prototype.hasOwnProperty.call(object, key);
}

function exactKeys(object, allowed, name) {
  if (
    object === null ||
    typeof object !== 'object' ||
    Array.isArray(object)
  ) {
    throw new AppError(422, 'invalid_request', `${name} must be an object.`);
  }
  for (const key of Object.keys(object)) {
    if (!allowed.has(key)) {
      throw new AppError(
        422,
        'invalid_request',
        `${name} contains an unsupported field.`,
      );
    }
  }
}

function validateCreateRequest(body, headerKey) {
  exactKeys(body, new Set(['attemptId', 'items']), 'Request');
  if (typeof body.attemptId !== 'string' || !ATTEMPT.test(body.attemptId)) {
    throw new AppError(
      422,
      'invalid_attempt_id',
      'attemptId must be a stable 16–128 character identifier.',
    );
  }
  if (headerKey && headerKey !== body.attemptId) {
    throw new AppError(
      409,
      'idempotency_key_mismatch',
      'Idempotency-Key must match attemptId.',
    );
  }
  if (!Array.isArray(body.items) || body.items.length < 1 || body.items.length > MAX_ITEMS) {
    throw new AppError(
      422,
      'invalid_items',
      `Checkout requires 1–${MAX_ITEMS} items.`,
    );
  }
  const seen = new Set();
  const items = body.items.map((item, index) => {
    exactKeys(item, new Set(['listingId', 'selectedSize']), `Item ${index + 1}`);
    if (typeof item.listingId !== 'string' || !IDENTIFIER.test(item.listingId)) {
      throw new AppError(422, 'invalid_listing', 'A listing ID is invalid.');
    }
    if (
      typeof item.selectedSize !== 'string' ||
      item.selectedSize.length < 1 ||
      item.selectedSize.length > 32
    ) {
      throw new AppError(422, 'invalid_size', 'A selected size is invalid.');
    }
    if (seen.has(item.listingId)) {
      throw new AppError(
        422,
        'duplicate_listing',
        'One-of-one listings can only appear once per checkout.',
      );
    }
    seen.add(item.listingId);
    return Object.freeze({
      listingId: item.listingId,
      selectedSize: item.selectedSize,
    });
  });
  items.sort((left, right) => left.listingId.localeCompare(right.listingId));
  return Object.freeze({ attemptId: body.attemptId, items: Object.freeze(items) });
}

function requestFingerprint(request) {
  return createHash('sha256')
    .update(JSON.stringify(request.items))
    .digest('hex');
}

function publicOrderId() {
  return `ord_${randomUUID().replaceAll('-', '')}`;
}

function normalizePaymentIntent(value) {
  if (typeof value === 'string') return value;
  if (value && typeof value.id === 'string') return value.id;
  return null;
}

function databaseRows(database, orderId) {
  const order = database.prepare('SELECT * FROM orders WHERE id = ?').get(orderId);
  if (!order) return null;
  const items = database
    .prepare(`
      SELECT listing_id AS listingId, listing_name AS name, brand,
             seller_handle AS sellerHandle, selected_size AS selectedSize,
             price_cents AS priceCents, seller_fee_cents AS sellerFeeCents,
             seller_payable_merchandise_cents AS sellerPayableMerchandiseCents
        FROM order_items
       WHERE order_id = ?
       ORDER BY listing_id
    `)
    .all(orderId);
  return { order, items };
}

function responseFromRows(rows, { includeUrl = false } = {}) {
  const { order, items } = rows;
  const response = {
    orderId: order.id,
    sessionId: order.stripe_session_id,
    checkoutSessionId: order.stripe_session_id,
    expiresAt: new Date(order.expires_at * 1000).toISOString(),
    status: order.status,
    quote: {
      currency: order.currency,
      merchandiseSubtotalCents: order.merchandise_subtotal_cents,
      buyerProtectionCents: order.buyer_protection_cents,
      shippingCents: order.shipping_cents,
      taxCents: order.tax_cents,
      totalCents: order.total_cents,
    },
    listingIds: items.map((item) => item.listingId),
    items: items.map((item) => ({
      listingId: item.listingId,
      name: item.name,
      selectedSize: item.selectedSize,
      sellerHandle: item.sellerHandle,
      priceCents: item.priceCents,
    })),
  };
  if (order.stripe_payment_intent_id) {
    response.paymentIntentId = order.stripe_payment_intent_id;
  }
  if (
    includeUrl &&
    order.stripe_checkout_url &&
    ['creating', 'open', 'processing'].includes(order.status)
  ) {
    response.url = order.stripe_checkout_url;
    response.checkoutUrl = order.stripe_checkout_url;
  }
  return response;
}

export class CheckoutService {
  #database;
  #stripe;
  #config;
  #clock;
  #inflightSessions = new Map();
  #inflightEvents = new Map();

  constructor({ database, stripeClient, config, clock = () => Date.now() }) {
    this.#database = database;
    this.#stripe = stripeClient;
    this.#config = config;
    this.#clock = clock;
  }

  async createCheckout(buyer, body, idempotencyHeader = '') {
    const request = validateCreateRequest(body, idempotencyHeader);
    const inflightKey = `${buyer.id}:${request.attemptId}`;
    if (this.#inflightSessions.has(inflightKey)) {
      return this.#inflightSessions.get(inflightKey);
    }
    const promise = this.#createCheckout(buyer, request).finally(() => {
      this.#inflightSessions.delete(inflightKey);
    });
    this.#inflightSessions.set(inflightKey, promise);
    return promise;
  }

  async #createCheckout(buyer, request) {
    this.#sweepExpiredCreatingReservations(this.#nowSeconds());
    const fingerprint = requestFingerprint(request);
    let rows = this.#existingAttempt(buyer.id, request.attemptId, fingerprint);
    if (!rows) rows = this.#reserveAndCreateOrder(buyer, request, fingerprint);
    if (
      rows.order.expires_at <= this.#nowSeconds() &&
      rows.order.status !== 'paid'
    ) {
      throw new AppError(
        409,
        'checkout_expired',
        'This checkout attempt expired. Start a new checkout attempt.',
      );
    }
    if (rows.order.stripe_session_id) {
      return responseFromRows(rows, { includeUrl: true });
    }

    const parameters = this.#stripeParameters(rows);
    let session;
    try {
      session = await this.#stripe.createCheckoutSession(
        parameters,
        rows.order.stripe_idempotency_key,
      );
    } catch (error) {
      this.#database
        .prepare(`
          UPDATE orders
             SET status_reason = 'stripe_create_failed', updated_at = ?
           WHERE id = ? AND stripe_session_id IS NULL
        `)
        .run(this.#nowSeconds(), rows.order.id);
      if (error instanceof AppError) throw error;
      throw new AppError(
        503,
        'checkout_provider_error',
        'Stripe Checkout is temporarily unavailable. Retry this checkout.',
        undefined,
        true,
      );
    }
    if (
      !session ||
      typeof session.id !== 'string' ||
      typeof session.url !== 'string' ||
      session.url.length < 1
    ) {
      throw new AppError(
        502,
        'invalid_provider_response',
        'Stripe returned an incomplete Checkout Session.',
        undefined,
        true,
      );
    }
    if (
      Number.isSafeInteger(session.amount_total) &&
      session.amount_total !== rows.order.total_cents
    ) {
      this.#database
        .prepare(`
          UPDATE orders
             SET status = 'payment_review',
                 status_reason = 'provider_total_mismatch', updated_at = ?
           WHERE id = ? AND status <> 'paid'
        `)
        .run(this.#nowSeconds(), rows.order.id);
      throw new AppError(
        502,
        'amount_mismatch',
        'Checkout was stopped because the payment total did not match.',
      );
    }

    immediateTransaction(this.#database, () => {
      const current = this.#database
        .prepare('SELECT stripe_session_id FROM orders WHERE id = ?')
        .get(rows.order.id);
      if (current.stripe_session_id && current.stripe_session_id !== session.id) {
        throw new AppError(
          409,
          'session_conflict',
          'This checkout attempt already has another Stripe Session.',
        );
      }
      this.#database
        .prepare(`
          UPDATE orders
             SET stripe_session_id = ?, stripe_checkout_url = ?, status = 'open',
                 status_reason = NULL, updated_at = ?
           WHERE id = ?
        `)
        .run(session.id, session.url, this.#nowSeconds(), rows.order.id);
    });
    rows = databaseRows(this.#database, rows.order.id);
    return responseFromRows(rows, { includeUrl: true });
  }

  #existingAttempt(buyerId, attemptId, fingerprint) {
    const order = this.#database
      .prepare('SELECT id, request_fingerprint FROM orders WHERE buyer_id = ? AND attempt_id = ?')
      .get(buyerId, attemptId);
    if (!order) return null;
    if (order.request_fingerprint !== fingerprint) {
      throw new AppError(
        409,
        'idempotency_conflict',
        'This attemptId was already used for a different cart.',
      );
    }
    return databaseRows(this.#database, order.id);
  }

  #sweepExpiredCreatingReservations(now) {
    immediateTransaction(this.#database, () => {
      const expiredOrders = this.#database
        .prepare(`
          SELECT id
            FROM orders
           WHERE status = 'creating'
             AND stripe_session_id IS NULL
             AND expires_at <= ?
        `)
        .all(now);
      if (expiredOrders.length === 0) return;
      const release = this.#database.prepare(`
        UPDATE listings
           SET status = 'live', reserved_order_id = NULL, reserved_until = NULL,
               version = version + 1, updated_at = ?
         WHERE reserved_order_id = ? AND status = 'reserved'
      `);
      const expire = this.#database.prepare(`
        UPDATE orders
           SET status = 'expired', status_reason = 'checkout_creation_expired',
               updated_at = ?
         WHERE id = ? AND status = 'creating' AND stripe_session_id IS NULL
      `);
      for (const order of expiredOrders) {
        release.run(now, order.id);
        expire.run(now, order.id);
      }
    });
  }

  #reserveAndCreateOrder(buyer, request, fingerprint) {
    const now = this.#nowSeconds();
    const expiresAt = now + this.#config.reservationMinutes * 60;
    const orderId = publicOrderId();
    const stripeIdempotencyKey = `checkout:${orderId}:v1`;
    return immediateTransaction(this.#database, () => {
      const raced = this.#database
        .prepare('SELECT id, request_fingerprint FROM orders WHERE buyer_id = ? AND attempt_id = ?')
        .get(buyer.id, request.attemptId);
      if (raced) {
        if (raced.request_fingerprint !== fingerprint) {
          throw new AppError(409, 'idempotency_conflict', 'attemptId is already in use.');
        }
        return databaseRows(this.#database, raced.id);
      }

      const placeholders = request.items.map(() => '?').join(', ');
      const listings = this.#database
        .prepare(`
          SELECT l.*, s.is_pro, s.stripe_connect_account_id, s.transfers_ready
            FROM listings l
            JOIN seller_accounts s ON s.seller_handle = l.seller_handle
           WHERE l.id IN (${placeholders})
        `)
        .all(...request.items.map((item) => item.listingId));
      const byId = new Map(listings.map((listing) => [listing.id, listing]));
      const missing = request.items
        .filter((item) => !byId.has(item.listingId))
        .map((item) => item.listingId);
      if (missing.length) {
        throw new AppError(
          409,
          'listing_unavailable',
          'One or more listings are no longer available.',
          { listingIds: missing },
        );
      }

      const pricedItems = [];
      for (const requested of request.items) {
        const listing = byId.get(requested.listingId);
        if (listing.seller_handle === buyer.sellerHandle) {
          throw new AppError(
            409,
            'own_listing',
            'Remove your own listing before checkout.',
            { listingIds: [listing.id] },
          );
        }
        if (listing.status !== 'live') {
          throw new AppError(
            409,
            'listing_unavailable',
            'One or more listings are no longer available.',
            { listingIds: [listing.id] },
          );
        }
        if (listing.currency !== CURRENCY) {
          throw new AppError(
            409,
            'listing_currency_unsupported',
            'One or more listings use a currency that this checkout cannot accept.',
            { listingIds: [listing.id] },
          );
        }
        const sizes = JSON.parse(listing.sizes_json);
        if (!sizes.includes(requested.selectedSize)) {
          throw new AppError(
            422,
            'invalid_size',
            `${requested.selectedSize} is not available for ${listing.name}.`,
            { listingIds: [listing.id] },
          );
        }
        if (
          this.#config.requireConnectPayouts &&
          (!listing.stripe_connect_account_id || listing.transfers_ready !== 1)
        ) {
          throw new AppError(
            409,
            'seller_payout_unavailable',
            'A seller must finish payout onboarding before this item can be purchased.',
            { listingIds: [listing.id] },
          );
        }
        const fee = sellerFeeCents(listing.price_cents, listing.is_pro === 1);
        pricedItems.push({
          ...listing,
          selectedSize: requested.selectedSize,
          sellerFeeCents: fee,
          sellerPayableMerchandiseCents: listing.price_cents - fee,
        });
      }

      const sellerHandles = [...new Set(pricedItems.map((item) => item.seller_handle))];
      const quote = calculateQuote(
        pricedItems.map((item) => ({ priceCents: item.price_cents })),
        sellerHandles,
      );
      const sellerFeeTotal = pricedItems.reduce(
        (sum, item) => sum + item.sellerFeeCents,
        0,
      );
      this.#database
        .prepare(`
          INSERT INTO orders (
            id, buyer_id, buyer_seller_handle, attempt_id, request_fingerprint,
            stripe_idempotency_key, status, policy_version, currency,
            merchandise_subtotal_cents, buyer_protection_cents, shipping_cents,
            tax_cents, total_cents, platform_revenue_cents, expires_at,
            created_at, updated_at
          ) VALUES (?, ?, ?, ?, ?, ?, 'creating', ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        `)
        .run(
          orderId,
          buyer.id,
          buyer.sellerHandle,
          request.attemptId,
          fingerprint,
          stripeIdempotencyKey,
          POLICY_VERSION,
          quote.currency,
          quote.merchandiseSubtotalCents,
          quote.buyerProtectionCents,
          quote.shippingCents,
          quote.taxCents,
          quote.totalCents,
          quote.buyerProtectionCents + sellerFeeTotal,
          expiresAt,
          now,
          now,
        );

      const insertItem = this.#database.prepare(`
        INSERT INTO order_items (
          order_id, listing_id, listing_name, brand, seller_handle,
          selected_size, price_cents, seller_fee_cents,
          seller_payable_merchandise_cents, listing_version
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      `);
      const reserve = this.#database.prepare(`
        UPDATE listings
           SET status = 'reserved', reserved_order_id = ?, reserved_until = ?,
               version = version + 1, updated_at = ?
         WHERE id = ? AND status = 'live'
      `);
      for (const item of pricedItems) {
        insertItem.run(
          orderId,
          item.id,
          item.name,
          item.brand,
          item.seller_handle,
          item.selectedSize,
          item.price_cents,
          item.sellerFeeCents,
          item.sellerPayableMerchandiseCents,
          item.version,
        );
        if (reserve.run(orderId, expiresAt, now, item.id).changes !== 1) {
          throw new AppError(
            409,
            'listing_unavailable',
            'A listing was reserved by another buyer.',
            { listingIds: [item.id] },
          );
        }
      }

      const insertLedger = this.#database.prepare(`
        INSERT INTO seller_ledger (
          order_id, seller_handle, merchandise_cents, seller_fee_cents,
          shipping_cents, payable_cents, connect_account_id, status, updated_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, 'awaiting_payment', ?)
      `);
      for (const sellerHandle of sellerHandles) {
        const sellerItems = pricedItems.filter(
          (item) => item.seller_handle === sellerHandle,
        );
        const merchandise = sellerItems.reduce(
          (sum, item) => sum + item.price_cents,
          0,
        );
        const fees = sellerItems.reduce(
          (sum, item) => sum + item.sellerFeeCents,
          0,
        );
        const account = sellerItems[0].stripe_connect_account_id;
        insertLedger.run(
          orderId,
          sellerHandle,
          merchandise,
          fees,
          SHIPPING_PER_SELLER_CENTS,
          merchandise - fees + SHIPPING_PER_SELLER_CENTS,
          account,
          now,
        );
      }
      return databaseRows(this.#database, orderId);
    });
  }

  #stripeParameters(rows) {
    const { order, items } = rows;
    const lineItems = items.map((item) => ({
      price_data: {
        currency: order.currency,
        unit_amount: item.priceCents,
        product_data: {
          name: item.name,
          description: `${item.brand} · Size ${item.selectedSize}`,
          metadata: { listing_id: item.listingId },
        },
      },
      quantity: 1,
    }));
    lineItems.push({
      price_data: {
        currency: order.currency,
        unit_amount: order.buyer_protection_cents,
        product_data: { name: 'Drip buyer protection' },
      },
      quantity: 1,
    });
    return {
      mode: 'payment',
      // Stripe API 2026-06-24 renamed the hosted Checkout mode. Pin the
      // current value explicitly so a server upgrade cannot silently fall
      // back to an unsupported legacy enum.
      ui_mode: 'hosted_page',
      payment_method_types: ['card'],
      client_reference_id: order.id,
      line_items: lineItems,
      shipping_address_collection: {
        allowed_countries: this.#config.checkoutAllowedCountries,
      },
      shipping_options: [
        {
          shipping_rate_data: {
            type: 'fixed_amount',
            display_name: 'Standard marketplace shipping',
            fixed_amount: {
              amount: order.shipping_cents,
              currency: order.currency,
            },
          },
        },
      ],
      allow_promotion_codes: false,
      expires_at: order.expires_at,
      success_url: this.#config.checkoutSuccessUrl,
      cancel_url: this.#config.checkoutCancelUrl,
      metadata: {
        order_id: order.id,
        policy_version: order.policy_version,
        service: 'drip_checkout_v1',
      },
      payment_intent_data: {
        metadata: { order_id: order.id },
        transfer_group: `ORDER_${order.id}`,
      },
    };
  }

  getCheckout(buyer, sessionId) {
    if (typeof sessionId !== 'string' || !IDENTIFIER.test(sessionId)) {
      throw new AppError(404, 'checkout_not_found', 'Checkout was not found.');
    }
    const order = this.#database
      .prepare('SELECT id, buyer_id FROM orders WHERE stripe_session_id = ?')
      .get(sessionId);
    if (!order || order.buyer_id !== buyer.id) {
      throw new AppError(404, 'checkout_not_found', 'Checkout was not found.');
    }
    return responseFromRows(databaseRows(this.#database, order.id), {
      includeUrl: true,
    });
  }

  async expireCheckout(buyer, sessionId, body = {}) {
    exactKeys(body, new Set(['attemptId']), 'Request');
    const current = this.getCheckout(buyer, sessionId);
    const rows = databaseRows(this.#database, current.orderId);
    if (own(body, 'attemptId') && body.attemptId !== rows.order.attempt_id) {
      throw new AppError(409, 'attempt_mismatch', 'attemptId does not match checkout.');
    }
    if (['paid', 'payment_review'].includes(rows.order.status)) {
      throw new AppError(409, 'checkout_not_cancelable', 'This checkout cannot be canceled.');
    }
    if (['canceled', 'expired', 'payment_failed'].includes(rows.order.status)) {
      return responseFromRows(rows);
    }
    let session;
    try {
      session = await this.#stripe.expireCheckoutSession(
        sessionId,
        `expire:${rows.order.id}:v1`,
      );
    } catch (error) {
      if (error instanceof AppError) throw error;
      throw new AppError(
        503,
        'checkout_provider_error',
        'Stripe could not cancel this checkout. Check its status before retrying.',
        undefined,
        true,
      );
    }
    if (session.status !== 'expired' || session.payment_status === 'paid') {
      throw new AppError(
        409,
        'checkout_not_cancelable',
        'Stripe reports that this checkout can no longer be canceled.',
      );
    }
    this.#transitionUnpaid(rows.order.id, 'canceled', 'buyer_canceled');
    return responseFromRows(databaseRows(this.#database, rows.order.id));
  }

  async handleWebhook(rawBody, signature) {
    let event;
    try {
      event = this.#stripe.constructWebhookEvent(rawBody, signature);
    } catch (error) {
      if (error instanceof AppError) throw error;
      throw new AppError(400, 'invalid_webhook_signature', 'Webhook signature is invalid.');
    }
    if (
      !event ||
      typeof event.id !== 'string' ||
      typeof event.type !== 'string' ||
      !event.data?.object?.id
    ) {
      throw new AppError(400, 'invalid_webhook_event', 'Webhook event is invalid.');
    }
    if (!SUPPORTED_EVENTS.has(event.type)) return { received: true, ignored: true };
    if (this.#inflightEvents.has(event.id)) return this.#inflightEvents.get(event.id);
    const promise = this.#handleWebhookEvent(event).finally(() => {
      this.#inflightEvents.delete(event.id);
    });
    this.#inflightEvents.set(event.id, promise);
    return promise;
  }

  async #handleWebhookEvent(event) {
    const now = this.#nowSeconds();
    this.#database
      .prepare(`
        INSERT OR IGNORE INTO stripe_events (
          event_id, event_type, object_id, status, attempts, received_at
        ) VALUES (?, ?, ?, 'received', 0, ?)
      `)
      .run(event.id, event.type, event.data.object.id, now);
    const inbox = this.#database
      .prepare('SELECT status FROM stripe_events WHERE event_id = ?')
      .get(event.id);
    if (inbox.status === 'processed') return { received: true, duplicate: true };

    try {
      const session = await this.#stripe.retrieveCheckoutSession(
        event.data.object.id,
      );
      if (session?.metadata?.service !== 'drip_checkout_v1') {
        this.#database
          .prepare(`
            UPDATE stripe_events
               SET status = 'processed', attempts = attempts + 1,
                   processed_at = ?, last_error = 'ignored_external_session'
             WHERE event_id = ?
          `)
          .run(this.#nowSeconds(), event.id);
        return { received: true, ignored: true };
      }
      this.#applyAuthoritativeSession(event, session);
      return { received: true, processed: true };
    } catch (error) {
      this.#database
        .prepare(`
          UPDATE stripe_events
             SET status = 'failed', attempts = attempts + 1,
                 last_error = ?, processed_at = NULL
           WHERE event_id = ?
        `)
        .run(error instanceof AppError ? error.code : 'provider_error', event.id);
      if (error instanceof AppError) throw error;
      throw new AppError(
        503,
        'webhook_processing_failed',
        'Webhook processing will be retried.',
        undefined,
        true,
      );
    }
  }

  #applyAuthoritativeSession(event, session) {
    const orderId = session?.metadata?.order_id;
    if (typeof orderId !== 'string') {
      throw new AppError(422, 'missing_order_metadata', 'Stripe Session has no order ID.');
    }
    immediateTransaction(this.#database, () => {
      const order = this.#database.prepare('SELECT * FROM orders WHERE id = ?').get(orderId);
      if (!order) {
        throw new AppError(404, 'order_not_found', 'Stripe Session references no order.');
      }
      const mismatch =
        session.id !== event.data.object.id ||
        (order.stripe_session_id && order.stripe_session_id !== session.id) ||
        session.currency !== order.currency ||
        session.amount_total !== order.total_cents;
      if (mismatch) {
        if (order.status !== 'paid') {
          const paymentIntentId = normalizePaymentIntent(session.payment_intent);
          this.#database
            .prepare(`
              UPDATE orders
                 SET stripe_session_id = COALESCE(stripe_session_id, ?),
                     stripe_payment_intent_id = COALESCE(stripe_payment_intent_id, ?),
                     status = 'payment_review', status_reason = 'stripe_verification_mismatch',
                     updated_at = ?
               WHERE id = ?
            `)
            .run(session.id, paymentIntentId, this.#nowSeconds(), order.id);
        }
      } else if (session.payment_status === 'paid') {
        this.#markPaid(order, session);
      } else if (
        event.type === 'checkout.session.async_payment_failed' ||
        event.type === 'checkout.session.expired' ||
        session.status === 'expired'
      ) {
        if (
          event.type === 'checkout.session.expired' &&
          session.status !== 'expired'
        ) {
          throw new AppError(
            503,
            'stripe_state_not_ready',
            'Stripe Session state has not converged; retry the webhook.',
            undefined,
            true,
          );
        }
        const expired =
          event.type === 'checkout.session.expired' || session.status === 'expired';
        const status = expired ? 'expired' : 'payment_failed';
        this.#transitionUnpaidSync(
          order.id,
          status,
          expired ? 'stripe_authoritative_expired' : event.type,
        );
      } else if (['creating', 'open', 'processing'].includes(order.status)) {
        if (event.type === 'checkout.session.async_payment_succeeded') {
          throw new AppError(
            503,
            'stripe_state_not_ready',
            'Stripe payment state has not converged; retry the webhook.',
            undefined,
            true,
          );
        }
        this.#database
          .prepare(`
            UPDATE orders
               SET stripe_session_id = COALESCE(stripe_session_id, ?),
                   status = 'processing', status_reason = NULL, updated_at = ?
             WHERE id = ? AND status <> 'payment_review'
          `)
          .run(session.id, this.#nowSeconds(), order.id);
      }
      this.#database
        .prepare(`
          UPDATE stripe_events
             SET status = 'processed', attempts = attempts + 1,
                 processed_at = ?, last_error = NULL
           WHERE event_id = ?
        `)
        .run(this.#nowSeconds(), event.id);
    });
  }

  #markPaid(order, session) {
    if (order.status === 'paid') return;
    const now = this.#nowSeconds();
    const paymentIntentId = normalizePaymentIntent(session.payment_intent);
    if (!paymentIntentId || !/^pi_[A-Za-z0-9_]+$/.test(paymentIntentId)) {
      this.#database
        .prepare(`
          UPDATE orders
             SET stripe_session_id = COALESCE(stripe_session_id, ?),
                 status = 'payment_review',
                 status_reason = 'missing_payment_intent', updated_at = ?
           WHERE id = ? AND status <> 'paid'
        `)
        .run(session.id, now, order.id);
      return;
    }
    const inventory = this.#database
      .prepare(`
        SELECT COUNT(*) AS expected,
               SUM(CASE
                 WHEN l.status = 'reserved' AND l.reserved_order_id = oi.order_id
                 THEN 1 ELSE 0
               END) AS reserved
          FROM order_items oi
          JOIN listings l ON l.id = oi.listing_id
         WHERE oi.order_id = ?
      `)
      .get(order.id);
    if (inventory.expected === 0 || inventory.reserved !== inventory.expected) {
      this.#database
        .prepare(`
          UPDATE orders
             SET stripe_session_id = COALESCE(stripe_session_id, ?),
                 stripe_payment_intent_id = COALESCE(stripe_payment_intent_id, ?),
                 status = 'payment_review',
                 status_reason = 'captured_after_inventory_release_refund_required',
                 paid_at = COALESCE(paid_at, ?), updated_at = ?
           WHERE id = ? AND status <> 'paid'
        `)
        .run(session.id, paymentIntentId, now, now, order.id);
      return;
    }
    this.#database
      .prepare(`
        UPDATE orders
           SET stripe_session_id = COALESCE(stripe_session_id, ?),
               stripe_payment_intent_id = COALESCE(stripe_payment_intent_id, ?),
               status = 'paid', status_reason = NULL, paid_at = COALESCE(paid_at, ?),
               updated_at = ?
         WHERE id = ?
      `)
      .run(session.id, paymentIntentId, now, now, order.id);
    this.#database
      .prepare(`
        UPDATE listings
           SET status = 'sold', reserved_order_id = NULL, reserved_until = NULL,
               version = version + 1, updated_at = ?
         WHERE reserved_order_id = ? AND status = 'reserved'
      `)
      .run(now, order.id);
    this.#database
      .prepare(`
        UPDATE seller_ledger
           SET status = CASE
                 WHEN connect_account_id IS NULL OR NOT EXISTS (
                   SELECT 1
                     FROM seller_accounts s
                    WHERE s.seller_handle = seller_ledger.seller_handle
                      AND s.stripe_connect_account_id = seller_ledger.connect_account_id
                      AND s.transfers_ready = 1
                 ) THEN 'awaiting_connect'
                 ELSE 'held'
               END,
               updated_at = ?
         WHERE order_id = ? AND status = 'awaiting_payment'
      `)
      .run(now, order.id);
  }

  #transitionUnpaid(orderId, status, reason) {
    immediateTransaction(this.#database, () => {
      this.#transitionUnpaidSync(orderId, status, reason);
    });
  }

  #transitionUnpaidSync(orderId, status, reason) {
    const order = this.#database.prepare('SELECT status FROM orders WHERE id = ?').get(orderId);
    if (!order || ['paid', 'payment_review'].includes(order.status)) return;
    const now = this.#nowSeconds();
    this.#database
      .prepare('UPDATE orders SET status = ?, status_reason = ?, updated_at = ? WHERE id = ?')
      .run(status, reason, now, orderId);
    this.#database
      .prepare(`
        UPDATE listings
           SET status = 'live', reserved_order_id = NULL, reserved_until = NULL,
               version = version + 1, updated_at = ?
         WHERE reserved_order_id = ? AND status = 'reserved'
      `)
      .run(now, orderId);
  }

  #nowSeconds() {
    return Math.floor(this.#clock() / 1000);
  }
}

export function checkoutErrorResponse(error) {
  const appError = asAppError(error);
  const payload = {
    error: {
      code: appError.code,
      message: appError.message,
      retryable: appError.retryable,
    },
  };
  if (appError.details) payload.error.details = appError.details;
  return { status: appError.status, payload };
}
