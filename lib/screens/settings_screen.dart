import 'package:flutter/material.dart';

import '../app_state.dart';
import '../data/backup.dart';
import '../format.dart';
import '../theme/tokens.dart';
import '../version.dart';
import '../widgets/ai_settings_form.dart';
import '../widgets/common.dart';
import '../widgets/floating_nav_bar.dart';
import '../widgets/security_settings.dart';
import 'export_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _backingUp = false;

  Future<void> _backup() async {
    final s = AppScope.read(context);
    setState(() => _backingUp = true);
    try {
      final now = DateTime.now();
      final file = await Backup.createFile(s.repo, appVersion: versionLabel(), now: now);
      final saved = await s.files.save(file.fileName, file.bytes, file.mimeType);
      if (!saved) return;
      await s.config.backupDone(now);
      if (mounted) showSnack(context, 'Backup salvato.');
    } catch (e) {
      if (mounted) showSnack(context, 'Backup non riuscito: $e');
    } finally {
      if (mounted) setState(() => _backingUp = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final last = AppScope.of(context).config.lastBackupAt;
    Widget section(String t) => Padding(
          padding: const EdgeInsets.only(top: 28, bottom: Gap.sm),
          child: Semantics(header: true, child: Text(t, style: AppText.title.copyWith(color: c.onSurface))),
        );
    return SafeArea(
      bottom: false,
      child: ListView(
        padding: EdgeInsets.fromLTRB(Gap.gutter, Gap.xs, Gap.gutter, navBarSpace(context)),
        children: [
          ContentWidth(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              SizedBox(
                height: Sizes.touch,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Semantics(
                      header: true, child: Text('Impostazioni', style: AppText.headline.copyWith(color: c.onSurface))),
                ),
              ),
              section('Intelligenza artificiale'),
              AiSettingsForm(
                buttonLabel: 'Verifica e salva',
                onSaved: () => showSnack(context, 'Chiave verificata, impostazioni salvate.'),
              ),
              section('Sicurezza'),
              const SecuritySettings(),
              section('Dati'),
              Container(
                decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(Radii.md)),
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(children: [
                  const KeepPhotosSwitch(),
                  _ActionRow(
                    icon: Icons.save_alt,
                    label: 'Crea backup',
                    detail: last == null ? 'Nessun backup ancora' : 'Ultimo: ${longDate(last)}',
                    busy: _backingUp,
                    onTap: _backingUp ? null : _backup,
                  ),
                  _ActionRow(
                    icon: Icons.ios_share,
                    label: 'Esporta',
                    detail: 'CSV, JSON o PDF di un periodo',
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ExportScreen())),
                  ),
                ]),
              ),
              const SizedBox(height: Gap.xs),
              Text(
                "Il backup è un file che salvi dove vuoi (non contiene la chiave API; con le foto conservate "
                "è uno ZIP). Si può ripristinare solo al primo avvio, dopo aver reinstallato l'app.",
                style: AppText.bodySmall.copyWith(color: c.onSurfaceMuted),
              ),
              const SizedBox(height: Gap.xl),
              privacyCard,
              section('Informazioni'),
              Container(
                decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(Radii.md)),
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(children: [
                  _InfoRow(label: 'Versione', value: versionLabel()),
                  _InfoRow(label: 'Codice sorgente', value: 'GitHub', onTap: openSource, link: true),
                  const _InfoRow(label: 'Licenza', value: 'GPL-3.0'),
                ]),
              ),
            ]),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback? onTap;
  final bool link;
  const _InfoRow({required this.label, required this.value, this.onTap, this.link = false});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      link: link,
      child: InkWell(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 52),
          padding: const EdgeInsets.symmetric(horizontal: Gap.md),
          child: Row(children: [
            Expanded(child: Text(label, style: AppText.titleSmall.copyWith(color: c.onSurface))),
            Text(value, style: AppText.bodySmall.copyWith(color: link ? c.primary : c.onSurfaceMuted)),
            if (link) ...[const SizedBox(width: 4), Icon(Icons.open_in_new, size: 16, color: c.primary)],
          ]),
        ),
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String detail;
  final VoidCallback? onTap;
  final bool busy;
  const _ActionRow({required this.icon, required this.label, required this.detail, this.onTap, this.busy = false});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      button: true,
      child: InkWell(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 60),
          padding: const EdgeInsets.symmetric(horizontal: Gap.md, vertical: Gap.xs),
          child: Row(children: [
            Icon(icon, size: 22, color: c.onSurfaceMuted),
            const SizedBox(width: Gap.sm),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(label, style: AppText.titleSmall.copyWith(color: c.onSurface)),
                Text(detail, style: AppText.bodySmall.copyWith(color: c.onSurfaceMuted)),
              ]),
            ),
            busy ? SmallSpinner(color: c.onSurfaceMuted) : Icon(Icons.chevron_right, color: c.onSurfaceMuted),
          ]),
        ),
      ),
    );
  }
}
