// lib/core/widgets/gk_button.dart
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:gatekeepeer/core/theme/app_colors.dart';
import 'package:gatekeepeer/core/theme/app_spacing.dart';

enum GkButtonVariant { primary, secondary, ghost, danger }

class GkButton extends StatefulWidget {
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool isLoading;
  final GkButtonVariant variant;
  final double? width;
  final EdgeInsets? padding;

  const GkButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.isLoading = false,
    this.variant = GkButtonVariant.primary,
    this.width,
    this.padding,
  });

  @override
  State<GkButton> createState() => _GkButtonState();
}

class _GkButtonState extends State<GkButton>
    with SingleTickerProviderStateMixin {
  bool _pressed = false;

  (Color bg, Color fg) get _colors => switch (widget.variant) {
        GkButtonVariant.primary => (AppColors.primary, AppColors.onPrimary),
        GkButtonVariant.secondary => (
            AppColors.secondaryContainer,
            AppColors.onSecondaryContainer
          ),
        GkButtonVariant.ghost => (Colors.transparent, AppColors.primary),
        GkButtonVariant.danger => (AppColors.error, AppColors.onError),
      };

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = _colors;
    final isPrimary = widget.variant == GkButtonVariant.primary;

    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        if (!widget.isLoading) widget.onPressed?.call();
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.95 : 1.0,
        duration: 120.ms,
        curve: Curves.easeOutCubic,
        child: AnimatedContainer(
          duration: 200.ms,
          curve: Curves.easeOutCubic,
          width: widget.width ?? double.infinity,
          padding: widget.padding ??
              const EdgeInsets.symmetric(horizontal: 32, vertical: 18),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(100),
            boxShadow: isPrimary && !_pressed
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.1),
                      blurRadius: 8,
                      spreadRadius: 0,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : [],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (widget.isLoading)
                SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: fg,
                  ),
                )
              else ...[
                if (widget.icon != null) ...[
                  Icon(widget.icon, color: fg, size: 20),
                  const SizedBox(width: AppSpacing.xs),
                ],
                Text(
                  widget.label,
                  style: GoogleFonts.manrope(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: fg,
                    letterSpacing: -0.2,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
