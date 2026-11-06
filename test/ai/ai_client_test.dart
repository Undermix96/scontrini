import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:scontrini/ai/ai_client.dart';

const _openRouter = AiEndpoint(provider: AiProvider.openRouter, model: 'google/gemini-2.5-flash', apiKey: ' sk-or-1 ');
const _custom = AiEndpoint(
    provider: AiProvider.openAiCompatible, baseUrl: 'https://api.example.com/v1/', model: 'vision-1', apiKey: 'k');

http.Response _json(Object body, [int status = 200]) =>
    http.Response.bytes(utf8.encode(jsonEncode(body)), status, headers: {'content-type': 'application/json'});

Map<String, dynamic> _completion(String content, {String model = 'google/gemini-2.5-flash'}) => {
      'model': model,
      'choices': [
        {
          'message': {'role': 'assistant', 'content': content}
        }
      ],
    };

final _receipt = {
  'is_receipt': true,
  'merchant': 'Coop',
  'purchased_at': '2026-11-04T18:30:00',
  'total': 3.4,
  'currency': 'EUR',
  'payment_method': null,
  'items': [],
};

void main() {
  final image = Uint8List.fromList([1, 2, 3]);

  test('OpenRouter: richiesta con privacy, schema e categorie', () async {
    late http.Request sent;
    final ai = AiClient(client: MockClient((req) async {
      sent = req;
      return _json(_completion(jsonEncode(_receipt)));
    }));
    final r = await ai.scan(_openRouter, image, 'image/jpeg', ['Alimentari', 'Altro']);
    expect(sent.url.toString(), 'https://openrouter.ai/api/v1/chat/completions');
    expect(sent.headers['Authorization'], 'Bearer sk-or-1');
    expect(sent.headers['X-Title'], 'Scontrini');
    final body = jsonDecode(sent.body) as Map<String, dynamic>;
    expect(body['provider'], {'data_collection': 'deny'});
    expect(body['model'], 'google/gemini-2.5-flash');
    expect(body['response_format']['json_schema']['strict'], isTrue);
    final schema = body['response_format']['json_schema']['schema'];
    expect(schema['properties']['items']['items']['properties']['category']['enum'], ['Alimentari', 'Altro']);
    final content = body['messages'][0]['content'] as List;
    expect(content[0]['text'], contains('SOLO tra: Alimentari, Altro'));
    expect(content[1]['image_url']['url'], 'data:image/jpeg;base64,AQID');
    expect(r.parsed['merchant'], 'Coop');
    expect(r.model, 'google/gemini-2.5-flash');
  });

  test('compatibile OpenAI: indirizzo personalizzato, niente parametri OpenRouter', () async {
    late http.Request sent;
    final ai = AiClient(client: MockClient((req) async {
      sent = req;
      return _json(_completion(jsonEncode(_receipt), model: 'vision-1-2026'));
    }));
    final r = await ai.scan(_custom, image, 'image/png', ['Altro']);
    expect(sent.url.toString(), 'https://api.example.com/v1/chat/completions');
    expect(sent.headers.containsKey('X-Title'), isFalse);
    expect((jsonDecode(sent.body) as Map).containsKey('provider'), isFalse);
    expect(r.model, 'vision-1-2026');
  });

  test('compatibile OpenAI senza json_schema: nuovo tentativo senza response_format', () async {
    final bodies = <Map<String, dynamic>>[];
    final ai = AiClient(client: MockClient((req) async {
      bodies.add(jsonDecode(req.body) as Map<String, dynamic>);
      if (bodies.length == 1) return _json({'error': {'message': 'response_format not supported'}}, 400);
      return _json(_completion('```json\n${jsonEncode(_receipt)}\n```'));
    }));
    final r = await ai.scan(_custom, image, 'image/png', ['Altro']);
    expect(bodies.length, 2);
    expect(bodies[0].containsKey('response_format'), isTrue);
    expect(bodies[1].containsKey('response_format'), isFalse);
    expect(r.parsed['total'], 3.4);
  });

  test('risposte e errori', () async {
    Future<AiErrorKind> kind(http.Response res, [AiEndpoint e = _openRouter]) async {
      try {
        await AiClient(client: MockClient((_) async => res)).scan(e, image, 'image/jpeg', ['Altro']);
      } on AiException catch (err) {
        return err.kind;
      }
      fail('nessun errore');
    }

    expect(await kind(_json({}, 401)), AiErrorKind.badKey);
    expect(await kind(_json({}, 402)), AiErrorKind.noCredit);
    expect(await kind(_json({}, 404)), AiErrorKind.badModel);
    expect(await kind(_json({}, 429)), AiErrorKind.rateLimit);
    expect(await kind(_json({}, 500)), AiErrorKind.other);
    expect(await kind(_json(_completion('non è json'))), AiErrorKind.badResponse);
    expect(await kind(http.Response('<html>', 200)), AiErrorKind.badResponse);
    expect(await kind(_json(_completion(jsonEncode({..._receipt, 'is_receipt': false})))), AiErrorKind.notReceipt);
  });

  test('errore di rete', () async {
    final ai = AiClient(client: MockClient((_) async => throw http.ClientException('offline')));
    await expectLater(ai.scan(_openRouter, image, 'image/jpeg', ['Altro']),
        throwsA(isA<AiException>().having((e) => e.kind, 'kind', AiErrorKind.network)));
  });

  test('controlli prima dell\'invio', () async {
    final ai = AiClient(client: MockClient((_) async => fail('nessuna richiesta attesa')));
    await expectLater(ai.scan(_openRouter, image, 'image/gif', ['Altro']), throwsA(isA<AiException>()));
    await expectLater(
        ai.scan(const AiEndpoint(provider: AiProvider.openAiCompatible, baseUrl: 'http://x', model: 'm', apiKey: 'k'),
            image, 'image/png', ['Altro']),
        throwsA(isA<AiException>().having((e) => e.kind, 'kind', AiErrorKind.badUrl)));
    await expectLater(
        ai.scan(const AiEndpoint(provider: AiProvider.openRouter, model: ' ', apiKey: 'k'), image, 'image/png', ['Altro']),
        throwsA(isA<AiException>().having((e) => e.kind, 'kind', AiErrorKind.badModel)));
  });

  test('verifica della chiave', () async {
    final urls = <String>[];
    final ai = AiClient(client: MockClient((req) async {
      urls.add(req.url.toString());
      return req.headers['Authorization'] == 'Bearer k' ? _json({'data': []}) : _json({}, 401);
    }));
    await ai.probe(_custom);
    await expectLater(ai.probe(_openRouter), throwsA(isA<AiException>().having((e) => e.kind, 'kind', AiErrorKind.badKey)));
    expect(urls, ['https://api.example.com/v1/models', 'https://openrouter.ai/api/v1/key']);

    final notFound = AiClient(client: MockClient((_) async => _json({}, 404)));
    await expectLater(notFound.probe(_custom), throwsA(isA<AiException>().having((e) => e.kind, 'kind', AiErrorKind.badUrl)));
  });
}
