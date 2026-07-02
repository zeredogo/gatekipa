// lib/features/wallet/screens/add_funds_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:gatekipa/core/theme/app_colors.dart';
import 'package:gatekipa/core/widgets/gk_toast.dart';
import 'package:gatekipa/features/auth/providers/auth_provider.dart';
import 'package:gatekipa/features/wallet/providers/wallet_provider.dart';
import 'package:gatekipa/core/theme/app_spacing.dart';
import 'package:gatekipa/core/constants/routes.dart';
import 'package:gatekipa/core/providers/system_state_provider.dart';
import 'package:gatekipa/features/wallet/widgets/otp_dialog.dart';
import 'dart:convert';
import 'package:image_picker/image_picker.dart';
// Removed GkCheckout as we no longer use it for wallet funding
class AddFundsScreen extends ConsumerStatefulWidget {
  const AddFundsScreen({super.key});

  @override
  ConsumerState<AddFundsScreen> createState() => _AddFundsScreenState();
}

class _AddFundsScreenState extends ConsumerState<AddFundsScreen> {
  // Removed Paystack Card Top-Up Bottom Sheet

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
            if (user?.vaultNuban == null)
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
                  if (user?.kycStatus != 'verified' && user?.kycStatus != 'approved') {
                    GkToast.show(context,
                        message: 'Please complete your KYC Verification to generate an account.',
                        type: ToastType.warning);
                    context.push(Routes.kyc);
                    return;
                  }

                  // Direct Face/Selfie OTP bypass verification (SMS OTP retired)
                  final walletNotifier = ref.read(walletNotifierProvider.notifier);
                  String? capturedIdentityId;

                  try {
                    // Show screen flash/ring-light helper overlay
                    showDialog(
                      context: context,
                      barrierDismissible: false,
                      builder: (context) => const Scaffold(
                        backgroundColor: Colors.white,
                        body: Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              CircularProgressIndicator(color: Colors.blue),
                              SizedBox(height: 16),
                              Text(
                                'Preparing camera helper...',
                                style: TextStyle(color: Colors.black54, fontSize: 16, fontWeight: FontWeight.w500),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );

                    // Wait for screen white lighting to stabilize
                    await Future.delayed(const Duration(milliseconds: 400));
                    if (!context.mounted) return;

                    final navigator = Navigator.of(context);

                    // 2. Capture face image
                    final picker = ImagePicker();
                    XFile? picked;
                    try {
                      picked = await picker.pickImage(
                        source: ImageSource.camera, 
                        imageQuality: 80, 
                        preferredCameraDevice: CameraDevice.front,
                      );
                    } finally {
                      // Dismiss screen flash overlay
                      navigator.pop();
                    }

                    if (picked == null) {
                      if (!context.mounted) return;
                      GkToast.show(context, message: 'Selfie capture cancelled.', type: ToastType.warning);
                      return;
                    }

                    if (!context.mounted) return;
                    GkToast.show(context, message: 'Processing face verification...', type: ToastType.info);

                    final bytes = await picked.readAsBytes();
                    final base64Str = 'data:image/jpeg;base64,${base64Encode(bytes)}';

                    // 3. Initiate face verification
                    capturedIdentityId = await walletNotifier.initiateVaultVerification(faceImageBase64: base64Str);
                    if (capturedIdentityId == null) {
                      throw Exception("Facial recognition match failed. Please check camera lighting.");
                    }
                  } catch (e) {
                    if (!context.mounted) return;
                    String errorMsg = 'An error occurred';
                    if (e is FirebaseFunctionsException) {
                      errorMsg = e.message ?? errorMsg;
                    } else {
                      errorMsg = e.toString().replaceFirst('Exception: ', '');
                    }
                    GkToast.show(context, message: errorMsg, type: ToastType.error);
                    return;
                  }

                  // 4. Generate the vault account
                  final success = await walletNotifier.generateVaultAccount(uid, identityId: capturedIdentityId);

                  if (!context.mounted) return;
                  if (success) {
                    GkToast.show(context, message: 'Vault generated successfully!', type: ToastType.success);
                    Navigator.of(context).popUntil((route) => route.isFirst);
                  } else {
                    GkToast.show(context, message: 'Failed to generate vault account.', type: ToastType.error);
                  }
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
                Text(user.vaultBankName ?? 'Moniepoint MFB',
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
              Text(user.vaultNuban ?? '',
                  style: GoogleFonts.spaceGrotesk(
                      color: Colors.white,
                      fontSize: 32,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 4)),
              IconButton(
                onPressed: () {
                  Clipboard.setData(
                      ClipboardData(text: user.vaultNuban ?? ''));
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
          Text(user.vaultAccountName ?? 'Gatekipa Vault',
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
          Container(
            width: double.infinity,
            constraints: const BoxConstraints(minHeight: 56), // FIX: Flexible height
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
