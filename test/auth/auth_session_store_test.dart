import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:drip/auth/auth_session_store.dart';

import 'auth_test_fakes.dart';

typedef _StorageCall = ({String operation, String key, WebOptions? webOptions});

class _RecordingSecureStorage extends FlutterSecureStorage {
  String? value;
  final calls = <_StorageCall>[];

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    calls.add((operation: 'read', key: key, webOptions: webOptions));
    return value;
  }

  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    calls.add((operation: 'write', key: key, webOptions: webOptions));
    this.value = value;
  }

  @override
  Future<void> delete({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    calls.add((operation: 'delete', key: key, webOptions: webOptions));
    value = null;
  }
}

void _expectTabScoped(_StorageCall call, String operation) {
  expect(call.operation, operation);
  expect(call.key, 'drip.auth.session.v1');
  expect(call.webOptions, isNotNull);
  expect(call.webOptions!.publicKey, 'DripAuthSessionV1');
  expect(call.webOptions!.useSessionStorage, isTrue);
}

void main() {
  test(
    'secure session read, write, and clear stay tab-scoped on web',
    () async {
      final storage = _RecordingSecureStorage();
      final store = SecureAuthSessionStore(storage: storage);
      final session = authTestSession();

      await store.write(session);
      final restored = await store.read();
      await store.clear();

      expect(restored?.user.id, session.user.id);
      expect(restored?.user.email, session.user.email);
      expect(restored?.accessToken, session.accessToken);
      expect(restored?.expiresAt, session.expiresAt);
      expect(storage.value, isNull);
      expect(storage.calls, hasLength(3));
      _expectTabScoped(storage.calls[0], 'write');
      _expectTabScoped(storage.calls[1], 'read');
      _expectTabScoped(storage.calls[2], 'delete');
    },
  );

  test(
    'malformed tab-scoped session is deleted with the same web options',
    () async {
      final storage = _RecordingSecureStorage()..value = '{not-valid-json';
      final store = SecureAuthSessionStore(storage: storage);

      expect(await store.read(), isNull);

      expect(storage.value, isNull);
      expect(storage.calls, hasLength(2));
      _expectTabScoped(storage.calls[0], 'read');
      _expectTabScoped(storage.calls[1], 'delete');
    },
  );
}
