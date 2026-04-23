import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:gatekeepeer/core/constants/app_constants.dart';
import 'package:gatekeepeer/core/theme/app_colors.dart';
import 'package:gatekeepeer/core/widgets/gk_toast.dart';
import 'package:gatekeepeer/features/auth/providers/auth_provider.dart';
import 'package:gatekeepeer/core/theme/app_spacing.dart';

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

  Future<void> _togglePushNotifications(bool value) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    setState(() => _pushLoading = true);
    try {
      // blockAlerts = true means user wants to BLOCK alerts (i.e. push OFF)
      // so pushEnabled = true → blockAlerts = false
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
                _Section(title: 'LEGAL', items: [
                  const _LinkItem(
                    icon: Icons.privacy_tip_rounded,
                    label: 'Privacy Policy',
                    url: 'https://gatekipa.com/privacy',
                  ),
                  const _LinkItem(
                    icon: Icons.article_rounded,
                    label: 'Terms of Service',
                    url: 'https://gatekipa.com/terms',
                  ),
                  _LinkItem(
                    icon: Icons.help_outline_rounded,
                    label: 'Help & Support',
                    url: Uri.dataFromString('''<!DOCTYPE html>
<html>
<head>
<meta name="viewport" content="width=device-width, initial-scale=1">
<style>
  body { font-family: sans-serif; padding: 40px 24px; text-align: center; color: #111827; }
  h2 { color: #027A48; font-weight: 800; margin-bottom: 8px; }
  p { line-height: 1.6; color: #4B5563; margin-top: 0; }
  .box { background: #F9FAFB; border-radius: 16px; padding: 24px; margin-top: 32px; border: 1px solid #E5E7EB; }
  a { color: #027A48; text-decoration: none; font-weight: 700; font-size: 16px; }
</style>
</head>
<body>
  <h2>How can we help?</h2>
  <p>Our support team is always ready to assist you.</p>
  <div class="box">
    <p><b>Email us at:</b><br><a href="mailto:support@gatekeepeer.com">support@gatekeepeer.com</a></p>
    <br>
    <p><b>Call us on:</b><br><a href="tel:+2348000000000">+234 800 GATEKEEPEER</a></p>
  </div>
</body>
</html>''', mimeType: 'text/html').toString(),
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
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => _WebViewScreen(title: label, url: url),
          ),
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

// ── In-App WebView Screen ──────────────────────────────────────────────────────
class _WebViewScreen extends StatefulWidget {
  final String title;
  final String url;
  const _WebViewScreen({required this.title, required this.url});

  @override
  State<_WebViewScreen> createState() => _WebViewScreenState();
}

class _WebViewScreenState extends State<_WebViewScreen> {
  late final WebViewController _controller;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onPageFinished: (_) => setState(() => _isLoading = false),
      ))
      ..loadRequest(Uri.parse(widget.url));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: Text(
          widget.title,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700, color: AppColors.primary),
        ),
        leading: const CloseButton(color: AppColors.onSurface),
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_isLoading)
            const Center(child: CircularProgressIndicator(color: AppColors.primary)),
        ],
      ),
    );
  }
}
