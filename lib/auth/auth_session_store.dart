import 'dart:convert';

// Keep the injectable constructor readable without exposing its backing field.
// ignore_for_file: prefer_initializing_formals

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'auth_models.dart';

abstract interface class AuthSessionStore {
  Future<AuthSession?> read();

  Future<void> write(AuthSession session);

  Future<void> clear();
}

class SecureAuthSessionStore implements AuthSessionStore {
  static const _key = 'drip.auth.session.v1';
  static const _webOptions = WebOptions(
    publicKey: 'DripAuthSessionV1',
    useSessionStorage: true,
  );
  final FlutterSecureStorage _storage;

  const SecureAuthSessionStore({
    FlutterSecureStorage storage = const FlutterSecureStorage(),
  }) : _storage = storage;

  @override
  Future<AuthSession?> read() async {
    // Browser bearer tokens are tab-scoped. Native platforms ignore these web
    // options and continue using their Keychain/Keystore-backed defaults.
    final value = await _storage.read(key: _key, webOptions: _webOptions);
    if (value == null || value.isEmpty) return null;
    try {
      final decoded = jsonDecode(value);
      if (decoded is! Map) throw const FormatException();
      return AuthSession.fromJson(Map<String, Object?>.from(decoded));
    } on Object {
      await clear();
      return null;
    }
  }

  @override
  Future<void> write(AuthSession session) => _storage.write(
    key: _key,
    value: jsonEncode(session.toJson()),
    webOptions: _webOptions,
  );

  @override
  Future<void> clear() => _storage.delete(key: _key, webOptions: _webOptions);
}

class MemoryAuthSessionStore implements AuthSessionStore {
  AuthSession? value;
  Object? readError;
  Object? writeError;
  Object? clearError;

  MemoryAuthSessionStore([this.value]);

  @override
  Future<AuthSession?> read() async {
    if (readError != null) throw readError!;
    return value;
  }

  @override
  Future<void> write(AuthSession session) async {
    if (writeError != null) throw writeError!;
    value = session;
  }

  @override
  Future<void> clear() async {
    if (clearError != null) throw clearError!;
    value = null;
  }
}
