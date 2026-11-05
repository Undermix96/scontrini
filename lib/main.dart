import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'api.dart';
import 'config.dart';
import 'models.dart';
import 'screens/movements_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/stats_screen.dart';
import 'theme/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('it_IT');
  final config = AppConfig();
  await config.load();
  runApp(ScontriniApp(state: AppState(config)));
}

/// Stato condiviso minimale: configurazione, client API e categorie.
class AppState extends ChangeNotifier {
  final AppConfig config;
  late final Api api = Api(config);
  List<Category> categories = [];

  AppState(this.config);

  Category? category(int? id) {
    for (final c in categories) {
      if (c.id == id) return c;
    }
    return null;
  }

  Future<void> reloadCategories() async {
    if (!config.isConfigured) return;
    categories = await api.categories();
    notifyListeners();
  }

  /// Incrementato a ogni salvataggio della configurazione: le schermate lo
  /// osservano per ricaricare i dati.
  int configVersion = 0;

  Future<void> configSaved() async {
    configVersion++;
    try {
      await reloadCategories();
    } finally {
      notifyListeners();
    }
  }
}

class AppScope extends InheritedNotifier<AppState> {
  const AppScope({super.key, required AppState state, required super.child}) : super(notifier: state);

  static AppState of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<AppScope>()!.notifier!;
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
        home: const HomeShell(),
      ),
    );
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  late int _index;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final state = AppScope.of(context);
    if (!_initialized) {
      _initialized = true;
      _index = state.config.isConfigured ? 0 : 2;
      state.reloadCategories().catchError((_) {});
    }
  }

  bool _initialized = false;

  @override
  Widget build(BuildContext context) {
    const pages = [MovementsScreen(), StatsScreen(), SettingsScreen()];
    return Scaffold(
      // Ricostruisce la pagina a ogni cambio tab, così i dati sono sempre aggiornati.
      body: pages[_index],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.receipt_long_outlined), selectedIcon: Icon(Icons.receipt_long), label: 'Movimenti'),
          NavigationDestination(
              icon: Icon(Icons.pie_chart_outline), selectedIcon: Icon(Icons.pie_chart), label: 'Categorie'),
          NavigationDestination(
              icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings), label: 'Impostazioni'),
        ],
      ),
    );
  }
}
