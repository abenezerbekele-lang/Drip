# Drip Requirements Checklist

This checklist maps the photographed whiteboard requirements to repository
evidence and the remaining owner actions. “Code complete” means the capability
exists and is testable; it does not mean a third-party production account is
already connected.

| # | Whiteboard requirement | Delivery status | Evidence | Acceptance test / remaining action |
| ---: | --- | --- | --- | --- |
| 1 | Database (Firebase) | **Code complete; activation required** | `server/src/marketplace-database.js`, `firebase.json`, deny-by-default `firestore.rules`, provider configuration in `server/src/config.js`, and the data section in [`TECHNICAL_DOCUMENTATION.md`](TECHNICAL_DOCUMENTATION.md) | Select `firestore` in staging, attach owner-controlled Application Default Credentials, load approved `marketplace_listings`, and confirm readiness without a fallback |
| 2 | Payment system (Stripe) | **Code complete; activation required** | `lib/payments/`, `server/src/checkout-service.js`, `server/src/connect-service.js`, and signed webhook routes | Add Stripe test keys and separate Checkout/Connect webhook secrets; complete a webhook-confirmed test payment and recipient onboarding |
| 3 | User profile / login / logout | **Firebase and Google connected for iOS; Android debug OAuth configured; API/email deployment required for numeric codes** | `lib/auth/firebase_auth_gateway.dart`, `lib/auth/google_identity_client.dart`, native Firebase/OAuth configuration, `lib/profile_page.dart`, `server/src/firebase-auth.js`, `server/src/firebase-email-code-service.js`, protected-route token checks, and Firebase auth tests | Complete one manual Google account-picker login; create an email/password account and open the default verification link; after attaching Firebase Admin plus a verified sender, enable and test the six-digit flow; refresh the ID token, restore the session, request password reset, and separately revoke tokens to confirm rejection |
| 4 | Production website; no template data | **Build path complete; deployment/data activation required** | Website package in [`website/`](../website/), responsive Flutter web app, production provider boundary, and deployment section in [`TECHNICAL_DOCUMENTATION.md`](TECHNICAL_DOCUMENTATION.md). Final hosted URL: **pending deployment** | Build without `DRIP_ENABLE_DEMO_MODE`, use the HTTPS production API, populate real approved provider records, deploy, record the final hosted URL, and run the release smoke test |
| 5 | README | **Complete** | [`../README.md`](../README.md) | A new contributor can understand scope, run preview, connect the stack, and distinguish code from live activation |
| 6 | Business Model Canvas | **Complete** | [`BUSINESS_MODEL.md`](BUSINESS_MODEL.md) | Validate customer, pricing, and unit-economics assumptions with real evidence before calling them traction |
| 7 | Technical documentation | **Complete** | [`TECHNICAL_DOCUMENTATION.md`](TECHNICAL_DOCUMENTATION.md) and [`PRODUCTION_ROADMAP.md`](PRODUCTION_ROADMAP.md) | Keep architecture, variables, tests, security, gaps, and readiness state synchronized with code |
| 8 | Six-slide pitch deck | **Complete** | [`deliverables/drip_pitch_deck.pptx`](../deliverables/drip_pitch_deck.pptx) | Verified as exactly six slides, rendered slide-by-slide, visually inspected, and passed the automated overflow check |
| 9 | Two-minute demo video | **Complete** | [`deliverables/drip_demo_2min.mp4`](../deliverables/drip_demo_2min.mp4) | Verified at exactly 120 seconds with readable app footage, audible narration, and no exposed secrets or real card data |

## Production website “no template data” gate

A build passes this requirement only when all of the following are true:

- `DRIP_ENABLE_DEMO_MODE` is absent or false.
- `DRIP_API_URL` is an explicit HTTPS production origin.
- The server selects the Firestore marketplace provider.
- The Firebase project contains reviewed Drip catalog records owned by the
  operator.
- No local demo account, sample metric, placeholder seller, test card, or
  staging banner is represented as production customer data.
- Empty, loading, unavailable, and error states remain usable when production
  records are absent.
- Stripe and protected-API readiness are verified independently; a populated
  catalog must not make checkout or the deployed API appear configured.

## Final acceptance run

```sh
flutter analyze
flutter test
cd server && npm test
flutter build web --release \
  --dart-define=DRIP_API_URL=https://api.your-domain.example
```

Then complete one staging journey:

1. Open the deployed HTTPS website at phone and desktop widths.
2. Complete Google sign-in once, then sign out.
3. Create an email/password account and receive the real Firebase verification
   link. If the optional sender-backed code flow is enabled, receive and enter
   that code instead.
4. Open the link or verify the code, refresh the Firebase ID token, inspect the
   profile, and restore the session.
5. Browse catalog records returned from the staging Firebase project.
6. Ask Drip Concierge for an outfit and open a recommended in-stock listing.
7. Add the item, review all fees, and complete Stripe test Checkout.
8. Wait for webhook-confirmed order state.
9. Request a password-reset email, then sign out and confirm the device returns
   to account access. Separately revoke the user's refresh tokens and verify the
   server rejects the previous credential.
10. Review server logs to ensure no password, verification link, bearer token,
   provider secret, raw card data, or sensitive AI text was recorded.
