import 'package:google_sign_in/google_sign_in.dart';

/// Small boundary around Google's native account picker.
///
/// Keeping the Google SDK behind this interface makes the Firebase exchange
/// independently testable and ensures Drip never stores Google's ID token.
abstract interface class GoogleIdentityClient {
  Future<String> requestIdToken();

  Future<void> signOut();
}

final class GoogleSignInIdentityClient implements GoogleIdentityClient {
  final GoogleSignIn _signIn;
  Future<void>? _initialization;

  GoogleSignInIdentityClient({GoogleSignIn? signIn})
    : _signIn = signIn ?? GoogleSignIn.instance;

  Future<void> _initialize() => _initialization ??= _signIn.initialize();

  @override
  Future<String> requestIdToken() async {
    await _initialize();
    if (!_signIn.supportsAuthenticate()) {
      throw UnsupportedError(
        'This platform requires a provider-rendered Google sign-in button.',
      );
    }
    final account = await _signIn.authenticate();
    final idToken = account.authentication.idToken;
    if (idToken == null || idToken.trim().isEmpty) {
      throw const FormatException('Google did not return an ID token.');
    }
    return idToken;
  }

  @override
  Future<void> signOut() async {
    await _initialize();
    await _signIn.signOut();
  }
}
