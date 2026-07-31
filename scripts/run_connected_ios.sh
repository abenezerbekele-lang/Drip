#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
NODE_BIN="/Users/abeniizerbekele/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/bin/node"
FLUTTER_BIN="/Users/abeniizerbekele/downloads/flutter/bin/flutter"
STRIPE_BIN="$ROOT_DIR/.tools/stripe"
DEVICE_ID="${1:-ios}"
SERVER_PID=""
STRIPE_PID=""

cleanup() {
  if [[ -n "$STRIPE_PID" ]]; then
    kill "$STRIPE_PID" 2>/dev/null || true
  fi
  if [[ -n "$SERVER_PID" ]]; then
    kill "$SERVER_PID" 2>/dev/null || true
  fi
}
trap cleanup EXIT INT TERM

"$NODE_BIN" "$ROOT_DIR/scripts/check_connected_services.mjs" --config-only

if [[ ! -x "$STRIPE_BIN" ]]; then
  echo "Stripe CLI is missing at $STRIPE_BIN."
  echo "Install it before testing webhook-confirmed checkout."
  exit 1
fi

if ! curl --fail --silent --max-time 2 \
  http://127.0.0.1:4242/healthz >/dev/null 2>&1; then
  "$NODE_BIN" "$ROOT_DIR/server/src/server.js" &
  SERVER_PID="$!"
  for _ in {1..30}; do
    if curl --fail --silent --max-time 1 \
      http://127.0.0.1:4242/healthz >/dev/null 2>&1; then
      break
    fi
    sleep 0.2
  done
fi

"$NODE_BIN" "$ROOT_DIR/scripts/check_connected_services.mjs"

CONFIGURED_WEBHOOK_SECRET="$(
  sed -n 's/^STRIPE_WEBHOOK_SECRET=//p' "$ROOT_DIR/server/.env" | head -n 1
)"
CONFIGURED_WEBHOOK_SECRET="${CONFIGURED_WEBHOOK_SECRET#\"}"
CONFIGURED_WEBHOOK_SECRET="${CONFIGURED_WEBHOOK_SECRET%\"}"
CONFIGURED_WEBHOOK_SECRET="${CONFIGURED_WEBHOOK_SECRET#\'}"
CONFIGURED_WEBHOOK_SECRET="${CONFIGURED_WEBHOOK_SECRET%\'}"
ACTIVE_WEBHOOK_SECRET="$("$STRIPE_BIN" listen --print-secret)"
if [[ "$CONFIGURED_WEBHOOK_SECRET" != "$ACTIVE_WEBHOOK_SECRET" ]]; then
  echo "Stripe webhook signing secret does not match this CLI login."
  echo "Refresh STRIPE_WEBHOOK_SECRET in server/.env, then retry."
  exit 1
fi

"$STRIPE_BIN" listen \
  --forward-to http://127.0.0.1:4242/v1/stripe/webhook \
  --events checkout.session.completed,checkout.session.async_payment_succeeded,checkout.session.async_payment_failed,checkout.session.expired \
  >"$ROOT_DIR/.tools/stripe-listen.log" 2>&1 &
STRIPE_PID="$!"
sleep 0.5
if ! kill -0 "$STRIPE_PID" 2>/dev/null; then
  echo "Stripe webhook forwarding did not start."
  exit 1
fi

"$FLUTTER_BIN" run \
  --debug \
  -d "$DEVICE_ID" \
  --dart-define=DRIP_API_URL=http://localhost:4242
