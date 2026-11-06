import 'package:flutter/widgets.dart';

import 'ai/ai_client.dart';
import 'config.dart';
import 'data/repository.dart';
import 'files.dart';
import 'models.dart';
import 'scan_controller.dart';
import 'widgets/month_selector.dart';

/// Schede della shell, nell'ordine della barra di navigazione.
enum AppTab { movements, stats, categories, settings }

/// Stato condiviso: configurazione, dati locali, client AI, categorie,
/// scheda attiva, filtri di Movimenti e analisi in corso.
class AppState extends ChangeNotifier {
  final AppConfig config;
  final AiClient ai;
  final FileGateway files;
  late final ScanController scan = ScanController(this);
  List<Category> categories = [];

  /// [ai] e [files] si possono sostituire nei test.
  AppState(this.config, {AiClient? ai, FileGateway? files})
      : ai = ai ?? AiClient(),
        files = files ?? const SystemFiles();

  Repository get repo => config.repo;

  // ------------------------------------------------------------- dati

  /// Incrementato quando i dati cambiano (configurazione salvata,
  /// scontrino letto, modificato o eliminato): le schermate lo osservano per
  /// ricaricare.
  int dataVersion = 0;

  void dataChanged() {
    dataVersion++;
    notifyListeners();
  }

  /// Lo stato dell'analisi è cambiato (per la riga "Lettura in corso…").
  void scanChanged() => notifyListeners();

  Category? category(int? id) {
    if (id == null) return null;
    for (final c in categories) {
      if (c.id == id) return c;
    }
    return null;
  }

  Future<void> reloadCategories() async {
    categories = await repo.categories();
    notifyListeners();
  }

  /// Configurazione salvata o backup ripristinato: ricarica tutto.
  Future<void> configSaved() async {
    try {
      await reloadCategories();
    } finally {
      dataChanged();
    }
  }

  // ------------------------------------------------------------- navigazione

  AppTab tab = AppTab.movements;

  void setTab(AppTab t) {
    if (tab == t) return;
    tab = t;
    notifyListeners();
  }

  /// Mese, categoria e ricerca mostrati in Movimenti.
  DateTime movementsMonth = monthStart(DateTime.now());
  int? movementsCategory;
  String movementsQuery = '';

  void setMovementsMonth(DateTime m) {
    movementsMonth = monthStart(m);
    notifyListeners();
  }

  void setMovementsFilter({int? categoryId, String? query}) {
    movementsCategory = categoryId;
    if (query != null) movementsQuery = query;
    notifyListeners();
  }

  /// Apre Movimenti su un mese e, se indicata, su una categoria (da Spese).
  void openMovements({required DateTime month, int? categoryId}) {
    movementsMonth = monthStart(month);
    movementsCategory = categoryId;
    movementsQuery = '';
    tab = AppTab.movements;
    notifyListeners();
  }
}

class AppScope extends InheritedNotifier<AppState> {
  const AppScope({super.key, required AppState state, required super.child}) : super(notifier: state);

  static AppState of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<AppScope>()!.notifier!;

  /// Accesso senza registrare la dipendenza (per callback e initState).
  static AppState read(BuildContext context) => context.getInheritedWidgetOfExactType<AppScope>()!.notifier!;
}
