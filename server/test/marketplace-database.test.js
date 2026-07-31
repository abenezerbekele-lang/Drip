import assert from 'node:assert/strict';
import test from 'node:test';

import { loadConfig } from '../src/config.js';
import { createDatabase } from '../src/database.js';
import {
  createMarketplaceDatabase,
  FirestoreMarketplaceDatabase,
} from '../src/marketplace-database.js';

function firestoreConfig(overrides = {}) {
  return loadConfig({
    NODE_ENV: 'test',
    AUTH_MODE: 'development',
    DATABASE_PATH: ':memory:',
    MARKETPLACE_DATABASE_PROVIDER: 'firestore',
    FIREBASE_PROJECT_ID: 'drip-marketplace-test',
    FIREBASE_CREDENTIALS_MODE: 'application-default',
    ...overrides,
  });
}

function document(id, data) {
  return { id, data: () => data };
}

function fakeFirestore({ documents = [], connectivityError = null } = {}) {
  let terminated = false;
  const firestore = {
    collection(name) {
      if (name === '_drip_system') {
        return {
          doc() {
            return {
              async get() {
                if (connectivityError) throw connectivityError;
                return { exists: false };
              },
            };
          },
        };
      }
      assert.equal(name, 'marketplace_listings');
      return {
        limit(limit) {
          assert.equal(limit, 501);
          return {
            async get() {
              return { docs: documents };
            },
          };
        },
      };
    },
    async terminate() {
      terminated = true;
    },
  };
  return { firestore, wasTerminated: () => terminated };
}

test('SQLite remains the local catalog provider', async () => {
  const database = createDatabase(':memory:');
  try {
    const provider = await createMarketplaceDatabase(
      loadConfig({
        NODE_ENV: 'test',
        AUTH_MODE: 'development',
        DATABASE_PATH: ':memory:',
      }),
      { sqliteDatabase: database },
    );
    assert.equal(provider.provider, 'sqlite');
    assert.equal((await provider.listCatalog()).length, 44);
  } finally {
    database.close();
  }
});

test('Firestore initializes with explicit ADC and serves only validated catalog fields', async () => {
  const fake = fakeFirestore({
    documents: [
      document('future-runner', {
        name: 'Future Runner',
        brand: 'Drip Lab',
        sellerHandle: '@futurecloset',
        priceCents: 18_500,
        currency: 'usd',
        sizes: ['9', '10'],
        status: 'live',
        sortOrder: 20,
        privateNotes: 'must never leave the server boundary',
      }),
      document('archive-jacket', {
        name: 'Archive Jacket',
        brand: 'Signal',
        sellerHandle: '@archive',
        priceCents: 24_000,
        currency: 'usd',
        sizes: ['M'],
        status: 'paused',
        sortOrder: 10,
      }),
    ],
  });
  const initialized = [];
  const deleted = [];
  const provider = await createMarketplaceDatabase(firestoreConfig(), {
    sdk: {
      app: {
        applicationDefault: () => ({ kind: 'adc' }),
        initializeApp: (options, name) => {
          initialized.push({ options, name });
          return { name };
        },
        deleteApp: async (app) => deleted.push(app),
      },
      firestore: {
        getFirestore: () => fake.firestore,
      },
    },
  });
  assert.equal(provider.provider, 'firestore');
  assert.equal(initialized[0].options.projectId, 'drip-marketplace-test');
  assert.deepEqual(await provider.listCatalog(), [
    {
      id: 'archive-jacket',
      name: 'Archive Jacket',
      brand: 'Signal',
      sellerHandle: '@archive',
      priceCents: 24_000,
      currency: 'usd',
      sizes: ['M'],
      status: 'paused',
    },
    {
      id: 'future-runner',
      name: 'Future Runner',
      brand: 'Drip Lab',
      sellerHandle: '@futurecloset',
      priceCents: 18_500,
      currency: 'usd',
      sizes: ['9', '10'],
      status: 'live',
    },
  ]);
  await provider.close();
  assert.equal(fake.wasTerminated(), true);
  assert.equal(deleted.length, 1);
});

test('Firestore startup and malformed production data fail closed', async () => {
  const unavailable = fakeFirestore({
    connectivityError: new Error('missing application default credentials'),
  });
  await assert.rejects(
    () =>
      createMarketplaceDatabase(firestoreConfig(), {
        sdk: {
          app: {
            applicationDefault: () => ({ kind: 'adc' }),
            initializeApp: () => ({ name: 'failed-app' }),
            deleteApp: async () => {},
          },
          firestore: { getFirestore: () => unavailable.firestore },
        },
      }),
    (error) =>
      error.code === 'database_unavailable' && error.retryable === true,
  );

  const malformed = fakeFirestore({
    documents: [
      document('unsafe-listing', {
        name: 'Unsafe',
        brand: 'Drip',
        sellerHandle: '@seller',
        priceCents: -1,
        currency: 'usd',
        sizes: ['M'],
        status: 'live',
      }),
    ],
  });
  const provider = new FirestoreMarketplaceDatabase({
    firestore: malformed.firestore,
    timeoutMs: 1_000,
  });
  await provider.assertReady();
  await assert.rejects(
    () => provider.listCatalog(),
    (error) => error.code === 'invalid_marketplace_data',
  );
});
