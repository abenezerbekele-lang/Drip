# Drip Business Model Canvas

## One-sentence model

Drip helps style-conscious buyers discover distinctive secondhand fashion and
helps independent sellers turn inventory into income; the marketplace earns
transaction fees plus optional seller subscription and promotion revenue.

This canvas is a decision document. Prices, conversion rates, and economics are
planning assumptions until production transactions and customer research
validate them.

## Canvas

| Canvas block | Drip decision |
| --- | --- |
| **Customer segments** | Primary buyers: mobile-first Gen Z and young millennial shoppers looking for expressive streetwear, vintage, and affordable one-of-one pieces. Primary sellers: casual closet sellers, student resellers, vintage curators, and emerging independent stores. Later segments: creators with curated drops and professional multi-channel sellers. |
| **Value propositions** | Buyers get visual discovery, transparent totals, a conversational outfit assistant, and Stripe-hosted payment. Sellers get fast listing, merchandising, performance views, promotion tools, and a lower success fee through Drip Pro. Both sides get a clear transaction trail without unsupported claims that every item or seller is authenticated. |
| **Channels** | Flutter mobile/web product, creator-led social content, seller referral links, campus/community ambassadors, search-friendly editorial collections, lifecycle email, and curated drop notifications. Paid acquisition should begin only after activation and repeat-purchase economics are measured. |
| **Customer relationships** | Self-service onboarding, saved items and carts, AI styling help, seller dashboards, transactional email, proactive order updates, and human escalation for claims. Trust must come from visible policy, responsive support, and evidence-backed status—not vague “verified” badges. |
| **Revenue streams** | Basic seller success fee: 10% with a $1 minimum. Pro seller success fee: 7% with a $1 minimum. Buyer protection: 4% of merchandise plus $0.99, bounded to $1.49–$4.99. Drip Pro: $9.99/month. Promotions: $1.99 for 24 hours or $5.99 for 7 days. Shipping is modeled as a pass-through, not platform revenue. |
| **Key resources** | Two-sided marketplace brand and community, catalog and behavioral data, Flutter client, Drip API, Firebase Authentication identity, Firestore catalog data, transactional payment ledger, ranking and merchandising logic, AI prompt/evaluation assets, payment and email relationships, policies, moderation operations, and customer-support knowledge. |
| **Key activities** | Acquire and activate sellers, curate inventory, improve discovery and outfit relevance, convert carts, keep listings and order state accurate, moderate content, operate shipping/claims/refunds, reconcile money movement, support customers, and instrument retention and unit economics. |
| **Key partners** | Stripe for Checkout and Connect, Firebase for native account authentication and production catalog data, a verified transactional-email provider such as Resend for the optional Firebase six-digit code flow, OpenAI for the concierge, cloud hosting/storage providers, shipping-label carriers or aggregators, moderation tooling, creators/ambassadors, and qualified legal/accounting advisors. Vendor names describe the intended architecture, not proof of live production contracts. |
| **Cost structure** | Payment processing, cloud compute/database/storage/CDN, AI inference and moderation, transactional email, refunds and loss reserve, support labor, content moderation, shipping tooling, engineering/design, analytics/observability, legal/compliance/accounting, and customer acquisition. |

## Marketplace flywheel

1. Better seller tools and early demand bring in distinctive inventory.
2. Distinctive inventory makes editorial discovery and AI outfits more useful.
3. Better discovery raises saves, checkout conversion, and seller sell-through.
4. Seller success improves retention, referrals, and willingness to use Pro or
   promotions.
5. More high-quality supply improves the buyer experience again.

The flywheel breaks if inventory is stale, fees surprise the buyer, payouts are
unclear, or support is slow. Those operational systems are core product work.

## Revenue mechanics

| Revenue stream | Planning policy | Customer value |
| --- | ---: | --- |
| Basic success fee | 10% of merchandise, $1 minimum | No required monthly seller subscription |
| Pro success fee | 7% of merchandise, $1 minimum | Lower fee for active sellers |
| Buyer protection | 4% + $0.99, bounded to $1.49–$4.99 | Funds marketplace protection and support operations |
| Drip Pro | $9.99/month | Fee savings, three 24-hour boost credits, and advanced metrics |
| 24-hour boost | $1.99 | Short merchandising window |
| 7-day boost | $5.99 | Longer merchandising window |
| Shipping | $6.99 per seller package in the current policy | Pass-through fulfillment charge; not counted as revenue |

Taxes are currently modeled as zero in the checkout snapshot. Drip must
configure Stripe Tax or adopt a reviewed tax policy before accepting live
payments.

## Illustrative unit economics

For a Basic seller transaction with $51.86 in merchandise:

| Line | Illustrative amount |
| --- | ---: |
| Merchandise GMV | $51.86 |
| Seller success fee | $5.19 |
| Buyer protection | $3.06 |
| Shipping pass-through | $6.99 |
| Buyer total before tax | $61.91 |
| Gross transaction revenue | $8.25 |
| Processing estimate, 2.9% + $0.30 | -$2.10 |
| Protection reserve, 1% of GMV | -$0.52 |
| Support allowance | -$0.50 |
| Illustrative contribution | $5.14 |

That equals roughly 15.9% gross transaction revenue per GMV and 9.9%
illustrative contribution per GMV before fixed costs and acquisition. The
processing rate, reserve, and support allowance are placeholders, not Stripe
quotes or historical results.

## Drip Pro customer logic

The difference between Basic and Pro success fees is three percentage points.
Ignoring the value of boosts and metrics, a $9.99 subscription breaks even for
a seller at approximately:

```text
$9.99 ÷ 0.03 = $333 monthly seller GMV
```

At $800 monthly GMV, the fee saving is $24; after the subscription, the seller
is approximately $14.01 ahead before valuing included boosts. Product copy
should show this math plainly and avoid implying guaranteed sales.

## Go-to-market sequence

### Phase 1: concentrated supply

- Recruit a small group of quality local sellers in one community or style
  niche.
- Help each seller publish a complete first drop.
- Curate editorial collections from real available inventory.
- Personally observe first-listing friction, shipping questions, and failed
  checkouts.

### Phase 2: repeat demand

- Run creator outfit content that links to available listings.
- Use saves and price/style preferences for relevant return notifications.
- Introduce buyer referrals only after the first-purchase experience is
  reliable.
- Measure 30- and 60-day buyer repeat purchase before increasing paid spend.

### Phase 3: seller monetization

- Offer Pro only after active sellers can see credible fee savings and metrics.
- Sell promotions only with transparent labeling and attribution.
- Expand to professional sellers after inventory sync and operations can handle
  greater volume.

## Metrics and guardrails

### North-star candidate

Completed, issue-free orders per monthly active buyer. It combines discovery,
conversion, payment success, inventory accuracy, and marketplace operations.

### Buyer funnel

- Product-detail view to save
- Save or cart to checkout start
- Checkout start to webhook-confirmed payment
- Time to first purchase
- 30/60/90-day repeat purchase
- Refund, cancellation, and claim rate

### Seller funnel

- Signup to verified account
- Verified account to first live listing
- Time to first sale
- 30-day sell-through
- On-time shipment and delivery
- 30/90-day seller retention
- Pro conversion and promotion repeat usage

### Economics

- Merchandise GMV and average order value
- Seller-fee, buyer-protection, subscription, and promotion revenue
- Payment cost, loss/refund reserve, support cost, and contribution
- Contribution after acquisition by cohort
- Payout aging and unreconciled ledger balance

### Trust guardrails

- Never call a seller or item “verified” without a completed operational
  verification process.
- Never count shipping or tax as revenue.
- Never call projected metrics traction.
- Never show a seller payout as sent until Stripe and the internal ledger agree.
- Never optimize conversion by hiding mandatory fees.

## Highest-risk assumptions to test

| Assumption | Cheapest credible test | Success signal |
| --- | --- | --- |
| Buyers value outfit help while shopping | Concierge prototype against a real, in-stock collection | Recommendations lead to materially more product-detail views, saves, or carts than browsing alone |
| Sellers accept a 10% fee | Ten seller interviews plus a small real drop | Sellers publish again after seeing fee-inclusive earnings |
| Transparent protection improves trust | Checkout comprehension test | Most participants can state their total and what the charge covers |
| Pro is valuable above ~$333 monthly GMV | Price interview with active sellers | Sellers choose Pro for fee savings before relying on speculative promotion value |
| Curated density beats broad inventory | Launch one narrow style/community cohort | Better sell-through and repeat behavior than an uncurated control |

## Evidence status

The application can calculate and display planning economics, but the
repository contains no verified claims of revenue, customer acquisition cost,
lifetime value, growth, or processor performance. Those figures belong in a
pitch only after they are measured from production systems and reconciled.
