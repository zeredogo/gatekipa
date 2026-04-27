import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:gatekipa/features/auth/providers/auth_provider.dart';
import 'package:gatekipa/core/theme/app_colors.dart';
import 'package:gatekipa/core/widgets/gk_toast.dart';
import 'package:gatekipa/core/theme/app_spacing.dart';

class PinManagementScreen extends ConsumerStatefulWidget {
  const PinManagementScreen({super.key});

  @override
  ConsumerState<PinManagementScreen> createState() =>
      _PinManagementScreenState();
}

class _PinManagementScreenState extends ConsumerState<PinManagementScreen> {
  final _formKey = GlobalKey<FormState>();
  final _pinCtrl = TextEditingController();
  final _confirmPinCtrl = TextEditingController();
  final _oldPinCtrl = TextEditingController();

  bool _isLoading = false;
  bool _hasExistingPin = false;
  bool _needsManualOldPin = false;
  bool _obscureNew = true;
  bool _obscureConfirm = true;
  bool _obscureOld = true;

  @override
  void initState() {
    super.initState();
    _checkExistingPin();
  }

  @override
  void dispose() {
    _pinCtrl.dispose();
    _confirmPinCtrl.dispose();
    _oldPinCtrl.dispose();
    super.dispose();
  }

  Future<void> _checkExistingPin() async {
    final user = ref.read(authStateProvider).value;
    if (user == null) return;

    const storage = FlutterSecureStorage();
    final secureKey = '${user.uid}_transaction_pin';

    String? securePin = await storage.read(key: secureKey);

    // Silent migration from legacy plaintext SharedPreferences storage
    if (securePin == null) {
      final prefs = await SharedPreferences.getInstance();
      final legacyPin = prefs.getString('transaction_pin');
      if (legacyPin != null) {
        await storage.write(key: secureKey, value: legacyPin);
        await prefs.remove('transaction_pin');
        securePin = legacyPin;
      }
    }

    final userProfile = ref.read(userProfileProvider).value;

    if (!mounted) return;
    setState(() {
      _hasExistingPin =
          securePin != null || (userProfile?.hasTransactionPin ?? false);
      _needsManualOldPin =
          securePin == null && (userProfile?.hasTransactionPin == true);
    });
  }

  Future<void> _savePin() async {
    if (!_formKey.currentState!.validate()) return;

    final user = ref.read(authStateProvider).value;
    if (user == null) return;

    setState(() => _isLoading = true);

    try {
      const storage = FlutterSecureStorage();
      final secureKey = '${user.uid}_transaction_pin';
      final localOldPin = await storage.read(key: secureKey);
      final finalOldPin =
          _needsManualOldPin ? _oldPinCtrl.text : localOldPin;

      final callable =
          FirebaseFunctions.instance.httpsCallable('setTransactionPin');
      await callable.call({
        'pin': _pinCtrl.text,
        'oldPin': finalOldPin,
      });

      // Only persist locally after backend confirms
      await storage.write(key: secureKey, value: _pinCtrl.text);

      if (!mounted) return;
      GkToast.show(context,
          message: 'Transaction PIN saved successfully ✓',
          type: ToastType.success);
      context.pop();
    } catch (e) {
      if (!mounted) return;
      String errorMsg = 'An unexpected error occurred. Please try again.';
      if (e is FirebaseFunctionsException) {
        errorMsg = e.message ?? 'Server rejected PIN change.';
      }
      GkToast.show(context, message: errorMsg, type: ToastType.error);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ── Shared PIN input field builder ──────────────────────────────────────
  Widget _buildPinField({
    required TextEditingController controller,
    required String label,
    required bool obscure,
    required VoidCallback onToggleObscure,
    required String? Function(String?) validator,
    String hintText = '● ● ● ●',
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.onSurfaceVariant,
                letterSpacing: 0.2,
              ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          keyboardType: TextInputType.number,
          obscureText: obscure,
          obscuringCharacter: '●',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontSize: 28,
                letterSpacing: 20,
                fontWeight: FontWeight.w800,
                color: AppColors.onSurface,
              ),
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(4),
          ],
          decoration: InputDecoration(
            hintText: hintText,
            hintStyle: TextStyle(
              fontSize: 16,
              letterSpacing: 12,
              color: AppColors.onSurfaceVariant.withValues(alpha: 0.4),
            ),
            suffixIcon: IconButton(
              icon: Icon(
                obscure
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
                size: 20,
                color: AppColors.onSurfaceVariant,
              ),
              onPressed: onToggleObscure,
            ),
            filled: true,
            fillColor: AppColors.surfaceContainerLowest,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(
                color: AppColors.outlineVariant.withValues(alpha: 0.5),
                width: 1.5,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide:
                  const BorderSide(color: AppColors.primary, width: 2),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: AppColors.error, width: 1.5),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: AppColors.error, width: 2),
            ),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
          ),
          validator: validator,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: Text(
          'Transaction PIN',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppColors.onSurface,
              ),
        ),
        backgroundColor: AppColors.surface,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          color: AppColors.onSurface,
          onPressed: () => context.pop(),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header ──────────────────────────────────────────────────
              Text(
                _hasExistingPin ? 'Update Your PIN' : 'Set a Security PIN',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: AppColors.onSurface,
                    ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Your 4-digit Transaction PIN authorises plan purchases, card creation, and transfers. Keep it secret.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontSize: 14,
                      color: AppColors.onSurfaceVariant,
                      height: 1.5,
                    ),
              ),
              const SizedBox(height: 32),

              // ── Security info banner ─────────────────────────────────────
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppColors.primary.withValues(alpha: 0.15),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.shield_rounded,
                        color: AppColors.primary, size: 22),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Your PIN is cryptographically hashed on the server and never stored in plain text.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              fontSize: 13,
                              color: AppColors.primary,
                              height: 1.4,
                            ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),

              // ── Old PIN field (only when user has a server PIN but no local copy) ──
              if (_needsManualOldPin) ...[
                _buildPinField(
                  controller: _oldPinCtrl,
                  label: 'Current PIN',
                  obscure: _obscureOld,
                  onToggleObscure: () =>
                      setState(() => _obscureOld = !_obscureOld),
                  validator: (v) {
                    if (v == null || v.isEmpty || v.length != 4) {
                      return 'Enter your current 4-digit PIN';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 20),
              ],

              // ── New PIN ──────────────────────────────────────────────────
              _buildPinField(
                controller: _pinCtrl,
                label: _hasExistingPin ? 'New PIN' : 'PIN',
                obscure: _obscureNew,
                onToggleObscure: () =>
                    setState(() => _obscureNew = !_obscureNew),
                validator: (v) {
                  if (v == null || v.length != 4) {
                    return 'PIN must be exactly 4 digits';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 20),

              // ── Confirm PIN ──────────────────────────────────────────────
              _buildPinField(
                controller: _confirmPinCtrl,
                label: 'Confirm PIN',
                obscure: _obscureConfirm,
                onToggleObscure: () =>
                    setState(() => _obscureConfirm = !_obscureConfirm),
                validator: (v) {
                  if (v == null || v.length != 4) {
                    return 'Please confirm your 4-digit PIN';
                  }
                  if (v != _pinCtrl.text) {
                    return 'PINs do not match';
                  }
                  return null;
                },
              ),
            ],
          ),
        ),
      ),

      // ── Bottom save button — properly constrained ────────────────────────
      bottomNavigationBar: Container(
        color: AppColors.surface,
        padding: EdgeInsets.fromLTRB(24, 12, 24, bottomPad + 16),
        child: SizedBox(
          height: 56,
          width: double.infinity,
          child: FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              textStyle: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.2,
              ),
            ),
            onPressed: _isLoading ? null : _savePin,
            child: _isLoading
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: Colors.white,
                    ),
                  )
                : Text(_hasExistingPin ? 'Update PIN' : 'Save PIN'),
          ),
        ),
      ),
    );
  }
}
