// lib/core/widgets/gk_virtual_card.dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_colors.dart';
import '../../features/cards/models/virtual_card_model.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../features/accounts/providers/account_provider.dart';

import 'package:local_auth/local_auth.dart';

class GkVirtualCard extends ConsumerStatefulWidget {
  final VirtualCardModel card;
  final bool showDetails;
  final VoidCallback? onTap;
  final VoidCallback? onMoreTap;

  const GkVirtualCard({
    super.key,
    required this.card,
    this.showDetails = false,
    this.onTap,
    this.onMoreTap,
  });

  @override
  ConsumerState<GkVirtualCard> createState() => _GkVirtualCardState();
}

class _GkVirtualCardState extends ConsumerState<GkVirtualCard> {
  bool _isRevealed = false;
  final _localAuth = LocalAuthentication();

  Color get _cardGradientStart {
    if (widget.card.color != null) {
      try {
        return Color(int.parse(widget.card.color!.replaceFirst('#', '0xFF')));
      } catch (_) {}
    }
    return switch (widget.card.type) {
      'trial' => const Color(0xFF003629),
      'subscription' => const Color(0xFF1a1a2e),
      _ => const Color(0xFF1B4D3E),
    };
  }

  Future<void> _toggleReveal() async {
    if (_isRevealed) {
      setState(() => _isRevealed = false);
      return;
    }
    try {
      final canAuth = await _localAuth.canCheckBiometrics || await _localAuth.isDeviceSupported();
      if (!canAuth) {
        setState(() => _isRevealed = true);
        return;
      }
      final authenticated = await _localAuth.authenticate(
        localizedReason: 'Authenticate to reveal card details',
        options: const AuthenticationOptions(stickyAuth: true, biometricOnly: false),
      );
      if (authenticated) {
        setState(() => _isRevealed = true);
      }
    } catch (_) {
      // Allow fallback if error occurs
    }
  }

  String get _displayNumber {
    if (!_isRevealed) return '•••• •••• •••• ${widget.card.last4 ?? '****'}';
    return widget.card.maskedNumber ?? '4123 4567 8901 ${widget.card.last4 ?? '1234'}';
  }

  String get _displayCvv {
    if (!_isRevealed) return '•••';
    return widget.card.cvv ?? '123';
  }

  @override
  Widget build(BuildContext context) {
    // Look up the account by ID to show to the user
    final accounts = ref.watch(accountsStreamProvider).valueOrNull ?? [];
    final account = accounts.where((a) => a.id == widget.card.accountId).firstOrNull;
    final accountName = account?.name.toUpperCase() ?? 'GATEKIPA CARD';

    return GestureDetector(
      onTap: widget.onTap,
      child: Container(
        width: 300,
        height: 180,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              _cardGradientStart,
              _cardGradientStart.withValues(alpha: 0.7)
            ],
          ),
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(
              color: _cardGradientStart.withValues(alpha: 0.35),
              blurRadius: 24,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Stack(
          children: [
            // Grid pattern
            Positioned.fill(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(28),
                child: CustomPaint(painter: _GridPatternPainter()),
              ),
            ),
            // Card content
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              accountName,
                              style: GoogleFonts.inter(
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                                color: Colors.white.withValues(alpha: 0.6),
                                letterSpacing: 2,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              widget.card.displayName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.manrope(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Row(
                        children: [
                          _StatusChip(status: widget.card.status),
                          const SizedBox(width: 8),
                          GestureDetector(
                            onTap: _toggleReveal,
                            child: Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(
                                _isRevealed ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                                color: Colors.white,
                                size: 16,
                              ),
                            ),
                          ),
                          if (widget.onMoreTap != null) ...[
                            const SizedBox(width: 8),
                            GestureDetector(
                              onTap: widget.onMoreTap,
                              child: Container(
                                width: 32,
                                height: 32,
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Icon(
                                  Icons.more_vert_rounded,
                                  color: Colors.white,
                                  size: 16,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _displayNumber,
                        style: GoogleFonts.inter(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                          letterSpacing: 3,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'CVV',
                                style: GoogleFonts.inter(
                                  fontSize: 8,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white.withValues(alpha: 0.5),
                                  letterSpacing: 1.5,
                                ),
                              ),
                              Text(
                                _displayCvv,
                                style: GoogleFonts.manrope(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                          if (widget.card.rule.expiryDate != null)
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  'EXPIRES',
                                  style: GoogleFonts.inter(
                                    fontSize: 8,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white.withValues(alpha: 0.5),
                                    letterSpacing: 1.5,
                                  ),
                                ),
                                Text(
                                  '${widget.card.rule.expiryDate!.month.toString().padLeft(2, '0')} / ${widget.card.rule.expiryDate!.year.toString().substring(2)}',
                                  style: GoogleFonts.manrope(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                  ),
                                ),
                              ],
                            ),
                          const Icon(
                            Icons.contactless_rounded,
                            color: Colors.white60,
                            size: 28,
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String status;
  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    final (bg, fg, label) = switch (status) {
      'active' => (
          AppColors.primaryFixed.withValues(alpha: 0.2),
          AppColors.primaryFixed,
          'Active'
        ),
      'blocked' => (
          AppColors.errorContainer.withValues(alpha: 0.3),
          AppColors.errorContainer,
          'Blocked'
        ),
      _ => (Colors.white12, Colors.white60, 'Expired'),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(100),
        border: Border.all(color: fg.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (status == 'active')
            Container(
              width: 6,
              height: 6,
              margin: const EdgeInsets.only(right: 5),
              decoration: BoxDecoration(color: fg, shape: BoxShape.circle),
            ),
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: fg,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _GridPatternPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.06)
      ..strokeWidth = 1;
    const step = 32.0;
    for (double x = 0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(_) => false;
}
