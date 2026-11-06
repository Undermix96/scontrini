import 'dart:convert';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// PIN dell'app salvato come PBKDF2-HMAC-SHA256 con salt casuale.
///
/// Formato: `pbkdf2-sha256$<iterazioni>$<lunghezza PIN>$<salt b64>$<hash b64>`.
/// La lunghezza serve a sbloccare appena si digita l'ultima cifra.
class PinHash {
  static const defaultIterations = 120000;
  static const _prefix = 'pbkdf2-sha256';

  final int iterations;
  final int length;
  final Uint8List salt;
  final Uint8List hash;

  const PinHash._(this.iterations, this.length, this.salt, this.hash);

  static Future<PinHash> create(String pin, {int iterations = defaultIterations}) async {
    final rnd = Random.secure();
    final salt = Uint8List.fromList(List.generate(16, (_) => rnd.nextInt(256)));
    final hash = await _derive(pin, salt, iterations);
    return PinHash._(iterations, pin.length, salt, hash);
  }

  static PinHash? parse(String? s) {
    if (s == null) return null;
    final p = s.split(r'$');
    if (p.length != 5 || p[0] != _prefix) return null;
    final it = int.tryParse(p[1]);
    final len = int.tryParse(p[2]);
    if (it == null || len == null || it < 1) return null;
    try {
      return PinHash._(it, len, base64Decode(p[3]), base64Decode(p[4]));
    } on FormatException {
      return null;
    }
  }

  String encode() => [_prefix, iterations, length, base64Encode(salt), base64Encode(hash)].join(r'$');

  Future<bool> verify(String pin) async {
    if (pin.length != length) return false;
    final h = await _derive(pin, salt, iterations);
    var diff = h.length ^ hash.length;
    for (var i = 0; i < h.length && i < hash.length; i++) {
      diff |= h[i] ^ hash[i];
    }
    return diff == 0;
  }

  /// Calcolo in un isolate per non bloccare l'interfaccia.
  static Future<Uint8List> _derive(String pin, Uint8List salt, int iterations) =>
      Isolate.run(() => pbkdf2(utf8.encode(pin), salt, iterations));
}

/// PBKDF2 con HMAC-SHA256, un solo blocco (32 byte).
Uint8List pbkdf2(List<int> password, List<int> salt, int iterations) {
  final hmac = Hmac(sha256, password);
  var u = hmac.convert([...salt, 0, 0, 0, 1]).bytes;
  final out = Uint8List.fromList(u);
  for (var i = 1; i < iterations; i++) {
    u = hmac.convert(u).bytes;
    for (var j = 0; j < out.length; j++) {
      out[j] ^= u[j];
    }
  }
  return out;
}
