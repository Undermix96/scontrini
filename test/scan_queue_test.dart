import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:scontrini/ai/ai_client.dart';
import 'package:scontrini/app_state.dart';
import 'package:scontrini/scan_controller.dart';

import 'support/fake_app.dart';

Uint8List _img(int n) => Uint8List.fromList([n, n, n]);

/// Aspetta che la coda abbia finito (le letture usano il database vero).
Future<void> _idle(AppState s) async {
  for (var i = 0; i < 200 && s.scan.running; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  await Future<void>.delayed(const Duration(milliseconds: 20));
}

void main() {
  group('richiesta con più parti', () {
    test('tutte le immagini nello stesso messaggio, con le istruzioni', () async {
      late Map body;
      final ai = AiClient(client: MockClient((req) async {
        body = jsonDecode(req.body) as Map;
        return http.Response.bytes(
            utf8.encode(jsonEncode({
              'choices': [
                {
                  'message': {
                    'content': jsonEncode({
                      'is_receipt': true,
                      'merchant': 'Coop',
                      'purchased_at': null,
                      'total': 1,
                      'currency': 'EUR',
                      'payment_method': null,
                      'items': [],
                    })
                  }
                }
              ]
            })),
            200);
      }));
      const e = AiEndpoint(provider: AiProvider.openRouter, model: 'm', apiKey: 'k');
      await ai.scanParts(e, [(_img(1), 'image/jpeg'), (_img(2), 'image/png')], ['Altro']);
      final content = (body['messages'] as List).single['content'] as List;
      expect(content.where((c) => c['type'] == 'image_url').length, 2);
      expect(content[1]['image_url']['url'], startsWith('data:image/jpeg;base64,'));
      expect(content[2]['image_url']['url'], startsWith('data:image/png;base64,'));
      expect(content.first['text'], contains('parti consecutive dello STESSO scontrino'));
    });

    test('una sola foto: niente istruzioni sulle parti', () {
      expect(AiClient.prompt(['Altro']), isNot(contains('parti consecutive')));
    });

    test('troppe parti o troppo pesanti: rifiutate prima di inviare', () async {
      var calls = 0;
      final ai = AiClient(client: MockClient((_) async {
        calls++;
        return http.Response('{}', 500);
      }));
      const e = AiEndpoint(provider: AiProvider.openRouter, model: 'm', apiKey: 'k');
      await expectLater(
          ai.scanParts(e, [for (var i = 0; i < maxScanParts + 1; i++) (_img(i), 'image/jpeg')], ['Altro']),
          throwsA(isA<AiException>()));
      final big = Uint8List(5 * 1024 * 1024);
      await expectLater(ai.scanParts(e, [(big, 'image/jpeg'), (big, 'image/jpeg')], ['Altro']),
          throwsA(isA<AiException>()));
      expect(calls, 0);
    });
  });

  group('coda delle letture', () {
    late FakeApp app;
    late AppState s;
    setUp(() async {
      app = FakeApp();
      s = await app.state(seeded: false);
    });
    tearDown(() => app.db.close());

    test('una alla volta, in ordine, con le parti', () async {
      app.ai.scanCompleter = Completer<AiScan>();
      s.scan.enqueue([(_img(1), 'image/jpeg'), (_img(2), 'image/jpeg')]);
      s.scan.enqueue([(_img(3), 'image/jpeg')]);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(app.ai.scans, 1, reason: 'la seconda aspetta la prima');
      expect(s.scan.jobs.map((j) => j.status), [ScanStatus.running, ScanStatus.waiting]);
      expect(s.scan.pending, 2);
      app.ai.scanCompleter!.complete(AiScan(FakeAi.sampleScan, 'm'));
      // La stessa risposta finta vale per entrambe.
      await _idle(s);
      expect(app.ai.partsPerScan, [2, 1]);
      expect(s.scan.jobs.every((j) => j.status == ScanStatus.done), isTrue);
      expect((await app.repo.allReceipts()).length, 2);
    });

    test('annullare una lettura in attesa: non parte mai', () async {
      app.ai.scanCompleter = Completer<AiScan>();
      s.scan.enqueue([(_img(1), 'image/jpeg')]);
      final second = s.scan.enqueue([(_img(2), 'image/jpeg')]);
      s.scan.cancel(second);
      app.ai.scanCompleter!.complete(AiScan(FakeAi.sampleScan, 'm'));
      await _idle(s);
      expect(app.ai.scans, 1);
      expect((await app.repo.allReceipts()).length, 1);
    });

    test("un errore non blocca le altre; si riprova con le stesse foto", () async {
      app.ai.failures = 1;
      final first = s.scan.enqueue([(_img(1), 'image/jpeg')]);
      s.scan.enqueue([(_img(2), 'image/jpeg')]);
      await _idle(s);
      expect(first.status, ScanStatus.error);
      expect(s.scan.jobs.last.status, ScanStatus.done);
      s.scan.retry(first);
      await _idle(s);
      expect(first.status, ScanStatus.done);
      expect(app.ai.scans, 3);
    });

    test('con "Conserva le foto" ogni parte diventa una foto', () async {
      await s.config.setKeepPhotos(true);
      s.scan.enqueue([(_img(1), 'image/jpeg'), (_img(2), 'image/jpeg'), (_img(3), 'image/png')]);
      await _idle(s);
      final r = s.scan.jobs.single.result!;
      final photos = await app.repo.photosOf(r.id);
      expect(photos.map((p) => p.position), [0, 1, 2]);
      expect(photos.last.fileName, endsWith('.png'));
      await app.photos.dir.delete(recursive: true);
    });
  });
}
