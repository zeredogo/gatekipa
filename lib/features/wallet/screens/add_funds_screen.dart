// lib/features/wallet/screens/add_funds_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';


import 'package:gatekipa/core/theme/app_colors.dart';
import 'package:gatekipa/core/widgets/gk_toast.dart';
import 'package:gatekipa/features/auth/providers/auth_provider.dart';
import 'package:gatekipa/features/wallet/providers/wallet_provider.dart';
import 'package:gatekipa/core/theme/app_spacing.dart';
import 'package:go_router/go_router.dart';
import 'package:gatekipa/core/constants/routes.dart';
import 'package:gatekipa/core/providers/system_state_provider.dart';
import 'package:gatekipa/core/widgets/gk_checkout.dart';

class AddFundsScreen extends ConsumerStatefulWidget {
  const AddFundsScreen({super.key});

  @override
  ConsumerState<AddFundsScreen> createState() => _AddFundsScreenState();
}

class _AddFundsScreenState extends ConsumerState<AddFundsScreen> {
  void _showTopUpBottomSheet(
      BuildContext context, String email, String uid) {
    final amountCtrl = TextEditingController();

    showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            final bottomInsets =
                MediaQuery.of(sheetContext).viewInsets.bottom;
            return Container(
              margin: EdgeInsets.only(bottom: bottomInsets),
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
              decoration: const BoxDecoration(
                color: AppColors.surface,
                borderRadius:
                    BorderRadius.vertical(top: Radius.circular(28)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Handle bar
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 20),
                      decoration: BoxDecoration(
                        color: AppColors.outlineVariant,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Text(
                    'Card Top-Up',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: AppColors.primary,),
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    'Secure checkout via Westgate Stratagem. Funds are credited instantly.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 13,
                        color: AppColors.onSurfaceVariant),
                  ),
                  const SizedBox(height: AppSpacing.lg),

                  // Quick-select amount chips
                  Wrap(
                    spacing: 8,
                    children: [1000, 2000, 5000, 10000].map((preset) {
                      return ActionChip(
                        label: Text(
                          '₦$preset',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600,
                              fontSize: 13,
                              color: AppColors.primary),
                        ),
                        onPressed: () {
                          amountCtrl.text = preset.toString();
                          setSheetState(() {});
                        },
                        backgroundColor:
                            AppColors.primary.withValues(alpha: 0.08),
                        side: const BorderSide(
                            color: AppColors.primary, width: 1),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: AppSpacing.md),

                  // Amount input
                  TextField(
                    controller: amountCtrl,
                    keyboardType: const TextInputType.numberWithOptions(
                        decimal: false),
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly
                    ],
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary,
                    ),
                    decoration: InputDecoration(
                      hintText: '0',
                      hintStyle: GoogleFonts.spaceGrotesk(
                        fontSize: 28,
                        color: AppColors.outline,
                        fontWeight: FontWeight.w700,
                      ),
                      prefixIcon: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 14),
                        child: Text(
                          '₦',
                          style: GoogleFonts.spaceGrotesk(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: AppColors.primary,
                          ),
                        ),
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: const BorderSide(
                            color: AppColors.outlineVariant),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: const BorderSide(
                            color: AppColors.primary, width: 2),
                      ),
                    ),
                    onChanged: (_) => setSheetState(() {}),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text('Minimum: ₦100',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 12, color: AppColors.outline)),
                  const SizedBox(height: 28),

                  // Proceed button
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      onPressed: () {
                        final amt =
                            double.tryParse(amountCtrl.text) ?? 0;
                        if (amt < 100) {
                          GkToast.show(sheetContext,
                              message: 'Minimum deposit is ₦100',
                              type: ToastType.warning);
                          return;
                        }
                        // Close the sheet, open Paystack checkout
                        Navigator.pop(ctx);
                        Navigator.of(context, rootNavigator: true).push(
                          MaterialPageRoute(
                            builder: (_) => GkCheckout(
                              type: GkCheckoutType.fundWallet,
                              amountInNgn: amt,
                              email: email,
                              uid: uid,
                              onSuccess: (reference) async {
                                final scaffoldMsg =
                                    ScaffoldMessenger.of(context);
                                GkToast.show(
                                  context,
                                  message: 'Verifying payment…',
                                  type: ToastType.info,
                                );
                                final textTheme = Theme.of(context).textTheme;
                                final success = await ref
                                    .read(walletNotifierProvider.notifier)
                                    .verifyPaystackPayment(
                                        reference: reference);
                                scaffoldMsg.showSnackBar(SnackBar(
                                  content: Text(
                                    success
                                        ? '₦${amt.toStringAsFixed(0)} added to your vault!'
                                        : 'Verification failed. Contact support.',
                                    style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                                  ),
                                  backgroundColor: success
                                      ? AppColors.primary
                                      : AppColors.error,
                                  behavior: SnackBarBehavior.floating,
                                  shape: RoundedRectangleBorder(
                                      borderRadius:
                                          BorderRadius.circular(12)),
                                ));
                              },
                            ),
                          ),
                        );
                      },
                      icon: const Icon(Icons.credit_card_rounded,
                          color: Colors.white),
                      label: const Text(
                        'Pay with Card',
                        style: TextStyle(height: 1.2, fontFamily: 'Manrope', fontSize: 16,
                          fontWeight: FontWeight.w700,),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),

                  // Security badge
                  Center(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.lock_rounded,
                            size: 14, color: AppColors.outline),
                        const SizedBox(width: 6),
                        Text(
                          'Secured by Westgate Stratagem · PCI DSS compliant',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 12, color: AppColors.outline),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(userProfileProvider).valueOrNull;
    final sysState = ref.watch(systemStateProvider).valueOrNull ?? SystemState.normal;

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: Text('Add Funds',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800, color: AppColors.primary)),
        leading: const BackButton(color: AppColors.onSurface),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 140),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Your Dedicated Vault Account',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Transfer any amount to this account number to automatically fund your vault. Powered by Westgate Stratagem & Banking Partners.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 14, color: AppColors.onSurfaceVariant),
            ),
            const SizedBox(height: 28),

            // Vault NUBAN / generate card
            if (user?.bridgecardNuban == null)
              _GenerateAccountCard(
                isDisabled: !sysState.isOperational,
                onGenerate: () async {
                  // System gate
                  if (!sysState.isOperational) {
                    GkToast.show(context,
                        message: sysState.bannerMessage,
                        type: ToastType.error,
                        duration: const Duration(seconds: 4));
                    return;
                  }
                  final uid = user?.uid;
                  if (uid == null) return;
                  if (user?.kycStatus != 'verified') {
                    GkToast.show(context,
                        message: 'Please verify your identity to generate an account.',
                        type: ToastType.warning);
                    context.push(Routes.kyc);
                    return;
                  }
                  final scaffoldMsg = ScaffoldMessenger.of(context);
                  final textTheme = Theme.of(context).textTheme;
                  final success = await ref
                      .read(walletNotifierProvider.notifier)
                      .generateVaultAccount(uid);
                  scaffoldMsg.showSnackBar(SnackBar(
                    content: Text(
                      success
                          ? 'Vault Account Generated!'
                          : 'Failed to generate account',
                      style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    backgroundColor:
                        success ? AppColors.primary : AppColors.error,
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ));
                },
              )
            else
              _NubanCard(user: user!)
                  .animate()
                  .fadeIn()
                  .slideY(begin: 0.1, end: 0),

            const SizedBox(height: AppSpacing.lg),

            // Info banner
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color:
                    AppColors.secondaryContainer.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                    color: AppColors.secondary.withValues(alpha: 0.2)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline_rounded,
                      color: AppColors.secondary),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      'Funds transferred to this account will appear in your Gatekipa Vault balance automatically.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 13,
                          color: AppColors.onSurfaceVariant,
                          height: 1.4),
                    ),
                  ),
                ],
              ),
            ).animate().fadeIn(delay: 200.ms),

            const SizedBox(height: AppSpacing.xxl),

            // Card top-up section
            Text('Instant Card Top-Up',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Top up instantly using any NG debit or credit card via Westgate Stratagem secure checkout.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 14, color: AppColors.onSurfaceVariant),
            ),
            const SizedBox(height: AppSpacing.md),
            SizedBox(
              width: double.infinity,
              height: 56,
              child: OutlinedButton.icon(
                onPressed: () {
                  // System mode gate — checked before opening the sheet
                  if (!sysState.isOperational) {
                    GkToast.show(context,
                        message: sysState.bannerMessage,
                        type: ToastType.error,
                        duration: const Duration(seconds: 4));
                    return;
                  }
                  final email = user?.email;
                  final uid = user?.uid;
                  if (email == null || uid == null) {
                    GkToast.show(context,
                        message: 'Please complete your profile first',
                        type: ToastType.warning);
                    return;
                  }
                  if (user?.kycStatus != 'verified') {
                    GkToast.show(context,
                        message: 'Please verify your identity to add funds.',
                        type: ToastType.warning);
                    context.push(Routes.kyc);
                    return;
                  }
                  _showTopUpBottomSheet(context, email, uid);
                },
                icon: const Icon(Icons.credit_card_rounded),
                label: const Text('Top up with Card',
                    style: TextStyle(height: 1.2, fontFamily: 'Manrope', fontSize: 16, fontWeight: FontWeight.w700)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  side: const BorderSide(
                      color: AppColors.primary, width: 2),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                ),
              ),
            ).animate().fadeIn(delay: 300.ms),

            const SizedBox(height: AppSpacing.md),
            Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.lock_rounded,
                      size: 14, color: AppColors.outline),
                  const SizedBox(width: 6),
                  Text('Secured by Westgate Stratagem · PCI DSS compliant',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 12, color: AppColors.outline)),
                ],
              ),
            ).animate().fadeIn(delay: 400.ms),
          ],
        ),
      ),
    );
  }
}





// ── NUBAN Card ────────────────────────────────────────────────────────────────
class _NubanCard extends StatelessWidget {
  final dynamic user;
  const _NubanCard({required this.user});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.primary, Color(0xFF1B4D3E)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.2),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('BANK NAME',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.white60,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1)),
                const SizedBox(height: AppSpacing.xxs),
                Text(user.bridgecardBankName ?? 'Moniepoint MFB',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700)),
              ]),
              const Icon(Icons.account_balance_rounded,
                  color: Colors.white54, size: 28),
            ],
          ),
          const SizedBox(height: AppSpacing.xl),
          Text('ACCOUNT NUMBER',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.white60,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1)),
          const SizedBox(height: AppSpacing.xxs),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(user.bridgecardNuban ?? '',
                  style: GoogleFonts.spaceGrotesk(
                      color: Colors.white,
                      fontSize: 32,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 4)),
              IconButton(
                onPressed: () {
                  Clipboard.setData(
                      ClipboardData(text: user.bridgecardNuban ?? ''));
                  GkToast.show(context,
                      message: 'Account number copied',
                      type: ToastType.success);
                },
                icon: const Icon(Icons.copy_rounded, color: Colors.white),
                tooltip: 'Copy',
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xl),
          Text('ACCOUNT NAME',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.white60,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1)),
          const SizedBox(height: AppSpacing.xxs),
          Text(user.bridgecardAccountName ?? 'Gatekipa Vault',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

// ── Generate Account Card ─────────────────────────────────────────────────────
class _GenerateAccountCard extends StatefulWidget {
  final Future<void> Function() onGenerate;
  final bool isDisabled;
  const _GenerateAccountCard({required this.onGenerate, this.isDisabled = false});

  @override
  State<_GenerateAccountCard> createState() => _GenerateAccountCardState();
}

class _GenerateAccountCardState extends State<_GenerateAccountCard> {
  bool _loading = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.primary, Color(0xFF1B4D3E)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.2),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          const Icon(Icons.account_balance_rounded,
              color: Colors.white, size: 48),
          const SizedBox(height: AppSpacing.md),
          Text('No Vault Account Yet',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w800)),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Generate your dedicated virtual account to start funding your Gatekipa wallet instantly.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.white70, fontSize: 14, height: 1.5),
          ),
          const SizedBox(height: AppSpacing.lg),
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton(
              onPressed: (_loading || widget.isDisabled)
                  ? null
                  : () async {
                      setState(() => _loading = true);
                      await widget.onGenerate();
                      if (mounted) setState(() => _loading = false);
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: AppColors.primary,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
                elevation: 0,
              ),
              child: _loading
                  ? const SizedBox(
                      height: 22,
                      width: 22,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: AppColors.primary))
                  : Text(widget.isDisabled ? 'Transactions Disabled' : 'Generate Vault Account',
                      style: const TextStyle(height: 1.2, fontFamily: 'Manrope', fontSize: 16, fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
    ).animate().fadeIn().slideY(begin: 0.1, end: 0);
  }
}
