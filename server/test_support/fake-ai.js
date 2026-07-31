export class FakeAiClient {
  constructor({ moderation = { flagged: false, categories: {} } } = {}) {
    this.moderation = moderation;
    this.moderationCalls = [];
    this.generateCalls = [];
    this.responses = [];
    this.moderationError = null;
    this.generateError = null;
    this.generateGate = null;
  }

  queueResponse(payload) {
    this.responses.push(payload);
  }

  async moderate(input) {
    this.moderationCalls.push(input);
    if (this.moderationError) throw this.moderationError;
    return this.moderation;
  }

  async generate(parameters) {
    this.generateCalls.push(parameters);
    if (this.generateGate) await this.generateGate;
    if (this.generateError) throw this.generateError;
    if (this.responses.length) return this.responses.shift();
    return {
      status: 'completed',
      output_text: JSON.stringify({
        reply:
          'Tell me the occasion, preferred palette, and budget, and I will shape a polished fit around them.',
        intent: 'general',
        followUps: ['Build a casual outfit'],
        productIds: [],
        outfit: null,
        needsHumanSupport: false,
      }),
    };
  }
}
