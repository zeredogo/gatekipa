// lib/core/widgets/gk_checkout.dart
//
// Gatekipa Branded Checkout — replaces all Paystack WebView screens.
// Uses Paystack Inline JS under the hood but wraps it in a fully
// Gatekipa-branded native Flutter experience.
//
// IMPORTANT: Only the presentation layer is custom. The payment
// processing still routes through Paystack → Firebase Cloud Functions.
// Do NOT modify the callback URL scheme ('gatekipa://') as the
// WebView navigation interceptor depends on it.

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:gatekipa/core/constants/app_constants.dart';
import 'package:gatekipa/core/theme/app_colors.dart';

/// The type of checkout being performed — drives label and icon selection.
enum GkCheckoutType {
  /// Adding funds to the Gatekipa Vault
  fundWallet,

  /// Purchasing a subscription plan
  planActivation,

  /// Upgrading to Sentinel Prime
  premiumUpgrade,
}

/// A fully Gatekipa-branded checkout screen.
///
/// Usage:
/// ```dart
/// Navigator.push(context, MaterialPageRoute(
///   builder: (_) => GkCheckout(
///     type: GkCheckoutType.fundWallet,
///     amountInNgn: 5000,
///     email: user.email,
///     uid: user.uid,
///     reference: 'GTK-...',
///     onSuccess: (ref) async { ... },
///   ),
/// ));
/// ```
class GkCheckout extends StatefulWidget {
  final GkCheckoutType type;
  final double amountInNgn;
  final String email;
  final String uid;
  final String? reference;
  final String? label; // e.g. "Premium Plan", "Activation Plan"
  final Map<String, String>? metadata; // extra metadata for paystack
  final Future<void> Function(String reference) onSuccess;
  final VoidCallback? onCancel;

  const GkCheckout({
    super.key,
    required this.type,
    required this.amountInNgn,
    required this.email,
    required this.uid,
    required this.onSuccess,
    this.reference,
    this.label,
    this.metadata,
    this.onCancel,
  });

  @override
  State<GkCheckout> createState() => _GkCheckoutState();
}

class _GkCheckoutState extends State<GkCheckout> {
  late final String _reference;
  bool _showWebView = false;
  bool _webViewLoading = true;
  bool _processing = false;
  WebViewController? _controller;

  @override
  void initState() {
    super.initState();
    _reference = widget.reference ??
        'GTK-${widget.uid.substring(0, 6)}-${DateTime.now().millisecondsSinceEpoch}';
  }

  String get _title {
    switch (widget.type) {
      case GkCheckoutType.fundWallet:
        return 'Fund Vault';
      case GkCheckoutType.planActivation:
        return 'Activate Plan';
      case GkCheckoutType.premiumUpgrade:
        return 'Upgrade to Sentinel Prime';
    }
  }

  String get _subtitle {
    switch (widget.type) {
      case GkCheckoutType.fundWallet:
        return 'Adding to your Gatekipa Vault';
      case GkCheckoutType.planActivation:
        return widget.label != null
            ? '${widget.label} — One-time activation'
            : 'Plan activation fee';
      case GkCheckoutType.premiumUpgrade:
        return 'Monthly subscription';
    }
  }

  IconData get _icon {
    switch (widget.type) {
      case GkCheckoutType.fundWallet:
        return Icons.account_balance_wallet_rounded;
      case GkCheckoutType.planActivation:
        return Icons.rocket_launch_rounded;
      case GkCheckoutType.premiumUpgrade:
        return Icons.workspace_premium_rounded;
    }
  }

  Color get _accentColor {
    switch (widget.type) {
      case GkCheckoutType.fundWallet:
        return AppColors.primary;
      case GkCheckoutType.planActivation:
        return AppColors.primary;
      case GkCheckoutType.premiumUpgrade:
        return const Color(0xFFEAB308);
    }
  }

  void _initiatePayment() {
    final amountInKobo = (widget.amountInNgn * 100).toInt();

    setState(() {
      _showWebView = true;
      _webViewLoading = true;
    });

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onPageFinished: (_) {
          if (mounted) setState(() => _webViewLoading = false);
        },
        onNavigationRequest: (req) {
          if (req.url.startsWith('gatekipa://payment-success')) {
            final uri = Uri.parse(req.url);
            final ref = uri.queryParameters['reference'] ?? _reference;
            setState(() {
              _showWebView = false;
              _processing = true;
            });
            widget.onSuccess(ref).then((_) {
              if (mounted) Navigator.pop(context);
            });
            return NavigationDecision.prevent;
          }
          if (req.url.startsWith('gatekipa://payment-cancelled')) {
            setState(() => _showWebView = false);
            return NavigationDecision.prevent;
          }
          return NavigationDecision.navigate;
        },
      ))
      ..loadHtmlString(_buildPaystackHtml(amountInKobo));
  }

  String _buildPaystackHtml(int amountInKobo) {
    final metadataEntries = <String>[];
    metadataEntries.add("uid: '${widget.uid}'");
    if (widget.metadata != null) {
      for (final entry in widget.metadata!.entries) {
        metadataEntries.add("${entry.key}: '${entry.value}'");
      }
    }

    final customFields = <String>[];
    if (widget.label != null) {
      customFields.add(
          "{ display_name: 'Item', variable_name: 'item', value: '${widget.label}' }");
    }

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
      background: transparent;
      display: flex;
      align-items: center;
      justify-content: center;
      min-height: 100vh;
    }
    .loading {
      text-align: center;
      color: #6b7280;
      font-size: 14px;
    }
    .spinner {
      width: 32px; height: 32px;
      border: 3px solid #e5e7eb;
      border-top-color: #1a6b47;
      border-radius: 50%;
      animation: spin 0.8s linear infinite;
      margin: 0 auto 12px;
    }
    @keyframes spin { to { transform: rotate(360deg); } }
  </style>
</head>
<body>
  <div class="loading">
    <div class="spinner"></div>
    <p>Initializing secure payment…</p>
  </div>
  <script>
    function payWithPaystack() {
      var handler = PaystackPop.setup({
        key: '${AppConstants.paystackPublicKey}',
        email: '${widget.email}',
        amount: $amountInKobo,
        currency: 'NGN',
        ref: '$_reference',
        metadata: {
          ${metadataEntries.join(',\n          ')}${customFields.isNotEmpty ? ',\n          custom_fields: [${customFields.join(', ')}]' : ''}
        },
        onClose: function() {
          window.location.href = 'gatekipa://payment-cancelled';
        },
        callback: function(response) {
          window.location.href = 'gatekipa://payment-success?reference=' + response.reference;
        }
      });
      handler.openIframe();
    }
    window.onload = function() {
      setTimeout(payWithPaystack, 200);
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
        backgroundColor: AppColors.surface,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close_rounded, color: AppColors.onSurface),
          onPressed: () {
            widget.onCancel?.call();
            Navigator.pop(context);
          },
        ),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: _accentColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(Icons.shield_rounded, color: _accentColor, size: 16),
            ),
            const SizedBox(width: 8),
            Text(
              'Gatekipa Checkout',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    fontSize: 17,
                    color: AppColors.onSurface,
                  ),
            ),
          ],
        ),
        centerTitle: true,
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: 16),
            child: Icon(Icons.lock_rounded,
                size: 16, color: AppColors.outline),
          ),
        ],
      ),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        child: _processing
            ? _buildProcessingView()
            : _showWebView
                ? _buildWebViewLayer()
                : _buildOrderSummary(),
      ),
    );
  }

  Widget _buildOrderSummary() {
    final amountStr = '₦${widget.amountInNgn.toStringAsFixed(0)}';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const SizedBox(height: 20),

          // ── Brand Header ──
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  _accentColor.withValues(alpha: 0.15),
                  _accentColor.withValues(alpha: 0.05),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(24),
            ),
            child: Icon(_icon, color: _accentColor, size: 36),
          ).animate().fadeIn().scale(begin: const Offset(0.8, 0.8), end: const Offset(1, 1)),

          const SizedBox(height: 24),

          Text(
            _title,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  fontSize: 24,
                ),
          ).animate().fadeIn(delay: 100.ms),

          const SizedBox(height: 6),

          Text(
            _subtitle,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.onSurfaceVariant,
                  fontSize: 14,
                ),
          ).animate().fadeIn(delay: 150.ms),

          const SizedBox(height: 32),

          // ── Amount Card ──
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 24),
            decoration: BoxDecoration(
              color: AppColors.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                  color: AppColors.outlineVariant.withValues(alpha: 0.5)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.03),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              children: [
                Text(
                  'Amount',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontSize: 12,
                        color: AppColors.outline,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1,
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  amountStr,
                  style: Theme.of(context).textTheme.displaySmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: _accentColor,
                        fontSize: 40,
                      ),
                ),
                const SizedBox(height: 12),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.outlineVariant.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(100),
                  ),
                  child: Text(
                    widget.email,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontSize: 13,
                          color: AppColors.onSurfaceVariant,
                        ),
                  ),
                ),
              ],
            ),
          ).animate().fadeIn(delay: 200.ms).slideY(begin: 0.05, end: 0),

          const SizedBox(height: 24),

          // ── Details Rows ──
          const _DetailRow(
            label: 'Payment method',
            value: 'Card / Bank Transfer',
            icon: Icons.credit_card_rounded,
          ).animate().fadeIn(delay: 250.ms),
          const SizedBox(height: 10),
          _DetailRow(
            label: 'Reference',
            value: _reference.length > 20
                ? '${_reference.substring(0, 20)}…'
                : _reference,
            icon: Icons.tag_rounded,
          ).animate().fadeIn(delay: 300.ms),
          const SizedBox(height: 10),
          const _DetailRow(
            label: 'Processor',
            value: 'Westgate Stratagem',
            icon: Icons.shield_rounded,
          ).animate().fadeIn(delay: 350.ms),

          const SizedBox(height: 36),

          // ── Pay Button ──
          SizedBox(
            width: double.infinity,
            height: 58,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: _accentColor,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
                elevation: 0,
              ),
              onPressed: _initiatePayment,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.lock_rounded, size: 18, color: Colors.white),
                  const SizedBox(width: 10),
                  Text(
                    'Pay $amountStr Securely',
                    style: const TextStyle(
                      height: 1.2,
                      fontFamily: 'Manrope',
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ).animate().fadeIn(delay: 400.ms).slideY(begin: 0.1, end: 0),

          const SizedBox(height: 20),

          // ── Security Footer ──
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.verified_user_rounded,
                  size: 14, color: AppColors.outline),
              const SizedBox(width: 6),
              Text(
                'Secured by Westgate Stratagem · PCI DSS',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontSize: 11,
                      color: AppColors.outline,
                    ),
              ),
            ],
          ).animate().fadeIn(delay: 500.ms),
        ],
      ),
    );
  }

  Widget _buildWebViewLayer() {
    return Stack(
      children: [
        if (_controller != null) WebViewWidget(controller: _controller!),
        if (_webViewLoading)
          Container(
            color: AppColors.surface,
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(color: AppColors.primary),
                  const SizedBox(height: 16),
                  Text(
                    'Loading payment gateway…',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppColors.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildProcessingView() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: _accentColor.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const CircularProgressIndicator(color: AppColors.primary),
          ),
          const SizedBox(height: 24),
          Text(
            'Processing payment…',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  fontSize: 20,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            'Please wait while we verify your transaction.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.onSurfaceVariant,
                ),
          ),
        ],
      ),
    ).animate().fadeIn();
  }
}

// ── Detail Row ────────────────────────────────────────────────────────────────
class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _DetailRow({
    required this.label,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
        border:
            Border.all(color: AppColors.outlineVariant.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: AppColors.primary, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontSize: 13,
                    color: AppColors.onSurfaceVariant,
                  ),
            ),
          ),
          Text(
            value,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.onSurface,
                ),
          ),
        ],
      ),
    );
  }
}
