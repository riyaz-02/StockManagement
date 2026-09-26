import 'package:local_auth/local_auth.dart';

/// Thin wrapper around local_auth — fingerprint/face unlock used as a
/// shortcut for typing mobile+password on the login screen.
class BiometricAuthService {
  static final BiometricAuthService _instance = BiometricAuthService._();
  factory BiometricAuthService() => _instance;
  BiometricAuthService._();

  final LocalAuthentication _auth = LocalAuthentication();

  Future<bool> isDeviceSupported() async {
    try {
      final canCheck = await _auth.canCheckBiometrics;
      final isSupported = await _auth.isDeviceSupported();
      return canCheck && isSupported;
    } catch (_) {
      return false;
    }
  }

  Future<bool> authenticate({String reason = 'Confirm it\'s you to log in'}) async {
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: false,
        ),
      );
    } catch (_) {
      return false;
    }
  }
}
