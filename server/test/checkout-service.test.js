import assert from 'node:assert/strict';
import test from 'node:test';

import { listCatalog } from '../src/database.js';
import { demoBuyer, testConfig, testContext } from '../test_support/setup.js';
import { stripeEvent } from '../test_support/fake-stripe.js';

const multiSellerBody = Object.freeze({
  attemptId: 'attempt_multi_seller_0001',
  items: [
    { listingId: 'nike-red-court', selectedSize: '9' },
    { listingId: 'white-heavy-tee', selectedSize: 'M' },
  ],
});

test('database seeds the entire Flutter catalog and preserves sold state', () => {
  const context = testContext();
  try {
    const catalog = listCatalog(context.database);
    assert.equal(catalog.length, 44);
    assert.equal(
      catalog.find((item) => item.id === 'black-backpack').status,
      'sold',
    );
  } finally {
    context.database.close();
  }
});

test('creates a server-priced multi-seller Checkout Session and payable ledger', async () => {
  const context = testContext();
  try {
    const checkout = await context.service.createCheckout(
      demoBuyer,
      multiSellerBody,
      multiSellerBody.attemptId,
    );
    assert.equal(checkout.status, 'open');
    assert.equal(checkout.sessionId, 'cs_test_1');
    assert.equal(checkout.url, 'https://checkout.stripe.test/cs_test_1');
    assert.deepEqual(checkout.quote, {
      currency: 'usd',
      merchandiseSubtotalCents: 13_000,
      buyerProtectionCents: 499,
      shippingCents: 1398,
      taxCents: 0,
      totalCents: 14_897,
    });
    assert.equal(context.stripeClient.createCalls.length, 1);
    const call = context.stripeClient.createCalls[0];
    assert.equal(call.parameters.ui_mode, 'hosted_page');
    assert.equal(call.parameters.expires_at, 1_800_001_860);
    assert.equal(call.parameters.shipping_options[0].shipping_rate_data.fixed_amount.amount, 1398);
    assert.equal(call.parameters.payment_intent_data.transfer_group, `ORDER_${checkout.orderId}`);
    assert.equal(call.parameters.metadata.order_id, checkout.orderId);

    const ledger = context.database
      .prepare('SELECT * FROM seller_ledger WHERE order_id = ? ORDER BY seller_handle')
      .all(checkout.orderId);
    assert.deepEqual(
      ledger.map((row) => ({
        seller: row.seller_handle,
        merchandise: row.merchandise_cents,
        fee: row.seller_fee_cents,
        shipping: row.shipping_cents,
        payable: row.payable_cents,
        status: row.status,
      })),
      [
        {
          seller: '@jordanscloset',
          merchandise: 9200,
          fee: 920,
          shipping: 699,
          payable: 8979,
          status: 'awaiting_payment',
        },
        {
          seller: '@miacloset',
          merchandise: 3800,
          fee: 380,
          shipping: 699,
          payable: 4119,
          status: 'awaiting_payment',
        },
      ],
    );
  } finally {
    context.database.close();
  }
});

test('same attempt is idempotent and changed cart conflicts', async () => {
  const context = testContext();
  try {
    const first = await context.service.createCheckout(
      demoBuyer,
      multiSellerBody,
      multiSellerBody.attemptId,
    );
    const second = await context.service.createCheckout(
      demoBuyer,
      structuredClone(multiSellerBody),
      multiSellerBody.attemptId,
    );
    assert.equal(second.orderId, first.orderId);
    assert.equal(second.sessionId, first.sessionId);
    assert.equal(context.stripeClient.createCalls.length, 1);

    await assert.rejects(
      context.service.createCheckout(
        demoBuyer,
        {
          attemptId: multiSellerBody.attemptId,
          items: [{ listingId: 'black-heavy-tee', selectedSize: 'L' }],
        },
        multiSellerBody.attemptId,
      ),
      (error) => error.code === 'idempotency_conflict',
    );
  } finally {
    context.database.close();
  }
});

test('concurrent buyers cannot reserve the same one-of-one listing', async () => {
  const context = testContext();
  try {
    const first = context.service.createCheckout(demoBuyer, {
      attemptId: 'attempt_concurrent_first_01',
      items: [{ listingId: 'black-heavy-tee', selectedSize: 'L' }],
    });
    await assert.rejects(
      context.service.createCheckout(
        { id: 'buyer-two', sellerHandle: '@buyertwo' },
        {
          attemptId: 'attempt_concurrent_second_1',
          items: [{ listingId: 'black-heavy-tee', selectedSize: 'L' }],
        },
      ),
      (error) => error.code === 'listing_unavailable',
    );
    assert.equal((await first).status, 'open');
    assert.equal(
      context.database
        .prepare("SELECT COUNT(*) AS count FROM orders WHERE status = 'open'")
        .get().count,
      1,
    );
  } finally {
    context.database.close();
  }
});

test('retry recovers a Stripe Session whose first response was lost', async () => {
  const context = testContext();
  const body = {
    attemptId: 'attempt_lost_response_0001',
    items: [{ listingId: 'black-heavy-tee', selectedSize: 'L' }],
  };
  try {
    context.stripeClient.throwAfterCreateOnce = true;
    await assert.rejects(
      context.service.createCheckout(demoBuyer, body),
      (error) => error.code === 'checkout_provider_error',
    );
    const recovered = await context.service.createCheckout(demoBuyer, body);
    assert.equal(recovered.sessionId, 'cs_test_1');
    assert.equal(context.stripeClient.createCalls.length, 2);
    assert.equal(
      context.stripeClient.createCalls[0].idempotencyKey,
      context.stripeClient.createCalls[1].idempotencyKey,
    );
    assert.equal(
      context.database.prepare('SELECT COUNT(*) AS count FROM orders').get().count,
      1,
    );
  } finally {
    context.database.close();
  }
});

test('server rejects own, sold, unavailable-size, and client price fields', async () => {
  const context = testContext();
  try {
    await assert.rejects(
      context.service.createCheckout(
        demoBuyer,
        {
          attemptId: 'attempt_owned_listing_001',
          items: [{ listingId: 'nike-noir-runner', selectedSize: '9' }],
        },
      ),
      (error) => error.code === 'own_listing',
    );
    await assert.rejects(
      context.service.createCheckout(
        { id: 'another-buyer', sellerHandle: '@buyer' },
        {
          attemptId: 'attempt_sold_listing_0001',
          items: [{ listingId: 'black-backpack', selectedSize: 'One size' }],
        },
      ),
      (error) => error.code === 'listing_unavailable',
    );
    await assert.rejects(
      context.service.createCheckout(
        demoBuyer,
        {
          attemptId: 'attempt_invalid_size_0001',
          items: [{ listingId: 'nike-red-court', selectedSize: '99' }],
        },
      ),
      (error) => error.code === 'invalid_size',
    );
    await assert.rejects(
      context.service.createCheckout(
        demoBuyer,
        {
          attemptId: 'attempt_client_price_0001',
          items: [
            {
              listingId: 'nike-red-court',
              selectedSize: '9',
              priceCents: 1,
            },
          ],
        },
      ),
      (error) => error.code === 'invalid_request',
    );
  } finally {
    context.database.close();
  }
});

test('server rejects a listing whose stored currency differs from checkout policy', async () => {
  const context = testContext();
  try {
    context.database
      .prepare('UPDATE listings SET currency = ? WHERE id = ?')
      .run('eur', 'black-heavy-tee');
    await assert.rejects(
      context.service.createCheckout(demoBuyer, {
        attemptId: 'attempt_currency_mismatch_01',
        items: [{ listingId: 'black-heavy-tee', selectedSize: 'L' }],
      }),
      (error) => error.code === 'listing_currency_unsupported',
    );
    assert.equal(
      context.database.prepare('SELECT COUNT(*) AS count FROM orders').get().count,
      0,
    );
  } finally {
    context.database.close();
  }
});

test('verified paid webhook atomically sells inventory and is replay-safe', async () => {
  const context = testContext();
  try {
    const checkout = await context.service.createCheckout(
      demoBuyer,
      multiSellerBody,
      multiSellerBody.attemptId,
    );
    context.stripeClient.updateSession(checkout.sessionId, {
      status: 'complete',
      payment_status: 'paid',
      payment_intent: 'pi_test_paid',
    });
    const event = stripeEvent(
      'evt_paid_1',
      'checkout.session.completed',
      checkout.sessionId,
    );
    const raw = Buffer.from(JSON.stringify(event));
    assert.deepEqual(
      await context.service.handleWebhook(raw, 'test_signature'),
      { received: true, processed: true },
    );
    assert.deepEqual(
      await context.service.handleWebhook(raw, 'test_signature'),
      { received: true, duplicate: true },
    );
    const status = context.service.getCheckout(demoBuyer, checkout.sessionId);
    assert.equal(status.status, 'paid');
    assert.equal(status.paymentIntentId, 'pi_test_paid');
    const listingStates = context.database
      .prepare(`SELECT status FROM listings WHERE id IN ('nike-red-court', 'white-heavy-tee') ORDER BY id`)
      .all();
    assert.deepEqual(listingStates.map((row) => row.status), ['sold', 'sold']);
    const ledgers = context.database
      .prepare('SELECT status FROM seller_ledger WHERE order_id = ?')
      .all(checkout.orderId);
    assert.deepEqual(ledgers.map((row) => row.status), [
      'awaiting_connect',
      'awaiting_connect',
    ]);
    assert.equal(
      context.database.prepare('SELECT COUNT(*) AS count FROM stripe_events').get().count,
      1,
    );
  } finally {
    context.database.close();
  }
});

test('expired webhook releases inventory but cannot overwrite a paid order', async () => {
  const context = testContext();
  try {
    const body = {
      attemptId: 'attempt_expiration_test_01',
      items: [{ listingId: 'black-heavy-tee', selectedSize: 'L' }],
    };
    const checkout = await context.service.createCheckout(demoBuyer, body);
    context.stripeClient.updateSession(checkout.sessionId, { status: 'expired' });
    await context.service.handleWebhook(
      Buffer.from(
        JSON.stringify(
          stripeEvent('evt_expired_1', 'checkout.session.expired', checkout.sessionId),
        ),
      ),
      'test_signature',
    );
    assert.equal(context.service.getCheckout(demoBuyer, checkout.sessionId).status, 'expired');
    assert.equal(
      context.database.prepare('SELECT status FROM listings WHERE id = ?').get('black-heavy-tee').status,
      'live',
    );

    const paidBody = {
      attemptId: 'attempt_paid_then_old_001',
      items: [{ listingId: 'cream-luxe-tee', selectedSize: 'M' }],
    };
    const paid = await context.service.createCheckout(demoBuyer, paidBody);
    context.stripeClient.updateSession(paid.sessionId, {
      status: 'complete',
      payment_status: 'paid',
      payment_intent: 'pi_paid_late_event',
    });
    await context.service.handleWebhook(
      Buffer.from(JSON.stringify(stripeEvent('evt_paid_2', 'checkout.session.completed', paid.sessionId))),
      'test_signature',
    );
    context.stripeClient.updateSession(paid.sessionId, {
      status: 'expired',
      payment_status: 'unpaid',
    });
    await context.service.handleWebhook(
      Buffer.from(JSON.stringify(stripeEvent('evt_stale_expired', 'checkout.session.expired', paid.sessionId))),
      'test_signature',
    );
    assert.equal(context.service.getCheckout(demoBuyer, paid.sessionId).status, 'paid');
    assert.equal(
      context.database.prepare('SELECT status FROM listings WHERE id = ?').get('cream-luxe-tee').status,
      'sold',
    );
  } finally {
    context.database.close();
  }
});

test('out-of-order completed event cannot reopen a terminal unpaid checkout', async () => {
  const context = testContext();
  try {
    const checkout = await context.service.createCheckout(demoBuyer, {
      attemptId: 'attempt_terminal_ordering_01',
      items: [{ listingId: 'black-heavy-tee', selectedSize: 'L' }],
    });
    context.stripeClient.updateSession(checkout.sessionId, {
      status: 'expired',
      payment_status: 'unpaid',
    });
    await context.service.handleWebhook(
      Buffer.from(
        JSON.stringify(
          stripeEvent(
            'evt_terminal_expired',
            'checkout.session.expired',
            checkout.sessionId,
          ),
        ),
      ),
      'test_signature',
    );

    await context.service.handleWebhook(
      Buffer.from(
        JSON.stringify(
          stripeEvent(
            'evt_stale_completed',
            'checkout.session.completed',
            checkout.sessionId,
          ),
        ),
      ),
      'test_signature',
    );

    assert.equal(
      context.service.getCheckout(demoBuyer, checkout.sessionId).status,
      'expired',
    );
    assert.equal(
      context.database.prepare('SELECT status FROM listings WHERE id = ?').get('black-heavy-tee').status,
      'live',
    );
  } finally {
    context.database.close();
  }
});

test('paid provider state without a PaymentIntent enters manual review', async () => {
  const context = testContext();
  try {
    const checkout = await context.service.createCheckout(demoBuyer, {
      attemptId: 'attempt_missing_payment_intent_01',
      items: [{ listingId: 'black-heavy-tee', selectedSize: 'L' }],
    });
    context.stripeClient.updateSession(checkout.sessionId, {
      status: 'complete',
      payment_status: 'paid',
      payment_intent: null,
    });
    await context.service.handleWebhook(
      Buffer.from(
        JSON.stringify(
          stripeEvent(
            'evt_missing_payment_intent',
            'checkout.session.completed',
            checkout.sessionId,
          ),
        ),
      ),
      'test_signature',
    );

    const order = context.database
      .prepare('SELECT status, status_reason FROM orders WHERE id = ?')
      .get(checkout.orderId);
    assert.deepEqual({ ...order }, {
      status: 'payment_review',
      status_reason: 'missing_payment_intent',
    });
    assert.equal(
      context.database.prepare('SELECT status FROM listings WHERE id = ?').get('black-heavy-tee').status,
      'reserved',
    );
  } finally {
    context.database.close();
  }
});

test('amount mismatch enters payment review without selling or releasing stock', async () => {
  const context = testContext();
  try {
    const body = {
      attemptId: 'attempt_amount_review_001',
      items: [{ listingId: 'black-heavy-tee', selectedSize: 'L' }],
    };
    const checkout = await context.service.createCheckout(demoBuyer, body);
    context.stripeClient.updateSession(checkout.sessionId, {
      status: 'complete',
      payment_status: 'paid',
      amount_total: checkout.quote.totalCents + 1,
      payment_intent: 'pi_mismatch',
    });
    await context.service.handleWebhook(
      Buffer.from(JSON.stringify(stripeEvent('evt_mismatch', 'checkout.session.completed', checkout.sessionId))),
      'test_signature',
    );
    assert.equal(
      context.service.getCheckout(demoBuyer, checkout.sessionId).status,
      'payment_review',
    );
    assert.equal(
      context.database.prepare('SELECT status FROM listings WHERE id = ?').get('black-heavy-tee').status,
      'reserved',
    );
  } finally {
    context.database.close();
  }
});

test('explicit cancel expires Stripe first and then releases inventory', async () => {
  const context = testContext();
  try {
    const body = {
      attemptId: 'attempt_explicit_cancel_01',
      items: [{ listingId: 'black-heavy-tee', selectedSize: 'L' }],
    };
    const checkout = await context.service.createCheckout(demoBuyer, body);
    const canceled = await context.service.expireCheckout(
      demoBuyer,
      checkout.sessionId,
      { attemptId: body.attemptId },
    );
    assert.equal(canceled.status, 'canceled');
    assert.equal(context.stripeClient.expireCalls.length, 1);
    assert.equal(
      context.database.prepare('SELECT status FROM listings WHERE id = ?').get('black-heavy-tee').status,
      'live',
    );
  } finally {
    context.database.close();
  }
});

test('production payout gate rejects sellers without Connect readiness', async () => {
  const context = testContext({
    config: testConfig({ REQUIRE_CONNECT_PAYOUTS: 'true' }),
  });
  try {
    await assert.rejects(
      context.service.createCheckout(demoBuyer, {
        attemptId: 'attempt_connect_gate_0001',
        items: [{ listingId: 'nike-red-court', selectedSize: '9' }],
      }),
      (error) => error.code === 'seller_payout_unavailable',
    );
  } finally {
    context.database.close();
  }
});

test('expired ambiguous Session creation releases its reservation and requires a new attempt', async () => {
  let now = 1_800_000_000_000;
  const context = testContext({ clock: () => now });
  const firstBody = {
    attemptId: 'attempt_ambiguous_create_01',
    items: [{ listingId: 'black-heavy-tee', selectedSize: 'L' }],
  };
  try {
    context.stripeClient.createError = new Error('Simulated network timeout.');
    await assert.rejects(
      context.service.createCheckout(demoBuyer, firstBody),
      (error) => error.code === 'checkout_provider_error',
    );
    assert.equal(
      context.database.prepare('SELECT status FROM listings WHERE id = ?').get('black-heavy-tee').status,
      'reserved',
    );

    now += 31 * 60 * 1000 + 1000;
    context.stripeClient.createError = null;
    const replacement = await context.service.createCheckout(demoBuyer, {
      attemptId: 'attempt_after_timeout_0001',
      items: [{ listingId: 'black-heavy-tee', selectedSize: 'L' }],
    });
    assert.equal(replacement.status, 'open');
    const oldOrder = context.database
      .prepare('SELECT status, status_reason FROM orders WHERE attempt_id = ?')
      .get(firstBody.attemptId);
    assert.deepEqual({ ...oldOrder }, {
      status: 'expired',
      status_reason: 'checkout_creation_expired',
    });
    await assert.rejects(
      context.service.createCheckout(demoBuyer, firstBody),
      (error) => error.code === 'checkout_expired',
    );
  } finally {
    context.database.close();
  }
});

test('late captured payment after inventory release enters refund-required review', async () => {
  const context = testContext();
  try {
    const body = {
      attemptId: 'attempt_late_capture_0001',
      items: [{ listingId: 'black-heavy-tee', selectedSize: 'L' }],
    };
    const checkout = await context.service.createCheckout(demoBuyer, body);
    await context.service.expireCheckout(demoBuyer, checkout.sessionId, {
      attemptId: body.attemptId,
    });
    context.stripeClient.updateSession(checkout.sessionId, {
      status: 'complete',
      payment_status: 'paid',
      payment_intent: 'pi_late_capture',
    });
    await context.service.handleWebhook(
      Buffer.from(
        JSON.stringify(
          stripeEvent('evt_late_capture', 'checkout.session.completed', checkout.sessionId),
        ),
      ),
      'test_signature',
    );
    const order = context.database
      .prepare('SELECT status, status_reason FROM orders WHERE id = ?')
      .get(checkout.orderId);
    assert.deepEqual({ ...order }, {
      status: 'payment_review',
      status_reason: 'captured_after_inventory_release_refund_required',
    });
    assert.equal(
      context.database.prepare('SELECT status FROM listings WHERE id = ?').get('black-heavy-tee').status,
      'live',
    );
  } finally {
    context.database.close();
  }
});
