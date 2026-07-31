import { AppError } from '../src/errors.js';

export class FakeEmailClient {
  constructor() {
    this.verificationCalls = [];
    this.welcomeCalls = [];
    this.error = null;
    this.verificationError = null;
    this.welcomeError = null;
  }

  async sendVerification(message) {
    this.verificationCalls.push(structuredClone(message));
    if (this.verificationError || this.error) {
      throw this.verificationError || this.error;
    }
    return Object.freeze({
      providerMessageId: `email_verification_test_${this.verificationCalls.length}`,
    });
  }

  async sendWelcome(message) {
    this.welcomeCalls.push(structuredClone(message));
    if (this.welcomeError || this.error) throw this.welcomeError || this.error;
    return Object.freeze({
      providerMessageId: `email_test_${this.welcomeCalls.length}`,
    });
  }
}

export function failingEmailClient() {
  const client = new FakeEmailClient();
  client.error = new AppError(
    503,
    'email_provider_unavailable',
    'Email unavailable.',
    undefined,
    true,
  );
  return client;
}
