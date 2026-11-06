import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'app_state.dart';
import 'config.dart';
import 'data/db.dart';
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
  final config = AppConfig(Repository(db));
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
      if (p != null && mounted && !_state.scan.running) _state.scan.start(p.$1, p.$2);
    });
  }

  @override
  void dispose() {
    _state.scan.removeListener(_onScan);
    super.dispose();
  }

  /// Risultato di un'analisi proseguita in sottofondo.
  void _onScan() {
    final scan = _state.scan;
    final job = scan.job;
    if (job == null || scan.screenAttached || !mounted) return;
    if (job.status == ScanStatus.done) {
      final r = job.result!;
      scan.clear();
      budgetAlertText(_state, r).then((alert) {
        if (!mounted) return;
        showSnack(context, 'Scontrino letto: ${r.displayMerchant}${alert == null ? '' : '. $alert'}',
            actionLabel: 'Apri', onAction: () {
          Navigator.of(context).push(MaterialPageRoute(builder: (_) => ReceiptScreen(receiptId: r.id)));
        });
      });
    } else if (job.status == ScanStatus.error) {
      showSnack(context, 'Lettura non riuscita', actionLabel: 'Riprova', onAction: () {
        scan.retry();
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ScanScreen()));
      });
    }
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
