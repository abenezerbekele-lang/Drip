import assert from 'node:assert/strict';
import test from 'node:test';

import {
  createRealAiClient,
  UnavailableAiClient,
} from '../src/ai-client.js';
import { testConfig } from '../test_support/setup.js';

test('OpenAI client stays unavailable without a server key', async () => {
  const client = await createRealAiClient(testConfig());
  assert.ok(client instanceof UnavailableAiClient);
  await assert.rejects(
    client.generate({}),
    (error) => error.code === 'ai_unavailable' && error.status === 503,
  );
});

test('configured client exposes only moderation and Responses boundaries', async () => {
  const client = await createRealAiClient(
    testConfig({
      AI_ENABLED: 'true',
      OPENAI_API_KEY: 'sk-test-constructor-only',
    }),
  );
  assert.equal(typeof client.moderate, 'function');
  assert.equal(typeof client.generate, 'function');
  assert.deepEqual(Object.keys(client).sort(), ['generate', 'moderate']);
});
