import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'app_state.dart';
import 'config.dart';
import 'data/db.dart';
import 'data/photos.dart';
import 'data/repository.dart';
import 'scan_controller.dart';
import 'screens/categories_screen.dart';
import 'screens/movements_screen.dart';
import 'screens/pin_screen.dart';
import 'screens/receipt_screen.dart';
import 'screens/scan_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/setup_screen.dart';
import 'screens/stats_screen.dart';
import 'theme/theme.dart';
import 'widgets/budget_widgets.dart';
import 'widgets/common.dart';
import 'widgets/floating_nav_bar.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('it_IT');
  final db = await AppDatabase.open();
  final repo = Repository(db, photos: await PhotoStore.open());
  // Foto senza scontrino (salvataggio interrotto) o scontrini senza file.
  repo.cleanPhotos().catchError((Object e) => debugPrint('Pulizia delle foto non riuscita: $e'));
  final config = AppConfig(repo);
  await config.load();
  final state = AppState(config);
  await state.lock.load();
  runApp(ScontriniApp(state: state));
}

class ScontriniApp extends StatelessWidget {
  final AppState state;
  const ScontriniApp({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    return AppScope(
      state: state,
      child: MaterialApp(
        title: 'Scontrini',
        debugShowCheckedModeBanner: false,
        locale: const Locale('it', 'IT'),
        supportedLocales: const [Locale('it', 'IT')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        theme: buildTheme(Brightness.light),
        darkTheme: buildTheme(Brightness.dark),
        themeMode: ThemeMode.system,
        builder: (context, child) => LockGate(child: child!),
        home: const _Root(),
      ),
    );
  }
}

/// Primo avvio finché l'app non è configurata, poi la shell con le schede.
class _Root extends StatelessWidget {
  const _Root();

  @override
  Widget build(BuildContext context) {
    final configured = AppScope.of(context).config.isConfigured;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      child: configured ? const HomeShell(key: ValueKey('shell')) : const SetupScreen(key: ValueKey('setup')),
    );
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  late final AppState _state = AppScope.read(context);

  @override
  void initState() {
    super.initState();
    _state.reloadCategories().catchError((_) {});
    _state.scan.addListener(_onScan);
    ScanController.recoverLost().then((p) {
      if (p != null && mounted) _state.scan.start(p.$1, p.$2);
    });
  }

  @override
  void dispose() {
    _state.scan.removeListener(_onScan);
    super.dispose();
  }

  /// Risultati delle letture proseguite in sottofondo: a coda finita, un
  /// solo avviso con il riepilogo.
  void _onScan() {
    final scan = _state.scan;
    if (scan.jobs.isEmpty || scan.running || scan.screenAttached || !mounted) return;
    final done = [for (final j in scan.jobs) if (j.status == ScanStatus.done) j];
    final failed = [for (final j in scan.jobs) if (j.status == ScanStatus.error) j];
    // Le letture non riuscite si possono riprovare con le stesse foto.
    final retryParts = [for (final j in failed) j.parts];
    for (final j in [...done, ...failed]) {
      scan.clear(j);
    }
    if (done.length == 1 && failed.isEmpty) {
      final r = done.single.result!;
      budgetAlertText(_state, r).then((alert) {
        if (!mounted) return;
        showSnack(context, 'Scontrino letto: ${r.displayMerchant}${alert == null ? '' : '. $alert'}',
            actionLabel: 'Apri', onAction: () {
          Navigator.of(context).push(MaterialPageRoute(builder: (_) => ReceiptScreen(receiptId: r.id)));
        });
      });
      return;
    }
    final text = [
      if (done.isNotEmpty) done.length == 1 ? '1 scontrino letto' : '${done.length} scontrini letti',
      if (failed.isNotEmpty) failed.length == 1 ? '1 lettura non riuscita' : '${failed.length} letture non riuscite',
    ].join(', ');
    showSnack(context, text,
        actionLabel: failed.isEmpty ? null : 'Riprova',
        onAction: failed.isEmpty
            ? null
            : () {
                openScanScreen(context);
                for (final parts in retryParts) {
                  scan.enqueue(parts);
                }
              });
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final tab = state.tab;
    return PopScope(
      canPop: tab == AppTab.movements,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) state.setTab(AppTab.movements);
      },
      child: Scaffold(
        body: Stack(children: [
          Positioned.fill(
            child: IndexedStack(
              index: tab.index,
              children: const [MovementsScreen(), StatsScreen(), CategoriesScreen(), SettingsScreen()],
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: FloatingNavBar(
              current: tab,
              onSelect: state.setTab,
              onCamera: () => startScanFlow(context),
            ),
          ),
        ]),
      ),
    );
  }
}
