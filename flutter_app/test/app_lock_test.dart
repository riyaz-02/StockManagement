import 'package:flutter_test/flutter_test.dart';
import 'package:jewellery_stock_app/services/app_lock_service.dart';

void main() {
  late AppLockService lock;
  late MemoryLockStore store;
  setUp(() {
    store = MemoryLockStore();
    lock = AppLockService(store: store);
  });

  test('a passcode is never stored as typed, and the same code hashes differently with another salt', () async {
    await lock.setPin('4821', owner: 'u1');
    expect(store.data.values.any((v) => v == '4821'), isFalse);
    expect(AppLockService.hash('4821', 'a'), isNot(AppLockService.hash('4821', 'b')));
    expect(AppLockService.hash('4821', 'a'), AppLockService.hash('4821', 'a'));
  });

  test('the right passcode unlocks, a wrong one counts down the tries', () async {
    await lock.setPin('4821', owner: 'u1');
    expect((await lock.verifyPin('4821')).check, PinCheck.ok);
    final r = await lock.verifyPin('1111');
    expect(r.check, PinCheck.wrong);
    expect(r.triesLeft, AppLockService.maxTries - 1);
  });

  test('a right passcode resets the count', () async {
    await lock.setPin('4821', owner: 'u1');
    await lock.verifyPin('0000');
    await lock.verifyPin('0000');
    expect((await lock.verifyPin('4821')).check, PinCheck.ok);
    expect((await lock.verifyPin('0000')).triesLeft, AppLockService.maxTries - 1);
  });

  test('five wrong tries remove the passcode and the fingerprint with it', () async {
    await lock.setPin('4821', owner: 'u1');
    await lock.setFingerprint(true);
    PinResult? last;
    for (var i = 0; i < AppLockService.maxTries; i++) {
      last = await lock.verifyPin('9999');
    }
    expect(last!.check, PinCheck.tooMany);
    expect(await lock.hasPin(), isFalse);
    expect(await lock.fingerprintOn(), isFalse);
    expect((await lock.verifyPin('4821')).check, PinCheck.notSet);
  });

  test('the fingerprint can only be on while a passcode exists', () async {
    await lock.setFingerprint(true);
    expect(await lock.fingerprintOn(), isFalse);
    await lock.setPin('4821', owner: 'u1');
    await lock.setFingerprint(true);
    expect(await lock.fingerprintOn(), isTrue);
    await lock.setFingerprint(false);
    expect(await lock.fingerprintOn(), isFalse);
  });

  test('the passcode remembers whose it is', () async {
    await lock.setPin('4821', owner: 'user-7');
    expect(await lock.owner(), 'user-7');
  });

  test('only 4 digits are accepted, and easy ones are called weak', () async {
    expect(AppLockService.isValidPin('1234'), isTrue);
    for (final bad in ['123', '12345', 'abcd', '12a4', '']) {
      expect(AppLockService.isValidPin(bad), isFalse, reason: bad);
    }
    for (final weak in ['0000', '1111', '1234', '4321', '2345', '9876']) {
      expect(AppLockService.isWeakPin(weak), isTrue, reason: weak);
    }
    for (final ok in ['4821', '1357', '2580', '7391']) {
      expect(AppLockService.isWeakPin(ok), isFalse, reason: ok);
    }
    expect(() => lock.setPin('12', owner: 'u'), throwsArgumentError);
  });

  test('clearAll (sign-out) leaves nothing behind', () async {
    await lock.setPin('4821', owner: 'u1');
    await lock.setFingerprint(true);
    await lock.addSetupSkip();
    await lock.clearAll();
    expect(store.data, isEmpty);
  });

  test('the set-up offer is skipped twice at most', () async {
    expect(await lock.setupSkips(), 0);
    await lock.addSetupSkip();
    await lock.addSetupSkip();
    expect(await lock.setupSkips(), 2);
  });
}
