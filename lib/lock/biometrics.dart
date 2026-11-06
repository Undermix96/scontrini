import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:local_auth_android/local_auth_android.dart';

/// Sblocco biometrico tramite le API di sistema (BiometricPrompt, Face ID /
/// Touch ID). Sostituibile nei test.
abstract class Biometrics {
  /// Vero se il dispositivo ha un sensore e almeno un'impronta o un volto registrati.
  Future<bool> available();

  /// Vero se l'utente si è riconosciuto.
  Future<bool> authenticate(String reason);
}

class SystemBiometrics implements Biometrics {
  final _auth = LocalAuthentication();

  @override
  Future<bool> available() async {
    try {
      return await _auth.canCheckBiometrics && (await _auth.getAvailableBiometrics()).isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> authenticate(String reason) async {
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        biometricOnly: true,
        authMessages: const [
          AndroidAuthMessages(signInTitle: 'Sblocca Scontrini', cancelButton: 'Usa il PIN'),
        ],
      );
    } catch (_) {
      // Annullato, troppi tentativi o sensore non disponibile: resta il PIN.
      return false;
    }
  }
}

/// Schermo sicuro: FLAG_SECURE su Android, sfocatura nelle app recenti su iOS.
class SecureWindow {
  static const _channel = MethodChannel('scontrini/window');

  const SecureWindow();

  Future<void> set(bool secure) async {
    try {
      await _channel.invokeMethod<void>('setSecure', secure);
    } catch (_) {
      // Piattaforma senza canale (test, desktop): niente da fare.
    }
  }
}
