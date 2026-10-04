import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Where the lock keeps its few values. The real one is the phone's secure storage (Android Keystore); tests use memory.
abstract class LockStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class SecureLockStore implements LockStore {
  final FlutterSecureStorage _s = const FlutterSecureStorage(aOptions: AndroidOptions(encryptedSharedPreferences: true));

  @override
  Future<String?> read(String key) async {
    try {
      return await _s.read(key: key);
    } catch (_) {
      return null; // an unreadable store counts as "nothing set"
    }
  }

  @override
  Future<void> write(String key, String value) => _s.write(key: key, value: value);

  @override
  Future<void> delete(String key) async {
    try {
      await _s.delete(key: key);
    } catch (_) {/* nothing to remove */}
  }
}

class MemoryLockStore implements LockStore {
  final Map<String, String> data = {};
  @override
  Future<String?> read(String key) async => data[key];
  @override
  Future<void> write(String key, String value) async => data[key] = value;
  @override
  Future<void> delete(String key) async => data.remove(key);
}

enum PinCheck { ok, wrong, tooMany, notSet }

class PinResult {
  const PinResult(this.check, [this.triesLeft = 0]);
  final PinCheck check;
  final int triesLeft;
}

/// The 4-digit passcode and the fingerprint switch of a phone that stays signed in.
///
/// The passcode is never stored: only a salted, repeatedly hashed copy, in the phone's secure storage, together with who
/// it belongs to. Five wrong tries in a row remove it, and the person has to sign in with the password again.
class AppLockService {
  AppLockService({LockStore? store}) : _store = store ?? SecureLockStore();
  static final AppLockService instance = AppLockService();

  static const maxTries = 5;
  static const pinLength = 4;
  static const _kHash = 'lock_pin_hash';
  static const _kSalt = 'lock_pin_salt';
  static const _kOwner = 'lock_owner';
  static const _kFails = 'lock_fails';
  static const _kFinger = 'lock_fingerprint';
  static const _kSkips = 'lock_setup_skips';
  final LockStore _store;

  static String hash(String pin, String salt) {
    List<int> d = utf8.encode('$salt:$pin');
    for (var i = 0; i < 4000; i++) {
      d = sha256.convert([...d, ...utf8.encode(salt)]).bytes;
    }
    return base64.encode(d);
  }

  static bool isValidPin(String pin) => RegExp(r'^\d{4}$').hasMatch(pin);

  /// Passcodes that are easy to guess are refused: 0000, 1111, 1234, 4321 ...
  static bool isWeakPin(String pin) {
    if (!isValidPin(pin)) return true;
    if (pin.split('').toSet().length == 1) return true;
    const up = '0123456789012', down = '9876543210987';
    return up.contains(pin) || down.contains(pin);
  }

  Future<bool> hasPin() async => (await _store.read(_kHash)) != null;

  /// Whose passcode it is (the signed-in person's id), so a passcode never unlocks someone else's session.
  Future<String?> owner() => _store.read(_kOwner);

  Future<void> setPin(String pin, {required String owner}) async {
    if (!isValidPin(pin)) throw ArgumentError('The passcode must be 4 digits');
    final rnd = Random.secure();
    final salt = base64.encode(List<int>.generate(16, (_) => rnd.nextInt(256)));
    await _store.write(_kSalt, salt);
    await _store.write(_kHash, hash(pin, salt));
    await _store.write(_kOwner, owner);
    await _store.write(_kFails, '0');
  }

  Future<PinResult> verifyPin(String pin) async {
    final stored = await _store.read(_kHash);
    final salt = await _store.read(_kSalt);
    if (stored == null || salt == null) return const PinResult(PinCheck.notSet);
    if (hash(pin, salt) == stored) {
      await _store.write(_kFails, '0');
      return const PinResult(PinCheck.ok);
    }
    final fails = (int.tryParse(await _store.read(_kFails) ?? '0') ?? 0) + 1;
    if (fails >= maxTries) {
      await removePin();
      return const PinResult(PinCheck.tooMany);
    }
    await _store.write(_kFails, '$fails');
    return PinResult(PinCheck.wrong, maxTries - fails);
  }

  Future<void> removePin() async {
    for (final k in [_kHash, _kSalt, _kOwner, _kFails, _kFinger]) {
      await _store.delete(k);
    }
  }

  Future<bool> fingerprintOn() async => (await hasPin()) && (await _store.read(_kFinger)) == '1';

  Future<void> setFingerprint(bool on) async {
    if (on) {
      await _store.write(_kFinger, '1');
    } else {
      await _store.delete(_kFinger);
    }
  }

  /// How many times the person pressed "Not now" on the set-up offer (after 2 it stops asking; Account settings stays).
  Future<int> setupSkips() async => int.tryParse(await _store.read(_kSkips) ?? '0') ?? 0;
  Future<void> addSetupSkip() async => _store.write(_kSkips, '${(await setupSkips()) + 1}');
  Future<void> clearSetupSkips() => _store.delete(_kSkips);

  /// Everything: used when someone signs out (the next person on a shared phone starts clean).
  Future<void> clearAll() async {
    await removePin();
    await clearSetupSkips();
  }
}
