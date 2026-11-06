import 'package:flutter/material.dart';

import '../app_state.dart';
import '../lock/lock_controller.dart';
import '../screens/pin_screen.dart';
import '../theme/tokens.dart';
import 'common.dart';

/// "Subito", "Dopo 1 minuto"…
String timeoutLabel(Duration d) => switch (d.inSeconds) {
      0 => 'Subito',
      60 => 'Dopo 1 minuto',
      _ => 'Dopo ${d.inMinutes} minuti',
    };

/// Opzioni del blocco: PIN, impronta, tempo e schermo sicuro. Nel primo
/// avvio ([onboarding]) solo PIN, impronta e schermo sicuro.
class SecuritySettings extends StatefulWidget {
  final bool onboarding;
  const SecuritySettings({super.key, this.onboarding = false});

  @override
  State<SecuritySettings> createState() => _SecuritySettingsState();
}

class _SecuritySettingsState extends State<SecuritySettings> {
  late final LockController _lock = AppScope.read(context).lock;
  bool? _bioAvailable;

  @override
  void initState() {
    super.initState();
    _lock.biometrics.available().then((v) {
      if (mounted) setState(() => _bioAvailable = v);
    });
  }

  Future<void> _togglePin(bool on) async {
    if (on) {
      final pin = await createPin(context);
      if (pin == null) return;
      await _lock.setPin(pin);
      _snack('Blocco attivato.');
    } else {
      if (!await verifyPin(context)) return;
      await _lock.disable();
      _snack('Blocco disattivato.');
    }
  }

  /// Nel primo avvio basta l'interruttore (e lo snackbar coprirebbe il pulsante).
  void _snack(String text) {
    if (mounted && !widget.onboarding) showSnack(context, text);
  }

  Future<void> _changePin() async {
    if (!await verifyPin(context)) return;
    if (!mounted) return;
    final pin = await createPin(context);
    if (pin == null) return;
    await _lock.setPin(pin);
    _snack('PIN cambiato.');
  }

  Future<void> _toggleBiometric(bool on) async {
    if (on && !await _lock.suspendWhile(() => _lock.biometrics.authenticate("Conferma l'impronta"))) return;
    await _lock.setBiometric(on);
  }

  Future<void> _chooseTimeout() async {
    final c = context.colors;
    final d = await showModalBottomSheet<Duration>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          for (final t in LockController.timeouts)
            ListTile(
              minTileHeight: 56,
              contentPadding: const EdgeInsets.symmetric(horizontal: Gap.gutter),
              title: Text(timeoutLabel(t), style: AppText.titleSmall.copyWith(color: c.onSurface)),
              trailing: t == _lock.timeout ? Icon(Icons.check, color: c.primary) : null,
              onTap: () => Navigator.pop(ctx, t),
            ),
        ]),
      ),
    );
    if (d != null) await _lock.setTimeout(d);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ListenableBuilder(
      listenable: _lock,
      builder: (context, _) {
        final on = _lock.enabled;
        final bio = _bioAvailable ?? false;
        return Container(
          decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(Radii.md)),
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(children: [
            _SwitchRow(
              icon: Icons.lock_outline,
              label: 'Blocca con PIN',
              detail: on ? 'PIN di ${_lock.pinLength} cifre' : "Chiesto all'apertura dell'app",
              value: on,
              onChanged: _togglePin,
            ),
            if (on && !widget.onboarding) _TapRow(icon: Icons.password, label: 'Cambia PIN', onTap: _changePin),
            if (on)
              _SwitchRow(
                icon: Icons.fingerprint,
                label: "Sblocca con l'impronta",
                detail: _bioAvailable == null
                    ? null
                    : bio
                        ? 'Il PIN resta come riserva'
                        : 'Nessuna impronta registrata sul telefono',
                value: _lock.biometric,
                onChanged: bio || _lock.biometric ? _toggleBiometric : null,
              ),
            if (on && !widget.onboarding)
              _TapRow(
                icon: Icons.timer_outlined,
                label: 'Blocca',
                value: timeoutLabel(_lock.timeout),
                detail: "Quando esci dall'app",
                onTap: _chooseTimeout,
              ),
            if (on || !widget.onboarding)
              _SwitchRow(
                icon: Icons.visibility_off_outlined,
                label: 'Nascondi nelle app recenti',
                detail: 'Impedisce anche gli screenshot',
                value: _lock.secureScreen,
                onChanged: _lock.setSecureScreen,
              ),
          ]),
        );
      },
    );
  }
}

class _SwitchRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? detail;
  final bool value;
  final ValueChanged<bool>? onChanged;
  const _SwitchRow({required this.icon, required this.label, this.detail, required this.value, this.onChanged});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return MergeSemantics(
      child: InkWell(
        onTap: onChanged == null ? null : () => onChanged!(!value),
        child: Container(
          constraints: const BoxConstraints(minHeight: 60),
          padding: const EdgeInsets.symmetric(horizontal: Gap.md, vertical: Gap.xs),
          child: Row(children: [
            Icon(icon, size: 22, color: c.onSurfaceMuted),
            const SizedBox(width: Gap.sm),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(label, style: AppText.titleSmall.copyWith(color: c.onSurface)),
                if (detail != null) Text(detail!, style: AppText.bodySmall.copyWith(color: c.onSurfaceMuted)),
              ]),
            ),
            Switch(value: value, onChanged: onChanged),
          ]),
        ),
      ),
    );
  }
}

class _TapRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? value;
  final String? detail;
  final VoidCallback onTap;
  const _TapRow({required this.icon, required this.label, this.value, this.detail, required this.onTap});

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
                if (detail != null) Text(detail!, style: AppText.bodySmall.copyWith(color: c.onSurfaceMuted)),
              ]),
            ),
            if (value != null) Text(value!, style: AppText.bodySmall.copyWith(color: c.onSurfaceMuted)),
            const SizedBox(width: 4),
            Icon(Icons.chevron_right, color: c.onSurfaceMuted),
          ]),
        ),
      ),
    );
  }
}
