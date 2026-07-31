export const BASIC_SELLER_FEE_BPS = 1000;
export const PRO_SELLER_FEE_BPS = 700;

export const POLICY_VERSION = 'marketplace-v1';
export const CURRENCY = 'usd';
export const SHIPPING_PER_SELLER_CENTS = 699;

function basisPoints(cents, bps) {
  return Math.floor((cents * bps + 5000) / 10000);
}

export function sellerFeeCents(priceCents, sellerIsPro = false) {
  assertCents(priceCents);
  return Math.max(
    100,
    basisPoints(
      priceCents,
      sellerIsPro ? PRO_SELLER_FEE_BPS : BASIC_SELLER_FEE_BPS,
    ),
  );
}

export function buyerProtectionCents(subtotalCents) {
  assertCents(subtotalCents);
  return Math.max(
    149,
    Math.min(499, basisPoints(subtotalCents, 400) + 99),
  );
}

export function assertCents(value) {
  if (!Number.isSafeInteger(value) || value < 0) {
    throw new TypeError('Money must be a non-negative safe integer in cents.');
  }
}

export function calculateQuote(items, sellers) {
  const merchandiseSubtotalCents = items.reduce(
    (total, item) => total + item.priceCents,
    0,
  );
  assertCents(merchandiseSubtotalCents);
  const buyerProtection = buyerProtectionCents(merchandiseSubtotalCents);
  const shippingCents = sellers.length * SHIPPING_PER_SELLER_CENTS;
  const taxCents = 0;
  return Object.freeze({
    currency: CURRENCY,
    merchandiseSubtotalCents,
    buyerProtectionCents: buyerProtection,
    shippingCents,
    taxCents,
    totalCents:
      merchandiseSubtotalCents + buyerProtection + shippingCents + taxCents,
  });
}
