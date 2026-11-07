import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// Pulsante tondo a icona da 44 (Indietro, mese precedente, cerca, chiudi…).
class RoundIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final Color? background;
  final Color? foreground;
  final double size;

  const RoundIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.background,
    this.foreground,
    this.size = Sizes.iconButton,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final enabled = onPressed != null;
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        enabled: enabled,
        label: tooltip,
        excludeSemantics: true,
        child: Material(
          color: background ?? c.surface,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onPressed,
            child: SizedBox.square(
              dimension: size,
              child: Icon(icon, size: 20, color: enabled ? (foreground ?? c.onSurface) : c.onSurfaceMuted.withValues(alpha: 0.5)),
            ),
          ),
        ),
      ),
    );
  }
}

/// Pallino del colore di una categoria.
class CategoryDot extends StatelessWidget {
  final Color color;
  final double size;
  final Color? borderColor;
  final double borderWidth;

  const CategoryDot({super.key, required this.color, this.size = 10, this.borderColor, this.borderWidth = 0});

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: borderColor == null ? null : Border.all(color: borderColor!, width: borderWidth),
        ),
      );
}

/// Campo di testo con l'etichetta sopra e l'aiuto sotto.
class LabeledField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final String? hint;
  final IconData? icon;
  final Widget? prefix;
  final String? helper;
  final String? error;
  final bool obscure;
  final VoidCallback? onToggleObscure;
  final TextInputType? keyboardType;
  final bool autocorrect;
  final ValueChanged<String>? onChanged;
  final TextInputAction? textInputAction;
  final bool autofocus;

  const LabeledField({
    super.key,
    required this.label,
    required this.controller,
    this.hint,
    this.icon,
    this.prefix,
    this.helper,
    this.error,
    this.obscure = false,
    this.onToggleObscure,
    this.keyboardType,
    this.autocorrect = true,
    this.onChanged,
    this.textInputAction,
    this.autofocus = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: AppText.label.copyWith(color: c.onSurface)),
      const SizedBox(height: Gap.xs),
      TextField(
        controller: controller,
        obscureText: obscure,
        autocorrect: autocorrect && !obscure,
        enableSuggestions: autocorrect && !obscure,
        keyboardType: keyboardType,
        textInputAction: textInputAction,
        onChanged: onChanged,
        autofocus: autofocus,
        style: AppText.body.copyWith(color: c.onSurface, height: 1.2),
        decoration: InputDecoration(
          hintText: hint,
          errorText: error,
          errorMaxLines: 3,
          prefixIcon: prefix ?? (icon == null ? null : Icon(icon, size: 20)),
          suffixIcon: onToggleObscure == null
              ? null
              : IconButton(
                  tooltip: obscure ? 'Mostra chiave' : 'Nascondi chiave',
                  icon: Icon(obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined, size: 20),
                  onPressed: onToggleObscure,
                ),
        ),
      ),
      if (helper != null) ...[
        const SizedBox(height: Gap.xs),
        Text(helper!, style: AppText.bodySmall.copyWith(color: c.onSurfaceMuted)),
      ],
    ]);
  }
}

/// Card informativa con icona in un riquadro (privacy, ecc.).
class InfoCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String text;

  const InfoCard({super.key, required this.icon, required this.iconColor, required this.title, required this.text});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.all(Gap.md),
      decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(Radii.md)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(color: c.surfaceHigh, borderRadius: BorderRadius.circular(Radii.sm)),
          child: Icon(icon, size: 22, color: iconColor),
        ),
        const SizedBox(width: Gap.sm),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: AppText.titleSmall.copyWith(color: c.onSurface)),
            const SizedBox(height: 2),
            Text(text, style: AppText.bodySmall.copyWith(color: c.onSurfaceMuted)),
          ]),
        ),
      ]),
    );
  }
}

/// Pulsante compatto a pillola (es. "Nuova" nelle intestazioni).
class CompactButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final double height;

  const CompactButton({super.key, required this.label, this.icon, this.onPressed, this.height = Sizes.touch});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Material(
      color: c.cta,
      shape: const StadiumBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPressed,
        child: Container(
          height: height,
          padding: const EdgeInsets.symmetric(horizontal: Gap.md),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (icon != null) ...[Icon(icon, size: 18, color: c.onCta), const SizedBox(width: 6)],
            Text(label, style: AppText.buttonSmall.copyWith(color: c.onCta, fontSize: 14)),
          ]),
        ),
      ),
    );
  }
}

/// Limita la larghezza del contenuto su schermi larghi.
class ContentWidth extends StatelessWidget {
  final Widget child;
  const ContentWidth({super.key, required this.child});

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: Gap.maxContent), child: child),
      );
}

/// Indicatore circolare piccolo per i pulsanti occupati.
class SmallSpinner extends StatelessWidget {
  final Color? color;
  const SmallSpinner({super.key, this.color});

  @override
  Widget build(BuildContext context) => SizedBox.square(
        dimension: 20,
        child: CircularProgressIndicator(strokeWidth: 2.2, color: color ?? context.colors.onCta),
      );
}

void showSnack(BuildContext context, String message, {String? actionLabel, VoidCallback? onAction}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(message),
      // Con un'azione Flutter lo terrebbe aperto finché non lo si chiude.
      persist: false,
      action: actionLabel == null ? null : SnackBarAction(label: actionLabel, onPressed: onAction ?? () {}),
    ));
}
