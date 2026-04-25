import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:gatekipa/features/auth/providers/auth_provider.dart';
import 'package:gatekipa/core/theme/app_colors.dart';
import 'package:gatekipa/core/widgets/gk_button.dart';
import 'package:gatekipa/core/widgets/gk_toast.dart';
import 'package:gatekipa/core/theme/app_spacing.dart';

class PinManagementScreen extends ConsumerStatefulWidget {
  const PinManagementScreen({super.key});

  @override
  ConsumerState<PinManagementScreen> createState() => _PinManagementScreenState();
}

class _PinManagementScreenState extends ConsumerState<PinManagementScreen> {
  final _formKey = GlobalKey<FormState>();
  final _pinCtrl = TextEditingController();
  final _oldPinCtrl = TextEditingController();
  bool _isLoading = false;
  bool _hasExistingPin = false;
  bool _needsManualOldPin = false;

  @override
  void initState() {
    super.initState();
    _checkExistingPin();
  }

  Future<void> _checkExistingPin() async {
    final user = ref.read(authStateProvider).value;
    if (user == null) return;

    const storage = FlutterSecureStorage();
    final secureKey = '${user.uid}_transaction_pin';
    
    String? securePin = await storage.read(key: secureKey);
    
    // Silent migration from plaintext to encrypted storage
    if (securePin == null) {
      final prefs = await SharedPreferences.getInstance();
      final legacyPin = prefs.getString('transaction_pin');
      if (legacyPin != null) {
        await storage.write(key: secureKey, value: legacyPin);
        await prefs.remove('transaction_pin'); // Destroy plaintext
        securePin = legacyPin;
      }
    }

    final userProfile = ref.read(userProfileProvider).value;

    setState(() {
      _hasExistingPin = securePin != null || (userProfile?.hasTransactionPin ?? false);
      _needsManualOldPin = securePin == null && (userProfile?.hasTransactionPin == true);
    });
  }

  @override
  void dispose() {
    _pinCtrl.dispose();
    _oldPinCtrl.dispose();
    super.dispose();
  }

  Future<void> _savePin() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    final user = ref.read(authStateProvider).value;
    if (user == null) return;
    
    try {
      const storage = FlutterSecureStorage();
      final secureKey = '${user.uid}_transaction_pin';
      final localOldPin = await storage.read(key: secureKey);
      final finalOldPin = _needsManualOldPin ? _oldPinCtrl.text : localOldPin;
      
      // Sync cryptographically to the backend
      final callable = FirebaseFunctions.instance.httpsCallable('setTransactionPin');
      await callable.call({
        'pin': _pinCtrl.text,
        'oldPin': finalOldPin, // Will be null if on a new device and no backend PIN
      });
      
      // Update local hardware storage only if backend accepts it
      await storage.write(key: secureKey, value: _pinCtrl.text);

      if (!mounted) return;
      GkToast.show(context, message: 'PIN configured securely', type: ToastType.success);
      context.pop();
    } catch (e) {
      if (!mounted) return;
      String errorMsg = "An error occurred.";
      if (e is FirebaseFunctionsException) {
        errorMsg = e.message ?? "Server rejected PIN change.";
      }
      GkToast.show(context, message: errorMsg, type: ToastType.error);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: Text(
          'Transaction PIN',
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
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: AppSpacing.md),
              Text(
                _hasExistingPin ? 'Update Security PIN' : 'Set Security PIN',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: AppColors.onSurface,),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'This 4-digit PIN protects your virtual cards, wire transfers, and account settings.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 15,
                  color: AppColors.onSurfaceVariant,
                  height: 1.5,),
              ),
              const SizedBox(height: 36),
              
              if (_needsManualOldPin) ...[
                Text(
                  'Current PIN',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.onSurfaceVariant,),
                ),
                const SizedBox(height: AppSpacing.xs),
                TextFormField(
                  controller: _oldPinCtrl,
                  keyboardType: TextInputType.number,
                  obscureText: true,
                  obscuringCharacter: '●',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(fontSize: 24,
                    letterSpacing: 16,
                    fontWeight: FontWeight.w800,),
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(4),
                  ],
                  decoration: InputDecoration(
                    hintText: '●●●●',
                    hintStyle: const TextStyle(height: 1.2, fontFamily: 'Manrope', letterSpacing: 16),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: const BorderSide(color: AppColors.outline, width: 1.5),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: const BorderSide(color: AppColors.primary, width: 2),
                    ),
                    filled: true,
                    fillColor: AppColors.surface,
                    contentPadding: const EdgeInsets.symmetric(vertical: 20),
                  ),
                  validator: (v) {
                    if (v == null || v.isEmpty || v.length != 4) return 'Enter your current 4-digit PIN';
                    return null;
                  },
                ),
                const SizedBox(height: 24),
              ],
              
              Text(
                'New PIN',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.onSurfaceVariant,),
              ),
              const SizedBox(height: AppSpacing.xs),
              TextFormField(
                controller: _pinCtrl,
                keyboardType: TextInputType.number,
                obscureText: true,
                obscuringCharacter: '●',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontSize: 24,
                  letterSpacing: 16,
                  fontWeight: FontWeight.w800,),
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(4),
                ],
                decoration: InputDecoration(
                  hintText: '●●●●',
                  hintStyle: const TextStyle(height: 1.2, fontFamily: 'Manrope', letterSpacing: 16),
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
                  if (v == null || v.length != 4) {
                    return 'PIN must be exactly 4 digits';
                  }
                  return null;
                },
              ),
              const SizedBox(height: AppSpacing.lg),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.shield_rounded, color: AppColors.primary, size: 20),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        'Your PIN is securely hashed and never stored locally in plain text.',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 13,
                          color: AppColors.primary,
                          height: 1.4,),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: Container(
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
          label: 'Save PIN',
          isLoading: _isLoading,
          onPressed: _savePin,
        ),
      ),
    );
  }
}
