import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import '../widgets/brand_mark.dart';
import '../widgets/common.dart';
import '../widgets/connection_form.dart';

/// Primo avvio: collega l'app al server.
class SetupScreen extends StatelessWidget {
  const SetupScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      body: SafeArea(
        child: ContentWidth(
          child: ConnectionForm(
            buttonLabel: 'Prova e collega',
            buttonAtBottom: true,
            padding: const EdgeInsets.fromLTRB(Gap.gutter, Gap.md, Gap.gutter, Gap.xxl),
            header: Padding(
              padding: const EdgeInsets.only(bottom: 28),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const BrandMark(size: 64),
                const SizedBox(height: Gap.lg),
                Semantics(
                  header: true,
                  child: Text('Collega il tuo server', style: AppText.headlineOnboarding.copyWith(color: c.onSurface)),
                ),
                const SizedBox(height: Gap.xs),
                Text(
                  "Scontrini salva i dati sul server che scegli tu. Ti servono l'indirizzo e il token di accesso.",
                  style: AppText.body.copyWith(color: c.onSurfaceMuted),
                ),
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
