import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:gatekipa/core/constants/app_constants.dart';
import 'package:gatekipa/core/theme/app_colors.dart';
import 'package:gatekipa/core/widgets/gk_toast.dart';
import 'package:gatekipa/features/auth/providers/auth_provider.dart';
import 'package:gatekipa/core/theme/app_spacing.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _biometrics = false;
  bool _biometricsLoading = true;
  String _language = 'English';
  final _localAuth = LocalAuthentication();
  bool _pushLoading = false;
  bool _languageLoading = false;
  bool _spendingLockLoading = false;
  bool _autoDeductionsLoading = false;

  @override
  void initState() {
    super.initState();
    _loadBiometricPref();
  }

  Future<void> _loadBiometricPref() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      setState(() => _biometricsLoading = false);
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    final savedLang = prefs.getString('${uid}_language') ?? 'English';
    setState(() {
      _biometrics = prefs.getBool('${uid}_use_biometrics') ?? false;
      _language = savedLang;
      _biometricsLoading = false;
    });
  }

  Future<void> _toggleBiometrics(bool value) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    if (value) {
      // Verify device supports biometrics first
      try {
        final canCheck = await _localAuth.canCheckBiometrics;
        final isSupported = await _localAuth.isDeviceSupported();
        if (!canCheck && !isSupported) {
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
              message: 'Biometrics are not set up on this device. Please enable Face ID or Fingerprint in your device settings.',
              type: ToastType.error);
        }
        return;
      }
    }

    // Persist the preference
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('${uid}_use_biometrics', value);

    if (mounted) {
      setState(() => _biometrics = value);
      GkToast.show(
        context,
        message: value ? 'Biometric login enabled' : 'Biometric login disabled',
        type: ToastType.success,
      );
    }
  }

  Future<void> _togglePushNotifications(bool value) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    setState(() => _pushLoading = true);
    try {
      await FirebaseFirestore.instance
          .collection(AppConstants.usersCollection)
          .doc(uid)
          .update({'blockAlerts': !value});
      if (mounted) {
        GkToast.show(context,
            message: value ? 'Push notifications enabled' : 'Push notifications disabled',
            type: ToastType.success);
      }
    } catch (e) {
      if (mounted) {
        GkToast.show(context,
            message: 'Failed to update notification preference',
            type: ToastType.error);
      }
    } finally {
      if (mounted) setState(() => _pushLoading = false);
    }
  }

  Future<void> _toggleAutoDeductions(bool value) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    setState(() => _autoDeductionsLoading = true);
    try {
      await FirebaseFirestore.instance
          .collection(AppConstants.usersCollection)
          .doc(uid)
          .update({'allow_auto_deductions': value});
      if (mounted) {
        GkToast.show(context,
            message: value ? 'Auto-deductions enabled' : 'Auto-deductions disabled',
            type: ToastType.success);
      }
    } catch (e) {
      if (mounted) {
        GkToast.show(context,
            message: 'Failed to update auto-deductions preference',
            type: ToastType.error);
      }
    } finally {
      if (mounted) setState(() => _autoDeductionsLoading = false);
    }
  }

  /// Shows a PIN dialog and returns the entered PIN, or null if dismissed.
  Future<String?> _promptPin() async {
    final pinCtrl = TextEditingController();
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.lock_rounded, color: AppColors.primary, size: 18),
            ),
            const SizedBox(width: 12),
            const Text('Enter PIN', style: TextStyle(fontFamily: 'Manrope', fontWeight: FontWeight.w800, fontSize: 18)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Enter your transaction PIN to change the Spending Lock.',
                style: TextStyle(fontSize: 13, color: Colors.grey)),
            const SizedBox(height: 16),
            TextField(
              controller: pinCtrl,
              obscureText: true,
              keyboardType: TextInputType.number,
              maxLength: 6,
              autofocus: true,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, letterSpacing: 8),
              decoration: InputDecoration(
                counterText: '',
                hintText: '······',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppColors.primary, width: 2),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, null), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, pinCtrl.text.trim()),
            style: FilledButton.styleFrom(backgroundColor: AppColors.primary, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
  }

  Future<void> _toggleSpendingLock(bool lock) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    // Always require PIN before changing the lock state
    final pin = await _promptPin();
    if (pin == null || pin.isEmpty) return;

    setState(() => _spendingLockLoading = true);
    try {
      final fn = FirebaseFunctions.instance.httpsCallable('toggleSpendingLock');
      await fn.call({'lock': lock, 'pin': pin});
      if (mounted) {
        GkToast.show(
          context,
          message: lock
              ? '🔒 Spending Lock enabled — transactions blocked'
              : '🔓 Spending Lock disabled — transactions allowed',
          type: lock ? ToastType.warning : ToastType.success,
          duration: const Duration(seconds: 4),
        );
      }
    } on FirebaseFunctionsException catch (e) {
      if (mounted) {
        GkToast.show(context,
            message: e.message ?? 'Failed to update Spending Lock',
            type: ToastType.error);
      }
    } catch (e) {
      if (mounted) {
        GkToast.show(context, message: 'An error occurred. Please try again.', type: ToastType.error);
      }
    } finally {
      if (mounted) setState(() => _spendingLockLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: Text(
          'Settings',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800, color: AppColors.primary),
        ),
        leading: const BackButton(color: AppColors.onSurface),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 140),
        child: Consumer(
          builder: (context, ref, _) {
            final user = ref.watch(userProfileProvider).valueOrNull;
            // blockAlerts = true means notifications are OFF
            final pushEnabled = !(user?.blockAlerts ?? false);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Section(title: 'PREFERENCES', items: [
                  _DropdownItem(
                    icon: Icons.language_rounded,
                    label: 'Language',
                    value: _language,
                    options: const ['English', 'Yoruba', 'Hausa', 'Igbo'],
                    onChanged: _languageLoading
                        ? null
                        : (v) async {
                            if (v == null || v == _language) return;
                            final uid = FirebaseAuth.instance.currentUser?.uid;
                            if (uid == null) return;
                            setState(() {
                              _language = v;
                              _languageLoading = true;
                            });
                            try {
                              final prefs = await SharedPreferences.getInstance();
                              await prefs.setString('${uid}_language', v);
                              await FirebaseFirestore.instance
                                  .collection(AppConstants.usersCollection)
                                  .doc(uid)
                                  .set({'preferredLanguage': v}, SetOptions(merge: true));
                            } finally {
                              if (mounted) setState(() => _languageLoading = false);
                            }
                          },
                  ),
                ]),
                const SizedBox(height: 20),
                _Section(title: 'NOTIFICATIONS', items: [
                  _ToggleItem(
                    icon: Icons.notifications_rounded,
                    label: 'Push Notifications',
                    sub: _pushLoading ? 'Updating...' : (pushEnabled ? 'Receive alerts for blocked charges' : 'Notifications are off'),
                    value: pushEnabled,
                    onChanged: _pushLoading ? (_) {} : _togglePushNotifications,
                  ),
                ]),
                const SizedBox(height: 20),

                // ── Spending Lock ────────────────────────────────────────────
                Builder(builder: (context) {
                  final isLocked = user?.spendingLock ?? false;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Warning banner when locked
                      if (isLocked)
                        Container(
                          width: double.infinity,
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFF3CD),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: const Color(0xFFFFC107), width: 1.5),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.warning_amber_rounded, color: Color(0xFFB45309), size: 18),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'Spending Lock is ON — all card & wallet payments are blocked.',
                                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    fontSize: 12, color: const Color(0xFF92400E), fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      _Section(title: 'WALLET SECURITY', items: [
                        _SpendingLockItem(
                          isLocked: isLocked,
                          isLoading: _spendingLockLoading,
                          onChanged: _spendingLockLoading ? (_) {} : _toggleSpendingLock,
                        ),
                        _ToggleItem(
                          icon: Icons.payments_rounded,
                          label: 'Allow Auto Deductions',
                          sub: _autoDeductionsLoading
                              ? 'Updating...'
                              : (user?.allowAutoDeductions ?? false
                                  ? 'Gatekipa can automatically deduct fees'
                                  : 'Auto-deductions are disabled'),
                          value: user?.allowAutoDeductions ?? false,
                          onChanged: _autoDeductionsLoading ? (_) {} : _toggleAutoDeductions,
                        ),
                      ]),
                    ],
                  );
                }),
                const SizedBox(height: 20),
                _Section(title: 'SECURITY', items: [
                  _biometricsLoading
                      ? const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 18),
                          child: LinearProgressIndicator(
                            color: AppColors.primary,
                            backgroundColor: AppColors.surfaceBright,
                          ),
                        )
                      : _ToggleItem(
                          icon: Icons.fingerprint_rounded,
                          label: 'Biometric Lock',
                          sub: _biometrics
                              ? 'Active — secures your app on launch'
                              : 'Tap to enable Face ID / Fingerprint',
                          value: _biometrics,
                          onChanged: _toggleBiometrics,
                        ),
                ]),
                const SizedBox(height: 20),
                const _Section(title: 'LEGAL', items: [
                  _LinkItem(
                    icon: Icons.privacy_tip_rounded,
                    label: 'Privacy Policy',
                    url: 'https://gatekipa.com/privacy',
                  ),
                  _LinkItem(
                    icon: Icons.article_rounded,
                    label: 'Terms of Service',
                    url: 'https://gatekipa.com/terms',
                  ),
                  _LinkItem(
                    icon: Icons.help_outline_rounded,
                    label: 'Help & Support',
                    url: 'mailto:hello@gatekipa.com',
                  ),
                ]),
                const SizedBox(height: 40),
                Center(
                  child: Text(
                    '${AppConstants.appName} — Built with ❤️ in Nigeria',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 11, color: AppColors.outline),
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final List<Widget> items;
  const _Section({required this.title, required this.items});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(
            children: [
              Container(
                width: 3,
                height: 14,
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(100),
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Text(
                title,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppColors.onSurfaceVariant,
                  letterSpacing: 1.2,),
              ),
            ],
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: AppColors.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
                color: AppColors.outlineVariant.withValues(alpha: 0.4)),
          ),
          child: Column(
            children: items.asMap().entries.map((e) {
              final isLast = e.key == items.length - 1;
              return Column(
                children: [
                  e.value,
                  if (!isLast)
                    const Divider(
                        height: 1,
                        indent: 72,
                        color: AppColors.outlineVariant),
                ],
              );
            }).toList(),
          ),
        ),
      ],
    );
  }
}

class _ToggleItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? sub;
  final bool value;
  final ValueChanged<bool>? onChanged; // nullable — null = disabled

  const _ToggleItem({
    required this.icon,
    required this.label,
    required this.value,
    this.onChanged,
    this.sub,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: AppColors.primary, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600, fontSize: 14)),
                if (sub != null)
                  Text(sub!,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 11, color: AppColors.outline)),
              ],
            ),
          ),
          Switch(
            value: value,
            thumbIcon: WidgetStateProperty.resolveWith<Icon?>((Set<WidgetState> states) {
              if (states.contains(WidgetState.selected)) {
                return const Icon(Icons.check, color: AppColors.primary);
              }
              return const Icon(Icons.close, color: AppColors.surface);
            }),
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

class _DropdownItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final List<String> options;
  final ValueChanged<String?>? onChanged; // nullable — null = disabled

  const _DropdownItem({
    required this.icon,
    required this.label,
    required this.value,
    required this.options,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: AppColors.primary, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(label,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600, fontSize: 14)),
          ),
          DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: value,
              isDense: true,
              items: options
                  .map((o) => DropdownMenuItem(
                        value: o,
                        child: Text(o,
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 14)),
                      ))
                  .toList(),
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }
}

class _LinkItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String url;
  const _LinkItem({required this.icon, required this.label, required this.url});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: () async {
        final Uri uri = Uri.parse(url);
        if (!await launchUrl(uri)) {
          debugPrint('Could not launch $url');
        }
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: AppColors.primary, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(label,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600, fontSize: 14)),
            ),
            const Icon(Icons.chevron_right_rounded,
                color: AppColors.outline, size: 20),
          ],
        ),
      ),
    );
  }
}

// ── Spending Lock widget ───────────────────────────────────────────────────────
class _SpendingLockItem extends StatelessWidget {
  final bool isLocked;
  final bool isLoading;
  final ValueChanged<bool> onChanged;

  const _SpendingLockItem({
    required this.isLocked,
    required this.isLoading,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final lockColor = isLocked ? const Color(0xFFDC2626) : const Color(0xFF16A34A);
    final lockBg = isLocked
        ? const Color(0xFFDC2626).withValues(alpha: 0.1)
        : AppColors.primary.withValues(alpha: 0.1);
    final lockIcon = isLocked ? Icons.lock_rounded : Icons.lock_open_rounded;
    final sub = isLocked
        ? 'All card & wallet payments are BLOCKED'
        : 'Payments are allowed — tap to lock';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: lockBg,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(lockIcon, color: lockColor, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Spending Lock',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: isLocked ? const Color(0xFFDC2626) : null,
                  ),
                ),
                Text(
                  sub,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontSize: 11,
                    color: isLocked ? const Color(0xFFDC2626).withValues(alpha: 0.8) : AppColors.outline,
                  ),
                ),
              ],
            ),
          ),
          if (isLoading)
            const SizedBox(
              width: 32,
              height: 32,
              child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
            )
          else
            Switch(
              value: isLocked,
              activeThumbColor: const Color(0xFFDC2626),
              thumbIcon: WidgetStateProperty.resolveWith<Icon?>((Set<WidgetState> states) {
                if (states.contains(WidgetState.selected)) {
                  return const Icon(Icons.lock_rounded, color: Colors.white, size: 14);
                }
                return const Icon(Icons.lock_open_rounded, color: AppColors.surface, size: 14);
              }),
              onChanged: onChanged,
            ),
        ],
      ),
    );
  }
}
