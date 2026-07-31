import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:drip/payments/stripe_connect_gateway.dart';
import 'package:drip/payments/stripe_connect_models.dart';

void main() {
  Map<String, Object?> statusJson({String status = 'ready'}) => {
    'status': status,
    'transfersReady': status == 'ready',
    'payoutsReady': status == 'ready',
    'requirementsDue': status == 'ready' ? 0 : 2,
    'canOpenDashboard': true,
    'livemode': false,
    'lastSyncedAt': '2030-01-02T03:04:05Z',
  };

  test('status uses the authenticated canonical endpoint', () async {
    late http.Request captured;
    final gateway = HttpStripeConnectGateway(
      baseUri: Uri.parse('https://api.drip.test/base'),
      accessTokenProvider: () async => 'verified-token',
      client: MockClient((request) async {
        captured = request;
        return http.Response(jsonEncode(statusJson()), 200);
      }),
    );

    final status = await gateway.getStatus();

    expect(captured.method, 'GET');
    expect(
      captured.url.toString(),
      'https://api.drip.test/base/v1/seller/connect/status',
    );
    expect(captured.headers['authorization'], 'Bearer verified-token');
    expect(status.status, StripeConnectStatus.ready);
    expect(status.livemode, isFalse);
  });

  test(
    'onboarding sends an empty JSON object and accepts Stripe only',
    () async {
      late http.Request captured;
      final expiry = DateTime.now().toUtc().add(const Duration(minutes: 10));
      final gateway = HttpStripeConnectGateway(
        baseUri: Uri.parse('https://api.drip.test'),
        accessTokenProvider: () async => 'verified-token',
        client: MockClient((request) async {
          captured = request;
          return http.Response(
            jsonEncode({
              'url': 'https://accounts.stripe.com/r/test#alu_opaque-state',
              'expiresAt': expiry.toIso8601String(),
            }),
            201,
          );
        }),
      );

      final link = await gateway.createOnboardingLink();

      expect(captured.method, 'POST');
      expect(captured.url.path, '/v1/seller/connect/onboarding');
      expect(jsonDecode(captured.body), <String, Object?>{});
      expect(link.url.host, 'accounts.stripe.com');
      expect(link.url.fragment, 'alu_opaque-state');
      expect(link.kind, StripeConnectLinkKind.onboarding);
    },
  );

  test('rejects a phishing link without exposing it', () async {
    final gateway = HttpStripeConnectGateway(
      baseUri: Uri.parse('https://api.drip.test'),
      accessTokenProvider: () async => 'verified-token',
      client: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'url': 'https://stripe.example.test/steal',
            'expiresAt': DateTime.now()
                .toUtc()
                .add(const Duration(minutes: 5))
                .toIso8601String(),
          }),
          200,
        ),
      ),
    );

    await expectLater(
      gateway.createDashboardLink(),
      throwsA(
        isA<StripeConnectException>()
            .having(
              (error) => error.code,
              'code',
              StripeConnectFailureCode.invalidResponse,
            )
            .having(
              (error) => error.toString(),
              'safe message',
              isNot(contains('stripe.example.test')),
            ),
      ),
    );
  });

  for (final unsafeUrl in <String>[
    'https://accounts.stripe.com:8443/r/test',
    'https://user:password@accounts.stripe.com/r/test',
    'https://accounts.stripe.com/r/test?next=%0Aheader',
    'https://accounts.stripe.com.evil.example/r/test',
    'https://connect.stripe.com/setup/s/test',
  ]) {
    test('rejects unsafe Stripe Connect link form: $unsafeUrl', () async {
      final gateway = HttpStripeConnectGateway(
        baseUri: Uri.parse('https://api.drip.test'),
        accessTokenProvider: () async => 'verified-token',
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'url': unsafeUrl,
              'expiresAt': DateTime.now()
                  .toUtc()
                  .add(const Duration(minutes: 5))
                  .toIso8601String(),
            }),
            200,
          ),
        ),
      );

      await expectLater(
        gateway.createOnboardingLink(),
        throwsA(isA<StripeConnectException>()),
      );
    });
  }

  test(
    'dashboard links use the separate Stripe host and reject fragments',
    () async {
      Future<StripeConnectLink> dashboardUrl(String url) {
        final gateway = HttpStripeConnectGateway(
          baseUri: Uri.parse('https://api.drip.test'),
          accessTokenProvider: () async => 'verified-token',
          client: MockClient(
            (_) async => http.Response(
              jsonEncode({
                'url': url,
                'expiresAt': DateTime.now()
                    .toUtc()
                    .add(const Duration(minutes: 5))
                    .toIso8601String(),
              }),
              200,
            ),
          ),
        );
        return gateway.createDashboardLink();
      }

      final dashboard = await dashboardUrl(
        'https://connect.stripe.com/express/test-login',
      );
      expect(dashboard.kind, StripeConnectLinkKind.dashboard);
      expect(dashboard.url.host, 'connect.stripe.com');
      await expectLater(
        dashboardUrl('https://connect.stripe.com/express/test-login#opaque'),
        throwsA(isA<StripeConnectException>()),
      );
      await expectLater(
        dashboardUrl('https://accounts.stripe.com/r/wrong-flow'),
        throwsA(isA<StripeConnectException>()),
      );
    },
  );

  test('strictly rejects inconsistent ready state', () async {
    final body = statusJson()..['payoutsReady'] = false;
    final gateway = HttpStripeConnectGateway(
      baseUri: Uri.parse('https://api.drip.test'),
      accessTokenProvider: () async => 'verified-token',
      client: MockClient((_) async => http.Response(jsonEncode(body), 200)),
    );

    await expectLater(
      gateway.getStatus(),
      throwsA(isA<StripeConnectException>()),
    );
  });
}
