// lib/features/profile/screens/settings_screen.dart
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/gk_toast.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _pushEnabled = true;
  bool _biometrics = false;
  bool _biometricsLoading = true;
  final bool _darkMode = false;
  String _language = 'English';
  final _localAuth = LocalAuthentication();

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
    setState(() {
      _biometrics = prefs.getBool('${uid}_use_biometrics') ?? false;
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
              message: 'Biometrics unavailable: ${e.toString()}',
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: Text(
          'Settings',
          style: GoogleFonts.manrope(
              fontWeight: FontWeight.w800, color: AppColors.primary),
        ),
        leading: const BackButton(color: AppColors.onSurface),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 140),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Section(title: 'PREFERENCES', items: [
              _ToggleItem(
                icon: Icons.dark_mode_rounded,
                label: 'Dark Mode',
                sub: 'Coming soon',
                value: _darkMode,
                onChanged: (_) => GkToast.show(context,
                    message: 'Dark mode coming soon!', type: ToastType.info),
              ),
              _DropdownItem(
                icon: Icons.language_rounded,
                label: 'Language',
                value: _language,
                options: const ['English', 'Yoruba', 'Hausa', 'Igbo'],
                onChanged: (v) => setState(() => _language = v!),
              ),
            ]),
            const SizedBox(height: 20),
            _Section(title: 'NOTIFICATIONS', items: [
              _ToggleItem(
                icon: Icons.notifications_rounded,
                label: 'Push Notifications',
                value: _pushEnabled,
                onChanged: (v) => setState(() => _pushEnabled = v),
              ),
            ]),
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
                url: 'https://gatekipa.com/support',
              ),
            ]),
            const SizedBox(height: 40),
            Center(
              child: Text(
                '${AppConstants.appName} v${AppConstants.appVersion} — Built with ❤️ in Nigeria',
                style:
                    GoogleFonts.inter(fontSize: 11, color: AppColors.outline),
              ),
            ),
            const SizedBox(height: 24),
          ],
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
              const SizedBox(width: 8),
              Text(
                title,
                style: GoogleFonts.inter(
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
  final ValueChanged<bool> onChanged;

  const _ToggleItem({
    required this.icon,
    required this.label,
    required this.value,
    required this.onChanged,
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
                    style: GoogleFonts.inter(
                        fontWeight: FontWeight.w600, fontSize: 14)),
                if (sub != null)
                  Text(sub!,
                      style: GoogleFonts.inter(
                          fontSize: 11, color: AppColors.outline)),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: AppColors.primary,
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
  final ValueChanged<String?> onChanged;

  const _DropdownItem({
    required this.icon,
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
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
                style: GoogleFonts.inter(
                    fontWeight: FontWeight.w600, fontSize: 14)),
          ),
          DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: value,
              isDense: true,
              items: options
                  .map((o) => DropdownMenuItem(
                        value: o,
                        child: Text(o,
                            style: GoogleFonts.inter(fontSize: 14)),
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
      onTap: () {
        // Show a coming-soon notice until the pages are live
        GkToast.show(
          context,
          message: '$label will be available at launch',
          type: ToastType.info,
        );
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
                  style: GoogleFonts.inter(
                      fontWeight: FontWeight.w600, fontSize: 14)),
            ),
            const Icon(Icons.chevron_right_rounded,
                color: AppColors.outline, size: 20),
          ],
        ),
      ),
    );
  }
}
