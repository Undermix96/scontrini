import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:scontrini/ai/ai_client.dart';
import 'package:scontrini/app_state.dart';
import 'package:scontrini/data/backup.dart';
import 'package:scontrini/format.dart';
import 'package:scontrini/main.dart';
import 'package:scontrini/screens/export_screen.dart';
import 'package:scontrini/screens/manual_entry_screen.dart';
import 'package:scontrini/screens/pin_screen.dart';
import 'package:scontrini/screens/receipt_screen.dart';
import 'package:scontrini/screens/scan_screen.dart';

import 'support/fake_app.dart';

/// Foto di prova valida (PNG 8×8), disegnata al volo.
Future<Uint8List> _photo(WidgetTester tester) async => (await tester.runAsync(() async {
      final recorder = ui.PictureRecorder();
      Canvas(recorder).drawRect(const Rect.fromLTWH(0, 0, 8, 8), Paint()..color = const Color(0xFFF2EFE8));
      final img = await recorder.endRecording().toImage(8, 8);
      return (await img.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
    }))!;

/// Fa avanzare il tempo a piccoli passi lasciando lavorare il database,
/// senza aspettare la fine delle animazioni infinite (schermata di analisi).
Future<void> _advance(WidgetTester tester, Duration total) async {
  const step = Duration(milliseconds: 100);
  for (var t = Duration.zero; t < total; t += step) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 5)));
    await tester.pump(step);
  }
}

Future<void> _pumpApp(WidgetTester tester, AppState state) async {
  tester.view.physicalSize = const Size(390, 844) * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ScontriniApp(state: state));
  await _settle(tester);
}

/// Lascia lavorare il database (I/O reale fuori dal tempo finto) e poi
/// completa animazioni e ricostruzioni.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 3; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
    await tester.pumpAndSettle();
  }
}

Future<AppState> _state(WidgetTester tester, FakeApp app, {bool configured = true, bool seeded = true}) async =>
    (await tester.runAsync(() => app.state(configured: configured, seeded: seeded)))!;

void _push(WidgetTester tester, Widget screen) => unawaited(
    tester.state<NavigatorState>(find.byType(Navigator).first).push(MaterialPageRoute<void>(builder: (_) => screen)));

/// Digita un PIN sul tastierino dentro [scope].
/// Porta [f] a metà schermo (sopra la barra di navigazione fluttuante).
Future<void> _center(WidgetTester tester, Finder f) async {
  await tester.scrollUntilVisible(f, 300, scrollable: find.byType(Scrollable).first);
  unawaited(Scrollable.ensureVisible(tester.element(f), alignment: 0.5));
  await tester.pumpAndSettle();
}

Future<void> _typePin(WidgetTester tester, String pin, Finder scope) async {
  for (final d in pin.split('')) {
    await tester.tap(find.descendant(of: scope, matching: find.text(d)));
    await tester.pump();
  }
  await _settle(tester);
}

void main() {
  setUpAll(() => initializeDateFormatting('it_IT'));

  testWidgets('Primo avvio: modello precompilato, pulsante disabilitato senza chiave', (tester) async {
    final app = FakeApp();
    await _pumpApp(tester, await _state(tester, app, configured: false, seeded: false));
    expect(find.text('Benvenuto in Scontrini'), findsOneWidget);
    expect(find.text('Ripristina da un backup'), findsOneWidget);
    expect(find.text(defaultOpenRouterModel), findsWidgets);
    final button = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Verifica e inizia'));
    expect(button.onPressed, isNull);
  });

  testWidgets('Primo avvio: chiave rifiutata, nulla viene salvato', (tester) async {
    final app = FakeApp();
    app.ai.probeError = AiException(AiErrorKind.badKey, 'Il servizio ha rifiutato la chiave.');
    final state = await _state(tester, app, configured: false, seeded: false);
    await _pumpApp(tester, state);
    await tester.enterText(find.byType(TextField).last, 'sbagliata');
    await tester.pump();
    await tester.tap(find.text('Verifica e inizia'));
    await _settle(tester);
    expect(find.text('Il servizio ha rifiutato la chiave.'), findsOneWidget);
    expect(state.config.isConfigured, isFalse);
    expect(app.keys.values, isEmpty);
  });

  testWidgets("Primo avvio: chiave valida, si entra nell'app", (tester) async {
    final app = FakeApp();
    final state = await _state(tester, app, configured: false, seeded: false);
    await _pumpApp(tester, state);
    await tester.enterText(find.byType(TextField).last, '  sk-or-v1-abc  ');
    await tester.pump();
    await tester.tap(find.text('Verifica e inizia'));
    await _settle(tester);
    expect(app.keys.values.values, contains('sk-or-v1-abc'));
    expect(app.ai.probes.single.provider, AiProvider.openRouter);
    expect(find.text("Proteggi l'app"), findsOneWidget);
    expect(state.config.isConfigured, isFalse);
    await tester.tap(find.text('Continua senza blocco'));
    await _settle(tester);
    expect(state.config.isConfigured, isTrue);
    expect(state.lock.enabled, isFalse);
    expect(find.byType(HomeShell), findsOneWidget);
  });

  testWidgets("Primo avvio: PIN e impronta nel passo \"Proteggi l'app\"", (tester) async {
    final app = FakeApp();
    final state = await _state(tester, app, configured: false, seeded: false);
    await _pumpApp(tester, state);
    await tester.enterText(find.byType(TextField).last, 'sk-or-v1-abc');
    await tester.pump();
    await tester.tap(find.text('Verifica e inizia'));
    await _settle(tester);
    expect(find.text("Sblocca con l'impronta"), findsNothing);

    await tester.tap(find.text('Blocca con PIN'));
    await _settle(tester);
    expect(find.text('Scegli un PIN'), findsOneWidget);
    await _typePin(tester, '258', find.byType(PinEntry));
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Avanti')).onPressed, isNull,
        reason: 'almeno 4 cifre');
    await _typePin(tester, '0', find.byType(PinEntry));
    await tester.tap(find.text('Avanti'));
    await _settle(tester);
    expect(find.text('Conferma il PIN'), findsOneWidget);
    await _typePin(tester, '1111', find.byType(PinEntry));
    expect(find.text('I PIN non coincidono: ricomincia.'), findsOneWidget);
    await _typePin(tester, '2580', find.byType(PinEntry));
    await tester.tap(find.text('Avanti'));
    await _settle(tester);
    await _typePin(tester, '2580', find.byType(PinEntry));
    expect(state.lock.enabled, isTrue);
    expect(state.lock.secureScreen, isTrue);
    expect(find.text('Non dimenticare il PIN'), findsOneWidget);

    await tester.tap(find.text("Sblocca con l'impronta"));
    await _settle(tester);
    expect(app.biometrics.prompts, 1);
    expect(state.lock.biometric, isTrue);

    await tester.tap(find.text('Inizia'));
    await _settle(tester);
    expect(state.config.isConfigured, isTrue);
    expect(find.byType(HomeShell), findsOneWidget);
    expect(find.byType(LockScreen), findsNothing);
  });

  testWidgets('Blocco: PIN errato e poi giusto', (tester) async {
    final app = FakeApp();
    final state = await _state(tester, app);
    await tester.runAsync(() async {
      await state.lock.setPin('2580');
      await state.lock.load();
    });
    await _pumpApp(tester, state);
    expect(find.text('Scontrini è bloccato'), findsOneWidget);
    expect(app.biometrics.prompts, 0, reason: 'impronta non attiva');
    await _typePin(tester, '1111', find.byType(LockScreen));
    expect(find.text('PIN errato'), findsOneWidget);
    await _typePin(tester, '2580', find.byType(LockScreen));
    expect(find.byType(LockScreen), findsNothing);
    expect(find.byType(HomeShell), findsOneWidget);
  });

  testWidgets("Blocco: l'impronta viene proposta subito", (tester) async {
    final app = FakeApp();
    final state = await _state(tester, app);
    await tester.runAsync(() async {
      await state.lock.setPin('2580');
      await state.lock.setBiometric(true);
      await state.lock.load();
    });
    app.biometrics.succeed = false;
    await _pumpApp(tester, state);
    expect(app.biometrics.prompts, 1);
    expect(find.byType(LockScreen), findsOneWidget);
    app.biometrics.succeed = true;
    await tester.tap(find.byIcon(Icons.fingerprint));
    await _settle(tester);
    expect(app.biometrics.prompts, 2);
    expect(find.byType(LockScreen), findsNothing);
  });

  testWidgets('Primo avvio: endpoint compatibile senza https', (tester) async {
    final app = FakeApp();
    await _pumpApp(tester, await _state(tester, app, configured: false, seeded: false));
    await tester.tap(find.text('Altro servizio'));
    await tester.pumpAndSettle();
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'http://192.168.1.10:11434/v1');
    await tester.enterText(fields.at(1), 'llava');
    await tester.enterText(fields.at(2), 'chiave');
    await tester.pump();
    await tester.tap(find.text('Verifica e inizia'));
    await tester.pumpAndSettle();
    expect(find.textContaining('deve iniziare con https://'), findsOneWidget);
    expect(app.ai.probes, isEmpty);
  });

  testWidgets('Primo avvio: ripristino di un backup, poi la chiave', (tester) async {
    final source = FakeApp();
    final bytes = (await tester.runAsync(() async {
      await source.state();
      return Backup.create(source.repo, appVersion: 'test');
    }))!;
    final app = FakeApp();
    app.files.toOpen = bytes;
    final state = await _state(tester, app, configured: false, seeded: false);
    await _pumpApp(tester, state);
    await tester.tap(find.text('Ripristina da un backup'));
    await _settle(tester);
    expect(find.text('Backup ripristinato'), findsOneWidget);
    expect(find.textContaining('5 scontrini'), findsOneWidget);
    expect(find.text('Ripristina da un backup'), findsNothing);
    expect(find.text('Inserisci la chiave API'), findsOneWidget);
    expect(state.config.isConfigured, isFalse);
  });

  testWidgets('Inserimento manuale: due righe, totale e salvataggio', (tester) async {
    final app = FakeApp();
    final state = await _state(tester, app, seeded: false);
    await _pumpApp(tester, state);
    await tester.tap(find.bySemanticsLabel('Fotografa uno scontrino'));
    await _settle(tester);
    expect(find.text('Inserisci a mano'), findsOneWidget);
    await tester.tap(find.text('Inserisci a mano'));
    await _settle(tester);
    expect(find.text('Nuova spesa'), findsOneWidget);
    final save = find.widgetWithText(FilledButton, 'Salva');
    expect(tester.widget<FilledButton>(save).onPressed, isNull);

    await tester.enterText(find.byType(TextField).first, 'Mercato');
    // Prima riga: descrizione, quantità e prezzo unitario calcolano l'importo.
    final fields = find.descendant(of: find.byKey(const ValueKey('edit-draft-0')), matching: find.byType(TextField));
    await tester.enterText(fields.at(0), 'Mele');
    await tester.enterText(fields.at(2), '3');
    await tester.enterText(fields.at(3), '1,10');
    await tester.pump();
    expect(find.text('3,30'), findsOneWidget);
    await tester.ensureVisible(find.text('Alimentari'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Alimentari'));
    await tester.pump();

    await tester.ensureVisible(find.text('Aggiungi riga'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Aggiungi riga'));
    await tester.pumpAndSettle();
    final second = find.descendant(of: find.byKey(const ValueKey('edit-draft-1')), matching: find.byType(TextField));
    await tester.enterText(second.at(0), 'Pane');
    await tester.enterText(second.at(1), '2,20');
    await tester.pump();
    expect(find.text(money(5.5)), findsOneWidget);
    expect(tester.widget<FilledButton>(save).onPressed, isNotNull);

    await tester.tap(save);
    await _settle(tester);
    expect(find.byType(ReceiptScreen), findsOneWidget);
    expect(find.text('Inserito a mano.'), findsOneWidget);
    final saved = (await tester.runAsync(() => app.repo.allReceipts()))!.single;
    expect(saved.merchant, 'Mercato');
    expect(saved.total, 5.5);
    expect(saved.items.map((i) => (i.description, i.total, i.categoryId)), [('Mele', 3.3, 1), ('Pane', 2.2, 1)]);
    expect(saved.items.first.quantity, 3);
    expect(saved.items.first.unitPrice, 1.1);
  });

  testWidgets('Inserimento manuale: uscendo con dati chiede conferma', (tester) async {
    final app = FakeApp();
    final state = await _state(tester, app, seeded: false);
    await _pumpApp(tester, state);
    _push(tester, const ManualEntryScreen());
    await _settle(tester);
    await tester.tap(find.byTooltip('Chiudi'));
    await _settle(tester);
    expect(find.text('Nuova spesa'), findsNothing, reason: 'vuota: si chiude subito');

    _push(tester, const ManualEntryScreen());
    await _settle(tester);
    await tester.enterText(find.byType(TextField).first, 'Bar');
    await tester.pump();
    await tester.tap(find.byTooltip('Chiudi'));
    await _settle(tester);
    expect(find.text('Scartare la spesa?'), findsOneWidget);
    await tester.tap(find.text('Continua a scrivere'));
    await _settle(tester);
    expect(find.text('Nuova spesa'), findsOneWidget);
    await tester.tap(find.byTooltip('Chiudi'));
    await _settle(tester);
    await tester.tap(find.text('Scarta'));
    await _settle(tester);
    expect(find.text('Nuova spesa'), findsNothing);
    expect((await tester.runAsync(() => app.repo.allReceipts()))!, isEmpty);
  });

  testWidgets('Movimenti: card, gruppi per giorno e badge', (tester) async {
    final app = FakeApp();
    await _pumpApp(tester, await _state(tester, app));
    expect(find.textContaining('4 scontrini · 2 da controllare'), findsOneWidget);
    expect(find.text('Esselunga'), findsOneWidget);
    expect(find.text('Totale da verificare'), findsOneWidget);
    expect(find.text('Possibile doppione'), findsOneWidget);
    expect(find.textContaining('Oggi · '), findsOneWidget);
    expect(find.text('2 righe · Salute'), findsOneWidget);
  });

  testWidgets('Navigazione tra le schede', (tester) async {
    final app = FakeApp();
    final state = await _state(tester, app);
    await _pumpApp(tester, state);
    await tester.tap(find.bySemanticsLabel('Spese'));
    await _settle(tester);
    expect(state.tab, AppTab.stats);
    expect(find.text('Categoria principale'), findsOneWidget);
    expect(find.text('Senza categoria'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Categorie'));
    await _settle(tester);
    expect(find.text('5 righe'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel(RegExp('^Casa')));
    await _settle(tester);
    expect(find.text('Modifica categoria'), findsOneWidget);
    expect(find.textContaining('la sua riga resta'), findsOneWidget);
  });

  testWidgets('Spese: tocco su una categoria apre Movimenti filtrato', (tester) async {
    final app = FakeApp();
    final state = await _state(tester, app);
    await _pumpApp(tester, state);
    state.setTab(AppTab.stats);
    await _settle(tester);
    await tester.tap(find.bySemanticsLabel(RegExp(r'^Salute,')));
    await _settle(tester);
    expect(state.tab, AppTab.movements);
    expect(state.movementsCategory, 5);
    expect(find.text('Farmacia Comunale'), findsOneWidget);
    expect(find.text('Esselunga'), findsNothing);
  });

  testWidgets('Budget: impostato da Spese, visibile anche in Movimenti', (tester) async {
    final app = FakeApp();
    final state = await _state(tester, app);
    await _pumpApp(tester, state);
    state.setTab(AppTab.stats);
    await _settle(tester);
    await tester.tap(find.text('Imposta un budget mensile'));
    await _settle(tester);
    expect(find.text('Budget mensile'), findsOneWidget);
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), '100');
    await tester.enterText(fields.at(5), '10'); // Salute: 18,90 spesi
    await tester.tap(find.text('Salva'));
    await _settle(tester);

    final month = DateTime(DateTime.now().year, DateTime.now().month);
    final budget = (await tester.runAsync(() => app.repo.budgetFor(month)))!;
    expect(budget.total, 100);
    expect(budget.categories, {5: 10});
    expect(find.textContaining('Budget di'), findsOneWidget);
    // Spese confronta il budget con la somma delle righe (123,75 €), Movimenti
    // con i totali degli scontrini (125,25 €): ognuna con il totale che mostra.
    expect(find.text('Superato di ${money(23.75)}'), findsOneWidget);
    expect(find.text('Superato di ${money(8.9)} su ${money(10)}'), findsOneWidget);

    state.setTab(AppTab.movements);
    await _settle(tester);
    expect(find.text('Superato di ${money(25.25)} · budget ${money(100)}'), findsOneWidget);
  });

  testWidgets('Budget: impostato dal pannello della categoria', (tester) async {
    final app = FakeApp();
    final state = await _state(tester, app);
    await _pumpApp(tester, state);
    state.setTab(AppTab.categories);
    await _settle(tester);
    await tester.tap(find.bySemanticsLabel(RegExp('^Casa')));
    await _settle(tester);
    await tester.enterText(find.widgetWithText(TextField, 'Nessuno'), '50');
    await tester.tap(find.widgetWithText(FilledButton, 'Salva'));
    await _settle(tester);
    final month = DateTime(DateTime.now().year, DateTime.now().month);
    expect((await tester.runAsync(() => app.repo.budgetFor(month)))!.categories, {3: 50});
  });

  testWidgets('Budget: avviso dopo un inserimento che lo supera', (tester) async {
    final app = FakeApp();
    final state = await _state(tester, app, seeded: false);
    final month = DateTime(DateTime.now().year, DateTime.now().month);
    await tester.runAsync(() => app.repo.setBudget(null, month, 10));
    await _pumpApp(tester, state);
    _push(tester, const ManualEntryScreen());
    await _settle(tester);
    final row = find.descendant(of: find.byKey(const ValueKey('edit-draft-0')), matching: find.byType(TextField));
    await tester.enterText(row.at(0), 'Cena');
    await tester.enterText(row.at(1), '12');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Salva'));
    await _settle(tester);
    expect(find.text('Budget del mese superato.'), findsOneWidget);
  });

  testWidgets('Spese: esercente apre Movimenti con la ricerca', (tester) async {
    final app = FakeApp();
    final state = await _state(tester, app);
    await _pumpApp(tester, state);
    state.setTab(AppTab.stats);
    await _settle(tester);
    expect(find.text('Ultimi 12 mesi'), findsOneWidget);
    final merchant = find.bySemanticsLabel(RegExp(r'^Farmacia Comunale,'));
    await _center(tester, merchant);
    await tester.tap(merchant);
    await _settle(tester);
    expect(state.tab, AppTab.movements);
    expect(state.movementsQuery, 'Farmacia Comunale');
    expect(find.text('Esselunga'), findsNothing);
  });

  testWidgets('Spese: le barre si filtrano per categoria', (tester) async {
    final app = FakeApp();
    final state = await _state(tester, app);
    await _pumpApp(tester, state);
    state.setTab(AppTab.stats);
    await _settle(tester);
    final chip = find.bySemanticsLabel(RegExp('^Categoria del grafico'));
    await _center(tester, chip);
    await tester.tap(chip);
    await _settle(tester);
    await tester.tap(find.text('Salute').last);
    await _settle(tester);
    expect(find.bySemanticsLabel(RegExp('^Categoria del grafico: Salute')), findsOneWidget);
  });

  testWidgets('Dettaglio: banner del totale e riga espandibile', (tester) async {
    final app = FakeApp();
    await _pumpApp(tester, await _state(tester, app));
    await tester.tap(find.text('Esselunga'));
    await _settle(tester);
    expect(find.byType(ReceiptScreen), findsOneWidget);
    expect(find.textContaining('Le righe sommano'), findsOneWidget);
    expect(find.text('Va bene così'), findsOneWidget);
    await tester.tap(find.text('Pane casereccio'));
    await tester.pumpAndSettle();
    expect(find.text('Descrizione'), findsOneWidget);
    await tester.ensureVisible(find.bySemanticsLabel('Casa').last);
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Casa').last);
    await _settle(tester);
    final r = (await tester.runAsync(() => app.repo.receipt('r1')))!;
    expect(r.items.firstWhere((i) => i.description == 'Pane casereccio').categoryId, 3);
  });

  testWidgets('Analisi: passaggi e Annulla', (tester) async {
    final app = FakeApp();
    app.ai.scanCompleter = Completer<AiScan>();
    final state = await _state(tester, app);
    await _pumpApp(tester, state);
    state.scan.start(await _photo(tester), 'image/png');
    _push(tester, const ScanScreen());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Sto leggendo le righe…'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('Esercente e data, in corso')), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    expect(find.bySemanticsLabel(RegExp('Esercente e data, fatto')), findsOneWidget);
    await tester.tap(find.text('Annulla'));
    await tester.pumpAndSettle();
    expect(state.scan.job, isNull);
    // La risposta arriva dopo l'annullamento: lo scontrino non viene salvato.
    app.ai.scanCompleter!.complete(AiScan(FakeAi.sampleScan, 'm'));
    await _settle(tester);
    expect((await tester.runAsync(app.repo.allReceipts))!.length, 5);
  });

  testWidgets('Analisi completata: lo scontrino viene salvato e aperto', (tester) async {
    final app = FakeApp();
    app.ai.scanCompleter = Completer<AiScan>();
    final state = await _state(tester, app);
    await _pumpApp(tester, state);
    state.scan.start(await _photo(tester), 'image/png');
    _push(tester, const ScanScreen());
    await tester.pump();
    app.ai.scanCompleter!.complete(AiScan(FakeAi.sampleScan, 'google/gemini-2.5-flash'));
    await _advance(tester, const Duration(seconds: 2));
    await _settle(tester);
    expect(find.byType(ReceiptScreen), findsOneWidget);
    expect(find.text('Latte'), findsOneWidget);
    expect((await tester.runAsync(app.repo.allReceipts))!.length, 6);
  });

  testWidgets('Impostazioni: backup salvato senza chiave API', (tester) async {
    final app = FakeApp();
    final state = await _state(tester, app);
    await _pumpApp(tester, state);
    state.setTab(AppTab.settings);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Crea backup'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Crea backup'));
    await _settle(tester);
    expect(app.files.saved.keys.single, startsWith('scontrini-backup-'));
    final text = app.savedText(app.files.saved.keys.single);
    expect(text, contains('"format": "scontrini-backup"'));
    expect(text, isNot(contains('sk-or-test-key')));
    expect(find.textContaining('Ultimo: '), findsOneWidget);
  });

  testWidgets('Esportazione: CSV righe del mese', (tester) async {
    final app = FakeApp();
    await _pumpApp(tester, await _state(tester, app));
    _push(tester, const ExportScreen());
    await _settle(tester);
    expect(find.text('4 scontrini nel periodo.'), findsOneWidget);
    await tester.tap(find.text('Esporta e salva'));
    await _settle(tester);
    final name = app.files.saved.keys.single;
    expect(name, matches(RegExp(r'^scontrini-righe-\d{4}-\d{2}\.csv$')));
    final csv = app.savedText(name);
    expect(csv.split('\r\n').where((l) => l.isNotEmpty).length, 1 + 11);
    expect(csv, contains(';Spazzolino;Igiene;;;50,40;EUR;r1'));
  });
}
