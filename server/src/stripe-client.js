import { AppError } from './errors.js';

export class UnavailableStripeClient {
  #unavailable(message = 'Stripe Checkout is not configured on this server.') {
    throw new AppError(
      503,
      'payments_unavailable',
      message,
      undefined,
      true,
    );
  }

  async createCheckoutSession() {
    return this.#unavailable();
  }

  async retrieveCheckoutSession() {
    return this.createCheckoutSession();
  }

  async expireCheckoutSession() {
    return this.createCheckoutSession();
  }

  constructWebhookEvent() {
    return this.#unavailable('Stripe webhooks are not configured on this server.');
  }

  async createConnectedAccount() {
    return this.#unavailable('Stripe Connect is not configured on this server.');
  }

  async retrieveConnectedAccount() {
    return this.createConnectedAccount();
  }

  async createConnectedAccountLink() {
    return this.createConnectedAccount();
  }

  async createExpressDashboardLoginLink() {
    return this.createConnectedAccount();
  }

  constructConnectEvent() {
    return this.#unavailable('Stripe Connect webhooks are not configured on this server.');
  }
}

export async function createRealStripeClient(config) {
  if (!config.paymentsConfigured) return new UnavailableStripeClient();
  const { default: Stripe } = await import('stripe');
  const stripe = new Stripe(config.stripeSecretKey, {
    apiVersion: '2026-06-24.dahlia',
    maxNetworkRetries: 2,
    timeout: 20_000,
    telemetry: false,
    appInfo: {
      name: 'Drip Checkout Service',
      version: '1.0.0',
    },
  });

  return Object.freeze({
    createCheckoutSession(parameters, idempotencyKey) {
      return stripe.checkout.sessions.create(parameters, { idempotencyKey });
    },
    retrieveCheckoutSession(sessionId) {
      return stripe.checkout.sessions.retrieve(sessionId, {
        expand: ['line_items'],
      });
    },
    expireCheckoutSession(sessionId, idempotencyKey) {
      return stripe.checkout.sessions.expire(
        sessionId,
        {},
        { idempotencyKey },
      );
    },
    constructWebhookEvent(rawBody, signature) {
      return stripe.webhooks.constructEvent(
        rawBody,
        signature,
        config.stripeWebhookSecret,
      );
    },
    createConnectedAccount({ displayName, email, sellerHandle }, idempotencyKey) {
      return stripe.v2.core.accounts.create(
        {
          display_name: displayName,
          contact_email: email,
          dashboard: 'express',
          identity: { country: config.connectDefaultCountry },
          defaults: {
            currency: config.connectDefaultCurrency,
            profile: {
              product_description:
                'Peer-to-peer resale marketplace for clothing, footwear, and accessories.',
            },
            responsibilities: {
              fees_collector: 'application',
              losses_collector: 'application',
            },
          },
          configuration: {
            recipient: {
              capabilities: {
                stripe_balance: {
                  stripe_transfers: { requested: true },
                },
              },
            },
          },
          metadata: {
            drip_seller_handle: sellerHandle,
            drip_service: 'drip_connect_v2',
          },
          include: [
            'configuration.recipient',
            'defaults',
            'future_requirements',
            'identity',
            'requirements',
          ],
        },
        { idempotencyKey },
      );
    },
    retrieveConnectedAccount(accountId) {
      return stripe.v2.core.accounts.retrieve(accountId, {
        include: [
          'configuration.recipient',
          'defaults',
          'future_requirements',
          'identity',
          'requirements',
        ],
      });
    },
    createConnectedAccountLink(accountId, { refreshUrl, returnUrl }) {
      return stripe.v2.core.accountLinks.create({
        account: accountId,
        use_case: {
          type: 'account_onboarding',
          account_onboarding: {
            configurations: ['recipient'],
            refresh_url: refreshUrl,
            return_url: returnUrl,
            collection_options: {
              fields: 'eventually_due',
              future_requirements: 'include',
            },
          },
        },
      });
    },
    createExpressDashboardLoginLink(accountId) {
      return stripe.accounts.createLoginLink(accountId);
    },
    constructConnectEvent(rawBody, signature) {
      return stripe.parseEventNotification(
        rawBody,
        signature,
        config.stripeConnectWebhookSecret,
      );
    },
  });
}
