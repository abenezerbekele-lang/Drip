import { loadConfig } from '../src/config.js';
import { CheckoutService } from '../src/checkout-service.js';
import { createDatabase } from '../src/database.js';
import { FakeStripeClient } from './fake-stripe.js';

export const demoBuyer = Object.freeze({
  id: 'dev-alex',
  sellerHandle: '@alexwears',
});

export function testConfig(overrides = {}) {
  const config = loadConfig({
    NODE_ENV: 'test',
    AUTH_MODE: 'development',
    DATABASE_PATH: ':memory:',
    CHECKOUT_RESERVATION_MINUTES: '31',
    CHECKOUT_SUCCESS_URL:
      'http://localhost:4242/checkout/success?session_id={CHECKOUT_SESSION_ID}',
    CHECKOUT_CANCEL_URL: 'http://localhost:4242/checkout/cancel',
    CORS_ALLOWED_ORIGINS: 'http://localhost:8080',
    ...overrides,
  });
  return config;
}

export function testContext({
  config = testConfig(),
  now = 1_800_000_000_000,
  clock = () => now,
} = {}) {
  const database = createDatabase(':memory:');
  const stripeClient = new FakeStripeClient();
  const service = new CheckoutService({
    database,
    stripeClient,
    config,
    clock,
  });
  return { database, stripeClient, service, config };
}
