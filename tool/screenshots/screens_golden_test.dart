// Genera le schermate dell'app in tema chiaro e scuro, con i font veri, per
// confrontarle con le tavole del design (docs/design/canvas).
//
//   flutter test tool/screenshots --update-goldens
//
// Le immagini finiscono in tool/screenshots/out/ (non versionate). Non fa
// parte di `flutter test`: il rendering dei font cambia tra sistemi.
import 'dart:async';
import 'dart:io';
import 'dart:ui' show ImageByteFormat, PictureRecorder;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:scontrini/ai/ai_client.dart';
import 'package:scontrini/app_state.dart';
import 'package:scontrini/main.dart';
import 'package:scontrini/scan/crop.dart';
import 'package:scontrini/screens/crop_screen.dart';
import 'package:scontrini/screens/export_screen.dart';
import 'package:scontrini/screens/manual_entry_screen.dart';
import 'package:scontrini/screens/pin_screen.dart';
import 'package:scontrini/screens/receipt_screen.dart';
import 'package:scontrini/screens/scan_screen.dart';

import '../../test/support/fake_app.dart';

Future<void> _loadFont(String family, List<String> paths) async {
  final loader = FontLoader(family);
  for (final p in paths) {
    loader.addFont(Future.value(ByteData.sublistView(File(p).readAsBytesSync())));
  }
  await loader.load();
}

Future<void> _loadFonts() async {
  await _loadFont('Manrope', [
    for (final w in ['Medium', 'SemiBold', 'Bold', 'ExtraBold']) 'assets/fonts/Manrope-$w.ttf',
  ]);
  final sdk = Platform.environment['FLUTTER_ROOT'] ?? File(Platform.resolvedExecutable).parent.parent.parent.parent.parent.path;
  final icons = File('$sdk/bin/cache/artifacts/material_fonts/materialicons-regular.otf');
  if (icons.existsSync()) await _loadFont('MaterialIcons', [icons.path]);
}

/// Lascia lavorare il database (I/O reale fuori dal tempo finto).
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 3; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
    await tester.pumpAndSettle();
  }
}

Future<AppState> _setup(WidgetTester tester, FakeApp app, Brightness b, {bool configured = true}) async {
  tester.view.physicalSize = const Size(390, 844) * 2;
  tester.view.devicePixelRatio = 2;
  tester.platformDispatcher.platformBrightnessTestValue = b;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
  final state = (await tester.runAsync(() => app.state(configured: configured, seeded: configured)))!;
  await tester.pumpWidget(ScontriniApp(state: state));
  await _settle(tester);
  return state;
}


/// Foto finta di uno scontrino storto su un tavolo scuro.
Future<Uint8List> _fakeReceipt(WidgetTester tester) async => (await tester.runAsync(() async {
      final recorder = PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.drawRect(const Rect.fromLTWH(0, 0, 900, 1200), Paint()..color = const Color(0xFF4A3F38));
      final path = Path()
        ..moveTo(240, 140)
        ..lineTo(690, 190)
        ..lineTo(640, 1080)
        ..lineTo(190, 1040)
        ..close();
      canvas.drawPath(path, Paint()..color = const Color(0xFFF4F1EA));
      final ink = Paint()
        ..color = const Color(0xFF2A2A2A)
        ..strokeWidth = 7;
      for (var i = 0; i < 14; i++) {
        final y = 260.0 + i * 52;
        canvas.drawLine(Offset(290 - i * 2.5, y), Offset(560 - i * 2.5, y + 6), ink);
      }
      final im = await recorder.endRecording().toImage(900, 1200);
      return (await im.toByteData(format: ImageByteFormat.png))!.buffer.asUint8List();
    }))!;

void _push(WidgetTester tester, Widget screen) => unawaited(
    tester.state<NavigatorState>(find.byType(Navigator).first).push(MaterialPageRoute<void>(builder: (_) => screen)));

Future<void> _shot(String name) =>
    expectLater(find.byType(MaterialApp), matchesGoldenFile('out/$name.png'));

void main() {
  setUpAll(() async {
    await initializeDateFormatting('it_IT');
    await _loadFonts();
  });

  // Testo ingrandito a 1,3: nessun importo tagliato (checklist del design).
  for (final tab in [AppTab.movements, AppTab.stats, AppTab.categories, AppTab.settings]) {
    testWidgets('text 1.3 ${tab.name}', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final s = await _setup(tester, FakeApp(), Brightness.dark);
      s.setTab(tab);
      await _settle(tester);
      await _shot('text13_${tab.name}');
    });
  }

  testWidgets('text 1.3 receipt', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await _setup(tester, FakeApp(), Brightness.light);
    await tester.tap(find.text('Esselunga'));
    await _settle(tester);
    await _shot('text13_receipt');
  });

  testWidgets('text 1.3 setup', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await _setup(tester, FakeApp(), Brightness.light, configured: false);
    await _shot('text13_setup');
  });

  for (final b in Brightness.values) {
    final t = b == Brightness.dark ? 'dark' : 'light';

    testWidgets('setup $t', (tester) async {
      await _setup(tester, FakeApp(), b, configured: false);
      await _shot('setup_$t');
      await tester.tap(find.text('Altro servizio'));
      await tester.pumpAndSettle();
      await _shot('setup_custom_$t');
    });

    testWidgets('protect $t', (tester) async {
      final s = await _setup(tester, FakeApp(), b, configured: false);
      await tester.runAsync(() async {
        await s.config.save(const AiEndpoint(
            provider: AiProvider.openRouter, model: defaultOpenRouterModel, apiKey: 'sk-or-test-key'));
        await s.configSaved();
      });
      await _settle(tester);
      await _shot('protect_$t');
      await tester.runAsync(() async {
        await s.lock.setPin('2580');
        await s.lock.setBiometric(true);
      });
      await _settle(tester);
      await _shot('protect_on_$t');
      await tester.tap(find.text('Blocca con PIN'));
      await _settle(tester);
      await _shot('pin_verify_$t');
    });

    testWidgets('lock $t', (tester) async {
      final app = FakeApp();
      app.biometrics.succeed = false;
      final s = await _setup(tester, app, b);
      await tester.runAsync(() async {
        await s.lock.setPin('2580');
        await s.lock.setBiometric(true);
        await s.lock.load();
      });
      await _settle(tester);
      await _shot('lock_$t');
      for (final d in '1111'.split('')) {
        await tester.tap(find.descendant(of: find.byType(LockScreen), matching: find.text(d)));
        await tester.pump();
      }
      await _settle(tester);
      await _shot('lock_wrong_$t');
    });

    testWidgets('pin create $t', (tester) async {
      await _setup(tester, FakeApp(), b);
      unawaited(createPin(tester.element(find.byType(HomeShell))));
      await _settle(tester);
      for (final d in '25'.split('')) {
        await tester.tap(find.descendant(of: find.byType(PinEntry), matching: find.text(d)));
        await tester.pump();
      }
      await _settle(tester);
      await _shot('pin_create_$t');
    });

    testWidgets('manual $t', (tester) async {
      await _setup(tester, FakeApp(), b);
      _push(tester, const ManualEntryScreen());
      await _settle(tester);
      final first = find.descendant(of: find.byKey(const ValueKey('edit-draft-0')), matching: find.byType(TextField));
      await tester.enterText(first.at(0), 'Mele Golden');
      await tester.enterText(first.at(2), '2');
      await tester.enterText(first.at(3), '1,35');
      await tester.tap(find.text('Alimentari'));
      FocusManager.instance.primaryFocus?.unfocus();
      await _settle(tester);
      await _shot('manual_$t');
    });

    testWidgets('new sheet $t', (tester) async {
      await _setup(tester, FakeApp(), b);
      await tester.tap(find.bySemanticsLabel('Fotografa uno scontrino'));
      await _settle(tester);
      await _shot('new_sheet_$t');
    });

    testWidgets('budget $t', (tester) async {
      final app = FakeApp();
      final s = await _setup(tester, app, b);
      final month = DateTime(DateTime.now().year, DateTime.now().month);
      await tester.runAsync(() async {
        await app.repo.setBudget(null, month, 150);
        await app.repo.setBudget(5, month, 15);
        await app.repo.setBudget(1, month, 40);
      });
      s.dataChanged();
      await _settle(tester);
      await _shot('budget_home_$t');
      s.setTab(AppTab.stats);
      await _settle(tester);
      await _shot('budget_stats_$t');
      await tester.tap(find.byTooltip('Modifica budget'));
      await _settle(tester);
      await _shot('budget_sheet_$t');
    });

    testWidgets('trends $t', (tester) async {
      final app = FakeApp();
      final s = await _setup(tester, app, b);
      await tester.runAsync(() => app.repo.setBudget(null, DateTime(DateTime.now().year, DateTime.now().month), 150));
      s.dataChanged();
      s.setTab(AppTab.stats);
      await _settle(tester);
      await tester.scrollUntilVisible(find.text('Ultimi 12 mesi'), 300, scrollable: find.byType(Scrollable).first);
      await _settle(tester);
      await _shot('trends_bars_$t');
      await tester.scrollUntilVisible(find.text('Dove spendi di più'), 300, scrollable: find.byType(Scrollable).first);
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -200));
      await _settle(tester);
      await _shot('trends_more_$t');
    });

    testWidgets('crop $t', (tester) async {
      await _setup(tester, FakeApp(), b);
      final src = await _fakeReceipt(tester);
      final preview = (await tester.runAsync(() => makePreview(src)))!;
      _push(tester, CropScreen(original: src, initial: preview, actionLabel: 'Analizza', moreLabel: 'Altra parte'));
      await _settle(tester);
      await _shot('crop_$t');
    });

    testWidgets('receipt photos $t', (tester) async {
      final app = FakeApp();
      final s = await _setup(tester, app, b);
      final src = await _fakeReceipt(tester);
      await tester.runAsync(() async {
        await s.config.setKeepPhotos(true);
        final out = (await cropToJpeg(src, (await makePreview(src))!.detected))!;
        await app.repo.addPhoto('r1', out);
        await app.repo.addPhoto('r1', out);
      });
      await tester.tap(find.text('Esselunga'));
      await _settle(tester);
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
      await _settle(tester);
      await _shot('receipt_photos_$t');
      await tester.tap(find.bySemanticsLabel(RegExp('^Foto 1 di 2')));
      await _settle(tester);
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
      await _settle(tester);
      await _shot('photo_viewer_$t');
    });

    testWidgets('home $t', (tester) async {
      await _setup(tester, FakeApp(), b);
      await _shot('home_$t');
    });

    testWidgets('stats $t', (tester) async {
      final s = await _setup(tester, FakeApp(), b);
      s.setTab(AppTab.stats);
      await _settle(tester);
      await _shot('stats_$t');
    });

    testWidgets('categories $t', (tester) async {
      final s = await _setup(tester, FakeApp(), b);
      s.setTab(AppTab.categories);
      await _settle(tester);
      await _shot('categories_$t');
      await tester.tap(find.bySemanticsLabel(RegExp('^Casa')));
      await _settle(tester);
      await _shot('categories_sheet_$t');
    });

    testWidgets('settings $t', (tester) async {
      final s = await _setup(tester, FakeApp(), b);
      s.setTab(AppTab.settings);
      await _settle(tester);
      await _shot('settings_$t');
      await tester.runAsync(() => s.lock.setPin('2580'));
      await tester.ensureVisible(find.text('Sicurezza'));
      await _settle(tester);
      await _shot('settings_security_$t');
      await tester.ensureVisible(find.text('Informazioni'));
      await tester.pumpAndSettle();
      await _shot('settings_data_$t');
    });

    testWidgets('export $t', (tester) async {
      await _setup(tester, FakeApp(), b);
      _push(tester, const ExportScreen());
      await _settle(tester);
      await _shot('export_$t');
    });

    testWidgets('receipt $t', (tester) async {
      await _setup(tester, FakeApp(), b);
      await tester.tap(find.text('Esselunga'));
      await _settle(tester);
      expect(find.byType(ReceiptScreen), findsOneWidget);
      await _shot('receipt_$t');
      await tester.tap(find.text('Pane casereccio'));
      await tester.pumpAndSettle();
      await _shot('receipt_edit_$t');
    });

    testWidgets('scan queue $t', (tester) async {
      final app = FakeApp();
      app.ai.scanCompleter = Completer<AiScan>();
      final s = await _setup(tester, app, b);
      final bytes = await _receiptPhoto(tester);
      s.scan.enqueue([(bytes, 'image/png'), (bytes, 'image/png'), (bytes, 'image/png')]);
      s.scan.enqueue([(bytes, 'image/png')]);
      s.scan.enqueue([(bytes, 'image/png')]);
      _push(tester, const ScanScreen());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 600));
      await _shot('scan_queue_$t');
      s.scan.cancel();
      s.scan.cancel();
      s.scan.cancel();
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('scan $t', (tester) async {
      final app = FakeApp();
      app.ai.scanCompleter = Completer<AiScan>();
      final s = await _setup(tester, app, b);
      final bytes = await _receiptPhoto(tester);
      s.scan.start(bytes, 'image/png');
      _push(tester, const ScanScreen());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 2000));
      await tester.pump(const Duration(milliseconds: 600));
      await _shot('scan_$t');
      await tester.tap(find.text('Annulla'));
      await tester.pumpAndSettle();
      app.ai.scanCompleter!.complete(AiScan(FakeAi.sampleScan, 'm'));
      await _settle(tester);
    });
  }
}

/// Immagine finta di uno scontrino, disegnata al volo.
Future<Uint8List> _receiptPhoto(WidgetTester tester) async {
  return (await tester.runAsync(() async {
    final recorder = PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawRect(const Rect.fromLTWH(0, 0, 600, 700), Paint()..color = const Color(0xFF8A8478));
    canvas.save();
    canvas.translate(300, 350);
    canvas.rotate(-0.07);
    canvas.drawRect(const Rect.fromLTWH(-150, -300, 300, 600), Paint()..color = const Color(0xFFF2EFE8));
    final ink = Paint()..color = const Color(0xFF55525E);
    for (var i = 0; i < 12; i++) {
      canvas.drawRect(Rect.fromLTWH(-120, -240 + i * 36.0, 140.0 - (i % 3) * 30, 10), ink);
      canvas.drawRect(Rect.fromLTWH(70, -240 + i * 36.0, 50, 10), ink);
    }
    canvas.restore();
    final img = await recorder.endRecording().toImage(600, 700);
    final data = await img.toByteData(format: ImageByteFormat.png);
    return data!.buffer.asUint8List();
  }))!;
}
