export class FakeStripeClient {
  constructor() {
    this.createCalls = [];
    this.retrieveCalls = [];
    this.expireCalls = [];
    this.sessions = new Map();
    this.idempotentSessions = new Map();
    this.createError = null;
    this.throwAfterCreateOnce = false;
  }

  async createCheckoutSession(parameters, idempotencyKey) {
    this.createCalls.push({ parameters, idempotencyKey });
    if (this.createError) throw this.createError;
    const existing = this.idempotentSessions.get(idempotencyKey);
    if (existing) return structuredClone(existing);
    const lineItemTotal = parameters.line_items.reduce(
      (sum, item) => sum + item.price_data.unit_amount * item.quantity,
      0,
    );
    const shipping =
      parameters.shipping_options[0].shipping_rate_data.fixed_amount.amount;
    const id = `cs_test_${this.idempotentSessions.size + 1}`;
    const session = {
      id,
      url: `https://checkout.stripe.test/${id}`,
      status: 'open',
      payment_status: 'unpaid',
      amount_total: lineItemTotal + shipping,
      currency: parameters.line_items[0].price_data.currency,
      metadata: structuredClone(parameters.metadata),
      payment_intent: null,
      expires_at: parameters.expires_at,
    };
    this.idempotentSessions.set(idempotencyKey, session);
    this.sessions.set(id, session);
    if (this.throwAfterCreateOnce) {
      this.throwAfterCreateOnce = false;
      throw new Error('Simulated lost response after Stripe created a Session.');
    }
    return structuredClone(session);
  }

  async retrieveCheckoutSession(sessionId) {
    this.retrieveCalls.push(sessionId);
    const session = this.sessions.get(sessionId);
    if (!session) throw new Error('Unknown fake Stripe Session.');
    return structuredClone(session);
  }

  async expireCheckoutSession(sessionId, idempotencyKey) {
    this.expireCalls.push({ sessionId, idempotencyKey });
    const session = this.sessions.get(sessionId);
    if (!session) throw new Error('Unknown fake Stripe Session.');
    if (session.payment_status === 'paid') return structuredClone(session);
    session.status = 'expired';
    return structuredClone(session);
  }

  constructWebhookEvent(rawBody, signature) {
    if (signature !== 'test_signature') throw new Error('Bad signature.');
    return JSON.parse(Buffer.from(rawBody).toString('utf8'));
  }

  updateSession(sessionId, patch) {
    const session = this.sessions.get(sessionId);
    if (!session) throw new Error('Unknown fake Stripe Session.');
    Object.assign(session, patch);
    return session;
  }
}

export function stripeEvent(id, type, sessionId) {
  return {
    id,
    type,
    data: { object: { id: sessionId } },
  };
}
