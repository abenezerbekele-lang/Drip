import { existsSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

import { createRealAiClient } from './ai-client.js';
import { AiConciergeService } from './ai-service.js';
import { AccountService } from './account-service.js';
import { CheckoutService } from './checkout-service.js';
import { ConnectService } from './connect-service.js';
import { loadConfig } from './config.js';
import { createDatabase } from './database.js';
import { createRealEmailClient } from './email-client.js';
import { createFirebaseAuthVerifier } from './firebase-auth.js';
import { FirebaseEmailCodeService } from './firebase-email-code-service.js';
import { createHttpServer } from './http-server.js';
import { createMarketplaceDatabase } from './marketplace-database.js';
import { createRealStripeClient } from './stripe-client.js';

const [major, minor] = process.versions.node.split('.').map(Number);
if (major < 24 || (major === 24 && minor < 12)) {
  throw new Error('Drip Checkout requires Node.js 24.12 or newer.');
}

// Resolve local configuration and relative storage from the server directory,
// even when this entrypoint is launched from the repository root or an IDE.
// Provider secrets remain in server/.env and are never copied into Flutter.
const serverDirectory = fileURLToPath(new URL('..', import.meta.url));
process.chdir(serverDirectory);
if (existsSync('.env')) process.loadEnvFile('.env');

const config = loadConfig();
const database = createDatabase(config.databasePath);
const marketplaceDatabase = await createMarketplaceDatabase(config, {
  sqliteDatabase: database,
});
const stripeClient = await createRealStripeClient(config);
const aiClient = await createRealAiClient(config);
const emailClient = createRealEmailClient(config);
const firebaseAuthVerifier = await createFirebaseAuthVerifier(config);
const checkoutService = new CheckoutService({
  database,
  stripeClient,
  config,
});
const aiService = new AiConciergeService({
  database,
  aiClient,
  config,
});
const accountService = config.accountAuthEnabled
  ? new AccountService({ database, emailClient, config })
  : null;
const firebaseEmailCodeService = config.firebaseEmailCodeConfigured
  ? new FirebaseEmailCodeService({
      database,
      emailClient,
      firebaseAuth: firebaseAuthVerifier,
      config,
    })
  : null;
const connectService = config.stripeConnectConfigured
  ? new ConnectService({ database, stripeClient, config })
  : null;
const welcomeEmailWorker = accountService?.startWelcomeEmailWorker() ?? null;
const server = createHttpServer({
  checkoutService,
  aiService,
  accountService,
  connectService,
  config,
  database,
  firebaseEmailCodeService,
  firebaseAuthVerifier,
  marketplaceDatabase,
});

server.listen(config.port, config.host, () => {
  console.log(
    `Drip Checkout listening on http://${config.host}:${config.port} ` +
      `(Stripe ${config.paymentsConfigured ? 'configured' : 'disabled'}, ` +
      `AI ${config.aiConfigured ? 'configured' : 'disabled'}, ` +
      `accounts ${
        config.accountAuthEnabled || config.authMode === 'firebase'
          ? config.authMode
          : 'disabled'
      }, ` +
      `Connect ${config.stripeConnectConfigured ? 'configured' : 'disabled'}, ` +
      `catalog ${marketplaceDatabase.provider})`,
  );
});

let closing = false;
function shutdown(signal) {
  if (closing) return;
  closing = true;
  console.log(`Received ${signal}; closing Drip Checkout.`);
  const servicesStopped = Promise.all([
    welcomeEmailWorker?.stop() ?? Promise.resolve(),
    firebaseAuthVerifier?.close() ?? Promise.resolve(),
  ]);
  server.close(async () => {
    try {
      await servicesStopped;
      await marketplaceDatabase.close();
    } finally {
      database.close();
      process.exit(0);
    }
  });
  setTimeout(() => process.exit(1), 10_000).unref();
}

process.on('SIGINT', () => shutdown('SIGINT'));
process.on('SIGTERM', () => shutdown('SIGTERM'));
