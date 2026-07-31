import { AppError } from './errors.js';

function providerError(error) {
  if (error instanceof AppError) return error;
  if (error?.status === 429) {
    return new AppError(
      503,
      'ai_provider_busy',
      'Drip AI is receiving more requests than usual. Try again shortly.',
      undefined,
      true,
    );
  }
  return new AppError(
    503,
    'ai_provider_unavailable',
    'Drip AI could not answer right now. Try again shortly.',
    undefined,
    true,
  );
}

export class UnavailableAiClient {
  async moderate() {
    throw new AppError(
      503,
      'ai_unavailable',
      'Drip AI is not connected on this server.',
      undefined,
      true,
    );
  }

  async generate() {
    return this.moderate();
  }
}

export async function createRealAiClient(config) {
  if (!config.aiConfigured) return new UnavailableAiClient();
  const { default: OpenAI } = await import('openai');
  const openai = new OpenAI({
    apiKey: config.openaiApiKey,
    maxRetries: 2,
    timeout: config.aiTimeoutMs,
  });

  return Object.freeze({
    async moderate(input) {
      try {
        const result = await openai.moderations.create({
          model: config.openaiModerationModel,
          input,
        });
        const moderation = result.results?.[0];
        if (!moderation || typeof moderation.flagged !== 'boolean') {
          throw new AppError(
            503,
            'ai_moderation_unavailable',
            'Drip AI safety checks could not complete. Try again shortly.',
            undefined,
            true,
          );
        }
        return moderation;
      } catch (error) {
        throw providerError(error);
      }
    },

    async generate(parameters) {
      try {
        return await openai.responses.create(parameters);
      } catch (error) {
        throw providerError(error);
      }
    },
  });
}
