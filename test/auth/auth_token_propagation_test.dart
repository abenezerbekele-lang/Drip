import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:drip/app_state.dart';
import 'package:drip/assistant/assistant_gateway.dart';
import 'package:drip/assistant/assistant_models.dart';
import 'package:drip/auth/auth_controller.dart';
import 'package:drip/auth/auth_session_store.dart';

import 'auth_test_fakes.dart';

void main() {
  test(
    'verified auth token reaches the AI boundary and expires fail closed',
    () async {
      var now = authTestNow;
      final session = authTestSession(
        accessToken: 'verified-ai-token',
        expiresAt: authTestNow.add(const Duration(minutes: 30)),
      );
      final store = MemoryAuthSessionStore(session);
      final authGateway = FakeAuthGateway()..restoreResult = session;
      final controller = AuthController(
        gateway: authGateway,
        store: store,
        clock: () => now,
        ownsGateway: false,
        initializeImmediately: false,
      );
      addTearDown(controller.dispose);
      await controller.initialize();

      final authorizationHeaders = <String?>[];
      final client = MockClient((request) async {
        authorizationHeaders.add(request.headers['authorization']);
        return http.Response(
          jsonEncode({
            'reply': 'A concise, grounded answer.',
            'intent': 'general',
            'followUps': <String>[],
            'productIds': <String>[],
            'needsHumanSupport': false,
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final assistantGateway = HttpAssistantGateway(
        baseUri: Uri.parse('https://api.drip.test'),
        client: client,
        accessTokenProvider: controller.accessToken,
      );
      addTearDown(assistantGateway.close);
      final appState = AppState();
      addTearDown(appState.dispose);
      final request = AssistantRequest(
        message: 'Build a professional fit for me.',
        history: const [],
        context: AssistantContext.fromAppState(appState),
      );

      await assistantGateway.respond(request);
      expect(authorizationHeaders, ['Bearer verified-ai-token']);

      now = session.expiresAt;
      await assistantGateway.respond(request);
      expect(authorizationHeaders, ['Bearer verified-ai-token', null]);
      expect(controller.status, AuthStatus.signedOut);
      expect(store.value, isNull);
    },
  );
}
