import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:scontrini/ai/ai_client.dart';
import 'package:scontrini/app_state.dart';
import 'package:scontrini/config.dart';
import 'package:scontrini/data/db.dart';
import 'package:scontrini/data/photos.dart';
import 'package:scontrini/data/repository.dart';
import 'package:scontrini/files.dart';
import 'package:scontrini/lock/biometrics.dart';

/// Database in memoria via FFI (sqlite3 del sistema di sviluppo, vedi
/// `hooks` in pubspec.yaml). L'app usa invece sqflite.
AppDatabase memoryDatabase() => AppDatabase(NativeDatabase.memory());

/// Servizio AI finto: niente rete.
class FakeAi extends AiClient {
  /// Se impostato, scan resta in attesa finché non viene completato.
  Completer<AiScan>? scanCompleter;

  /// Errore restituito dalla verifica della chiave (null = chiave valida).
  AiException? probeError;
  final probes = <AiEndpoint>[];
  int scans = 0;

  /// Le prossime [failures] letture falliscono.
  int failures = 0;

  /// Numero di foto di ogni lettura.
  final partsPerScan = <int>[];

  static Map<String, dynamic> get sampleScan => {
        'is_receipt': true,
        'merchant': 'Esselunga',
        'purchased_at': null,
        'total': 3.4,
        'currency': 'EUR',
        'payment_method': 'carta',
        'items': [
          {'description': 'Latte', 'quantity': 2, 'unit_price': 0.65, 'total': 1.3, 'category': 'Alimentari'},
          {'description': 'Pane', 'quantity': null, 'unit_price': null, 'total': 2.1, 'category': 'Alimentari'},
        ],
      };

  @override
  Future<void> probe(AiEndpoint e) async {
    probes.add(e);
    if (probeError != null) throw probeError!;
  }

  @override
  Future<AiScan> scanParts(AiEndpoint e, List<(Uint8List, String)> parts, List<String> categories) {
    scans++;
    partsPerScan.add(parts.length);
    if (failures > 0) {
      failures--;
      return Future.error(AiException(AiErrorKind.network, 'Servizio non raggiungibile'));
    }
    return scanCompleter?.future ?? Future.value(AiScan(sampleScan, 'google/gemini-2.5-flash'));
  }
}

class FakeBiometrics implements Biometrics {
  bool isAvailable = true;
  bool succeed = true;
  int prompts = 0;

  @override
  Future<bool> available() async => isAvailable;

  @override
  Future<bool> authenticate(String reason) async {
    prompts++;
    return succeed;
  }
}

class FakeFiles implements FileGateway {
  final saved = <String, Uint8List>{};
  Uint8List? toOpen;

  @override
  Future<bool> save(String fileName, Uint8List bytes, String mimeType) async {
    saved[fileName] = bytes;
    return true;
  }

  @override
  Future<Uint8List?> open() async => toOpen;
}

/// App con database in memoria e gli stessi dati delle tavole del design.
class FakeApp {
  /// Orologio dell'app: si può spostare in avanti nei test.
  DateTime now;
  final db = memoryDatabase();
  /// Cartella temporanea per le foto conservate, eliminata a fine test.
  late final photos = PhotoStore(Directory.systemTemp.createTempSync('scontrini_photos_'));
  late final repo = Repository(db, now: () => now, photos: photos);
  final keys = MemoryKeyStore();
  final ai = FakeAi();
  final files = FakeFiles();
  final biometrics = FakeBiometrics();

  FakeApp({DateTime? now}) : now = now ?? DateTime.now() {
    // Ogni test crea il proprio database in memoria: è voluto.
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  }

  /// Giorni fa, senza uscire dal mese corrente (le schermate mostrano un
  /// mese alla volta).
  int _clamp(int daysAgo) => now.day - 1 < daysAgo ? 0 : daysAgo;

  int _at(int daysAgo, int h, int m) =>
      DateTime(now.year, now.month, now.day - _clamp(daysAgo), h, m).toUtc().millisecondsSinceEpoch;

  /// Inserisce gli scontrini dimostrativi. Categorie del seed: 1 Alimentari,
  /// 2 Bevande, 3 Casa, 4 Igiene, 5 Salute, …, 10 Altro.
  Future<void> seed() async {
    Future<void> receipt(String id, String merchant, int at, int total, List<(String, double?, int?, int, int?)> items,
        {String? duplicateOf, String payment = 'carta'}) async {
      await db.into(db.receipts).insert(ReceiptsCompanion.insert(
            id: id,
            merchant: Value(merchant),
            purchasedAt: Value(at),
            totalCents: Value(total),
            paymentMethod: Value(payment),
            aiModel: const Value('google/gemini-2.5-flash'),
            duplicateOf: Value(duplicateOf),
            createdAt: at + 5 * 60000,
            updatedAt: at + 5 * 60000,
          ));
      for (var i = 0; i < items.length; i++) {
        final (desc, qty, unit, tot, cat) = items[i];
        await db.into(db.receiptItems).insert(ReceiptItemsCompanion.insert(
              id: '$id-i${i + 1}',
              receiptId: id,
              position: Value(i),
              description: desc,
              quantity: Value(qty),
              unitPriceCents: Value(unit),
              totalCents: Value(tot),
              categoryId: Value(cat),
              createdAt: at,
            ));
      }
    }

    // Scontrino originale del doppione, nel mese precedente.
    final prev = DateTime(now.year, now.month - 1, 10, 19, 2).toUtc().millisecondsSinceEpoch;
    await receipt('r9', 'Coop', prev, 3785, [('Spesa', null, null, 3785, 1)]);
    await receipt('r1', 'Esselunga', _at(0, 18, 42), 6420, [
      ('Latte intero 1 l', 2, 65, 130, 1),
      ('Pane casereccio', null, null, 210, 1),
      ('Detersivo piatti', null, null, 349, 3),
      ('Mele Golden', 1.24, 199, 247, 1),
      ('Acqua frizzante 6×1,5 l', null, null, 294, 2),
      ('Spazzolino', null, null, 5040, 4),
    ]);
    await receipt('r2', 'Farmacia Comunale', _at(0, 10, 5), 1890, [
      ('Tachipirina', null, null, 990, 5),
      ('Cerotti', null, null, 900, 5),
    ]);
    await receipt('r3', 'Coop', _at(1, 19, 2), 3785, [('Spesa', null, null, 3785, 1)], duplicateOf: 'r9');
    await receipt('r4', 'Bar Centrale', _at(1, 8, 15), 430, [
      ('Cappuccino', null, null, 150, 2),
      ('Brioche', null, null, 280, null),
    ], payment: 'contanti');
  }

  /// [configured]: chiave salvata e primo avvio completato.
  Future<AppState> state({bool configured = true, bool seeded = true}) async {
    if (seeded) await seed();
    final config = AppConfig(repo, keys: keys);
    if (configured) {
      await config.save(const AiEndpoint(
          provider: AiProvider.openRouter, model: defaultOpenRouterModel, apiKey: 'sk-or-test-key'));
      await config.finishSetup();
    }
    await config.load();
    final state = AppState(config, ai: ai, files: files, biometrics: biometrics, pinIterations: 10);
    await state.lock.load();
    return state;
  }

  /// Contenuto di un file salvato, come testo.
  String savedText(String name) => utf8.decode(files.saved[name]!);
}
