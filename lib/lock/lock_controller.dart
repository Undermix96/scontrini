import 'package:flutter/foundation.dart';

import '../config.dart';
import '../data/repository.dart';
import 'biometrics.dart';
import 'pin_hash.dart';

/// Esito di un tentativo con il PIN.
sealed class PinResult {
  const PinResult();
}

class PinOk extends PinResult {
  const PinOk();
}

class PinWrong extends PinResult {
  /// Attesa imposta dopo questo errore (null se si può riprovare subito).
  final Duration? wait;
  const PinWrong([this.wait]);
}

class PinWait extends PinResult {
  final Duration remaining;
  const PinWait(this.remaining);
}

/// Blocco dell'app con PIN (e impronta facoltativa).
///
/// Il PIN sta solo nell'archivio sicuro del sistema, come hash PBKDF2; le
/// preferenze nella tabella delle impostazioni, ma non nel backup: dopo un
/// ripristino il blocco va riattivato.
class LockController extends ChangeNotifier {
  static const kPin = 'lock_pin';
  static const kBiometric = 'lock_biometric';
  static const kTimeout = 'lock_timeout';
  static const kSecureScreen = 'lock_secure_screen';
  static const kFailed = 'lock_failed';
  static const kWaitUntil = 'lock_wait_until';

  static const timeouts = [Duration.zero, Duration(minutes: 1), Duration(minutes: 5), Duration(minutes: 15)];
  static const defaultTimeout = Duration(minutes: 1);

  /// Errori consentiti prima delle attese.
  static const freeAttempts = 5;

  final Repository repo;
  final KeyStore keys;
  final Biometrics biometrics;
  final SecureWindow window;
  final int iterations;

  LockController(this.repo, this.keys, this.biometrics,
      {this.window = const SecureWindow(), this.iterations = PinHash.defaultIterations});

  DateTime _now() => repo.now();

  PinHash? _pin;
  bool biometric = false;
  Duration timeout = defaultTimeout;
  bool secureScreen = false;
  bool locked = false;
  int failed = 0;
  DateTime? waitUntil;

  /// Blocco attivo (PIN impostato).
  bool get enabled => _pin != null;
  int get pinLength => _pin?.length ?? 0;

  Future<void> load() async {
    try {
      _pin = PinHash.parse(await keys.read(kPin));
    } catch (_) {
      _pin = null;
    }
    biometric = enabled && await repo.setting(kBiometric) == 'true';
    final t = int.tryParse(await repo.setting(kTimeout) ?? '');
    timeout = t == null ? defaultTimeout : Duration(seconds: t);
    secureScreen = await repo.setting(kSecureScreen) == 'true';
    failed = int.tryParse(await repo.setting(kFailed) ?? '') ?? 0;
    final w = int.tryParse(await repo.setting(kWaitUntil) ?? '');
    waitUntil = w == null ? null : DateTime.fromMillisecondsSinceEpoch(w);
    locked = enabled;
    await window.set(secureScreen);
    notifyListeners();
  }

  // ------------------------------------------------------------ PIN

  /// Imposta o cambia il PIN. Alla prima attivazione lo schermo sicuro si
  /// accende (si può spegnere a parte).
  Future<void> setPin(String pin) async {
    final first = !enabled;
    final h = await PinHash.create(pin, iterations: iterations);
    await keys.write(kPin, h.encode());
    _pin = h;
    locked = false;
    await _resetFailures();
    if (first) await setSecureScreen(true);
    notifyListeners();
  }

  /// Disattiva il blocco: PIN, impronta e schermo sicuro.
  Future<void> disable() async {
    await keys.delete(kPin);
    _pin = null;
    locked = false;
    await setBiometric(false);
    await setSecureScreen(false);
    await _resetFailures();
    notifyListeners();
  }

  /// Attesa rimasta prima di poter riprovare (null se nessuna).
  Duration? get remainingWait {
    final w = waitUntil;
    if (w == null) return null;
    final d = w.difference(_now());
    return d > Duration.zero ? d : null;
  }

  /// Attesa dopo [n] errori: dal quinto 30 s, poi raddoppia, al massimo un'ora.
  static Duration? waitAfter(int n) {
    if (n < freeAttempts) return null;
    final s = 30 * (1 << (n - freeAttempts).clamp(0, 7));
    return Duration(seconds: s.clamp(30, 3600));
  }

  Future<PinResult> checkPin(String pin) async {
    final h = _pin;
    if (h == null) return const PinOk();
    final wait = remainingWait;
    if (wait != null) return PinWait(wait);
    if (await h.verify(pin)) {
      await _resetFailures();
      return const PinOk();
    }
    failed++;
    await repo.setSetting(kFailed, '$failed');
    final w = waitAfter(failed);
    if (w != null) {
      waitUntil = _now().add(w);
      await repo.setSetting(kWaitUntil, '${waitUntil!.millisecondsSinceEpoch}');
    }
    notifyListeners();
    return PinWrong(w);
  }

  Future<PinResult> unlockWithPin(String pin) async {
    final r = await checkPin(pin);
    if (r is PinOk) _unlock();
    return r;
  }

  Future<bool> unlockWithBiometric() async {
    if (!biometric || !locked) return false;
    final ok = await suspendWhile(() => biometrics.authenticate('Sblocca Scontrini'));
    if (ok) {
      await _resetFailures();
      _unlock();
    }
    return ok;
  }

  void _unlock() {
    locked = false;
    notifyListeners();
  }

  Future<void> _resetFailures() async {
    if (failed == 0 && waitUntil == null) return;
    failed = 0;
    waitUntil = null;
    await repo.setSetting(kFailed, null);
    await repo.setSetting(kWaitUntil, null);
  }

  // ------------------------------------------------------------ preferenze

  Future<void> setBiometric(bool on) async {
    biometric = on && enabled;
    await repo.setSetting(kBiometric, biometric ? 'true' : null);
    notifyListeners();
  }

  Future<void> setTimeout(Duration d) async {
    timeout = d;
    await repo.setSetting(kTimeout, '${d.inSeconds}');
    notifyListeners();
  }

  Future<void> setSecureScreen(bool on) async {
    secureScreen = on;
    await repo.setSetting(kSecureScreen, on ? 'true' : null);
    await window.set(on);
    notifyListeners();
  }

  // ------------------------------------------------------------ ciclo di vita

  int _suspended = 0;
  DateTime? _pausedAt;

  /// Esegue [f] (fotocamera, galleria, selettore di file, impronta) senza
  /// contare il tempo passato fuori dall'app.
  Future<T> suspendWhile<T>(Future<T> Function() f) async {
    _suspended++;
    try {
      return await f();
    } finally {
      _suspended--;
    }
  }

  /// L'app è andata in background.
  void paused() {
    if (_suspended > 0 || !enabled || locked) return;
    _pausedAt ??= _now();
  }

  /// L'app è tornata in primo piano: si blocca se è passato il tempo scelto.
  void resumed() {
    final p = _pausedAt;
    _pausedAt = null;
    if (p == null || !enabled || locked) return;
    if (_now().difference(p) >= timeout) {
      locked = true;
      notifyListeners();
    }
  }
}
