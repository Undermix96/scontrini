import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../theme/tokens.dart';
import '../widgets/common.dart';
import '../widgets/connection_form.dart';
import '../widgets/floating_nav_bar.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String? _version;

  @override
  void initState() {
    super.initState();
    PackageInfo.fromPlatform().then((p) {
      if (mounted) setState(() => _version = '${p.version} (${p.buildNumber})');
    }).catchError((_) {});
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
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
              section('Connessione'),
              ConnectionForm(
                buttonLabel: 'Salva e verifica',
                onConnected: () => showSnack(context, 'Connessione riuscita, impostazioni salvate.'),
              ),
              const SizedBox(height: Gap.xl),
              privacyCard,
              section('Informazioni'),
              Container(
                decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(Radii.md)),
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(children: [
                  _InfoRow(label: 'Versione', value: _version ?? '—'),
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
