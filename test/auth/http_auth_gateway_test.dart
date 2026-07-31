import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:drip/auth/auth_gateway.dart';
import 'package:drip/auth/auth_models.dart';

import 'auth_test_fakes.dart';

Map<String, Object?> _authResponse({
  String token = 'server-session-token',
  String? welcomeStatus,
  bool? welcomeSent,
  String? welcomeMessage,
  String? sellerHandle,
}) => {
  'user': {
    'id': 'acct_server_123',
    'name': 'Jordan Lee',
    'email': 'jordan@example.com',
    'sellerHandle': ?sellerHandle,
  },
  'session': {'accessToken': token, 'expiresAt': '2035-01-02T03:04:05Z'},
  if (welcomeStatus != null || welcomeSent != null || welcomeMessage != null)
    'welcomeEmail': {
      'status': ?welcomeStatus,
      'sent': ?welcomeSent,
      'message': ?welcomeMessage,
    },
};

Map<String, Object?> _verificationResponse({
  String email = 'jordan@example.com',
  String challengeToken = authTestChallengeToken,
  String expiresAt = '2035-01-02T03:14:05Z',
  String resendAvailableAt = '2035-01-02T03:04:35Z',
}) => {
  'verification': {
    'email': email,
    'challengeToken': challengeToken,
    'expiresAt': expiresAt,
    'resendAvailableAt': resendAvailableAt,
  },
};

Future<AuthException> _failure(Future<Object?> operation) async {
  try {
    await operation;
  } on AuthException catch (error) {
    return error;
  }
  throw TestFailure('Expected an AuthException.');
}

void main() {
  test(
    'health verifies account and Stripe readiness without credentials',
    () async {
      late http.Request captured;
      final gateway = HttpAuthGateway(
        baseUri: Uri.parse('https://api.drip.test/base'),
        client: MockClient((request) async {
          captured = request;
          return http.Response(
            jsonEncode({
              'status': 'ok',
              'service': 'drip-checkout',
              'accountAuthConfigured': true,
              'paymentsConfigured': false,
            }),
            200,
          );
        }),
      );

      final readiness = await gateway.getServiceReadiness();

      expect(captured.method, 'GET');
      expect(captured.url.toString(), 'https://api.drip.test/base/healthz');
      expect(captured.headers, isNot(contains('authorization')));
      expect(readiness.accountsConfigured, isTrue);
      expect(readiness.paymentsConfigured, isFalse);
    },
  );

  test('health reports a reachable server with accounts disabled', () async {
    final gateway = HttpAuthGateway(
      baseUri: Uri.parse('https://api.drip.test'),
      client: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'status': 'ok',
            'service': 'drip-checkout',
            'accountAuthConfigured': false,
            'paymentsConfigured': true,
          }),
          200,
        ),
      ),
    );

    final readiness = await gateway.getServiceReadiness();

    expect(readiness.accountsConfigured, isFalse);
    expect(readiness.paymentsConfigured, isTrue);
  });

  test('health rejects a lookalike or incomplete service response', () async {
    for (final body in [
      {
        'status': 'ok',
        'service': 'lookalike',
        'accountAuthConfigured': true,
        'paymentsConfigured': true,
      },
      {'status': 'ok', 'service': 'drip-checkout', 'paymentsConfigured': true},
    ]) {
      final gateway = HttpAuthGateway(
        baseUri: Uri.parse('https://api.drip.test'),
        client: MockClient((_) async => http.Response(jsonEncode(body), 200)),
      );

      final error = await _failure(gateway.getServiceReadiness());

      expect(error.code, AuthFailureCode.invalidResponse);
      expect(error.retryable, isTrue);
    }
  });

  test(
    'signup posts canonical fields and parses pending verification',
    () async {
      late http.Request captured;
      final client = MockClient((request) async {
        captured = request;
        return http.Response(jsonEncode(_verificationResponse()), 202);
      });
      final gateway = HttpAuthGateway(
        baseUri: Uri.parse('https://api.drip.test/base'),
        client: client,
      );

      final result = await gateway.signUp(
        name: 'Jordan Lee',
        email: 'jordan@example.com',
        password: 'Correct-Horse-9!Battery',
      );

      expect(captured.method, 'POST');
      expect(
        captured.url.toString(),
        'https://api.drip.test/base/v1/auth/signup',
      );
      expect(jsonDecode(captured.body), {
        'name': 'Jordan Lee',
        'email': 'jordan@example.com',
        'password': 'Correct-Horse-9!Battery',
      });
      expect(captured.headers['authorization'], isNull);
      expect(captured.headers['cache-control'], 'no-store');
      expect(result.email, 'jordan@example.com');
      expect(result.challengeToken, authTestChallengeToken);
      expect(result.expiresAt, DateTime.parse('2035-01-02T03:14:05Z'));
      expect(result.resendAvailableAt, DateTime.parse('2035-01-02T03:04:35Z'));
    },
  );

  test(
    'verification challenges reject short or non-base64url tokens',
    () async {
      for (final token in ['too-short', '$authTestChallengeToken!']) {
        final client = MockClient(
          (_) async => http.Response(
            jsonEncode(_verificationResponse(challengeToken: token)),
            202,
          ),
        );
        final gateway = HttpAuthGateway(
          baseUri: Uri.parse('https://api.drip.test'),
          client: client,
        );

        final error = await _failure(
          gateway.signUp(
            name: 'Jordan Lee',
            email: 'jordan@example.com',
            password: 'Correct-Horse-9!Battery',
          ),
        );

        expect(error.code, AuthFailureCode.invalidResponse, reason: token);
      }
    },
  );

  test(
    'parses an authoritative seller handle from the account response',
    () async {
      final client = MockClient(
        (_) async => http.Response(
          jsonEncode(_authResponse(sellerHandle: '@jordan-shop')),
          200,
        ),
      );
      final gateway = HttpAuthGateway(
        baseUri: Uri.parse('https://api.drip.test'),
        client: client,
      );

      final result = await gateway.signIn(
        email: 'jordan@example.com',
        password: 'Correct-Horse-9!Battery',
      );

      expect(result.session.user.sellerHandle, '@jordan-shop');
      expect(result.session.user.toJson()['sellerHandle'], '@jordan-shop');
    },
  );

  for (final delivery in <({String status, String message})>[
    (status: 'pending', message: 'Delivery is queued.'),
    (status: 'failed', message: 'Provider rejected the message.'),
  ]) {
    test(
      'verification preserves truthful ${delivery.status} delivery status',
      () async {
        final client = MockClient(
          (_) async => http.Response(
            jsonEncode(
              _authResponse(
                welcomeStatus: delivery.status,
                welcomeSent: false,
                welcomeMessage: delivery.message,
              ),
            ),
            200,
          ),
        );
        final gateway = HttpAuthGateway(
          baseUri: Uri.parse('https://api.drip.test'),
          client: client,
        );

        final result = await gateway.verifyEmail(
          challengeToken: authTestChallengeToken,
          code: '123456',
        );

        expect(result.welcomeEmailSent, isFalse);
        expect(result.welcomeEmailStatus, delivery.status);
        expect(result.welcomeEmailMessage, delivery.message);
        expect(
          result.signupNotice(),
          isNot(contains('welcome email was sent')),
        );
      },
    );
  }

  test(
    'contradictory welcome delivery claims fail closed to not sent',
    () async {
      final client = MockClient(
        (_) async => http.Response(
          jsonEncode(
            _authResponse(
              welcomeStatus: 'failed',
              welcomeSent: true,
              welcomeMessage: 'Sent successfully.',
            ),
          ),
          200,
        ),
      );
      final gateway = HttpAuthGateway(
        baseUri: Uri.parse('https://api.drip.test'),
        client: client,
      );

      final result = await gateway.verifyEmail(
        challengeToken: authTestChallengeToken,
        code: '123456',
      );

      expect(result.welcomeEmailSent, isFalse);
      expect(result.welcomeEmailStatus, 'failed');
      expect(result.signupNotice(), contains('could not be sent'));
      expect(result.signupNotice(), isNot(contains('sent successfully')));
    },
  );

  test(
    'verification uses the opaque challenge token, never the email',
    () async {
      late http.Request captured;
      final client = MockClient((request) async {
        captured = request;
        return http.Response(
          jsonEncode(_authResponse(welcomeStatus: 'sent', welcomeSent: true)),
          200,
        );
      });
      final gateway = HttpAuthGateway(
        baseUri: Uri.parse('https://api.drip.test/base'),
        client: client,
      );

      final result = await gateway.verifyEmail(
        challengeToken: authTestChallengeToken,
        code: '123456',
      );

      expect(
        captured.url.toString(),
        'https://api.drip.test/base/v1/auth/verify-email',
      );
      expect(jsonDecode(captured.body), {
        'challengeToken': authTestChallengeToken,
        'code': '123456',
      });
      expect(captured.body, isNot(contains('jordan@example.com')));
      expect(result.session.accessToken, 'server-session-token');
    },
  );

  test('resend rotates the opaque in-memory challenge', () async {
    late http.Request captured;
    final client = MockClient((request) async {
      captured = request;
      return http.Response(
        jsonEncode(
          _verificationResponse(challengeToken: authTestRotatedChallengeToken),
        ),
        202,
      );
    });
    final gateway = HttpAuthGateway(
      baseUri: Uri.parse('https://api.drip.test'),
      client: client,
    );

    final challenge = await gateway.resendVerification(
      challengeToken: authTestChallengeToken,
    );

    expect(
      captured.url.toString(),
      'https://api.drip.test/v1/auth/resend-verification',
    );
    expect(jsonDecode(captured.body), {
      'challengeToken': authTestChallengeToken,
    });
    expect(challenge.challengeToken, authTestRotatedChallengeToken);
  });

  test('wrong confirmation codes expose one generic public failure', () async {
    final client = MockClient(
      (_) async => http.Response(
        jsonEncode({
          'error': {
            'code': 'invalid_verification_code',
            'message': 'hash mismatch for internal verification row',
          },
        }),
        422,
      ),
    );
    final gateway = HttpAuthGateway(
      baseUri: Uri.parse('https://api.drip.test'),
      client: client,
    );

    final error = await _failure(
      gateway.verifyEmail(
        challengeToken: authTestChallengeToken,
        code: '000000',
      ),
    );

    expect(error.code, AuthFailureCode.invalidVerificationCode);
    expect(error.publicMessage, isNot(contains('hash')));
    expect(error.publicMessage, contains('not correct'));
  });

  test('invalid opaque challenges direct the user to start over', () async {
    final client = MockClient(
      (_) async => http.Response(
        jsonEncode({
          'error': {
            'code': 'invalid_verification_challenge',
            'message': 'challenge digest does not exist',
          },
        }),
        422,
      ),
    );
    final gateway = HttpAuthGateway(
      baseUri: Uri.parse('https://api.drip.test'),
      client: client,
    );

    final error = await _failure(
      gateway.verifyEmail(
        challengeToken: authTestChallengeToken,
        code: '123456',
      ),
    );

    expect(error.code, AuthFailureCode.verificationExpired);
    expect(error.publicMessage, contains('create the account again'));
    expect(error.publicMessage, isNot(contains('digest')));
  });

  test(
    'all login 401 responses become the same generic public failure',
    () async {
      var call = 0;
      final client = MockClient((_) async {
        call += 1;
        return http.Response(
          jsonEncode({
            'error': {
              'code': call == 1 ? 'unknown_account' : 'wrong_password',
              'message': call == 1
                  ? 'No row for that email.'
                  : 'Password hash mismatch for acct_internal_123.',
            },
          }),
          401,
        );
      });
      final gateway = HttpAuthGateway(
        baseUri: Uri.parse('https://api.drip.test'),
        client: client,
      );

      final unknown = await _failure(
        gateway.signIn(
          email: 'missing@example.com',
          password: 'Correct-Horse-9!Battery',
        ),
      );
      final wrong = await _failure(
        gateway.signIn(
          email: 'jordan@example.com',
          password: 'Wrong-Password-9!',
        ),
      );

      for (final error in [unknown, wrong]) {
        expect(error.code, AuthFailureCode.invalidCredentials);
        expect(error.publicMessage, 'Email or password is incorrect.');
        expect(error.retryable, isFalse);
        expect(error.toString(), isNot(contains('acct_internal')));
        expect(error.toString(), isNot(contains('hash mismatch')));
      }
    },
  );

  test('duplicate signup maps 409 without exposing provider detail', () async {
    final client = MockClient(
      (_) async => http.Response(
        jsonEncode({
          'error': {
            'code': 'account_exists',
            'message': 'UNIQUE accounts_email_normalized_idx failed',
          },
        }),
        409,
      ),
    );
    final gateway = HttpAuthGateway(
      baseUri: Uri.parse('https://api.drip.test'),
      client: client,
    );

    final error = await _failure(
      gateway.signUp(
        name: 'Jordan Lee',
        email: 'jordan@example.com',
        password: 'Correct-Horse-9!Battery',
      ),
    );

    expect(error.code, AuthFailureCode.emailAlreadyInUse);
    expect(error.publicMessage, contains('already exists'));
    expect(error.publicMessage, isNot(contains('UNIQUE')));
  });

  test('429 honors Retry-After using a sanitized retryable error', () async {
    final client = MockClient(
      (_) async => http.Response(
        jsonEncode({
          'error': {
            'code': 'auth_rate_limited',
            'message': 'internal limiter shard 8',
          },
        }),
        429,
        headers: {'retry-after': '90'},
      ),
    );
    final gateway = HttpAuthGateway(
      baseUri: Uri.parse('https://api.drip.test'),
      client: client,
    );

    final error = await _failure(
      gateway.signIn(
        email: 'jordan@example.com',
        password: 'Wrong-Password-9!',
      ),
    );

    expect(error.code, AuthFailureCode.rateLimited);
    expect(error.retryable, isTrue);
    expect(error.retryAfter, const Duration(seconds: 90));
    expect(error.publicMessage, contains('2 minutes'));
    expect(error.publicMessage, isNot(contains('shard')));
  });

  test(
    'session restore uses the stored token and keeps it out of the URL',
    () async {
      late http.Request captured;
      final client = MockClient((request) async {
        captured = request;
        return http.Response(
          jsonEncode({
            'authenticated': true,
            'user': {
              'id': 'acct_server_123',
              'name': 'Jordan Lee',
              'email': 'jordan@example.com',
            },
            'expiresAt': '2035-01-02T03:04:05Z',
          }),
          200,
        );
      });
      final gateway = HttpAuthGateway(
        baseUri: Uri.parse('https://api.drip.test'),
        client: client,
      );
      final stored = authTestSession(accessToken: 'stored-restore-token');

      final restored = await gateway.restoreSession(stored);

      expect(captured.method, 'GET');
      expect(captured.url.toString(), 'https://api.drip.test/v1/auth/session');
      expect(captured.url.toString(), isNot(contains('stored-restore-token')));
      expect(captured.headers['authorization'], 'Bearer stored-restore-token');
      expect(restored.accessToken, 'stored-restore-token');
      expect(restored.user.id, 'acct_server_123');
    },
  );

  test('logout sends the session token with an empty canonical body', () async {
    late http.Request captured;
    final client = MockClient((request) async {
      captured = request;
      return http.Response('', 204);
    });
    final gateway = HttpAuthGateway(
      baseUri: Uri.parse('https://api.drip.test/api'),
      client: client,
    );
    final session = authTestSession(accessToken: 'logout-token');

    await gateway.signOut(session);

    expect(captured.method, 'POST');
    expect(captured.url.toString(), 'https://api.drip.test/api/v1/auth/logout');
    expect(captured.headers['authorization'], 'Bearer logout-token');
    expect(jsonDecode(captured.body), <String, Object?>{});
  });

  test(
    'malformed successful response fails closed without leaking content',
    () async {
      final client = MockClient(
        (_) async => http.Response(
          jsonEncode(_authResponse(token: 'unsafe\r\ninjected-token')),
          200,
        ),
      );
      final gateway = HttpAuthGateway(
        baseUri: Uri.parse('https://api.drip.test'),
        client: client,
      );

      final error = await _failure(
        gateway.signIn(
          email: 'jordan@example.com',
          password: 'Correct-Horse-9!Battery',
        ),
      );

      expect(error.code, AuthFailureCode.invalidResponse);
      expect(error.retryable, isTrue);
      expect(error.toString(), isNot(contains('injected-token')));
    },
  );

  test('oversized provider response is rejected before JSON parsing', () async {
    final client = MockClient(
      (_) async => http.Response('x' * (128 * 1024 + 1), 200),
    );
    final gateway = HttpAuthGateway(
      baseUri: Uri.parse('https://api.drip.test'),
      client: client,
    );

    final error = await _failure(
      gateway.signIn(
        email: 'jordan@example.com',
        password: 'Correct-Horse-9!Battery',
      ),
    );

    expect(error.code, AuthFailureCode.providerUnavailable);
    expect(error.retryable, isTrue);
  });

  test('base URL requires HTTPS except for explicit loopback development', () {
    for (final invalid in [
      'http://api.drip.test',
      'https://user:pass@api.drip.test',
      'https://api.drip.test?token=secret',
      'https://api.drip.test/#fragment',
    ]) {
      expect(
        () => HttpAuthGateway(
          baseUri: Uri.parse(invalid),
          client: MockClient((_) async => http.Response('{}', 200)),
        ),
        throwsA(
          isA<AuthException>().having(
            (error) => error.code,
            'code',
            AuthFailureCode.invalidResponse,
          ),
        ),
        reason: invalid,
      );
    }

    expect(
      () => HttpAuthGateway(
        baseUri: Uri.parse('https://api.drip.test'),
        client: MockClient((_) async => http.Response('{}', 200)),
      ),
      returnsNormally,
    );
    expect(
      () => HttpAuthGateway(
        baseUri: Uri.parse('http://127.0.0.1:4242'),
        client: MockClient((_) async => http.Response('{}', 200)),
      ),
      returnsNormally,
    );
  });
}
