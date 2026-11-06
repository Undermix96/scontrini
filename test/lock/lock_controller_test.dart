import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:scontrini/config.dart';
import 'package:scontrini/data/repository.dart';
import 'package:scontrini/lock/lock_controller.dart';
import 'package:scontrini/lock/pin_hash.dart';

import '../support/fake_app.dart';

String _hex(List<int> b) => b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

void main() {
  group('PBKDF2-HMAC-SHA256', () {
    // Vettori di prova (RFC 7914 §11 e set comunemente usati).
    test('vettori noti', () {
      expect(_hex(pbkdf2(utf8.encode('password'), utf8.encode('salt'), 1)),
          '120fb6cffcf8b32c43e7225256c4f837a86548c92ccc35480805987cb70be17b');
      expect(_hex(pbkdf2(utf8.encode('password'), utf8.encode('salt'), 2)),
          'ae4d0c95af6b46d32d0adff928f06dd02a303f8ef3c251dfd6e2d85a95474c43');
      expect(_hex(pbkdf2(utf8.encode('password'), utf8.encode('salt'), 4096)),
          'c5e478d59288c841aa530db6845c4c8d962893a001ce4e11a4963873aa98134a');
    });

    test('codifica, lettura e verifica', () async {
      final h = await PinHash.create('2580', iterations: 10);
      final back = PinHash.parse(h.encode())!;
      expect(back.length, 4);
      expect(await back.verify('2580'), isTrue);
      expect(await back.verify('2581'), isFalse);
      expect(await back.verify('25800'), isFalse);
      expect(PinHash.parse('qualcosa'), isNull);
      expect(PinHash.parse(null), isNull);
    });

    test('salt diverso a ogni PIN', () async {
      final a = await PinHash.create('1234', iterations: 10);
      final b = await PinHash.create('1234', iterations: 10);
      expect(a.encode(), isNot(b.encode()));
    });
  });

  group('LockController', () {
    late DateTime clock;
    late MemoryKeyStore keys;
    late Repository repo;
    late FakeBiometrics bio;

    LockController make() => LockController(repo, keys, bio, iterations: 10);

    setUp(() {
      clock = DateTime(2026, 11, 6, 12);
      keys = MemoryKeyStore();
      repo = Repository(memoryDatabase(), now: () => clock);
      bio = FakeBiometrics();
    });

    test('senza PIN non si blocca mai', () async {
      final l = make();
      await l.load();
      expect(l.enabled, isFalse);
      expect(l.locked, isFalse);
      l.paused();
      clock = clock.add(const Duration(hours: 1));
      l.resumed();
      expect(l.locked, isFalse);
    });

    test("PIN impostato: hash nell'archivio sicuro, bloccata al riavvio", () async {
      final l = make();
      await l.load();
      await l.setPin('2580');
      expect(l.locked, isFalse);
      expect(l.secureScreen, isTrue, reason: 'schermo sicuro acceso di default col blocco');
      expect(keys.values[LockController.kPin], startsWith('pbkdf2-sha256\$10\$4\$'));
      expect(keys.values[LockController.kPin], isNot(contains('2580')));

      final again = make();
      await again.load();
      expect(again.locked, isTrue);
      expect(again.pinLength, 4);
      expect(await again.unlockWithPin('1111'), isA<PinWrong>());
      expect(again.locked, isTrue);
      expect(await again.unlockWithPin('2580'), isA<PinOk>());
      expect(again.locked, isFalse);
    });

    test('si blocca solo dopo il tempo scelto', () async {
      final l = make();
      await l.load();
      await l.setPin('2580');
      expect(l.timeout, LockController.defaultTimeout);

      l.paused();
      clock = clock.add(const Duration(seconds: 59));
      l.resumed();
      expect(l.locked, isFalse);

      l.paused();
      clock = clock.add(const Duration(minutes: 1));
      l.resumed();
      expect(l.locked, isTrue);
    });

    test('il tempo nella fotocamera o nel selettore non conta', () async {
      final l = make();
      await l.load();
      await l.setPin('2580');
      await l.setTimeout(Duration.zero);
      await l.suspendWhile(() async {
        l.paused();
        clock = clock.add(const Duration(minutes: 10));
        l.resumed();
      });
      expect(l.locked, isFalse);
      l.paused();
      l.resumed();
      expect(l.locked, isTrue, reason: 'con "Subito" basta uscire');
    });

    test('attese crescenti dal quinto errore, azzerate dal PIN giusto', () async {
      final l = make();
      await l.load();
      await l.setPin('2580');
      for (var i = 0; i < 4; i++) {
        expect(await l.checkPin('0000'), isA<PinWrong>().having((r) => r.wait, 'wait', isNull));
      }
      final fifth = await l.checkPin('0000');
      expect(fifth, isA<PinWrong>().having((r) => r.wait, 'wait', const Duration(seconds: 30)));
      expect(await l.checkPin('2580'), isA<PinWait>(), reason: 'durante l\'attesa nemmeno il PIN giusto');

      // L'attesa sopravvive al riavvio.
      final again = make();
      await again.load();
      expect(again.remainingWait, const Duration(seconds: 30));

      clock = clock.add(const Duration(seconds: 31));
      expect(await again.checkPin('0000'), isA<PinWrong>().having((r) => r.wait, 'wait', const Duration(minutes: 1)));
      clock = clock.add(const Duration(minutes: 2));
      expect(await again.checkPin('2580'), isA<PinOk>());
      expect(again.failed, 0);
      expect(await repo.setting(LockController.kFailed), isNull);
    });

    test('impronta: solo con PIN, sblocca e azzera gli errori', () async {
      final l = make();
      await l.load();
      await l.setBiometric(true);
      expect(l.biometric, isFalse, reason: 'senza PIN non si attiva');
      await l.setPin('2580');
      await l.setBiometric(true);
      await l.checkPin('0000');

      final again = make();
      await again.load();
      expect(again.biometric, isTrue);
      bio.succeed = false;
      expect(await again.unlockWithBiometric(), isFalse);
      expect(again.locked, isTrue);
      bio.succeed = true;
      expect(await again.unlockWithBiometric(), isTrue);
      expect(again.locked, isFalse);
      expect(again.failed, 0);
    });

    test('disattivazione: via PIN, impronta e schermo sicuro', () async {
      final l = make();
      await l.load();
      await l.setPin('2580');
      await l.setBiometric(true);
      await l.disable();
      expect(l.enabled, isFalse);
      expect(l.biometric, isFalse);
      expect(l.secureScreen, isFalse);
      expect(keys.values, isEmpty);
      final again = make();
      await again.load();
      expect(again.locked, isFalse);
    });
  });
}
