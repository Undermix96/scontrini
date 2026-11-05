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
import 'package:http/http.dart' as http;
import 'package:intl/date_symbol_data_local.dart';
import 'package:scontrini/app_state.dart';
import 'package:scontrini/main.dart';
import 'package:scontrini/screens/receipt_screen.dart';
import 'package:scontrini/screens/scan_screen.dart';

import '../../test/support/fake_server.dart';

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

Future<AppState> _setup(WidgetTester tester, FakeServer server, Brightness b, {bool configured = true}) async {
  tester.view.physicalSize = const Size(390, 844) * 2;
  tester.view.devicePixelRatio = 2;
  tester.platformDispatcher.platformBrightnessTestValue = b;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
  final state = server.state(configured: configured);
  await tester.pumpWidget(ScontriniApp(state: state));
  await tester.pumpAndSettle();
  return state;
}

Future<void> _shot(String name) =>
    expectLater(find.byType(MaterialApp), matchesGoldenFile('out/$name.png'));

void main() {
  setUpAll(() async {
    await initializeDateFormatting('it_IT');
    await _loadFonts();
  });

  for (final b in Brightness.values) {
    final t = b == Brightness.dark ? 'dark' : 'light';

    testWidgets('setup $t', (tester) async {
      await _setup(tester, FakeServer(), b, configured: false);
      await _shot('setup_$t');
    });

    testWidgets('home $t', (tester) async {
      await _setup(tester, FakeServer(), b);
      await _shot('home_$t');
    });

    testWidgets('stats $t', (tester) async {
      final s = await _setup(tester, FakeServer(), b);
      s.setTab(AppTab.stats);
      await tester.pumpAndSettle();
      await _shot('stats_$t');
    });

    testWidgets('categories $t', (tester) async {
      final s = await _setup(tester, FakeServer(), b);
      s.setTab(AppTab.categories);
      await tester.pumpAndSettle();
      await _shot('categories_$t');
      await tester.tap(find.bySemanticsLabel(RegExp('^Casa')));
      await tester.pumpAndSettle();
      await _shot('categories_sheet_$t');
    });

    testWidgets('settings $t', (tester) async {
      final s = await _setup(tester, FakeServer(), b);
      s.setTab(AppTab.settings);
      await tester.pumpAndSettle();
      await _shot('settings_$t');
    });

    testWidgets('receipt $t', (tester) async {
      await _setup(tester, FakeServer(), b);
      await tester.tap(find.text('Esselunga'));
      await tester.pumpAndSettle();
      expect(find.byType(ReceiptScreen), findsOneWidget);
      await _shot('receipt_$t');
      await tester.tap(find.text('Pane casereccio'));
      await tester.pumpAndSettle();
      await _shot('receipt_edit_$t');
    });

    testWidgets('scan $t', (tester) async {
      final server = FakeServer()..scanCompleter = Completer<http.Response>();
      final s = await _setup(tester, server, b);
      final bytes = await _receiptPhoto(tester);
      s.scan.start(bytes, 'image/png');
      unawaited(tester.state<NavigatorState>(find.byType(Navigator).first)
          .push(MaterialPageRoute<void>(builder: (_) => const ScanScreen())));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 2000));
      await tester.pump(const Duration(milliseconds: 600));
      await _shot('scan_$t');
      await tester.tap(find.text('Annulla'));
      await tester.pumpAndSettle();
      server.scanCompleter!.complete(http.Response('{"id":"x","total":0,"items":[]}', 201));
      await tester.pumpAndSettle();
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
