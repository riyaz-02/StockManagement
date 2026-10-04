import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';

/// What the phone can do about fingerprints right now.
enum FingerprintState {
  /// The phone has no fingerprint sensor (or no screen lock at all).
  unsupported,

  /// A sensor exists but no fingerprint has been added in the phone's own Settings.
  notEnrolled,

  /// Ready: at least one fingerprint (or face) is registered on the phone.
  ready,
}

enum FingerprintResult { success, cancelled, failed, notEnrolled, unavailable, lockedOut }

/// Thin wrapper around local_auth. The fingerprint only decides whether to unlock the app on this phone: the signed-in
/// session itself lives in the app (see AppLockService), so no password is ever stored for it.
class BiometricAuthService {
  static final BiometricAuthService _instance = BiometricAuthService._();
  factory BiometricAuthService() => _instance;
  BiometricAuthService._();

  final LocalAuthentication _auth = LocalAuthentication();

  Future<FingerprintState> state() async {
    try {
      if (!await _auth.isDeviceSupported()) return FingerprintState.unsupported;
      if (!await _auth.canCheckBiometrics) return FingerprintState.unsupported;
      final enrolled = await _auth.getAvailableBiometrics();
      return enrolled.isEmpty ? FingerprintState.notEnrolled : FingerprintState.ready;
    } catch (_) {
      return FingerprintState.unsupported;
    }
  }

  Future<bool> isDeviceSupported() async => (await state()) == FingerprintState.ready;

  /// Asks the phone to scan a finger. Only a real biometric counts (no phone-PIN fallback): the app has its own passcode.
  Future<FingerprintResult> scan({String reason = 'Touch the fingerprint sensor'}) async {
    try {
      final ok = await _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(stickyAuth: true, biometricOnly: true),
      );
      return ok ? FingerprintResult.success : FingerprintResult.cancelled;
    } on PlatformException catch (e) {
      switch (e.code) {
        case 'NotEnrolled':
        case 'notEnrolled':
        case 'PasscodeNotSet':
        case 'passcodeNotSet':
          return FingerprintResult.notEnrolled;
        case 'LockedOut':
        case 'lockedOut':
        case 'PermanentlyLockedOut':
        case 'permanentlyLockedOut':
          return FingerprintResult.lockedOut;
        case 'NotAvailable':
        case 'notAvailable':
          return FingerprintResult.unavailable;
        default:
          return FingerprintResult.failed;
      }
    } catch (_) {
      return FingerprintResult.failed;
    }
  }

  Future<bool> authenticate({String reason = 'Confirm it is you'}) async => (await scan(reason: reason)) == FingerprintResult.success;
}
