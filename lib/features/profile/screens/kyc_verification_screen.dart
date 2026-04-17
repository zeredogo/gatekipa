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

class KycVerificationScreen extends ConsumerStatefulWidget {
  const KycVerificationScreen({super.key});

  @override
  ConsumerState<KycVerificationScreen> createState() => _KycVerificationScreenState();
}

class _KycVerificationScreenState extends ConsumerState<KycVerificationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _ninCtrl = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _ninCtrl.dispose();
    super.dispose();
  }

  Future<void> _verifyIdentity() async {
    if (!_formKey.currentState!.validate()) return;
    if (_isLoading) return;
    setState(() => _isLoading = true);

    try {
      final result = await FirebaseFunctions.instance
          .httpsCallable('verifyKyc')
          .call({'nin': _ninCtrl.text.trim()});
      
      if (!mounted) return;
      if (result.data['success'] == true) {
        GkToast.show(context, message: 'Identity verified successfully!', type: ToastType.success);
      } else {
        GkToast.show(context, message: 'Verification failed.', type: ToastType.error);
      }
    } catch (e) {
      if (!mounted) return;
      GkToast.show(context, message: 'Could not complete verification. Try again.', type: ToastType.error);
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
          'Identity Verification',
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
          final isVerified = user.kycStatus == 'verified';

          if (user.kycVerificationAttempts >= 1 && !isVerified) {
            return _buildSupportView();
          }

          return SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              24, 24, 24, MediaQuery.of(context).padding.bottom + 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const SizedBox(height: AppSpacing.xl),
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: isVerified
                        ? AppColors.primary.withValues(alpha: 0.1)
                        : Colors.orange.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    isVerified ? Icons.verified_user_rounded : Icons.pending_actions_rounded,
                    size: 64,
                    color: isVerified ? AppColors.primary : Colors.orange,
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),
                Text(
                  isVerified ? 'Verification Complete' : 'Verification Pending',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: AppColors.onSurface,),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  isVerified
                      ? 'Your identity has been fully verified. You have full access to all Gatekipa vault features.'
                      : 'Please verify your identity to unlock all features, including virtual cards.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 15,
                    color: AppColors.onSurfaceVariant,
                    height: 1.5,),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppSpacing.xl),
                if (!isVerified) ...[
                  Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'National Identity Number (NIN)',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppColors.onSurfaceVariant,),
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        TextFormField(
                          controller: _ninCtrl,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                            LengthLimitingTextInputFormatter(11),
                          ],
                          decoration: InputDecoration(
                            hintText: 'Enter 11-digit NIN',
                            prefixIcon: const Icon(Icons.badge_rounded),
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
                              return 'NIN must be exactly 11 digits';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        GkButton(
                          label: 'Verify NIN',
                          isLoading: _isLoading,
                          onPressed: _verifyIdentity,
                        ),
                      ],
                    ),
                  )
                ] else ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 24),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceBright,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: AppColors.outlineVariant.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Document Proof',
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 14,
                                color: AppColors.onSurfaceVariant,),
                            ),
                            Text(
                              'Provided',
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: AppColors.primary,),
                            ),
                          ],
                        ),
                        const Divider(height: 32),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Liveness Check',
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 14,
                                color: AppColors.onSurfaceVariant,),
                            ),
                            Text(
                              'Approved',
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: AppColors.primary,),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          );
        },
        loading: () => const Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
        error: (e, _) => const Center(child: Text('Failed to load data. Please pull to refresh.')),
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
            'You have reached the maximum number of attempts for identity verification. Please contact admin support for assistance.',
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
