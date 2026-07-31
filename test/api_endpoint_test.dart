import 'package:flutter_test/flutter_test.dart';

import 'package:drip/api_endpoint.dart';
import 'package:drip/auth/auth_gateway.dart';
import 'package:drip/payments/http_checkout_gateway.dart';

void main() {
  test('auth and checkout resolve the same canonical API setting', () {
    expect(HttpAuthGateway.environmentKey, DripApiEndpoint.environmentKey);
    expect(HttpCheckoutGateway.environmentKey, DripApiEndpoint.environmentKey);
  });

  test(
    'debug builds have a safe loopback fallback when no URL is supplied',
    () {
      if (!DripApiEndpoint.hasExplicitConfiguration) {
        expect(DripApiEndpoint.value, DripApiEndpoint.debugLoopbackUrl);
        expect(DripApiEndpoint.uri, Uri.parse('http://localhost:4242'));
      }
    },
  );

  test('API origins reject secrets and insecure remote transport', () {
    expect(
      DripApiEndpoint.isAllowedBaseUri(Uri.parse('https://api.drip.test')),
      isTrue,
    );
    expect(
      DripApiEndpoint.isAllowedBaseUri(Uri.parse('http://api.drip.test')),
      isFalse,
    );
    expect(
      DripApiEndpoint.isAllowedBaseUri(
        Uri.parse('https://user:secret@api.drip.test'),
      ),
      isFalse,
    );
    expect(
      DripApiEndpoint.isAllowedBaseUri(
        Uri.parse('https://api.drip.test?token=secret'),
      ),
      isFalse,
    );
  });
}
