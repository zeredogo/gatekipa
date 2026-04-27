import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:gatekipa/core/constants/app_constants.dart';
import 'package:gatekipa/core/constants/routes.dart';
import 'package:gatekipa/core/theme/app_colors.dart';
import 'package:gatekipa/core/widgets/gk_button.dart';
import 'package:gatekipa/core/widgets/gk_toast.dart';
import 'package:gatekipa/features/auth/providers/auth_provider.dart';
import 'package:gatekipa/features/auth/models/user_model.dart';
import 'package:gatekipa/core/theme/app_spacing.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  /// Returns true if biometric login is enabled for the current user.
  Future<bool> _isBiometricEnabled() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return false;
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('${uid}_use_biometrics') ?? false;
  }

  /// Locks the app (keeps Firebase session for biometric re-entry) or
  Future<void> _handleSignOut(BuildContext context, WidgetRef ref) async {
    final biometricEnabled = await _isBiometricEnabled();
    if (biometricEnabled) {
      await ref.read(authNotifierProvider.notifier).lockApp();
    } else {
      await ref.read(authNotifierProvider.notifier).signOut();
    }
    if (context.mounted) context.go(Routes.emailAuth);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userAsync = ref.watch(userProfileProvider);

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: Text(
          'Profile',
          style: Theme.of(context)
              .textTheme
              .titleMedium
              ?.copyWith(fontWeight: FontWeight.w800, color: AppColors.primary),
        ),
        leading: const BackButton(color: AppColors.onSurface),
        actions: [
          TextButton(
            onPressed: () => _handleSignOut(context, ref),
            child: const Text(
              'Sign Out',
              style: TextStyle(
                height: 1.2,
                fontFamily: 'Manrope',
                color: AppColors.error,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
      body: userAsync.when(
        data: (user) => RefreshIndicator(
          color: AppColors.primary,
          onRefresh: () async {
            ref.invalidate(userProfileProvider);
            await Future.delayed(const Duration(milliseconds: 500));
          },
          child: SingleChildScrollView(
            child: Column(
              children: [
                // ── Hero Banner ──────────────────────────────────────────
                Container(
                  width: double.infinity,
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [AppColors.primary, Color(0xFF004D2C)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  padding: const EdgeInsets.fromLTRB(24, 32, 24, 32),
                  child: Column(
                    children: [
                      // Avatar
                      Container(
                        width: 86,
                        height: 86,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(26),
                          border: Border.all(
                              color: Colors.white.withValues(alpha: 0.3),
                              width: 2),
                        ),
                        child: Center(
                          child: Text(
                            user?.displayName?.isNotEmpty == true
                                ? user!.displayName![0].toUpperCase()
                                : 'G',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(
                                  color: Colors.white,
                                  fontSize: 36,
                                  fontWeight: FontWeight.w800,
                                ),
                          ),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      Text(
                        user?.displayName ?? 'Gatekipa User',
                        style:
                            Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                ),
                      ),
                      const SizedBox(height: AppSpacing.xxs),
                      Text(
                        FirebaseAuth.instance.currentUser?.phoneNumber ??
                            FirebaseAuth.instance.currentUser?.email ??
                            '',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: Colors.white.withValues(alpha: 0.75),
                              fontSize: 14,
                            ),
                      ),
                      const SizedBox(height: 14),
                      // Plan badge
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 6),
                        decoration: BoxDecoration(
                          gradient: user?.isSentinelPrime == true
                              ? const LinearGradient(
                                  colors: [
                                    Color(0xFFFFD700),
                                    Color(0xFFFFA500)
                                  ],
                                )
                              : null,
                          color: user?.isSentinelPrime != true
                              ? Colors.white.withValues(alpha: 0.15)
                              : null,
                          borderRadius: BorderRadius.circular(100),
                        ),
                        child: Text(
                          // FIX #5: Show correct plan name per tier, not always 'Instant Plan'.
                          user?.isSentinelPrime == true
                              ? (user!.isTrialActive
                                  ? '⚡ Trial Active'
                                  : '✦ Sentinel Prime')
                              : switch (user?.planTier) {
                                  'business' => '🏢 Business Plan',
                                  'premium' => '✦ Sentinel Prime',
                                  'activation' => '🔓 Activation Plan',
                                  'free' => '⚡ Instant Plan',
                                  // FIX: 'none' is the downgraded state after expiry. Show a
                                  // clear prompt rather than the misleading "Basic Plan" label.
                                  'none' || null => '📭 No Active Plan',
                                  _ => '🔓 Basic Plan',
                                },
                          style:
                              Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                  ),
                        ),
                      ),
                    ],
                  ),
                ).animate().fadeIn(),
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Personal Information
                      _SettingsSection(title: 'Personal Info', items: [
                        _SettingsItem(
                          icon: Icons.person_outline_rounded,
                          label: 'Update Profile',
                          trailing: const Icon(Icons.chevron_right_rounded,
                              color: AppColors.outline),
                          onTap: () {
                            if (user != null) {
                              _showUpdateProfileSheet(context, ref, user);
                            }
                          },
                        ),
                      ]),
                      const SizedBox(height: 20),
                      // KYC Status
                      _SettingsSection(title: 'Identity', items: [
                        _SettingsItem(
                          icon: Icons.badge_rounded,
                          label: 'Government Issued ID',
                          trailing:
                              _KycBadge(status: user?.kycStatus ?? 'pending'),
                          onTap: () {
                            if (user?.kycStatus == 'approved' || user?.kycStatus == 'verified') {
                              GkToast.show(context, message: 'Your identity is already verified.', type: ToastType.success);
                            } else {
                              context.push(Routes.kyc);
                            }
                          },
                        ),
                      ]),
                      const SizedBox(height: 20),
                      // Security
                      _SettingsSection(title: 'Security', items: [
                        _SettingsItem(
                          icon: Icons.fingerprint_rounded,
                          label: 'Biometrics',
                          trailing: const Icon(Icons.chevron_right_rounded,
                              color: AppColors.outline),
                          onTap: () => context.push(Routes.biometrics),
                        ),
                        _SettingsItem(
                          icon: Icons.key_rounded,
                          label: 'PIN Management',
                          trailing: const Icon(Icons.chevron_right_rounded,
                              color: AppColors.outline),
                          onTap: () => context.push(Routes.pinManagement),
                        ),
                      ]),
                      const SizedBox(height: 20),
                      // Preferences & Settings
                      _SettingsSection(title: 'Preferences & Settings', items: [
                        _SettingsItem(
                          icon: Icons.settings_rounded,
                          label: 'App Settings & Notifications',
                          trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.outline),
                          onTap: () => context.push(Routes.settings),
                        ),
                      ]),
                      const SizedBox(height: 20),
                      // Premium upgrade
                      if (user?.isSentinelPrime != true) ...[
                        _SettingsSection(title: 'Subscription', items: [
                          _SettingsItem(
                            icon: Icons.workspace_premium_rounded,
                            label: 'Upgrade to Sentinel Prime',
                            iconColor: const Color(0xFFFFD700),
                            trailing: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFD700)
                                    .withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(100),
                              ),
                              child: Text(
                                AppConstants.premiumPriceLabel,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyMedium
                                    ?.copyWith(
                                      color: const Color(0xFFFF8C00),
                                      fontWeight: FontWeight.w700,
                                      fontSize: 12,
                                    ),
                              ),
                            ),
                            onTap: () => context.push(Routes.premiumUpgrade),
                          ),
                        ]),
                        const SizedBox(height: 20),
                      ],
                      // Help & Support
                      _SettingsSection(title: 'Support', items: [
                        _SettingsItem(
                          icon: Icons.headset_mic_rounded,
                          label: 'Help & Support',
                          trailing: const Icon(Icons.chevron_right_rounded,
                              color: AppColors.outline),
                          onTap: () => context.push(Routes.support),
                        ),
                      ]),
                      const SizedBox(height: 20),
                      // Danger zone
                      _SettingsSection(title: 'Danger Zone', items: [
                        _SettingsItem(
                          icon: Icons.delete_forever_rounded,
                          label: 'Delete Account',
                          iconColor: AppColors.error,
                          textColor: AppColors.error,
                          trailing: const Icon(Icons.chevron_right_rounded,
                              color: AppColors.outline),
                          onTap: () => _showDeleteDialog(context, ref),
                        ),
                      ]),
                      const SizedBox(height: AppSpacing.xl),
                      // Sign out
                      GkButton(
                        label: 'Sign Out',
                        icon: Icons.logout_rounded,
                        variant: GkButtonVariant.secondary,
                        onPressed: () => _handleSignOut(context, ref),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Center(
                        child: Text(
                          '${AppConstants.appName} • All rights reserved',
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(
                                  fontSize: 11, color: AppColors.outline),
                        ),
                      ),
                      const SizedBox(height: 140),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => const Center(
            child: Text(
                'Could not load your profile. Please pull down to refresh.')),
      ),
    );
  }

  void _showDeleteDialog(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (ctx) => _DeleteAccountDialog(parentRef: ref),
    );
  }
}

class _KycBadge extends StatelessWidget {
  final String status;
  const _KycBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final (color, label) = switch (status) {
      'approved' || 'verified' => (AppColors.tertiary, 'Verified'),
      'pending' => (const Color(0xFFFF6B35), 'Pending'),
      'rejected' => (AppColors.error, 'Rejected'),
      _ => (AppColors.outline, 'Not Done'),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(100),
      ),
      child: Text(
        label,
        style: Theme.of(context)
            .textTheme
            .bodyMedium
            ?.copyWith(fontSize: 12, fontWeight: FontWeight.w700, color: color),
      ),
    );
  }
}

class _SettingsSection extends StatelessWidget {
  final String title;
  final List<_SettingsItem> items;

  const _SettingsSection({required this.title, required this.items});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section label with pill accent
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
                title.toUpperCase(),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppColors.onSurfaceVariant,
                      letterSpacing: 1.2,
                    ),
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
              final item = e.value;
              final isLast = e.key == items.length - 1;
              return Column(
                children: [
                  item,
                  if (!isLast)
                    const Divider(
                        height: 1, indent: 72, color: AppColors.outlineVariant),
                ],
              );
            }).toList(),
          ),
        ),
      ],
    );
  }
}

class _SettingsItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final Widget trailing;
  final VoidCallback onTap;
  final Color? iconColor;
  final Color? textColor;

  const _SettingsItem({
    required this.icon,
    required this.label,
    required this.trailing,
    required this.onTap,
    this.iconColor,
    this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    final icolor = iconColor ?? AppColors.primary;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: icolor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: icolor, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                label,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      color: textColor ?? AppColors.onSurface,
                    ),
              ),
            ),
            trailing,
          ],
        ),
      ),
    );
  }
}

class _UpdateProfileSheet extends ConsumerStatefulWidget {
  final UserModel user;

  const _UpdateProfileSheet({required this.user});

  @override
  ConsumerState<_UpdateProfileSheet> createState() =>
      _UpdateProfileSheetState();
}

class _UpdateProfileSheetState extends ConsumerState<_UpdateProfileSheet> {
  late final TextEditingController _firstNameCtrl;
  late final TextEditingController _lastNameCtrl;
  late final TextEditingController _addressCtrl;
  late final TextEditingController _cityCtrl;
  late final TextEditingController _stateCtrl;
  late final TextEditingController _postalCodeCtrl;
  late final TextEditingController _houseNumberCtrl;
  late final TextEditingController _emailCtrl;
  late final TextEditingController _phoneCtrl;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    final parts = widget.user.displayName?.split(' ') ?? [];
    _firstNameCtrl = TextEditingController(
        text: widget.user.firstName ?? (parts.isNotEmpty ? parts.first : ''));
    _lastNameCtrl = TextEditingController(
        text: widget.user.lastName ??
            (parts.length > 1 ? parts.sublist(1).join(' ') : ''));
    _addressCtrl = TextEditingController(text: widget.user.address ?? '');
    _cityCtrl = TextEditingController(text: widget.user.city ?? '');
    _stateCtrl = TextEditingController(text: widget.user.state ?? '');
    _postalCodeCtrl = TextEditingController(text: widget.user.postalCode ?? '');
    _houseNumberCtrl =
        TextEditingController(text: widget.user.houseNumber ?? '');
    _emailCtrl = TextEditingController(text: widget.user.email ?? '');
    _phoneCtrl = TextEditingController(text: widget.user.phoneNumber ?? '');
  }

  @override
  void dispose() {
    _firstNameCtrl.dispose();
    _lastNameCtrl.dispose();
    _addressCtrl.dispose();
    _cityCtrl.dispose();
    _stateCtrl.dispose();
    _postalCodeCtrl.dispose();
    _houseNumberCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final firstName = _firstNameCtrl.text.trim();
    final lastName = _lastNameCtrl.text.trim();
    final address = _addressCtrl.text.trim();
    final city = _cityCtrl.text.trim();
    final addrState = _stateCtrl.text.trim();
    final postalCode = _postalCodeCtrl.text.trim();
    final houseNumber = _houseNumberCtrl.text.trim();
    final email = _emailCtrl.text.trim();
    final phone = _phoneCtrl.text.trim();

    if (firstName.isEmpty || lastName.isEmpty) {
      GkToast.show(context,
          message: 'First name and last name are required',
          type: ToastType.error);
      return;
    }

    final displayName = '$firstName $lastName';

    setState(() => _isLoading = true);
    try {
      await ref.read(authNotifierProvider.notifier).updateProfile(
        uid: widget.user.uid,
        data: {
          'firstName': firstName,
          'lastName': lastName,
          'displayName': displayName,
          'address': address.isNotEmpty ? address : null,
          'city': city.isNotEmpty ? city : null,
          'state': addrState.isNotEmpty ? addrState : null,
          'postalCode': postalCode.isNotEmpty ? postalCode : null,
          'houseNumber': houseNumber.isNotEmpty ? houseNumber : null,
          'email': email.isNotEmpty ? email : null,
          'phoneNumber': phone.isNotEmpty ? phone : null,
        },
      );
      if (mounted) {
        Navigator.pop(context);
        GkToast.show(context,
            message: 'Profile updated successfully', type: ToastType.success);
      }
    } catch (e) {
      if (mounted) {
        GkToast.show(context,
            message:
                'Could not update your profile. Please check your connection and try again.',
            type: ToastType.error);
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Edit Profile',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontSize: 20, fontWeight: FontWeight.w800)),
                IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.pop(context)),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            TextField(
              controller: _firstNameCtrl,
              decoration: InputDecoration(
                labelText: 'First Name',
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _lastNameCtrl,
              decoration: InputDecoration(
                labelText: 'Last Name',
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _emailCtrl,
              keyboardType: TextInputType.emailAddress,
              decoration: InputDecoration(
                labelText: 'Email Address',
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _phoneCtrl,
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(
                labelText: 'Phone Number',
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _addressCtrl,
              decoration: InputDecoration(
                labelText: 'Street Address',
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _cityCtrl,
                    decoration: InputDecoration(
                      labelText: 'City',
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16)),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: TextField(
                    controller: _stateCtrl,
                    decoration: InputDecoration(
                      labelText: 'State',
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16)),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _houseNumberCtrl,
                    decoration: InputDecoration(
                      labelText: 'House No.',
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16)),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: TextField(
                    controller: _postalCodeCtrl,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: 'Postal Code',
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16)),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xl),
            GkButton(
              label: 'Save Changes',
              isLoading: _isLoading,
              onPressed: _save,
            ),
          ],
        ),
      ),
    );
  }
}

void _showUpdateProfileSheet(
    BuildContext context, WidgetRef ref, UserModel user) {
  showModalBottomSheet(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _UpdateProfileSheet(user: user),
  );
}

// ── Delete Account Dialog ─────────────────────────────────────────────────────
class _DeleteAccountDialog extends ConsumerStatefulWidget {
  final WidgetRef parentRef;
  const _DeleteAccountDialog({required this.parentRef});

  @override
  ConsumerState<_DeleteAccountDialog> createState() =>
      _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends ConsumerState<_DeleteAccountDialog> {
  bool _deleting = false;

  Future<void> _confirmDelete() async {
    setState(() => _deleting = true);
    try {
      await FirebaseFunctions.instance
          .httpsCallable('deleteUserAccount')
          .call({'confirm': true});

      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      // Sign out locally and redirect
      await widget.parentRef.read(authNotifierProvider.notifier).signOut();
      if (mounted) context.go(Routes.emailAuth);
    } on FirebaseFunctionsException {
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        GkToast.show(
          context,
          message:
              'Could not delete your account at this time. Please try again later or contact support.',
          type: ToastType.error,
        );
      }
    } catch (_) {
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        GkToast.show(
          context,
          message: 'An unexpected error occurred. Try again.',
          type: ToastType.error,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      icon: const Icon(Icons.delete_forever_rounded,
          color: AppColors.error, size: 40),
      title: Text('Delete Account?',
          style: Theme.of(context)
              .textTheme
              .titleMedium
              ?.copyWith(fontWeight: FontWeight.w800)),
      content: Text(
        'This is permanent and cannot be undone.\n\nAll your cards, rules, wallet balance, and account data will be erased and your account deleted.',
        style: Theme.of(context)
            .textTheme
            .bodyMedium
            ?.copyWith(color: AppColors.onSurfaceVariant, height: 1.5),
      ),
      actions: [
        TextButton(
          onPressed: _deleting ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _deleting ? null : _confirmDelete,
          style: FilledButton.styleFrom(backgroundColor: AppColors.error),
          child: _deleting
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 2),
                )
              : const Text('Delete Everything'),
        ),
      ],
    );
  }
}

