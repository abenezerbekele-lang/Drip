import assert from 'node:assert/strict';
import test from 'node:test';

import { AiConciergeService } from '../src/ai-service.js';
import { createDatabase } from '../src/database.js';
import { createHttpServer } from '../src/http-server.js';
import { FakeAiClient } from '../test_support/fake-ai.js';
import { testConfig } from '../test_support/setup.js';

async function listen(server) {
  await new Promise((resolve, reject) => {
    server.once('error', reject);
    server.listen(0, '127.0.0.1', resolve);
  });
  const address = server.address();
  return `http://127.0.0.1:${address.port}`;
}

async function close(server) {
  await new Promise((resolve) => server.close(resolve));
}

function checkoutStub() {
  return {
    handleWebhook() {
      throw new Error('not used');
    },
  };
}

test('POST /v1/ai/chat exposes only the validated concierge contract', async () => {
  const config = testConfig({
    AI_ENABLED: 'true',
    OPENAI_API_KEY: 'sk-test-http-ai',
  });
  const database = createDatabase(':memory:');
  const aiClient = new FakeAiClient();
  const aiService = new AiConciergeService({ database, aiClient, config });
  const server = createHttpServer({
    checkoutService: checkoutStub(),
    aiService,
    config,
    database,
  });
  const base = await listen(server);
  try {
    const health = await fetch(`${base}/healthz`);
    assert.equal((await health.json()).aiConfigured, true);

    const response = await fetch(`${base}/v1/ai/chat`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Origin: 'http://localhost:8080',
      },
      body: JSON.stringify({
        message: 'Help me build a clean fit.',
        history: [],
        context: { entryPoint: 'home' },
      }),
    });
    assert.equal(response.status, 200);
    assert.equal(
      response.headers.get('access-control-allow-origin'),
      'http://localhost:8080',
    );
    assert.equal(response.headers.get('cache-control'), 'no-store');
    const payload = await response.json();
    assert.deepEqual(Object.keys(payload), [
      'reply',
      'intent',
      'followUps',
      'productIds',
      'outfit',
      'needsHumanSupport',
    ]);
    assert.equal(aiClient.generateCalls.length, 1);
  } finally {
    await close(server);
    database.close();
  }
});

test('AI HTTP surface fails closed when it is not configured', async () => {
  const config = testConfig();
  const database = createDatabase(':memory:');
  const server = createHttpServer({
    checkoutService: checkoutStub(),
    config,
    database,
  });
  const base = await listen(server);
  try {
    const response = await fetch(`${base}/v1/ai/chat`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        message: 'Hello',
        history: [],
        context: { entryPoint: 'ai' },
      }),
    });
    assert.equal(response.status, 503);
    const payload = await response.json();
    assert.equal(payload.error.code, 'ai_unavailable');
    assert.equal(payload.error.retryable, true);
  } finally {
    await close(server);
    database.close();
  }
});

test('AI HTTP rate limits include a standards-based Retry-After header', async () => {
  const config = testConfig({
    AI_ENABLED: 'true',
    OPENAI_API_KEY: 'sk-test-rate-ai',
    AI_RATE_LIMIT_PER_MINUTE: '1',
    AI_RATE_LIMIT_PER_DAY: '10',
  });
  const database = createDatabase(':memory:');
  const aiService = new AiConciergeService({
    database,
    aiClient: new FakeAiClient(),
    config,
    clock: () => 1_800_000_000_000,
  });
  const server = createHttpServer({
    checkoutService: checkoutStub(),
    aiService,
    config,
    database,
  });
  const base = await listen(server);
  const options = {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      message: 'Build a fit.',
      history: [],
      context: { entryPoint: 'ai' },
    }),
  };
  try {
    assert.equal((await fetch(`${base}/v1/ai/chat`, options)).status, 200);
    const limited = await fetch(`${base}/v1/ai/chat`, options);
    assert.equal(limited.status, 429);
    assert.ok(Number(limited.headers.get('retry-after')) > 0);
  } finally {
    await close(server);
    database.close();
  }
});
