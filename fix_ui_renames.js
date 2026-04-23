const fs = require('fs');
const path = './lib/features/cards/screens/card_creation_screen.dart';

let content = fs.readFileSync(path, 'utf8');

// Replace Sentinel Prime to Premium Plan
content = content.replace(/_buildPlanCard\('Sentinel Prime', 'premium', 2000,/g, "_buildPlanCard('Premium Plan', 'premium', 1999,");

// Also add local_auth to top of imports if not present
if (!content.includes('package:local_auth/local_auth.dart')) {
  content = content.replace("import 'package:flutter/material.dart';", "import 'package:flutter/material.dart';\nimport 'package:local_auth/local_auth.dart';");
}

let payFromVaultAuthStr = `
  Future<void> _payFromVault(String planId) async {
    final LocalAuthentication auth = LocalAuthentication();
    try {
      final bool canAuthenticateWithBiometrics = await auth.canCheckBiometrics;
      final bool canAuthenticate = canAuthenticateWithBiometrics || await auth.isDeviceSupported();
      if (canAuthenticate) {
        final bool didAuthenticate = await auth.authenticate(
          localizedReason: 'Authenticate to pay for plan via Vault',
          options: const AuthenticationOptions(biometricOnly: false, stickyAuth: true),
        );
        if (!didAuthenticate) {
          GkToast.show(context, message: 'Authentication required to use vault funds.', type: ToastType.error);
          return;
        }
      }
    } catch (e) {
      debugPrint('Biometric auth error: $e');
    }

    setState(() => _isLoading = true);
    try {
      final callable = FirebaseFunctions.instance.httpsCallable('purchasePlanFromVault');
      await callable.call({'plan': planId});
      if (mounted) {
        GkToast.show(context,
            message: '\${planId[0].toUpperCase()}\${planId.substring(1)} Plan Activated! 🎉',
            type: ToastType.success);
      }
    } catch (e) {
      if (mounted) {
        GkToast.show(context, message: 'Activation failed: $e', type: ToastType.error);
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }
`;

// Replace the old _payFromVault
const regex = /Future<void> _payFromVault\(String planId\) async \{[\s\S]*?finally \{\s*if \(mounted\) setState\(\(\) => _isLoading = false\);\s*\}\s*\}/;
content = content.replace(regex, payFromVaultAuthStr);

fs.writeFileSync(path, content, 'utf8');
console.log('Fixed UI Renames and Auth Vault in card_creation_screen.dart');
