import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Configurazione locale dell'app.
///
/// L'URL del progetto Supabase può essere passato in build con
/// `--dart-define=SUPABASE_URL=...` (non è un segreto). Il token dell'app
/// NON viene mai compilato nel binario: lo inserisce l'utente nelle
/// impostazioni ed è salvato nel Keystore (Android) / Keychain (iOS).
class AppConfig {
  static const _buildUrl = String.fromEnvironment('SUPABASE_URL');
  static const _kUrl = 'supabase_url';
  static const _kToken = 'app_token';

  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device),
  );

  String url = '';
  String token = '';

  bool get isConfigured => url.isNotEmpty && token.isNotEmpty;

  Future<void> load() async {
    url = (await _storage.read(key: _kUrl)) ?? _buildUrl;
    token = (await _storage.read(key: _kToken)) ?? '';
  }

  Future<void> save({required String url, required String token}) async {
    this.url = url.trim().replaceAll(RegExp(r'/+$'), '');
    this.token = token.trim();
    await _storage.write(key: _kUrl, value: this.url);
    await _storage.write(key: _kToken, value: this.token);
  }
}
