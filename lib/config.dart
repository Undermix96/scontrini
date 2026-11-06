import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'ai/ai_client.dart';
import 'data/repository.dart';

/// Dove sta la chiave API: Keystore (Android) / Keychain (iOS). Sostituibile
/// nei test.
abstract class KeyStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class SecureKeyStore implements KeyStore {
  static const _storage = FlutterSecureStorage(
    // Cifratura di default della 11.x (AES-GCM con chiave nel Keystore).
    aOptions: AndroidOptions(),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device),
  );

  const SecureKeyStore();

  @override
  Future<String?> read(String key) => _storage.read(key: key);
  @override
  Future<void> write(String key, String value) => _storage.write(key: key, value: value);
  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

class MemoryKeyStore implements KeyStore {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async => values[key] = value;
  @override
  Future<void> delete(String key) async => values.remove(key);
}

/// Configurazione dell'app.
///
/// Provider, indirizzo e modello stanno nel database (e quindi nel backup);
/// la chiave API solo nell'archivio sicuro del sistema: non entra mai nel
/// backup, nel binario o nel repository.
class AppConfig {
  static const kProvider = 'ai_provider';
  static const kBaseUrl = 'ai_base_url';
  static const kModel = 'ai_model';
  static const kSetupDone = 'setup_done';
  static const kLastBackup = 'last_backup_at';
  static const _kApiKey = 'ai_api_key';

  /// Chiavi della vecchia versione con server Supabase.
  static const _legacyKeys = ['supabase_url', 'app_token'];

  final Repository repo;
  final KeyStore keys;

  AppConfig(this.repo, {KeyStore? keys}) : keys = keys ?? const SecureKeyStore();

  AiProvider provider = AiProvider.openRouter;
  String baseUrl = '';
  String model = defaultOpenRouterModel;
  String apiKey = '';
  bool setupDone = false;
  DateTime? lastBackupAt;

  bool get isConfigured => setupDone && apiKey.isNotEmpty;

  AiEndpoint get endpoint => AiEndpoint(provider: provider, baseUrl: baseUrl, model: model, apiKey: apiKey);

  Future<void> load() async {
    provider = AiProvider.fromCode(await repo.setting(kProvider));
    baseUrl = await repo.setting(kBaseUrl) ?? '';
    model = await repo.setting(kModel) ?? (provider == AiProvider.openRouter ? defaultOpenRouterModel : '');
    setupDone = await repo.setting(kSetupDone) == 'true';
    lastBackupAt = DateTime.tryParse(await repo.setting(kLastBackup) ?? '')?.toLocal();
    try {
      apiKey = await keys.read(_kApiKey) ?? '';
      for (final k in _legacyKeys) {
        await keys.delete(k);
      }
    } catch (_) {
      // Archivio sicuro illeggibile (es. dopo un ripristino del sistema):
      // la chiave andrà reinserita.
      apiKey = '';
    }
  }

  /// Rilegge solo le impostazioni dal database (dopo un ripristino).
  Future<void> reloadSettings() async {
    final key = apiKey;
    await load();
    apiKey = key;
  }

  Future<void> save(AiEndpoint e) async {
    provider = e.provider;
    baseUrl = e.provider == AiProvider.openRouter ? '' : AiEndpoint.normalizeBaseUrl(e.baseUrl);
    model = e.model.trim();
    apiKey = e.apiKey.trim();
    await repo.setSetting(kProvider, provider.code);
    await repo.setSetting(kBaseUrl, baseUrl);
    await repo.setSetting(kModel, model);
    await keys.write(_kApiKey, apiKey);
    if (!setupDone) {
      setupDone = true;
      await repo.setSetting(kSetupDone, 'true');
    }
  }

  Future<void> backupDone(DateTime at) async {
    lastBackupAt = at;
    await repo.setSetting(kLastBackup, at.toUtc().toIso8601String());
  }
}
