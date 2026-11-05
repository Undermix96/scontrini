import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api.dart';
import '../app_state.dart';
import '../theme/tokens.dart';
import 'common.dart';

const sourceUrl = 'https://github.com/Undermix96/scontrini';

Future<void> openSource() => launchUrl(Uri.parse(sourceUrl), mode: LaunchMode.externalApplication);

/// Campi Indirizzo e Token con verifica: usati da Primo avvio e Impostazioni.
///
/// La configurazione viene salvata solo se la verifica riesce; altrimenti
/// l'errore compare sotto il campo interessato.
class ConnectionForm extends StatefulWidget {
  final String buttonLabel;
  final VoidCallback? onConnected;

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

  const ConnectionForm({
    super.key,
    required this.buttonLabel,
    this.onConnected,
    this.header,
    this.middle,
    this.footer,
    this.buttonAtBottom = false,
    this.padding = EdgeInsets.zero,
  });

  @override
  State<ConnectionForm> createState() => _ConnectionFormState();
}

class _ConnectionFormState extends State<ConnectionForm> {
  final _url = TextEditingController();
  final _token = TextEditingController();
  bool _obscure = true;
  bool busy = false;
  String? _urlError;
  String? _tokenError;
  bool _init = false;

  bool get canSubmit => !busy && _url.text.trim().isNotEmpty && _token.text.trim().isNotEmpty;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_init) {
      _init = true;
      final c = AppScope.read(context).config;
      _url.text = c.url;
      _token.text = c.token;
    }
  }

  @override
  void dispose() {
    _url.dispose();
    _token.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    if (!canSubmit) return;
    final state = AppScope.read(context);
    final url = _url.text.trim();
    final token = _token.text.trim();
    setState(() {
      _urlError = null;
      _tokenError = null;
    });
    if (!url.startsWith('https://')) {
      setState(() => _urlError = "L'indirizzo deve iniziare con https://");
      return;
    }
    setState(() => busy = true);
    try {
      await state.api.probe(url, token);
      await state.config.save(url: url, token: token);
      await state.configSaved().catchError((_) {});
      if (!mounted) return;
      widget.onConnected?.call();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        if (e.status == 401) {
          _tokenError = 'Il server ha rifiutato il token. Controlla di averlo copiato per intero.';
        } else if (e.status == 0) {
          _urlError = 'Server non raggiungibile. Controlla l\'indirizzo e la connessione.';
        } else if (e.status == 404) {
          _urlError = 'A questo indirizzo non risponde un server Scontrini.';
        } else {
          _urlError = 'Il server ha risposto con un errore: ${e.message}';
        }
      });
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final fields = <Widget>[
      if (widget.header != null) widget.header!,
      LabeledField(
        label: 'Indirizzo del server',
        controller: _url,
        hint: 'https://xxxx.supabase.co',
        icon: Icons.dns_outlined,
        keyboardType: TextInputType.url,
        autocorrect: false,
        textInputAction: TextInputAction.next,
        error: _urlError,
        onChanged: (_) => setState(() => _urlError = null),
      ),
      const SizedBox(height: Gap.md),
      LabeledField(
        label: 'Token di accesso',
        controller: _token,
        icon: Icons.key_outlined,
        obscure: _obscure,
        onToggleObscure: () => setState(() => _obscure = !_obscure),
        autocorrect: false,
        error: _tokenError,
        helper: "Lo trovi nel file di configurazione del server. Resta solo su questo telefono, nell'archivio sicuro del sistema.",
        onChanged: (_) => setState(() => _tokenError = null),
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
        text: 'La foto serve solo per la lettura e poi viene eliminata. Restano i dati dello scontrino.',
      );
}
