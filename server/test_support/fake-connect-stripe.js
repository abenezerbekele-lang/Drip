export function connectedAccount({
  id = 'acct_ConnectTest123456789',
  livemode = false,
  transfers = 'pending',
  payouts = 'pending',
  requirementStatus = null,
  closed = false,
  dashboard = 'express',
} = {}) {
  const requirements = requirementStatus
    ? {
        entries: [
          {
            awaiting_action_from: 'user',
            minimum_deadline: { status: requirementStatus },
          },
        ],
        summary: { minimum_deadline: { status: requirementStatus } },
      }
    : { entries: [], summary: {} };
  return {
    id,
    object: 'v2.core.account',
    livemode,
    closed,
    dashboard,
    identity: { country: 'US' },
    configuration: {
      recipient: {
        capabilities: {
          stripe_balance: {
            stripe_transfers: { status: transfers, status_details: [] },
            payouts: { status: payouts, status_details: [] },
          },
        },
      },
    },
    requirements,
  };
}

export class FakeConnectStripeClient {
  constructor({ account = connectedAccount() } = {}) {
    this.account = structuredClone(account);
    this.createCalls = [];
    this.retrieveCalls = [];
    this.accountLinkCalls = [];
    this.dashboardCalls = [];
    this.createDelay = null;
  }

  async createConnectedAccount(details, idempotencyKey) {
    this.createCalls.push({ details: structuredClone(details), idempotencyKey });
    if (this.createDelay) await this.createDelay;
    return structuredClone(this.account);
  }

  async retrieveConnectedAccount(accountId) {
    this.retrieveCalls.push(accountId);
    if (accountId !== this.account.id) throw new Error('Unknown connected account.');
    return structuredClone(this.account);
  }

  async createConnectedAccountLink(accountId, options) {
    this.accountLinkCalls.push({ accountId, options: structuredClone(options) });
    return {
      url: 'https://accounts.stripe.com/r/test-link#alu_opaque-state',
      expires_at: '2027-01-15T08:05:00.000Z',
    };
  }

  async createExpressDashboardLoginLink(accountId) {
    this.dashboardCalls.push(accountId);
    return { url: 'https://connect.stripe.com/express/test-login' };
  }

  constructConnectEvent(rawBody, signature) {
    if (signature !== 'connect_test_signature') throw new Error('Bad signature.');
    return JSON.parse(Buffer.from(rawBody).toString('utf8'));
  }

  updateAccount(patch) {
    this.account = { ...this.account, ...structuredClone(patch) };
  }
}

export function connectEvent({
  id = 'evt_connect_test_123456789',
  type = 'v2.core.account[configuration.recipient].capability_status_updated',
  accountId = 'acct_ConnectTest123456789',
  livemode = false,
} = {}) {
  return {
    id,
    object: 'v2.core.event',
    type,
    livemode,
    related_object: {
      id: accountId,
      type: 'v2.core.account',
      url: `/v2/core/accounts/${accountId}`,
    },
  };
}
