import assert from 'node:assert/strict';
import test from 'node:test';

import {
  buyerProtectionCents,
  calculateQuote,
  sellerFeeCents,
} from '../src/policy.js';

test('marketplace policy uses deterministic integer-cent math', () => {
  assert.equal(buyerProtectionCents(1000), 149);
  assert.equal(buyerProtectionCents(5186), 306);
  assert.equal(buyerProtectionCents(10_000), 499);
  assert.equal(sellerFeeCents(3800), 380);
  assert.equal(sellerFeeCents(3800, true), 266);
  assert.equal(sellerFeeCents(1000, true), 100);
  assert.deepEqual(
    calculateQuote(
      [{ priceCents: 9200 }, { priceCents: 3800 }],
      ['@jordanscloset', '@miacloset'],
    ),
    {
      currency: 'usd',
      merchandiseSubtotalCents: 13_000,
      buyerProtectionCents: 499,
      shippingCents: 1398,
      taxCents: 0,
      totalCents: 14_897,
    },
  );
});
