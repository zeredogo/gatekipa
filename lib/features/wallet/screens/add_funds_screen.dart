// lib/features/wallet/screens/add_funds_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'package:gatekeepeer/core/constants/app_constants.dart';
import 'package:gatekeepeer/core/theme/app_colors.dart';
import 'package:gatekeepeer/core/widgets/gk_toast.dart';
import 'package:gatekeepeer/features/auth/providers/auth_provider.dart';
import 'package:gatekeepeer/features/wallet/providers/wallet_provider.dart';
import 'package:gatekeepeer/core/theme/app_spacing.dart';
import 'package:gatekeepeer/core/providers/system_state_provider.dart';


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
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => _PaystackCheckoutScreen(
                              amountInNgn: amt,
                              email: email,
                              uid: uid,
                              onPaymentVerified: (reference) async {
                                // Capture context-dependent state before await
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

// ── Paystack Checkout WebView Screen ─────────────────────────────────────────
class _PaystackCheckoutScreen extends StatefulWidget {
  final double amountInNgn;
  final String email;
  final String uid;
  final Future<void> Function(String reference) onPaymentVerified;

  const _PaystackCheckoutScreen({
    required this.amountInNgn,
    required this.email,
    required this.uid,
    required this.onPaymentVerified,
  });

  @override
  State<_PaystackCheckoutScreen> createState() =>
      _PaystackCheckoutScreenState();
}

class _PaystackCheckoutScreenState
    extends State<_PaystackCheckoutScreen> {
  late final WebViewController _controller;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    final reference =
        'GTK-${widget.uid.substring(0, 6)}-${DateTime.now().millisecondsSinceEpoch}';
    final amountInKobo = (widget.amountInNgn * 100).toInt();

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onPageFinished: (_) => setState(() => _isLoading = false),
        onNavigationRequest: (req) {
          // Capture the success callback URL from Paystack inline JS
          if (req.url.startsWith('gatekeepeer://payment-success')) {
            final uri = Uri.parse(req.url);
            final ref = uri.queryParameters['reference'] ?? reference;
            Navigator.pop(context);
            widget.onPaymentVerified(ref);
            return NavigationDecision.prevent;
          }
          if (req.url.startsWith('gatekeepeer://payment-cancelled')) {
            Navigator.pop(context);
            return NavigationDecision.prevent;
          }
          return NavigationDecision.navigate;
        },
      ))
      ..loadHtmlString(_buildPaystackHtml(
        publicKey: AppConstants.paystackPublicKey,
        email: widget.email,
        amountInKobo: amountInKobo,
        reference: reference,
      ));
  }

  String _buildPaystackHtml({
    required String publicKey,
    required String email,
    required int amountInKobo,
    required String reference,
  }) {
    return '''
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
  <title>Secure Payment</title>
  <script src="https://js.paystack.co/v1/inline.js"></script>
  <style>
    * { margin: 0; padding: 0; box-sizing: border-box; }
    body {
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
      background: #f8fafc;
      display: flex;
      flex-direction: column;
      align-items: center;
      justify-content: center;
      min-height: 100vh;
      padding: 24px;
    }
    .card {
      background: white;
      border-radius: 20px;
      padding: 32px 24px;
      text-align: center;
      box-shadow: 0 4px 24px rgba(0,0,0,0.08);
      width: 100%;
      max-width: 400px;
    }
    .shield { font-size: 48px; margin-bottom: 16px; }
    h1 { font-size: 22px; font-weight: 800; color: #1a6b47; margin-bottom: 8px; }
    p { font-size: 14px; color: #6b7280; margin-bottom: 4px; }
    .amount { font-size: 32px; font-weight: 800; color: #1a6b47; margin: 16px 0; }
    .btn {
      display: inline-block;
      background: #1a6b47;
      color: white;
      border: none;
      border-radius: 12px;
      padding: 16px 32px;
      font-size: 16px;
      font-weight: 700;
      cursor: pointer;
      width: 100%;
      margin-top: 16px;
    }
    .btn:active { opacity: 0.85; }
    .lock { font-size: 12px; color: #9ca3af; margin-top: 16px; }
  </style>
</head>
<body>
  <div class="card">
    <div class="shield">🛡️</div>
    <h1>Gatekeepeer</h1>
    <p style="font-size: 13px; font-weight: 600; color: #6b7280; margin-bottom: 12px;">Powered by Westgate</p>
    <p>Adding to your vault</p>
    <div class="amount">₦${(amountInKobo / 100).toStringAsFixed(0)}</div>
    <p style="font-size:13px;color:#4b5563">$email</p>
    <button class="btn" onclick="payWithPaystack()">Pay Securely</button>
    <div class="lock">🔒 Secured by Westgate Stratagem · PCI DSS compliant</div>
  </div>

  <script>
    function payWithPaystack() {
      var handler = PaystackPop.setup({
        key: '$publicKey',
        email: '$email',
        amount: $amountInKobo,
        currency: 'NGN',
        ref: '$reference',
        metadata: { uid: '${widget.uid}' },
        onClose: function() {
          window.location.href = 'gatekeepeer://payment-cancelled';
        },
        callback: function(response) {
          window.location.href = 'gatekeepeer://payment-success?reference=' + response.reference;
        }
      });
      handler.openIframe();
    }

    // Auto-open on load for a smoother experience
    window.onload = function() {
      setTimeout(payWithPaystack, 300);
    };
  </script>
</body>
</html>
''';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: Text('Secure Payment',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800, color: AppColors.primary)),
        leading: const BackButton(color: AppColors.onSurface),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Row(
              children: [
                const Icon(Icons.lock_rounded,
                    size: 14, color: AppColors.outline),
                const SizedBox(width: AppSpacing.xxs),
                Text('Westgate Stratagem',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 12, color: AppColors.outline)),
              ],
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_isLoading)
            const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: AppColors.primary),
                  SizedBox(height: AppSpacing.md),
                  Text('Loading secure checkout…'),
                ],
              ),
            ),
        ],
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
