import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:gatekipa/core/theme/app_colors.dart';
import 'package:gatekipa/core/widgets/gk_button.dart';
import 'package:gatekipa/core/widgets/gk_toast.dart';
import 'package:gatekipa/features/auth/providers/auth_provider.dart';
import 'package:gatekipa/core/theme/app_spacing.dart';
import 'package:webview_flutter/webview_flutter.dart';

class BvnVerificationScreen extends ConsumerStatefulWidget {
  const BvnVerificationScreen({super.key});

  @override
  ConsumerState<BvnVerificationScreen> createState() => _BvnVerificationScreenState();
}

class _BvnVerificationScreenState extends ConsumerState<BvnVerificationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _bvnCtrl = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _bvnCtrl.dispose();
    super.dispose();
  }

  Future<void> _verifyBvn() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    try {
      final result = await FirebaseFunctions.instance
          .httpsCallable('verifyBvn')
          .call({'bvn': _bvnCtrl.text.trim()});

      if (!mounted) return;
      final success = result.data['success'] == true;
      if (success) {
        GkToast.show(context,
            message: 'BVN successfully verified and linked!',
            type: ToastType.success);
        // authNotifier already listens to Firestore — profile will auto-update
        context.pop();
      } else {
        GkToast.show(context,
            message: 'Verification failed. Please try again.',
            type: ToastType.error);
      }
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      GkToast.show(context,
          message: e.message ?? 'Could not verify BVN. Please try again.',
          type: ToastType.error,
          title: 'Verification Failed');
    } catch (_) {
      if (!mounted) return;
      GkToast.show(context,
          message: 'An unexpected error occurred.',
          type: ToastType.error);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final userAsync = ref.watch(userProfileProvider);

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: Text(
          'BVN / NIN',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(fontSize: 18,
            fontWeight: FontWeight.w700,
            color: AppColors.onSurface,),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          color: AppColors.onSurface,
          onPressed: () => context.pop(),
        ),
      ),
      body: userAsync.when(
        data: (user) {
          if (user == null) return const SizedBox.shrink();
          if (user.hasBvn) {
            return _buildSuccessView();
          }

          if (user.bvnVerificationAttempts >= 1) {
            return _buildSupportView();
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    'Link your BVN',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: AppColors.onSurface,),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'To access premium features, virtual cards, and increased limits, please provide your 11-digit Bank Verification Number.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 15,
                      color: AppColors.onSurfaceVariant,
                      height: 1.5,),
                  ),
                  const SizedBox(height: 36),
                  Text(
                    'BVN',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.onSurfaceVariant,),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  TextFormField(
                    controller: _bvnCtrl,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(11),
                    ],
                    decoration: InputDecoration(
                      hintText: 'Enter 11-digit BVN',
                      prefixIcon: const Icon(Icons.security_rounded),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide.none,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide(
                          color: AppColors.outlineVariant.withValues(alpha: 0.3),
                          width: 1.5,
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: const BorderSide(color: AppColors.primary, width: 2),
                      ),
                      filled: true,
                      fillColor: AppColors.surfaceBright,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
                    ),
                    validator: (v) {
                      if (v == null || v.length != 11) {
                        return 'BVN must be exactly 11 digits';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.blue.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.info_outline_rounded, color: Colors.blue, size: 20),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Text(
                            'Your BVN is securely encrypted and only used to verify your identity. Dial *565*0# on your registered mobile number to check.',
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 13,
                              color: Colors.blue.shade700,
                              height: 1.4,),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
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
          if (user == null || user.hasBvn || user.bvnVerificationAttempts >= 1) return const SizedBox.shrink();
          return Container(
            padding: EdgeInsets.fromLTRB(
                24, 16, 24, MediaQuery.of(context).padding.bottom + 16),
            decoration: BoxDecoration(
              color: AppColors.surface,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.06),
                  blurRadius: 20,
                  offset: const Offset(0, -4),
                ),
              ],
            ),
            child: GkButton(
              label: 'Verify BVN',
              isLoading: _isLoading,
              onPressed: _verifyBvn,
            ),
          );
        },
        loading: () => const SizedBox.shrink(),
        error: (_, __) => const SizedBox.shrink(),
      ),
    );
  }

  Widget _buildSuccessView() {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const SizedBox(height: AppSpacing.xxxl),
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.shield_rounded,
              size: 64,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          Text(
            'BVN Successfully Linked',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontSize: 24,
              fontWeight: FontWeight.w800,
              color: AppColors.onSurface,),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Your BVN and identity have been securely verified and linked to your Gatekipa vault.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 15,
              color: AppColors.onSurfaceVariant,
              height: 1.5,),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildSupportView() {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const SizedBox(height: AppSpacing.xxxl),
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.red.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.warning_rounded,
              size: 64,
              color: Colors.red,
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          Text(
            'Verification Limit Reached',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontSize: 24,
              fontWeight: FontWeight.w800,
              color: AppColors.onSurface,),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'You have reached the maximum number of attempts for BVN verification. Please contact admin support for assistance.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 15,
              color: AppColors.onSurfaceVariant,
              height: 1.5,),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.xxl),
          GkButton(
            label: 'Contact Admin Support',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => Scaffold(
                    appBar: AppBar(
                      title: Text('Admin Support', style: TextStyle(color: AppColors.primary)),
                      leading: const CloseButton(),
                    ),
                    body: WebViewWidget(
                      controller: WebViewController()
                        ..setJavaScriptMode(JavaScriptMode.unrestricted)
                        ..loadRequest(Uri.parse('https://gatekipa.com/support')),
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
