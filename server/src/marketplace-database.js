import { AppError } from './errors.js';
import { listCatalog } from './database.js';

const MAX_CATALOG_DOCUMENTS = 500;
let firebaseAppSequence = 0;

function withTimeout(promise, timeoutMs, message) {
  let timeout;
  const timeoutPromise = new Promise((_, reject) => {
    timeout = setTimeout(() => {
      reject(
        new AppError(
          503,
          'database_unavailable',
          message,
          undefined,
          true,
        ),
      );
    }, timeoutMs);
    timeout.unref?.();
  });
  return Promise.race([promise, timeoutPromise]).finally(() => {
    clearTimeout(timeout);
  });
}

function validText(value, { min = 1, max, pattern } = {}) {
  return (
    typeof value === 'string' &&
    value.length >= min &&
    value.length <= max &&
    (!pattern || pattern.test(value))
  );
}

function catalogItem(document) {
  const data = document.data();
  const item = {
    id: document.id,
    name: data?.name,
    brand: data?.brand,
    sellerHandle: data?.sellerHandle,
    priceCents: data?.priceCents,
    currency: data?.currency,
    sizes: data?.sizes,
    status: data?.status,
  };
  const valid =
    validText(item.id, {
      max: 80,
      pattern: /^[a-z0-9][a-z0-9-]+$/,
    }) &&
    validText(item.name, { max: 120 }) &&
    validText(item.brand, { max: 80 }) &&
    validText(item.sellerHandle, {
      max: 40,
      pattern: /^@[A-Za-z0-9._]+$/,
    }) &&
    Number.isSafeInteger(item.priceCents) &&
    item.priceCents >= 1_000 &&
    item.priceCents <= 100_000_000 &&
    validText(item.currency, {
      min: 3,
      max: 3,
      pattern: /^[a-z]{3}$/,
    }) &&
    Array.isArray(item.sizes) &&
    item.sizes.length >= 1 &&
    item.sizes.length <= 30 &&
    item.sizes.every((size) => validText(size, { max: 30 })) &&
    new Set(['live', 'reserved', 'sold', 'paused']).has(item.status);
  if (!valid) {
    throw new AppError(
      500,
      'invalid_marketplace_data',
      'A Firestore listing does not match the Drip catalog contract.',
    );
  }
  return Object.freeze({
    ...item,
    sizes: Object.freeze([...item.sizes]),
    sortOrder:
      Number.isSafeInteger(data.sortOrder) && data.sortOrder >= 0
        ? data.sortOrder
        : Number.MAX_SAFE_INTEGER,
  });
}

export class SqliteMarketplaceDatabase {
  provider = 'sqlite';
  #database;

  constructor(database) {
    this.#database = database;
  }

  async assertReady() {}

  async listCatalog() {
    return listCatalog(this.#database);
  }

  async close() {}
}

export class FirestoreMarketplaceDatabase {
  provider = 'firestore';
  #firestore;
  #firebaseApp;
  #deleteApp;
  #timeoutMs;
  #ready = false;

  constructor({
    firestore,
    firebaseApp,
    deleteApp,
    timeoutMs = 10_000,
  }) {
    this.#firestore = firestore;
    this.#firebaseApp = firebaseApp;
    this.#deleteApp = deleteApp;
    this.#timeoutMs = timeoutMs;
  }

  async assertReady() {
    try {
      await withTimeout(
        this.#firestore
          .collection('_drip_system')
          .doc('connectivity')
          .get(),
        this.#timeoutMs,
        'Firestore did not respond before startup timed out.',
      );
      this.#ready = true;
    } catch (error) {
      if (error instanceof AppError) throw error;
      throw new AppError(
        503,
        'database_unavailable',
        'Firestore could not be reached with the configured project and credentials.',
        undefined,
        true,
      );
    }
  }

  async listCatalog() {
    if (!this.#ready) {
      throw new AppError(
        503,
        'database_unavailable',
        'The Firestore marketplace database is not ready.',
        undefined,
        true,
      );
    }
    let snapshot;
    try {
      snapshot = await withTimeout(
        this.#firestore
          .collection('marketplace_listings')
          .limit(MAX_CATALOG_DOCUMENTS + 1)
          .get(),
        this.#timeoutMs,
        'The Firestore catalog request timed out.',
      );
    } catch (error) {
      if (error instanceof AppError) throw error;
      throw new AppError(
        503,
        'database_unavailable',
        'The marketplace catalog is temporarily unavailable.',
        undefined,
        true,
      );
    }
    if (snapshot.docs.length > MAX_CATALOG_DOCUMENTS) {
      throw new AppError(
        500,
        'invalid_marketplace_data',
        `The Firestore catalog exceeds ${MAX_CATALOG_DOCUMENTS} documents.`,
      );
    }
    return snapshot.docs
      .map(catalogItem)
      .sort(
        (left, right) =>
          left.sortOrder - right.sortOrder || left.id.localeCompare(right.id),
      )
      .map(({ sortOrder: _sortOrder, ...item }) => Object.freeze(item));
  }

  async close() {
    this.#ready = false;
    if (typeof this.#firestore.terminate === 'function') {
      await this.#firestore.terminate();
    }
    if (this.#firebaseApp && this.#deleteApp) {
      await this.#deleteApp(this.#firebaseApp);
    }
  }
}

async function firebaseSdk() {
  const [app, firestore] = await Promise.all([
    import('firebase-admin/app'),
    import('firebase-admin/firestore'),
  ]);
  return { app, firestore };
}

export async function createMarketplaceDatabase(
  config,
  { sqliteDatabase, sdk } = {},
) {
  if (config.marketplaceDatabaseProvider === 'sqlite') {
    if (!sqliteDatabase) {
      throw new TypeError('SQLite marketplace storage requires a database.');
    }
    const provider = new SqliteMarketplaceDatabase(sqliteDatabase);
    await provider.assertReady();
    return provider;
  }

  const firebase = sdk || (await firebaseSdk());
  let app;
  try {
    app = firebase.app.initializeApp(
      {
        credential: firebase.app.applicationDefault(),
        projectId: config.firebaseProjectId,
      },
      `drip-marketplace-${process.pid}-${firebaseAppSequence++}`,
    );
    const firestore = firebase.firestore.getFirestore(app);
    const provider = new FirestoreMarketplaceDatabase({
      firestore,
      firebaseApp: app,
      deleteApp: firebase.app.deleteApp,
      timeoutMs: config.firebaseConnectTimeoutMs,
    });
    await provider.assertReady();
    return provider;
  } catch (error) {
    if (app && typeof firebase.app.deleteApp === 'function') {
      await firebase.app.deleteApp(app).catch(() => {});
    }
    if (error instanceof AppError) throw error;
    throw new AppError(
      503,
      'database_unavailable',
      'Firestore could not start with the configured project and credentials.',
      undefined,
      true,
    );
  }
}
