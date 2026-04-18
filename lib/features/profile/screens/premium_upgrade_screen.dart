import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:gatekipa/core/theme/app_colors.dart';
import 'package:gatekipa/core/widgets/gk_button.dart';
import 'package:gatekipa/core/widgets/gk_toast.dart';
import 'package:gatekipa/features/auth/providers/auth_provider.dart';
import 'package:gatekipa/core/theme/app_spacing.dart';

class PremiumUpgradeScreen extends ConsumerStatefulWidget {
  const PremiumUpgradeScreen({super.key});

  @override
  ConsumerState<PremiumUpgradeScreen> createState() => _PremiumUpgradeScreenState();
}

class _PremiumUpgradeScreenState extends ConsumerState<PremiumUpgradeScreen> {
  bool _isLoading = false;

  Future<void> _upgrade() async {
    setState(() => _isLoading = true);
    try {
      // 1. Ask backend to create a Paystack payment session
      final result = await FirebaseFunctions.instance
          .httpsCallable('initiatePremiumUpgrade')
          .call();

      final dataMap = result.data as Map<dynamic, dynamic>;
      final authorizationUrl = dataMap['authorizationUrl'] as String?;
      final reference = dataMap['reference'] as String?;

      if (authorizationUrl == null || reference == null) {
        throw Exception('Invalid payment response from server.');
      }

      if (!mounted) return;

      // 2. Open Paystack checkout in an in-app WebView
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => _PaystackWebView(
            url: authorizationUrl,
            reference: reference,
          ),
        ),
      );

      // 3. After WebView closes, verify payment on backend
      if (!mounted) return;
      setState(() => _isLoading = true);

      await FirebaseFunctions.instance
          .httpsCallable('verifyPremiumPayment')
          .call({'reference': reference});

      if (!mounted) return;
      GkToast.show(context, message: 'Welcome to Sentinel Prime! 🎉', type: ToastType.success);
      context.pop();
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      GkToast.show(
        context,
        message: e.message ?? 'Upgrade failed. Please try again.',
        type: ToastType.error,
      );
    } catch (e) {
      if (!mounted) return;
      GkToast.show(context, message: 'Upgrade failed. Please try again.', type: ToastType.error);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final userAsync = ref.watch(userProfileProvider);

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A), // Dark slate bg for premium feel
      appBar: AppBar(
        title: Text(
          'Sentinel Prime',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(fontSize: 18,
            fontWeight: FontWeight.w700,
            color: Colors.white,),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          color: Colors.white,
          onPressed: () => context.pop(),
        ),
      ),
      body: userAsync.when(
        data: (user) {
          if (user == null) return const SizedBox.shrink();

          if (user.planTier == 'premium') {
            return _buildActivePremiumView();
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: AppSpacing.md),
                Center(
                  child: Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFFEAB308), Color(0xFFD97706)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFEAB308).withValues(alpha: 0.3),
                          blurRadius: 20,
                          spreadRadius: 5,
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.star_rounded,
                      size: 64,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.xxl),
                Text(
                  'Upgrade to\nSentinel Prime',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(fontSize: 32,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    height: 1.2,),
                ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  'Unlock the full power of Gatekipa. Highest tier features, elite limits, and zero boundaries.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 15,
                    color: Colors.white70,
                    height: 1.5,),
                ),
                const SizedBox(height: AppSpacing.xxl),
                _buildFeatureRow(Icons.card_membership_rounded, 'Unlimited Virtual Cards', 'Create infinite customizable cards.'),
                const SizedBox(height: AppSpacing.lg),
                _buildFeatureRow(Icons.flight_takeoff_rounded, 'Worldwide Acceptance', 'No cross-border transaction fees.'),
                const SizedBox(height: AppSpacing.lg),
                _buildFeatureRow(Icons.security_rounded, 'Advanced Geo-Fencing', 'Lock cards to specific countries / regions.'),
              ],
            ),
          );
        },
        loading: () => const Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
        error: (e, _) => const Center(child: Text('Failed to load data. Please pull to refresh.')),
      ),
      bottomNavigationBar: userAsync.when(
        data: (user) {
          if (user == null || user.planTier == 'premium') return const SizedBox.shrink();
          return Container(
            padding: EdgeInsets.fromLTRB(
                24, 16, 24, MediaQuery.of(context).padding.bottom + 16),
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.2),
                  blurRadius: 20,
                  offset: const Offset(0, -4),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                GkButton(
                  label: 'Upgrade for ₦2,000/mo',
                  isLoading: _isLoading,
                  onPressed: _upgrade,
                ),
                const SizedBox(height: 10),
                Text(
                  'Cancel anytime. No hidden fees.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 13,
                    color: Colors.white54,),
                ),
              ],
            ),
          );
        },
        loading: () => const SizedBox.shrink(),
        error: (_, __) => const SizedBox.shrink(),
      ),
    );
  }

  Widget _buildFeatureRow(IconData icon, String title, String subtitle) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: const Color(0xFFEAB308), size: 24),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,),
              ),
              const SizedBox(height: AppSpacing.xxs),
              Text(
                subtitle,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 14,
                  color: Colors.white70,),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildActivePremiumView() {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const SizedBox(height: AppSpacing.xxxl),
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.star_rounded,
              size: 64,
              color: Color(0xFFEAB308),
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          Text(
            'You are Sentinel Prime',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontSize: 24,
              fontWeight: FontWeight.w800,
              color: Colors.white,),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Your gatekipa account is upgraded. You have zero limits on transactions and ultimate control.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 15,
              color: Colors.white70,
              height: 1.5,),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

// ── Paystack Payment WebView ──────────────────────────────────────────────────
class _PaystackWebView extends StatefulWidget {
  final String url;
  final String reference;
  const _PaystackWebView({required this.url, required this.reference});

  @override
  State<_PaystackWebView> createState() => _PaystackWebViewState();
}

class _PaystackWebViewState extends State<_PaystackWebView> {
  late final WebViewController _controller;
  bool _isLoading = true;

  static const _successPattern = 'gatekipa.com/premium/success';

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onPageStarted: (url) {
          // Close WebView once Paystack redirects to our callback URL
          if (url.contains(_successPattern)) {
            Navigator.of(context).pop();
          }
        },
        onPageFinished: (_) => setState(() => _isLoading = false),
      ))
      ..loadRequest(Uri.parse(widget.url));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F172A),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close_rounded, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Secure Payment',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700, color: Colors.white),
        ),
        centerTitle: true,
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_isLoading)
            const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            ),
        ],
      ),
    );
  }
}
