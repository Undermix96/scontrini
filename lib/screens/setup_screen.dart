import 'package:flutter/material.dart';

import '../app_state.dart';
import '../data/backup.dart';
import '../format.dart';
import '../theme/tokens.dart';
import '../widgets/ai_settings_form.dart';
import '../widgets/brand_mark.dart';
import '../widgets/common.dart';

/// Primo avvio: scegli il servizio AI e inserisci la chiave, oppure
/// ripristina un backup. Il ripristino è possibile solo qui, finché l'app
/// non è mai stata configurata e non contiene scontrini.
class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key});

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  bool _canRestore = false;
  bool _restoring = false;
  RestoreSummary? _restored;
  int _formVersion = 0;

  @override
  void initState() {
    super.initState();
    _checkRestore();
  }

  Future<void> _checkRestore() async {
    final s = AppScope.read(context);
    final can = !s.config.setupDone && !await s.repo.hasReceipts();
    if (mounted) setState(() => _canRestore = can);
  }

  Future<void> _restore() async {
    final s = AppScope.read(context);
    setState(() => _restoring = true);
    try {
      final bytes = await s.files.open();
      if (bytes == null) return;
      final summary = await Backup.restore(s.repo, bytes);
      await s.config.reloadSettings();
      await s.configSaved().catchError((_) {});
      if (!mounted) return;
      setState(() {
        _restored = summary;
        _canRestore = false;
        _formVersion++;
      });
    } catch (e) {
      if (mounted) {
        showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Ripristino non riuscito'),
            content: Text('$e'),
            actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _restoring = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final s = AppScope.of(context);
    final restored = _restored;
    final returning = s.config.setupDone || restored != null;
    return Scaffold(
      body: SafeArea(
        child: ContentWidth(
          child: AiSettingsForm(
            key: ValueKey(_formVersion),
            buttonLabel: 'Verifica e inizia',
            buttonAtBottom: true,
            padding: const EdgeInsets.fromLTRB(Gap.gutter, Gap.md, Gap.gutter, Gap.xxl),
            header: Padding(
              padding: const EdgeInsets.only(bottom: 28),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                const Align(alignment: Alignment.centerLeft, child: BrandMark(size: 64)),
                const SizedBox(height: Gap.lg),
                Semantics(
                  header: true,
                  child: Text(returning ? 'Inserisci la chiave API' : 'Benvenuto in Scontrini',
                      style: AppText.headlineOnboarding.copyWith(color: c.onSurface)),
                ),
                const SizedBox(height: Gap.xs),
                Text(
                  returning
                      ? 'Per leggere gli scontrini serve la chiave del servizio AI: non viene mai salvata nei backup.'
                      : "Gli scontrini restano su questo telefono. Per leggerli l'app usa un servizio AI con la tua chiave.",
                  style: AppText.body.copyWith(color: c.onSurfaceMuted),
                ),
                if (restored != null) ...[
                  const SizedBox(height: Gap.md),
                  InfoCard(
                    icon: Icons.restore,
                    iconColor: c.success,
                    title: 'Backup ripristinato',
                    text: '${restored.receipts == 1 ? '1 scontrino' : '${restored.receipts} scontrini'}'
                        '${restored.createdAt == null ? '' : ', backup del ${longDate(restored.createdAt)}'}.',
                  ),
                ],
                if (_canRestore) ...[
                  const SizedBox(height: Gap.md),
                  OutlinedButton.icon(
                    onPressed: _restoring ? null : _restore,
                    icon: _restoring ? SmallSpinner(color: c.onSurface) : const Icon(Icons.restore),
                    label: const Text('Ripristina da un backup'),
                  ),
                  const SizedBox(height: Gap.xs),
                  Text(
                    "Il ripristino è possibile solo ora, al primo avvio.",
                    style: AppText.bodySmall.copyWith(color: c.onSurfaceMuted),
                  ),
                ],
              ]),
            ),
            middle: privacyCard,
            footer: const SourceLink(),
          ),
        ),
      ),
    );
  }
}

/// "Software libero · codice sorgente"
class SourceLink extends StatelessWidget {
  const SourceLink({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Wrap(alignment: WrapAlignment.center, crossAxisAlignment: WrapCrossAlignment.center, children: [
      Text('Software libero · ', style: AppText.bodySmall.copyWith(color: c.onSurfaceMuted)),
      Semantics(
        link: true,
        child: InkWell(
          onTap: openSource,
          borderRadius: BorderRadius.circular(Radii.sm),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: Sizes.touch),
            child: Center(
              widthFactor: 1,
              child: Text('codice sorgente',
                  style: AppText.label.copyWith(
                      color: c.primary, decoration: TextDecoration.underline, decorationColor: c.primary)),
            ),
          ),
        ),
      ),
    ]);
  }
}
