import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gatekipa/features/auth/providers/auth_provider.dart';
import 'package:gatekipa/core/theme/app_colors.dart';
import 'package:gatekipa/core/widgets/gk_toast.dart';
import 'package:gatekipa/core/theme/app_spacing.dart';

class BiometricsScreen extends ConsumerStatefulWidget {
  const BiometricsScreen({super.key});

  @override
  ConsumerState<BiometricsScreen> createState() => _BiometricsScreenState();
}

class _BiometricsScreenState extends ConsumerState<BiometricsScreen> {
  bool _useBiometrics = false;
  bool _isLoading = true;
  final _localAuth = LocalAuthentication();

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final user = ref.read(authStateProvider).value;
    if (user == null) return;
    
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _useBiometrics = prefs.getBool('${user.uid}_use_biometrics') ?? false;
      _isLoading = false;
    });
  }

  Future<void> _toggleBiometrics(bool value) async {
    if (value) {
      // Verify device supports biometrics before enabling
      try {
        final canCheck = await _localAuth.canCheckBiometrics;
        final isDeviceSupported = await _localAuth.isDeviceSupported();
        if (!canCheck || !isDeviceSupported) {
          if (mounted) {
            GkToast.show(context,
                message: 'Biometrics not available on this device',
                type: ToastType.error);
          }
          return;
        }
        final authenticated = await _localAuth.authenticate(
          localizedReason: 'Verify your identity to enable biometric login',
          options: const AuthenticationOptions(
            stickyAuth: true,
            biometricOnly: false,
          ),
        );
        if (!authenticated) {
          if (mounted) {
            GkToast.show(context,
                message: 'Biometric verification failed',
                type: ToastType.error);
          }
          return;
        }
      } catch (e) {
        if (mounted) {
          GkToast.show(context,
              message: 'Biometrics unavailable: ${e.toString()}',
              type: ToastType.error);
        }
        return;
      }
    }

    final user = ref.read(authStateProvider).value;
    if (user != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('${user.uid}_use_biometrics', value);
    }
    if (mounted) {
      setState(() => _useBiometrics = value);
      GkToast.show(context,
          message: value
              ? 'Biometric login enabled'
              : 'Biometric login disabled',
          type: ToastType.success);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: AppColors.surface,
        body: Center(child: CircularProgressIndicator(color: AppColors.primary)),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: Text(
          'Biometrics',
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
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.fingerprint_rounded,
                  size: 64,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              Text(
                'Hardware Security',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: AppColors.onSurface,),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Use your device\'s FaceID or Fingerprint scanner to securely unlock and authorize transactions in Gatekipa.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 15,
                  color: AppColors.onSurfaceVariant,
                  height: 1.5,),
              ),
              const SizedBox(height: 36),
              Container(
                decoration: BoxDecoration(
                  color: AppColors.surfaceBright,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: AppColors.outlineVariant.withValues(alpha: 0.3),
                  ),
                ),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  title: Text(
                    'Enable Biometric Login',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppColors.onSurface,),
                  ),
                  subtitle: Text(
                    'Bypass PIN entry for faster access',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 13,
                      color: AppColors.onSurfaceVariant,),
                  ),
                  trailing: Switch(
                    value: _useBiometrics,
                    thumbIcon: WidgetStateProperty.resolveWith<Icon?>((Set<WidgetState> states) {
                      if (states.contains(WidgetState.selected)) {
                        return const Icon(Icons.check, color: AppColors.primary);
                      }
                      return const Icon(Icons.close, color: AppColors.surface);
                    }),
                    onChanged: _toggleBiometrics,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
