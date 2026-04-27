// lib/core/widgets/gk_virtual_card.dart
import 'package:flutter/material.dart';
import 'package:gatekipa/core/theme/app_colors.dart';
import 'package:gatekipa/features/cards/models/virtual_card_model.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gatekipa/features/accounts/providers/account_provider.dart';
import 'package:gatekipa/features/cards/providers/card_provider.dart';

import 'package:local_auth/local_auth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:gatekipa/core/theme/app_spacing.dart';
import 'package:gatekipa/core/widgets/gk_toast.dart';
import 'package:firebase_auth/firebase_auth.dart';

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
  bool _isLoadingDetails = false;
  
  String? _liveCardNumber;
  String? _liveCvv;
  String? _liveExpiryMonth;
  String? _liveExpiryYear;

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

  Future<bool> _verifyTransactionPin() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;

    const storage = FlutterSecureStorage();
    final secureKey = '${user.uid}_transaction_pin';
    final savedPin = await storage.read(key: secureKey);

    if (savedPin == null) {
      if (mounted) {
        GkToast.show(context, message: 'Please set up your Transaction PIN in Profile -> Settings first.', type: ToastType.error);
      }
      return false;
    }

    String enteredPin = '';
    if (!mounted) return false;
    final bool? success = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: AppColors.surface,
          title: Text(
            'Enter Card PIN',
            style: Theme.of(ctx).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Please enter your 4-digit transaction PIN to reveal card details.',
                style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(color: AppColors.onSurfaceVariant),
              ),
              const SizedBox(height: 16),
              TextFormField(
                autofocus: true,
                keyboardType: TextInputType.number,
                maxLength: 4,
                obscureText: true,
                onChanged: (val) => enteredPin = val,
                decoration: InputDecoration(
                  hintText: '****',
                  counterText: '',
                  filled: true,
                  fillColor: AppColors.surfaceContainerLowest,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
                style: const TextStyle(letterSpacing: 8, fontSize: 24, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel', style: TextStyle(color: AppColors.outline)),
            ),
            FilledButton(
              onPressed: () {
                if (enteredPin == savedPin) {
                  Navigator.pop(ctx, true);
                } else {
                  GkToast.show(ctx, message: 'Incorrect PIN', type: ToastType.error);
                  Navigator.pop(ctx, false);
                }
              },
              style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
              child: const Text('Verify'),
            ),
          ],
        );
      },
    );

    return success ?? false;
  }

  Future<void> _toggleReveal() async {
    if (_isRevealed) {
      setState(() => _isRevealed = false);
      return;
    }
    try {
      bool authenticated = false;
      final canCheck = await _localAuth.canCheckBiometrics;
      if (canCheck) {
        authenticated = await _localAuth.authenticate(
          localizedReason: 'Authenticate to reveal card details',
          options: const AuthenticationOptions(stickyAuth: true, biometricOnly: true),
        );
      }
      
      // Fallback to Transaction PIN if biometric fails, cancels, or isn't available
      if (!authenticated) {
        authenticated = await _verifyTransactionPin();
      }

      if (authenticated) {
        if (_liveCardNumber == null) {
          setState(() => _isLoadingDetails = true);
          final details = await ref.read(cardNotifierProvider.notifier).revealCardDetails(cardId: widget.card.id);
          if (mounted) {
            setState(() => _isLoadingDetails = false);
            if (details != null) {
              _liveCardNumber = details['card_number']?.toString();
              _liveCvv = details['cvv']?.toString();
              _liveExpiryMonth = details['expiry_month']?.toString();
              _liveExpiryYear = details['expiry_year']?.toString();
              setState(() => _isRevealed = true);
            } else {
              GkToast.show(context, message: 'Failed to fetch secure card details.', type: ToastType.error);
            }
          }
        } else {
          setState(() => _isRevealed = true);
        }
      }
    } catch (_) {
      // Allow fallback if error occurs
      setState(() => _isLoadingDetails = false);
    }
  }

  String get _displayNumber {
    // Card pending issuance — no real PAN yet
    if (widget.card.status == 'pending_issuance' || widget.card.last4 == null) {
      return 'Awaiting Issuance';
    }
    if (!_isRevealed || _liveCardNumber == null) {
      return '•••• •••• •••• ${widget.card.last4}';
    }
    return _liveCardNumber!;
  }

  String get _displayCvv {
    if (widget.card.last4 == null) return '—';
    if (!_isRevealed || _liveCvv == null) return '•••';
    return _liveCvv!;
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
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 9,
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
                              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,),
                            ),
                          ],
                        ),
                      ),
                      Row(
                        children: [
                          _StatusChip(status: widget.card.status),
                          const SizedBox(width: AppSpacing.xs),
                          GestureDetector(
                            onTap: _toggleReveal,
                            child: Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: _isLoadingDetails 
                                ? const SizedBox(
                                    width: 14, height: 14, 
                                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                                  )
                                : Icon(
                                    _isRevealed ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                                    color: Colors.white,
                                    size: 16,
                                  ),
                            ),
                          ),
                          if (widget.onMoreTap != null) ...[
                            const SizedBox(width: AppSpacing.xs),
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
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                          letterSpacing: 3,),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'CVV',
                                style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 8,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white.withValues(alpha: 0.5),
                                  letterSpacing: 1.5,
                                ),
                              ),
                              Text(
                                _displayCvv,
                                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,),
                              ),
                            ],
                          ),
                            if (_liveExpiryMonth != null || widget.card.rule.expiryDate != null)
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    'EXPIRES',
                                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 8,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white.withValues(alpha: 0.5),
                                      letterSpacing: 1.5,
                                    ),
                                  ),
                                  Text(
                                    _liveExpiryMonth != null
                                      ? '${_liveExpiryMonth!.padLeft(2, '0')}/${_liveExpiryYear?.substring(_liveExpiryYear!.length - 2)}'
                                      : '${widget.card.rule.expiryDate!.month.toString().padLeft(2, '0')} / ${widget.card.rule.expiryDate!.year.toString().substring(2)}',
                                    style: Theme.of(context).textTheme.titleMedium?.copyWith(fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white,),
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
      'pending_issuance' => (
          Colors.amber.withValues(alpha: 0.2),
          Colors.amber,
          'Pending'
        ),
      'frozen' => (
          Colors.blueGrey.withValues(alpha: 0.25),
          Colors.blueGrey,
          'Frozen'
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
          if (status == 'pending_issuance')
            Container(
              width: 6,
              height: 6,
              margin: const EdgeInsets.only(right: 5),
              decoration: const BoxDecoration(color: Colors.amber, shape: BoxShape.circle),
            ),
          Text(
            label,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 10,
              fontWeight: FontWeight.w700,
              color: fg,
              letterSpacing: 0.5,),
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
