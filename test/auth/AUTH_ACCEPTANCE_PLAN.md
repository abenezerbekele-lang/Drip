# Drip authentication acceptance plan

## Current status

The server now creates unverified accounts, emails single-use confirmation
codes, issues sessions only after verification, persists/revokes expiring JWT
sessions, rate-limits auth and verification attempts, and dispatches welcome
email through an idempotent provider boundary. A durable, bounded outbox worker
retries recent welcome failures with the original idempotency key and stops
outside the provider safety window. Backend acceptance coverage is active in
`server/test/account-service-acceptance.test.js` and the HTTP suites.

The Flutter app now has a secure identity boundary, account-scoped marketplace
storage, session restore/expiry/logout, responsive login/signup screens, and
authenticated token propagation to checkout and Drip Concierge. The focused
Flutter acceptance suites bind directly to those production classes. Local
release checks pass; production still requires configured provider secrets and
a deployed integration run before launch.

## Implemented testable contract

Flutter should expose injectable boundaries equivalent to:

- `AuthGateway.signUp(name, email, password)` returning a memory-only challenge
- `AuthGateway.verifyEmail(challengeToken, code)`
- `AuthGateway.resendVerification(challengeToken)`
- `AuthGateway.signIn(email, password)`
- `AuthGateway.signOut(session)`
- `AuthGateway.restoreSession(storedSession)`
- immutable `AuthUser` and `AuthSession(expiresAt)` values
- typed failures: `emailAlreadyInUse`, `weakPassword`, `invalidCredentials`,
  `invalidVerificationCode`, `verificationExpired`, `providerUnavailable`, and
  `rateLimited`
- an injected clock and session store so expiry/restart behavior is
  deterministic in tests
- an auth controller/root state with `initializing`, `signedOut`, `signedIn`,
  and explicitly isolated `demo` states

Provider credentials and refresh tokens must be stored through a platform
secure-storage adapter, not `SharedPreferences`. Tests may use an in-memory
fake. Welcome-email dispatch belongs behind an idempotent server/provider
boundary keyed by immutable user ID; Flutter must not send it directly.

## P0 gateway and state tests

1. **Email normalization:** `"  Alice@Example.COM  "` is stored and submitted
   as `alice@example.com`. Empty, malformed, control-character, and overlength
   values are rejected. Do not invent Gmail dot or plus-address alias rules.
2. **Duplicate email:** the normalized address can create only one pending
   user. Sequential and concurrent signup attempts create no session or
   welcome-email job. Repeating a pending signup can rotate its challenge only
   after the same password is proven.
3. **Weak password:** a password below the documented minimum returns
   `weakPassword`, creates no user/session/email job, and displays actionable
   signup guidance. Passwords are never trimmed, logged, or echoed.
4. **Generic login failure:** an unknown email and a wrong password return the
   same `invalidCredentials` code and identical user-facing message. The UI
   must not reveal whether an account exists.
5. **Session restore:** a valid persisted session restores the same user after
   controller/app recreation without briefly rendering the signed-out form.
6. **Session expiry:** an expired session is never restored, is removed from
   storage, and routes to signed out. Sign-out also removes it. Use an injected
   clock rather than delays.
7. **Provider rejection:** if restore/refresh explicitly rejects a session,
   clear it and sign out. A transient provider outage must not be described as
   bad credentials or successful authentication.
8. **Provider failure truthfulness:** signup/signin timeout or 5xx leaves the
   user signed out, creates no local fake session, and shows a retryable
   “service unavailable” message without exposing provider internals.
9. **Submission idempotency:** repeated taps and a timeout retry do not create
   duplicate accounts, sessions, or welcome messages. The submit control is
   disabled while a request is active.
10. **Secret hygiene:** password, access token, refresh token, and provider
    response bodies never appear in exceptions, logs, analytics, widget text,
    or `SharedPreferences`.

## Email confirmation security tests

- Signup returns no user or session. It returns a 32-byte opaque challenge only
  to the initiating app, while storage contains only keyed challenge/code
  digests.
- Codes contain exactly six random decimal digits, expire after ten minutes,
  are accepted once, and stop working after five incorrect attempts.
- Verification and resend require the opaque challenge, not an email address.
  Resend rotates the code, observes cooldown/hourly limits, and never creates a
  session.
- Correct verification atomically marks the address verified, creates the
  seller identity and revocable session, consumes the code, and queues exactly
  one welcome message. Replay and concurrent verification cannot create a
  second session or welcome job.
- A lost in-memory challenge is recovered only by repeating signup with the
  same password. Abandoned unverified records are replaceable after the
  configured retention period.

## Welcome email exactly-once tests

Use a fake outbox/sender with call and idempotency-key recording.

- A committed successful verification enqueues one logical welcome message
  using a stable key such as `welcome:<user-id>`.
- Duplicate signup, login, session restore, and app restart enqueue none.
- Concurrent signup callbacks/webhook replay still create one outbox record.
- If the welcome provider fails, the verified account remains usable, the app
  does not claim delivery, and the same outbox record remains retryable.
- The retry worker uses the same idempotency key and cannot create a second
  logical welcome delivery.

## Flutter form and accessibility tests

Run both login and signup at 320x568, 390x844, and 1024x768, plus 200% text
scale, light/dark themes, and a simulated keyboard inset.

- No overflow; the form scrolls and the primary action remains reachable.
- Email and password have visible labels, semantic labels, correct keyboard
  types, and autofill hints (`email`, `password`, `newPassword`).
- Password starts obscured. Its visibility control has a changing accessible
  label such as “Show password” / “Hide password”.
- Submit controls have at least a 48x48 logical hit target and an accessible
  busy state. Enter submits once; rapid taps submit once.
- Validation and provider errors are readable text, not color-only, announced
  as a live region, and focus moves to the first invalid field.
- Login always shows the same message for unknown email and wrong password.
- Switching login/signup and retrying provider errors preserves the normalized
  email without claiming success.
- The six-digit field supports paste and one-time-code autofill, announces
  errors, keeps the challenge only in memory, and provides accessible resend,
  cooldown, expiry, and start-over states.

## Release gate

All P0 tests pass locally with fake providers and an injected clock. Duplicate,
expiry, replay, rate-limit, generic-failure, secret-hygiene, verification, and
welcome-idempotency tests must also pass against the deployed auth and email
integration before production release.
