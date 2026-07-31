import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:drip/auth/auth_models.dart';
import 'package:drip/auth/firebase_email_code_client.dart';

final _now = DateTime.utc(2031, 3, 10, 12);

Future<AuthException> _failure(Future<Object?> operation) async {
  try {
    await operation;
    fail('Expected the email-code request to fail.');
  } on AuthException catch (error) {
    return error;
  }
}

String _errorBody(String code, {String message = 'sensitive provider text'}) =>
    jsonEncode({
      'error': {'code': code, 'message': message},
    });

void main() {
  group('FirebaseEmailCodeConfiguration', () {
    test('requires both the explicit flag and canonical API URL', () {
      expect(
        FirebaseEmailCodeConfiguration.resolveApiUri(
          enabled: false,
          configuredApiUrl: 'https://api.drip.example',
        ),
        isNull,
      );
      expect(
        FirebaseEmailCodeConfiguration.resolveApiUri(
          enabled: true,
          configuredApiUrl: '',
        ),
        isNull,
      );
      expect(
        FirebaseEmailCodeConfiguration.resolveApiUri(
          enabled: true,
          configuredApiUrl: 'http://api.drip.example',
        ),
        isNull,
      );
      expect(
        FirebaseEmailCodeConfiguration.resolveApiUri(
          enabled: true,
          configuredApiUrl: 'https://api.drip.example/base',
        ),
        Uri.parse('https://api.drip.example/base'),
      );
    });

    test('never accepts credentials, query strings, or path traversal', () {
      for (final value in [
        'https://user:secret@api.drip.example',
        'https://api.drip.example?token=secret',
        'https://api.drip.example/#fragment',
        'https://api.drip.example/../admin',
      ]) {
        expect(
          FirebaseEmailCodeConfiguration.resolveApiUri(
            enabled: true,
            configuredApiUrl: value,
          ),
          isNull,
          reason: value,
        );
      }
    });
  });

  group('FirebaseEmailCodeHttpClient', () {
    test('requests a code with only the Firebase token and empty body', () async {
      final transport = MockClient((request) async {
        expect(request.method, 'POST');
        expect(
          request.url,
          Uri.parse(
            'https://api.drip.example/base/v1/auth/firebase/email-code/request',
          ),
        );
        expect(request.headers['authorization'], 'Bearer pending-id-token');
        expect(request.headers['cache-control'], 'no-store');
        expect(request.headers['accept'], 'application/json');
        expect(jsonDecode(request.body), isEmpty);
        expect(request.body, isNot(contains('email')));
        expect(request.body, isNot(contains('uid')));
        return http.Response(
          jsonEncode({
            'verification': {
              'status': 'code_sent',
              'email': 'Jordan@Example.com',
              'expiresAt': '2031-03-10T12:10:00.000Z',
              'resendAvailableAt': '2031-03-10T12:01:00.000Z',
            },
          }),
          202,
          headers: {'content-type': 'application/json'},
        );
      });
      final client = FirebaseEmailCodeHttpClient(
        baseUri: Uri.parse('https://api.drip.example/base'),
        client: transport,
        clock: () => _now,
      );

      final result = await client.requestCode(idToken: 'pending-id-token');

      expect(result.email, 'jordan@example.com');
      expect(result.expiresAt, DateTime.utc(2031, 3, 10, 12, 10));
      expect(result.resendAvailableAt, DateTime.utc(2031, 3, 10, 12, 1));
    });

    test(
      'verifies exactly one six-digit code with the Firebase token',
      () async {
        final transport = MockClient((request) async {
          expect(request.url.path, '/v1/auth/firebase/email-code/verify');
          expect(request.headers['authorization'], 'Bearer pending-id-token');
          expect(jsonDecode(request.body), {'code': '004279'});
          return http.Response(
            jsonEncode({
              'verified': true,
              'email': 'jordan@example.com',
              'refreshIdToken': true,
            }),
            200,
          );
        });
        final client = FirebaseEmailCodeHttpClient(
          baseUri: Uri.parse('https://api.drip.example'),
          client: transport,
          clock: () => _now,
        );

        final result = await client.verifyCode(
          idToken: 'pending-id-token',
          code: '004279',
        );

        expect(result.email, 'jordan@example.com');
        expect(result.refreshIdToken, isTrue);
      },
    );

    test(
      'rejects malformed codes and unsafe tokens before transport',
      () async {
        var calls = 0;
        final client = FirebaseEmailCodeHttpClient(
          baseUri: Uri.parse('https://api.drip.example'),
          client: MockClient((_) async {
            calls += 1;
            return http.Response('{}', 200);
          }),
          clock: () => _now,
        );

        final badCode = await _failure(
          client.verifyCode(idToken: 'pending-id-token', code: '12a456'),
        );
        final badToken = await _failure(
          client.requestCode(idToken: 'token\r\ninjected-header'),
        );

        expect(badCode.code, AuthFailureCode.invalidVerificationCode);
        expect(badToken.code, AuthFailureCode.sessionExpired);
        expect(calls, 0);
      },
    );

    test('maps server failures without exposing provider messages', () async {
      final cases =
          <
            ({
              int status,
              String serverCode,
              AuthFailureCode expected,
              Map<String, String> headers,
            })
          >[
            (
              status: 422,
              serverCode: 'invalid_verification_code',
              expected: AuthFailureCode.invalidVerificationCode,
              headers: const {},
            ),
            (
              status: 429,
              serverCode: 'auth_rate_limited',
              expected: AuthFailureCode.rateLimited,
              headers: const {'retry-after': '42'},
            ),
            (
              status: 503,
              serverCode: 'firebase_email_code_unavailable',
              expected: AuthFailureCode.providerUnavailable,
              headers: const {},
            ),
            (
              status: 401,
              serverCode: 'invalid_token',
              expected: AuthFailureCode.sessionExpired,
              headers: const {},
            ),
          ];

      for (final testCase in cases) {
        final client = FirebaseEmailCodeHttpClient(
          baseUri: Uri.parse('https://api.drip.example'),
          client: MockClient(
            (_) async => http.Response(
              _errorBody(testCase.serverCode),
              testCase.status,
              headers: testCase.headers,
            ),
          ),
          clock: () => _now,
        );

        final error = await _failure(
          client.verifyCode(idToken: 'pending-id-token', code: '123456'),
        );

        expect(error.code, testCase.expected, reason: testCase.serverCode);
        expect(
          error.publicMessage,
          isNot(contains('sensitive')),
          reason: testCase.serverCode,
        );
        if (testCase.status == 429) {
          expect(error.retryAfter, const Duration(seconds: 42));
        }
      }
    });

    test('fails closed on malformed or stale successful responses', () async {
      for (final body in [
        '{}',
        jsonEncode({
          'verification': {
            'status': 'code_sent',
            'email': 'jordan@example.com',
            'expiresAt': '2031-03-10T11:59:59.000Z',
            'resendAvailableAt': '2031-03-10T11:59:00.000Z',
          },
        }),
        jsonEncode({
          'verification': {
            'status': 'already_verified',
            'email': 'jordan@example.com',
          },
        }),
      ]) {
        final client = FirebaseEmailCodeHttpClient(
          baseUri: Uri.parse('https://api.drip.example'),
          client: MockClient((_) async => http.Response(body, 202)),
          clock: () => _now,
        );

        final error = await _failure(
          client.requestCode(idToken: 'pending-id-token'),
        );

        expect(error.code, AuthFailureCode.invalidResponse);
        expect(error.retryable, isTrue);
      }
    });

    test('rejects an unsafe API base URL', () {
      expect(
        () => FirebaseEmailCodeHttpClient(
          baseUri: Uri.parse('http://api.drip.example'),
          client: MockClient((_) async => http.Response('{}', 200)),
        ),
        throwsA(
          isA<AuthException>().having(
            (error) => error.code,
            'code',
            AuthFailureCode.invalidResponse,
          ),
        ),
      );
    });
  });
}
