import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:intl/date_symbol_data_local.dart';
import 'package:scontrini/app_state.dart';
import 'package:scontrini/main.dart';
import 'package:scontrini/screens/receipt_screen.dart';
import 'package:scontrini/screens/scan_screen.dart';

import 'support/fake_server.dart';

/// PNG 1×1 trasparente.
final _png = Uint8List.fromList(const [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52, //
  0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, 0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
  0x89, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE,
  0x42, 0x60, 0x82,
]);

Future<void> _pumpApp(WidgetTester tester, AppState state) async {
  tester.view.physicalSize = const Size(390, 844) * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ScontriniApp(state: state));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() => initializeDateFormatting('it_IT'));

  testWidgets('Primo avvio: pulsante disabilitato finché mancano i campi', (tester) async {
    final server = FakeServer();
    await _pumpApp(tester, server.state(configured: false));
    expect(find.text('Collega il tuo server'), findsOneWidget);
    final button = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Prova e collega'));
    expect(button.onPressed, isNull);
  });

  testWidgets('Primo avvio: token rifiutato, nulla viene salvato', (tester) async {
    final server = FakeServer()..healthStatus = 401;
    final state = server.state(configured: false);
    await _pumpApp(tester, state);
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'https://example.supabase.co');
    await tester.enterText(fields.at(1), 'sbagliato');
    await tester.pump();
    await tester.tap(find.text('Prova e collega'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Il server ha rifiutato il token'), findsOneWidget);
    expect(state.config.isConfigured, isFalse);
  });

  testWidgets('Primo avvio: indirizzo senza https', (tester) async {
    final server = FakeServer();
    final state = server.state(configured: false);
    await _pumpApp(tester, state);
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'http://example.org');
    await tester.enterText(fields.at(1), 'token');
    await tester.pump();
    await tester.tap(find.text('Prova e collega'));
    await tester.pumpAndSettle();
    expect(find.textContaining("deve iniziare con https://"), findsOneWidget);
    expect(server.requests, isEmpty);
  });

  testWidgets('Movimenti: card, gruppi per giorno e badge', (tester) async {
    final server = FakeServer();
    await _pumpApp(tester, server.state());
    expect(find.textContaining('4 scontrini · 2 da controllare'), findsOneWidget);
    expect(find.text('Esselunga'), findsOneWidget);
    expect(find.text('Totale da verificare'), findsOneWidget);
    expect(find.text('Possibile doppione'), findsOneWidget);
    expect(find.textContaining('Oggi · '), findsOneWidget);
    expect(find.text('2 righe · Salute'), findsOneWidget);
  });

  testWidgets('Navigazione tra le schede', (tester) async {
    final server = FakeServer();
    final state = server.state();
    await _pumpApp(tester, state);
    await tester.tap(find.bySemanticsLabel('Spese'));
    await tester.pumpAndSettle();
    expect(state.tab, AppTab.stats);
    expect(find.text('Categoria principale'), findsOneWidget);
    expect(find.text('Senza categoria'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Categorie'));
    await tester.pumpAndSettle();
    expect(find.text('212 righe'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel(RegExp('^Casa')));
    await tester.pumpAndSettle();
    expect(find.text('Modifica categoria'), findsOneWidget);
    expect(find.textContaining('le sue 64 righe restano'), findsOneWidget);
  });

  testWidgets('Spese: tocco su una categoria apre Movimenti filtrato', (tester) async {
    final server = FakeServer();
    final state = server.state();
    await _pumpApp(tester, state);
    state.setTab(AppTab.stats);
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel(RegExp(r'^Salute,')));
    await tester.pumpAndSettle();
    expect(state.tab, AppTab.movements);
    expect(state.movementsCategory, 5);
    expect(find.text('Farmacia Comunale'), findsOneWidget);
    expect(find.text('Esselunga'), findsNothing);
  });

  testWidgets('Dettaglio: banner del totale e riga espandibile', (tester) async {
    final server = FakeServer();
    await _pumpApp(tester, server.state());
    await tester.tap(find.text('Esselunga'));
    await tester.pumpAndSettle();
    expect(find.byType(ReceiptScreen), findsOneWidget);
    expect(find.textContaining('Le righe sommano'), findsOneWidget);
    expect(find.text('Va bene così'), findsOneWidget);
    await tester.tap(find.text('Pane casereccio'));
    await tester.pumpAndSettle();
    expect(find.text('Descrizione'), findsOneWidget);
    await tester.ensureVisible(find.bySemanticsLabel('Casa').last);
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Casa').last);
    await tester.pumpAndSettle();
    final patch = server.requests.where((r) => r.method == 'PATCH').toList();
    expect(patch.single.url.path, endsWith('/items/i2'));
    expect(patch.single.body, contains('"category_id":3'));
  });

  testWidgets('Analisi: passaggi e Annulla', (tester) async {
    final server = FakeServer()..scanCompleter = Completer<http.Response>();
    final state = server.state();
    await _pumpApp(tester, state);
    state.scan.start(_png, 'image/png');
    unawaited(tester.state<NavigatorState>(find.byType(Navigator).first).push(
      MaterialPageRoute<void>(builder: (_) => const ScanScreen()),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Sto leggendo le righe…'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('Esercente e data, in corso')), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    expect(find.bySemanticsLabel(RegExp('Esercente e data, fatto')), findsOneWidget);
    await tester.tap(find.text('Annulla'));
    await tester.pumpAndSettle();
    expect(state.scan.job, isNull);
    // La risposta arriva dopo l'annullamento: lo scontrino viene eliminato.
    server.scanCompleter!.complete(http.Response('{"id":"nuovo","total":1,"items":[]}', 201));
    await tester.pumpAndSettle();
    expect(server.requests.any((r) => r.method == 'DELETE' && r.url.path.endsWith('/receipts/nuovo')), isTrue);
  });
}

