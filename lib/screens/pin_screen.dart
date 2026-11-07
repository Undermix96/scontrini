import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_state.dart';
import '../lock/lock_controller.dart';
import '../theme/tokens.dart';
import '../widgets/brand_mark.dart';
import '../widgets/common.dart';

const minPinLength = 4;
const maxPinLength = 8;

/// "30 secondi", "2 minuti".
String waitLabel(Duration d) {
  final s = d.inSeconds + (d.inMilliseconds % 1000 > 0 ? 1 : 0);
  if (s < 60) return s == 1 ? '1 secondo' : '$s secondi';
  final m = (s / 60).ceil();
  return m == 1 ? '1 minuto' : '$m minuti';
}

/// Conto alla rovescia: "0:28", "4:00".
String countdown(Duration d) {
  final s = d.inSeconds + (d.inMilliseconds % 1000 > 0 ? 1 : 0);
  return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
}

String? pinResultMessage(PinResult r) => switch (r) {
      PinOk() => null,
      PinWrong(wait: null) => 'PIN errato',
      PinWrong(:final wait?) => 'PIN errato. Riprova tra ${waitLabel(wait)}.',
      PinWait(:final remaining) => 'Troppi tentativi. Riprova tra ${waitLabel(remaining)}.',
    };

/// Puntini e tastierino numerico.
///
/// Con [autoLength] il PIN viene inviato appena raggiunge quella lunghezza;
/// altrimenti serve il pulsante [submitLabel] (da [minPinLength] cifre).
/// [onSubmit] restituisce un messaggio d'errore (e il campo si svuota) o null.
/// Con [waitRemaining] (troppi errori) il tastierino resta disattivato e
/// mostra un conto alla rovescia fino a quando si può riprovare.
class PinEntry extends StatefulWidget {
  final String title;
  final String? subtitle;
  final int? autoLength;
  final String submitLabel;
  final Future<String?> Function(String pin) onSubmit;
  final VoidCallback? onBiometric;
  final Duration? Function()? waitRemaining;

  const PinEntry({
    super.key,
    required this.title,
    this.subtitle,
    this.autoLength,
    this.submitLabel = 'Avanti',
    required this.onSubmit,
    this.onBiometric,
    this.waitRemaining,
  });

  @override
  State<PinEntry> createState() => _PinEntryState();
}

class _PinEntryState extends State<PinEntry> {
  String _pin = '';
  String? _error;
  bool _busy = false;
  final _focus = FocusNode();
  Duration? _wait;
  Timer? _ticker;

  int get _max => widget.autoLength ?? maxPinLength;

  @override
  void initState() {
    super.initState();
    _syncWait();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _focus.dispose();
    super.dispose();
  }

  /// Aggiorna l'attesa dopo troppi errori, una volta al secondo finché dura.
  void _syncWait() {
    final w = widget.waitRemaining?.call();
    if (w != null) {
      _ticker ??= Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(_syncWait);
      });
    } else {
      _ticker?.cancel();
      _ticker = null;
      // Finita l'attesa, il vecchio messaggio non serve più.
      if (_wait != null) _error = null;
    }
    _wait = w;
  }

  void _digit(String d) {
    if (_busy || _wait != null || _pin.length >= _max) return;
    HapticFeedback.selectionClick();
    setState(() {
      _pin += d;
      _error = null;
    });
    if (widget.autoLength != null && _pin.length == widget.autoLength) _submit();
  }

  void _delete() {
    if (_busy || _pin.isEmpty) return;
    setState(() => _pin = _pin.substring(0, _pin.length - 1));
  }

  Future<void> _submit() async {
    if (_busy || _wait != null || _pin.length < minPinLength) return;
    setState(() => _busy = true);
    final error = await widget.onSubmit(_pin);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (error != null) {
        _error = error;
        _pin = '';
      }
      _syncWait();
    });
    if (error != null) HapticFeedback.heavyImpact();
  }

  KeyEventResult _key(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    final ch = e.character;
    if (ch != null && RegExp(r'^[0-9]$').hasMatch(ch)) {
      _digit(ch);
      return KeyEventResult.handled;
    }
    if (e.logicalKey == LogicalKeyboardKey.backspace) {
      _delete();
      return KeyEventResult.handled;
    }
    if (e.logicalKey == LogicalKeyboardKey.enter && widget.autoLength == null) {
      _submit();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final dots = widget.autoLength ?? (_pin.length < minPinLength ? minPinLength : _pin.length);
    final wait = _wait;
    // Durante l'attesa le cifre sono attenuate (l'impronta resta usabile).
    final digitColor = wait == null ? c.onSurface : c.onSurfaceMuted.withValues(alpha: 0.5);
    Widget key(String d) => _PadKey(
          onTap: () => _digit(d),
          semantics: d,
          child: Text(d, style: AppText.headline.copyWith(color: digitColor)),
        );
    final bio = widget.onBiometric;
    final message = wait != null ? 'Troppi tentativi. Riprova tra ${countdown(wait)}' : _error ?? '';
    return Focus(
      focusNode: _focus,
      autofocus: true,
      onKeyEvent: _key,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Semantics(
          header: true,
          child: Text(widget.title, textAlign: TextAlign.center, style: AppText.title.copyWith(color: c.onSurface)),
        ),
        if (widget.subtitle != null) ...[
          const SizedBox(height: Gap.xxs),
          Text(widget.subtitle!,
              textAlign: TextAlign.center, style: AppText.bodySmall.copyWith(color: c.onSurfaceMuted)),
        ],
        const SizedBox(height: Gap.lg),
        Semantics(
          label: 'Cifre inserite: ${_pin.length}',
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            for (var i = 0; i < dots; i++)
              Container(
                width: 14,
                height: 14,
                margin: const EdgeInsets.symmetric(horizontal: 7),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: i < _pin.length ? c.onSurface : Colors.transparent,
                  border: Border.all(color: i < _pin.length ? c.onSurface : c.outlineStrong, width: 2),
                ),
              ),
          ]),
        ),
        SizedBox(
          height: 44,
          child: Center(
            child: _busy
                ? SmallSpinner(color: c.onSurfaceMuted)
                : Text(message,
                    textAlign: TextAlign.center,
                    style:
                        AppText.bodySmall.copyWith(color: c.error, fontFeatures: const [FontFeature.tabularFigures()])),
          ),
        ),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 300),
          child: Column(children: [
            for (final row in const [
              ['1', '2', '3'],
              ['4', '5', '6'],
              ['7', '8', '9'],
            ])
              Row(children: [for (final d in row) Expanded(child: key(d))]),
            Row(children: [
              Expanded(
                child: bio == null
                    ? const SizedBox(height: 72)
                    : _PadKey(
                        onTap: bio,
                        semantics: 'Usa l\'impronta',
                        child: Icon(Icons.fingerprint, size: 30, color: c.primary),
                      ),
              ),
              Expanded(child: key('0')),
              Expanded(
                child: _PadKey(
                  onTap: _delete,
                  semantics: 'Cancella',
                  child: Icon(Icons.backspace_outlined, color: c.onSurfaceMuted),
                ),
              ),
            ]),
          ]),
        ),
        if (widget.autoLength == null) ...[
          const SizedBox(height: Gap.md),
          FilledButton(
            onPressed: _pin.length >= minPinLength && !_busy && wait == null ? _submit : null,
            child: Text(widget.submitLabel),
          ),
        ],
      ]),
    );
  }
}

class _PadKey extends StatelessWidget {
  final VoidCallback onTap;
  final String semantics;
  final Widget child;
  const _PadKey({required this.onTap, required this.semantics, required this.child});

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: semantics,
        excludeSemantics: true,
        child: SizedBox(
          height: 72,
          child: InkWell(
            onTap: onTap,
            customBorder: const CircleBorder(),
            child: Center(child: child),
          ),
        ),
      );
}

/// Copre l'app quando è bloccata e segue il ciclo di vita per bloccarla dopo
/// il tempo scelto. Sta sopra al Navigator (MaterialApp.builder), così copre
/// anche le schermate aperte.
class LockGate extends StatefulWidget {
  final Widget child;
  const LockGate({super.key, required this.child});

  @override
  State<LockGate> createState() => _LockGateState();
}

class _LockGateState extends State<LockGate> with WidgetsBindingObserver {
  late final LockController _lock = AppScope.read(context).lock;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    switch (s) {
      case AppLifecycleState.paused || AppLifecycleState.hidden:
        _lock.paused();
      case AppLifecycleState.resumed:
        _lock.resumed();
      default:
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: _lock,
        builder: (context, _) {
          final locked = _lock.locked;
          return Stack(children: [
            Positioned.fill(
              child: ExcludeSemantics(
                excluding: locked,
                child: TickerMode(enabled: !locked, child: widget.child),
              ),
            ),
            if (locked) const Positioned.fill(child: LockScreen()),
          ]);
        },
      );
}

/// Schermata di sblocco.
class LockScreen extends StatefulWidget {
  const LockScreen({super.key});

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> with WidgetsBindingObserver {
  late final LockController _lock = AppScope.read(context).lock;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _biometric());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// L'app è andata davvero in background (non basta la finestra
  /// dell'impronta, che la rende solo inattiva).
  bool _wentAway = false;

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    switch (s) {
      case AppLifecycleState.paused || AppLifecycleState.hidden:
        _wentAway = true;
      // Tornando nell'app ancora bloccata si ripropone l'impronta, ma non
      // dopo "Usa il PIN": la finestra si chiude e resta il tastierino.
      case AppLifecycleState.resumed when _wentAway:
        _wentAway = false;
        if (_lock.locked && !_prompting) _biometric();
      default:
    }
  }

  bool _prompting = false;

  Future<void> _biometric() async {
    if (!_lock.biometric || _prompting || !mounted) return;
    _prompting = true;
    try {
      await _lock.unlockWithBiometric();
    } finally {
      _prompting = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Material(
      color: c.background,
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(Gap.gutter),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const BrandMark(size: 56),
              const SizedBox(height: Gap.lg),
              PinEntry(
                title: 'Scontrini è bloccato',
                subtitle: _lock.biometric ? 'Usa l\'impronta o inserisci il PIN' : 'Inserisci il PIN',
                autoLength: _lock.pinLength,
                onSubmit: (pin) async => pinResultMessage(await _lock.unlockWithPin(pin)),
                onBiometric: _lock.biometric ? _biometric : null,
                waitRemaining: () => _lock.remainingWait,
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Pagina a schermo intero con un [PinEntry].
class _PinPage extends StatelessWidget {
  final Widget child;
  const _PinPage({required this.child});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(leading: const CloseButton()),
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(Gap.gutter, 0, Gap.gutter, Gap.xl),
              child: child,
            ),
          ),
        ),
      );
}

/// Chiede un nuovo PIN due volte. Restituisce il PIN o null se annullato.
Future<String?> createPin(BuildContext context) =>
    Navigator.of(context).push<String>(MaterialPageRoute(fullscreenDialog: true, builder: (_) => const _CreatePin()));

class _CreatePin extends StatefulWidget {
  const _CreatePin();

  @override
  State<_CreatePin> createState() => _CreatePinState();
}

class _CreatePinState extends State<_CreatePin> {
  String? _first;
  String? _mismatch;

  @override
  Widget build(BuildContext context) {
    final first = _first;
    return _PinPage(
      child: first == null
          ? PinEntry(
              key: const ValueKey('first'),
              title: 'Scegli un PIN',
              subtitle: _mismatch ?? 'Da $minPinLength a $maxPinLength cifre',
              onSubmit: (pin) async {
                setState(() {
                  _first = pin;
                  _mismatch = null;
                });
                return null;
              },
            )
          : PinEntry(
              key: const ValueKey('confirm'),
              title: 'Conferma il PIN',
              subtitle: 'Inseriscilo di nuovo',
              autoLength: first.length,
              onSubmit: (pin) async {
                if (pin == first) {
                  Navigator.pop(context, pin);
                } else {
                  setState(() {
                    _first = null;
                    _mismatch = 'I PIN non coincidono: ricomincia.';
                  });
                }
                return null;
              },
            ),
    );
  }
}

/// Chiede il PIN attuale. Vero se è corretto.
Future<bool> verifyPin(BuildContext context, {String title = 'Inserisci il PIN attuale'}) async {
  final lock = AppScope.read(context).lock;
  if (!lock.enabled) return true;
  final ok = await Navigator.of(context).push<bool>(MaterialPageRoute(
    fullscreenDialog: true,
    builder: (ctx) => _PinPage(
      child: PinEntry(
        title: title,
        autoLength: lock.pinLength,
        waitRemaining: () => lock.remainingWait,
        onSubmit: (pin) async {
          final r = await lock.checkPin(pin);
          if (r is PinOk && ctx.mounted) Navigator.pop(ctx, true);
          return pinResultMessage(r);
        },
      ),
    ),
  ));
  return ok ?? false;
}
