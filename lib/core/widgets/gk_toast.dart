// lib/core/widgets/gk_toast.dart
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:gatekeepeer/core/theme/app_colors.dart';
import 'package:gatekeepeer/core/theme/app_spacing.dart';

enum ToastType { success, error, warning, info }

class GkToast {
  static void show(
    BuildContext context, {
    required String message,
    String? title,
    ToastType type = ToastType.info,
    Duration duration = const Duration(seconds: 3),
  }) {
    final overlay = Overlay.of(context);
    late OverlayEntry entry;

    // Strip [prefix] from message to make it more professional
    final cleanMessage = message.replaceAll(RegExp(r'\[.*?\]\s*'), '').trim();

    entry = OverlayEntry(
      builder: (ctx) => _GkToastWidget(
        message: cleanMessage.isEmpty ? 'An error occurred' : cleanMessage,
        title: title,
        type: type,
        onDismiss: () => entry.remove(),
        duration: duration,
      ),
    );

    overlay.insert(entry);
  }
}

class _GkToastWidget extends StatefulWidget {
  final String message;
  final String? title;
  final ToastType type;
  final VoidCallback onDismiss;
  final Duration duration;

  const _GkToastWidget({
    required this.message,
    this.title,
    required this.type,
    required this.onDismiss,
    required this.duration,
  });

  @override
  State<_GkToastWidget> createState() => _GkToastWidgetState();
}

class _GkToastWidgetState extends State<_GkToastWidget> {
  (Color bg, Color fg, IconData icon) get _style => switch (widget.type) {
        ToastType.success => (
            AppColors.primary,
            AppColors.primaryFixed,
            Icons.check_circle_rounded
          ),
        ToastType.error => (
            AppColors.errorContainer,
            AppColors.onErrorContainer,
            Icons.gpp_maybe_rounded
          ),
        ToastType.warning => (
            const Color(0xFFFFF3CD),
            const Color(0xFF856404),
            Icons.warning_amber_rounded
          ),
        ToastType.info => (
            AppColors.surfaceContainerLowest,
            AppColors.onSurface,
            Icons.info_outline_rounded
          ),
      };

  @override
  void initState() {
    super.initState();
    Future.delayed(widget.duration, () {
      if (mounted) widget.onDismiss();
    });
  }

  @override
  Widget build(BuildContext context) {
    final (bg, fg, icon) = _style;
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Material(
            color: Colors.transparent,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Icon(icon, color: fg, size: 22),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (widget.title != null)
                          Text(
                            widget.title!,
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                  color: fg,
                                ),
                          ),
                        Text(
                          widget.message,
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                fontSize: 13,
                                color: fg.withValues(alpha: 0.85),
                              ),
                        ),
                      ],
                    ),
                  ),
                  GestureDetector(
                    onTap: widget.onDismiss,
                    child: Icon(Icons.close_rounded,
                        size: 18, color: fg.withValues(alpha: 0.5)),
                  ),
                ],
              ),
            ),
          ),
        ),
      )
          .animate()
          .slideY(begin: -1.0, end: 0, duration: 300.ms, curve: Curves.easeOut)
          .fadeIn(duration: 200.ms),
    );
  }
}
