import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../ai/ai_client.dart';
import '../app_state.dart';
import '../theme/tokens.dart';
import 'common.dart';

const sourceUrl = 'https://github.com/Undermix96/scontrini';

Future<void> openSource() => launchUrl(Uri.parse(sourceUrl), mode: LaunchMode.externalApplication);

/// Servizio, indirizzo, modello e chiave API con verifica: usati da Primo
/// avvio e Impostazioni.
///
/// La configurazione viene salvata solo se la verifica riesce; altrimenti
/// l'errore compare sotto il campo interessato.
class AiSettingsForm extends StatefulWidget {
  final String buttonLabel;
  final VoidCallback? onSaved;

  /// Widget tra i campi e il pulsante (es. la card sulla privacy).
  final Widget? middle;

  /// Widget sotto il pulsante (es. il link al codice sorgente).
  final Widget? footer;

  /// Widget sopra i campi (solo con [buttonAtBottom], scorre con loro).
  final Widget? header;

  /// Se vero il contenuto scorre e il pulsante resta fisso in fondo (Primo
  /// avvio): il modulo deve avere un'altezza limitata.
  final bool buttonAtBottom;

  /// Margini del contenuto con [buttonAtBottom].
  final EdgeInsets padding;

  const AiSettingsForm({
    super.key,
    required this.buttonLabel,
    this.onSaved,
    this.header,
    this.middle,
    this.footer,
    this.buttonAtBottom = false,
    this.padding = EdgeInsets.zero,
  });

  @override
  State<AiSettingsForm> createState() => _AiSettingsFormState();
}

class _AiSettingsFormState extends State<AiSettingsForm> {
  final _url = TextEditingController();
  final _model = TextEditingController();
  final _key = TextEditingController();
  AiProvider _provider = AiProvider.openRouter;
  bool _obscure = true;
  bool busy = false;
  String? _urlError;
  String? _modelError;
  String? _keyError;
  bool _init = false;

  bool get _custom => _provider == AiProvider.openAiCompatible;

  bool get canSubmit =>
      !busy &&
      _key.text.trim().isNotEmpty &&
      _model.text.trim().isNotEmpty &&
      (!_custom || _url.text.trim().isNotEmpty);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_init) {
      _init = true;
      final c = AppScope.read(context).config;
      _provider = c.provider;
      _url.text = c.baseUrl;
      _model.text = c.model;
      _key.text = c.apiKey;
    }
  }

  @override
  void dispose() {
    _url.dispose();
    _model.dispose();
    _key.dispose();
    super.dispose();
  }

  void _setProvider(AiProvider p) {
    if (p == _provider) return;
    setState(() {
      // Il modello predefinito vale solo per OpenRouter.
      if (p == AiProvider.openRouter && _model.text.trim().isEmpty) _model.text = defaultOpenRouterModel;
      if (p == AiProvider.openAiCompatible && _model.text.trim() == defaultOpenRouterModel) _model.clear();
      _provider = p;
      _urlError = _modelError = _keyError = null;
    });
  }

  Future<void> submit() async {
    if (!canSubmit) return;
    final state = AppScope.read(context);
    final endpoint = AiEndpoint(
      provider: _provider,
      baseUrl: _url.text.trim(),
      model: _model.text.trim(),
      apiKey: _key.text.trim(),
    );
    setState(() => _urlError = _modelError = _keyError = null);
    if (_custom && !endpoint.effectiveBaseUrl.startsWith('https://')) {
      setState(() => _urlError = "L'indirizzo deve iniziare con https://");
      return;
    }
    setState(() => busy = true);
    try {
      await state.ai.probe(endpoint);
      await state.config.save(endpoint);
      await state.configSaved().catchError((_) {});
      if (!mounted) return;
      widget.onSaved?.call();
    } on AiException catch (e) {
      if (!mounted) return;
      setState(() {
        switch (e.kind) {
          case AiErrorKind.badKey:
          case AiErrorKind.noCredit:
            _keyError = e.message;
          case AiErrorKind.badModel:
            _modelError = e.message;
          case AiErrorKind.network:
            if (_custom) {
              _urlError = 'Servizio non raggiungibile. Controlla indirizzo e connessione.';
            } else {
              _keyError = e.message;
            }
          default:
            if (_custom) {
              _urlError = e.message;
            } else {
              _keyError = e.message;
            }
        }
      });
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final fields = <Widget>[
      if (widget.header != null) widget.header!,
      Text('Servizio AI', style: AppText.label.copyWith(color: c.onSurface)),
      const SizedBox(height: Gap.xs),
      SegmentedButton<AiProvider>(
        segments: [
          for (final p in AiProvider.values) ButtonSegment(value: p, label: Text(p.label)),
        ],
        selected: {_provider},
        showSelectedIcon: false,
        onSelectionChanged: busy ? null : (s) => _setProvider(s.first),
      ),
      const SizedBox(height: Gap.xs),
      Text(
        _custom
            ? 'Qualsiasi servizio con API compatibile OpenAI (OpenAI, Mistral, un tuo server con https…). Il modello deve saper leggere le immagini.'
            : 'Un solo account per molti modelli. Chiede ai fornitori di non conservare né usare le foto per l\'addestramento.',
        style: AppText.bodySmall.copyWith(color: c.onSurfaceMuted),
      ),
      if (_custom) ...[
        const SizedBox(height: Gap.md),
        LabeledField(
          label: 'Indirizzo API',
          controller: _url,
          hint: 'https://api.openai.com/v1',
          icon: Icons.dns_outlined,
          keyboardType: TextInputType.url,
          autocorrect: false,
          textInputAction: TextInputAction.next,
          error: _urlError,
          onChanged: (_) => setState(() => _urlError = null),
        ),
      ],
      const SizedBox(height: Gap.md),
      LabeledField(
        label: 'Modello',
        controller: _model,
        hint: _custom ? 'es. gpt-4o-mini' : defaultOpenRouterModel,
        icon: Icons.auto_awesome_outlined,
        autocorrect: false,
        textInputAction: TextInputAction.next,
        error: _modelError,
        onChanged: (_) => setState(() => _modelError = null),
      ),
      const SizedBox(height: Gap.md),
      LabeledField(
        label: 'Chiave API',
        controller: _key,
        icon: Icons.key_outlined,
        obscure: _obscure,
        onToggleObscure: () => setState(() => _obscure = !_obscure),
        autocorrect: false,
        error: _keyError,
        helper: _custom
            ? "La crei sul sito del servizio. Resta solo su questo telefono, nell'archivio sicuro del sistema, e non finisce nei backup."
            : "La crei su openrouter.ai, alla voce Keys. Resta solo su questo telefono, nell'archivio sicuro del sistema, e non finisce nei backup.",
        onChanged: (_) => setState(() => _keyError = null),
      ),
      if (widget.middle != null) ...[const SizedBox(height: 28), widget.middle!],
    ];
    final bottom = <Widget>[
      ConnectButton(label: widget.buttonLabel, busy: busy, onPressed: canSubmit ? submit : null),
      if (widget.footer != null) ...[const SizedBox(height: Gap.sm), widget.footer!],
    ];
    if (!widget.buttonAtBottom) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [...fields, const SizedBox(height: Gap.lg), ...bottom],
      );
    }
    // Contenuto scorrevole e pulsante fisso in fondo (resta sopra la tastiera).
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Expanded(
        child: SingleChildScrollView(
          padding: widget.padding.copyWith(bottom: Gap.md),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: fields),
        ),
      ),
      Padding(
        padding: widget.padding.copyWith(top: 0),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: bottom),
      ),
    ]);
  }
}

class ConnectButton extends StatelessWidget {
  final String label;
  final bool busy;
  final VoidCallback? onPressed;
  const ConnectButton({super.key, required this.label, required this.busy, required this.onPressed});

  @override
  Widget build(BuildContext context) => FilledButton(
        onPressed: busy ? null : onPressed,
        child: busy
            ? Semantics(label: 'Verifica in corso', child: SmallSpinner(color: context.colors.onCta))
            : Text(label),
      );
}

const privacyCard = _PrivacyCard();

class _PrivacyCard extends StatelessWidget {
  const _PrivacyCard();

  @override
  Widget build(BuildContext context) => InfoCard(
        icon: Icons.verified_user_outlined,
        iconColor: context.colors.success,
        title: 'Nessun account, nessun tracker',
        text: 'I dati restano solo su questo telefono. La foto va soltanto al servizio AI che scegli tu, '
            'per la lettura, e poi viene eliminata.',
      );
}
