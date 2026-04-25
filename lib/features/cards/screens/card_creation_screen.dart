import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

// lib/features/cards/screens/card_creation_screen.dart
import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';




import 'package:gatekipa/core/theme/app_colors.dart';
import 'package:gatekipa/core/widgets/gk_button.dart';
import 'package:gatekipa/core/widgets/gk_toast.dart';
import 'package:gatekipa/core/widgets/gk_checkout.dart';
import 'package:gatekipa/features/accounts/providers/account_provider.dart';
import 'package:gatekipa/features/cards/providers/card_provider.dart';
import 'package:gatekipa/features/wallet/providers/wallet_provider.dart';
import 'package:gatekipa/features/auth/providers/auth_provider.dart';
import 'package:gatekipa/core/theme/app_spacing.dart';
import 'package:gatekipa/core/providers/system_state_provider.dart';
import 'package:gatekipa/features/accounts/screens/accounts_screen.dart';

// ── Comprehensive country list for global users ──
const List<String> _kCardCountries = [
  'Nigeria', 'Ghana', 'Kenya', 'South Africa', 'Uganda', 'Rwanda',
  'Tanzania', 'Egypt', 'Ethiopia', 'Cameroon', 'Senegal', 'Ivory Coast',
  'United States', 'United Kingdom', 'Canada', 'Germany', 'France',
  'India', 'Brazil', 'Australia', 'Japan', 'China', 'UAE',
  'Saudi Arabia', 'Netherlands', 'Italy', 'Spain', 'Mexico',
  'Argentina', 'Colombia', 'Turkey', 'Indonesia', 'Philippines',
  'Malaysia', 'Singapore', 'South Korea', 'Poland', 'Sweden',
  'Norway', 'Denmark', 'Switzerland', 'Austria', 'Belgium',
  'Portugal', 'Ireland', 'New Zealand', 'Other',
];

const Map<String, List<String>> _kCardStates = {
  'Nigeria': [
    'Abia', 'Adamawa', 'Akwa Ibom', 'Anambra', 'Bauchi', 'Bayelsa',
    'Benue', 'Borno', 'Cross River', 'Delta', 'Ebonyi', 'Edo',
    'Ekiti', 'Enugu', 'FCT Abuja', 'Gombe', 'Imo', 'Jigawa',
    'Kaduna', 'Kano', 'Katsina', 'Kebbi', 'Kogi', 'Kwara',
    'Lagos', 'Nasarawa', 'Niger', 'Ogun', 'Ondo', 'Osun',
    'Oyo', 'Plateau', 'Rivers', 'Sokoto', 'Taraba', 'Yobe', 'Zamfara',
  ],
  'Ghana': ['Greater Accra', 'Ashanti', 'Central', 'Eastern', 'Northern', 'Western', 'Volta', 'Upper East', 'Upper West', 'Brong-Ahafo'],
  'Kenya': ['Nairobi', 'Mombasa', 'Kisumu', 'Nakuru', 'Eldoret', 'Kiambu', 'Machakos', 'Kajiado', 'Uasin Gishu', 'Nyeri'],
  'South Africa': ['Gauteng', 'Western Cape', 'KwaZulu-Natal', 'Eastern Cape', 'Free State', 'Limpopo', 'Mpumalanga', 'North West', 'Northern Cape'],
  'United States': ['California', 'Texas', 'Florida', 'New York', 'Illinois', 'Pennsylvania', 'Ohio', 'Georgia', 'Michigan', 'North Carolina', 'New Jersey', 'Virginia', 'Washington', 'Arizona', 'Massachusetts', 'Other'],
  'United Kingdom': ['England', 'Scotland', 'Wales', 'Northern Ireland'],
  'Canada': ['Ontario', 'Quebec', 'British Columbia', 'Alberta', 'Manitoba', 'Saskatchewan', 'Nova Scotia', 'New Brunswick', 'Newfoundland', 'Prince Edward Island'],
  'India': ['Maharashtra', 'Karnataka', 'Tamil Nadu', 'Delhi', 'Uttar Pradesh', 'Gujarat', 'West Bengal', 'Telangana', 'Rajasthan', 'Kerala', 'Other'],
};

class CardCreationScreen extends ConsumerStatefulWidget {
  final Map<String, String>? prefillMerchant;
  final String? accountId;

  const CardCreationScreen({super.key, this.prefillMerchant, this.accountId});

  @override
  ConsumerState<CardCreationScreen> createState() => _CardCreationScreenState();
}

class _CardCreationScreenState extends ConsumerState<CardCreationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _cardNameCtrl = TextEditingController();


  final _addressCtrl = TextEditingController();
  final _cityCtrl = TextEditingController();
  final _stateCtrl = TextEditingController();
  final _postalCodeCtrl = TextEditingController();
  final _houseNumberCtrl = TextEditingController();

  String _cardType = 'subscription';
  bool _nightLockdown = false;
  bool _instantBreachAlert = false;
  bool _isLoading = false;
  bool _useProfileAddress = true;

  String _cardCurrency = 'NGN';
  String _country = 'Nigeria';

  String? _selectedAccountId;
  String? _selectedState;

  // ── locked mode: accountId was passed from Account Detail ─────────────────
  bool get _isLocked => widget.accountId != null;

  @override
  void initState() {
    super.initState();
    _selectedAccountId = widget.accountId;

    if (widget.prefillMerchant != null) {
      _cardNameCtrl.text = widget.prefillMerchant!['name'] ?? '';
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_isLocked && _selectedAccountId == null) {
        final activeAcc = ref.read(activeAccountProvider);
        if (activeAcc != null) {
          setState(() => _selectedAccountId = activeAcc.id);
        }
      }

      // Pre-fill billing address from user profile if available
      if (_hasProfileAddress) {
        _syncProfileAddress();
      } else {
        _useProfileAddress = false;
      }
    });
  }

  void _syncProfileAddress() {
    final user = ref.read(userProfileProvider).valueOrNull;
    if (user != null && _useProfileAddress) {
      if ((user.address ?? '').isNotEmpty) _addressCtrl.text = user.address!;
      if ((user.city ?? '').isNotEmpty) _cityCtrl.text = user.city!;
      if ((user.state ?? '').isNotEmpty) {
        _stateCtrl.text = user.state!;
        _selectedState = user.state;
      }
      if ((user.postalCode ?? '').isNotEmpty) _postalCodeCtrl.text = user.postalCode!;
      if ((user.houseNumber ?? '').isNotEmpty) _houseNumberCtrl.text = user.houseNumber!;
    }
  }

  bool get _hasProfileAddress {
    final user = ref.read(userProfileProvider).valueOrNull;
    return user != null && (user.address ?? '').isNotEmpty;
  }

  @override
  void dispose() {
    _cardNameCtrl.dispose();
    _addressCtrl.dispose();
    _cityCtrl.dispose();
    _stateCtrl.dispose();
    _postalCodeCtrl.dispose();
    _houseNumberCtrl.dispose();
    super.dispose();
  }

  Future<String?> _collectCardPin() async {
    String pin = '';
    return await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: AppColors.surface,
          title: Text(
            'Set Card PIN',
            style: Theme.of(ctx).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Enter a 4-digit PIN for your new card. You will need this for ATM or POS transactions.',
                style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(color: AppColors.onSurfaceVariant),
              ),
              const SizedBox(height: 16),
              TextFormField(
                autofocus: true,
                keyboardType: TextInputType.number,
                maxLength: 4,
                obscureText: true,
                onChanged: (val) => pin = val,
                decoration: InputDecoration(
                  hintText: '****',
                  counterText: '',
                  filled: true,
                  fillColor: AppColors.surfaceContainerLowest,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
                style: const TextStyle(letterSpacing: 8, fontSize: 24, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, null),
              child: const Text('Cancel', style: TextStyle(color: AppColors.outline)),
            ),
            TextButton(
              onPressed: () {
                if (pin.length == 4) {
                  Navigator.pop(ctx, pin);
                } else {
                  GkToast.show(ctx, message: 'PIN must be exactly 4 digits', type: ToastType.error);
                }
              },
              child: const Text('Set PIN', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }

  Future<Map<String, dynamic>?> _showPlanSelectionSheet() async {
    return showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(24, 24, 24, MediaQuery.of(ctx).padding.bottom + 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Select a Plan', style: Theme.of(ctx).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx)),
              ],
            ),
            const SizedBox(height: 8),
            Text('You need to activate a baseline subscription tier to start creating cards. This is a one-time deduction.', style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(color: AppColors.onSurfaceVariant)),
            const SizedBox(height: 24),
            
            // FIX #4 & #5: Accurate features + 5-day trial banner on Instant & Activation
            _buildMiniPlanCard(ctx, 'Instant Plan', 'free', 700,
              ['1 Virtual Card', 'Basic Rules Only', '⚡ 5-Day Sentinel Trial'], false, hasTrial: true),
            const SizedBox(height: 12),
            _buildMiniPlanCard(ctx, 'Activation Plan', 'activation', 1400,
              ['2 Virtual Cards', 'Basic Rules Only', '⚡ 5-Day Sentinel Trial'], false, hasTrial: true),
            const SizedBox(height: 12),
            _buildMiniPlanCard(ctx, 'Sentinel Prime', 'premium', 1999,
              ['Smart Alerts', 'Night Lockdown', 'Geo-Fence', 'Advanced Rules'], true),
            const SizedBox(height: 12),
            _buildMiniPlanCard(ctx, 'Business Plan', 'business', 5000,
              ['5 Cards', 'Team Access', 'Priority Protection', 'Full Suite'], false),
          ],
        ),
        ),
      ),
    );
  }

  Widget _buildMiniPlanCard(BuildContext ctx, String name, String id, int price, List<String> features, bool isPopular, {bool hasTrial = false}) {
    return InkWell(
      onTap: () => Navigator.pop(ctx, {'id': id, 'price': price, 'name': name}),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: isPopular ? AppColors.primary : AppColors.outlineVariant),
          color: isPopular ? AppColors.primary.withValues(alpha: 0.05) : AppColors.surfaceContainerLowest,
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(name, style: Theme.of(ctx).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                      if (isPopular) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(8)),
                          child: const Text('RECOMMENDED', style: TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold)),
                        ),
                      ]
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(features.join(' • '), style: Theme.of(ctx).textTheme.bodySmall?.copyWith(color: AppColors.onSurfaceVariant)),
                  if (hasTrial) ...[ 
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFA500).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: const Color(0xFFFFA500).withValues(alpha: 0.4)),
                      ),
                      child: const Text(
                        '⚡ Includes 5-Day Sentinel Prime Trial',
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Color(0xFFCC8400)),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Text('₦$price', style: Theme.of(ctx).textTheme.titleMedium?.copyWith(color: AppColors.primary, fontWeight: FontWeight.w800)),
          ],
        ),
      ),
    );
  }

  Future<bool> _showFundingPrompt(double deficit, double currentBalance) async {
    return await showModalBottomSheet<bool>(
      context: context,
      useRootNavigator: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 48),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: AppColors.error.withValues(alpha: 0.1), shape: BoxShape.circle),
              child: const Icon(Icons.account_balance_wallet_rounded, color: AppColors.error, size: 32),
            ),
            const SizedBox(height: 16),
            Text('Insufficient Funds', style: Theme.of(ctx).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Text(
              'Your Vault balance is ₦${currentBalance.toStringAsFixed(0)}. You need an additional ₦${deficit.toStringAsFixed(0)} to complete this creation.',
              textAlign: TextAlign.center,
              style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(color: AppColors.onSurfaceVariant),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 56,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                onPressed: () {
                  Navigator.pop(ctx, true);
                },
                child: const Text('Fund Externally', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
              ),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel', style: TextStyle(color: AppColors.outline)),
            ),
          ],
        ),
      ),
    ) ?? false;
  }

  Future<bool> _showVaultDeductionConfirm(double totalNeeded, int planCost, double balance) async {
    return await showModalBottomSheet<bool>(
      context: context,
      useRootNavigator: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 48),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.1), shape: BoxShape.circle),
              child: const Icon(Icons.check_circle_outline, color: AppColors.primary, size: 32),
            ),
            const SizedBox(height: 16),
            Text('Confirm Deduction', style: Theme.of(ctx).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Text(
              'A total of ₦${totalNeeded.toStringAsFixed(0)} (Plan: ₦$planCost) will be deducted from your Vault balance (₦${balance.toStringAsFixed(0)}).',
              textAlign: TextAlign.center,
              style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(color: AppColors.onSurfaceVariant),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 56,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Confirm & Create', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
              ),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel', style: TextStyle(color: AppColors.outline)),
            ),
          ],
        ),
      ),
    ) ?? false;
  }
  Future<void> _createCard() async {
    if (!_formKey.currentState!.validate()) return;
    
    final user = ref.read(userProfileProvider).valueOrNull;
    if (user == null) return;
    final wallet = ref.read(walletProvider).valueOrNull;
    // hasNoPlan: only users with NO plan at all need to select one.
    // FIX #3: 'activation' users have already paid — they keep their plan.
    // Only 'none' and empty tier should be forced through plan selection.
    final hasNoPlan = (user.planTier == 'none' || user.planTier.isEmpty);
    
    String? selectedPlanId;
    int planCost = 0;

    // STEP 1: Plan Selection (If needed)
    if (hasNoPlan) {
        final result = await _showPlanSelectionSheet();
        if (result == null) return; // user cancelled
        selectedPlanId = result['id'];
        planCost = result['price'];
    } else {
        selectedPlanId = user.planTier;
    }

    // FIX #7: 'free' is the canonical backend name for Instant plan.
    // 'instant' was a legacy alias — removed to prevent inconsistent gating.
    final isInstant = selectedPlanId == 'free';

    // STEP 2: Client Profile Check
    if (_selectedAccountId == null && !isInstant) {
        if (!mounted) return;
        GkToast.show(context, message: 'Please create a client profile first to map your card.', type: ToastType.info);
        final newAccountId = await showCreateAccountSheet(context, planTier: selectedPlanId);
        if (newAccountId == null) return; // user cancelled profile creation
        setState(() => _selectedAccountId = newAccountId);
    }

    final cardName = _cardNameCtrl.text.trim().isNotEmpty ? _cardNameCtrl.text.trim() : 'New Virtual Card';
    
    // Total needed: plan cost + minimum card funding
    double totalNeeded = planCost.toDouble();
    if (_cardCurrency == 'USD') {
        totalNeeded += 8000; // Minimum USD card funding
    }

    double currentBalance = wallet?.balance ?? 0.0;

    // STEP 3: Funding Check
    if (currentBalance < totalNeeded) {
        final deficit = totalNeeded - currentBalance;
        final wantToFund = await _showFundingPrompt(deficit, currentBalance);
        if (!wantToFund) return; // cancelled
        
        // Launch GkCheckout to fund exactly the missing amount
        final refStr = 'GTK-FUND-${user.uid.substring(0, 6)}-${DateTime.now().millisecondsSinceEpoch}';
        
        // Let's use Navigator push
        if (!mounted) return;
        final bool? checkoutSuccess = await Navigator.of(context, rootNavigator: true).push(
          MaterialPageRoute(
            builder: (_) => GkCheckout(
              type: GkCheckoutType.fundWallet,
              amountInNgn: deficit,
              email: user.email ?? '',
              uid: user.uid,
              reference: refStr,
              onSuccess: (String paidReference) async {
                // Return true so we can await it
                Navigator.pop(context, true);
              },
              onCancel: () {
                Navigator.pop(context, false);
              },
            ),
          ),
        );
        
        if (checkoutSuccess != true) {
            if (!mounted) return;
        GkToast.show(context, message: 'Funding was cancelled or failed.', type: ToastType.error);
            return;
        }
        
        // Verify payment
        if (!mounted) return;
        setState(() => _isLoading = true);
        final verified = await ref.read(walletNotifierProvider.notifier).verifyPaystackPayment(reference: refStr);
        if (!verified) {
            if (!mounted) return;
            setState(() => _isLoading = false);
            GkToast.show(context, message: 'Payment verification failed. Please contact support.', type: ToastType.error);
            return;
        }
    } else if (totalNeeded > 0) {
        // Just confirm vault deduction
        final confirm = await _showVaultDeductionConfirm(totalNeeded, planCost, currentBalance);
        if (!confirm) return;
    }

    if (!mounted) return;
    setState(() => _isLoading = true);

    // STEP 4: Purchase Plan (if selected and needed)
    if (hasNoPlan && selectedPlanId != null) {
        try {
            const storage = FlutterSecureStorage();
            final secureKey = '${user.uid}_transaction_pin';
            final pin = await storage.read(key: secureKey);
            
            if (pin == null || pin.isEmpty) {
               throw Exception("No Transaction PIN configured. Please set one up in Profile.");
            }

            final callable = FirebaseFunctions.instance.httpsCallable('purchasePlanFromVault');
            await callable.call({'plan': selectedPlanId, 'pin': pin});
        } catch (e) {
            if (!mounted) return;
            setState(() => _isLoading = false);
            GkToast.show(context, message: 'Could not activate your plan. Please ensure you have sufficient vault balance and try again.', type: ToastType.error);
            return;
        }
    }

    // STEP 5: KYC / Bridgecard Registration
    if (user.bridgecardCardholderId == null) {
      if (user.kycStatus != 'verified') {
        if (!mounted) return;
        setState(() => _isLoading = false);
        GkToast.show(context, message: 'Please complete your identity verification in Profile first.', type: ToastType.error);
        return;
      }

      final regSuccess = await ref.read(cardNotifierProvider.notifier).registerCardholder(
        firstName: user.firstName ?? '',
        lastName: user.lastName ?? '',
        phone: user.phoneNumber ?? '',
        address: _addressCtrl.text.trim(),
        city: _cityCtrl.text.trim(),
        regionState: _stateCtrl.text.trim(),
        postalCode: _postalCodeCtrl.text.trim(),
        houseNumber: _houseNumberCtrl.text.trim(),
        country: _country,
      );

      if (!regSuccess) {
        if (!mounted) return;
        setState(() => _isLoading = false);
        final stateErr = ref.read(cardNotifierProvider);
        String errMsg = 'Failed to verify billing address and identity. Please check your details and try again.';
        if (stateErr.hasError) {
          final err = stateErr.error;
          if (err is FirebaseFunctionsException) {
            errMsg = err.message ?? errMsg;
          } else {
            // Prevent raw stack traces from showing
            final errStr = err.toString();
            if (!errStr.contains('Exception: ') && !errStr.contains('Error: ')) {
               errMsg = errStr;
            }
          }
          // Sanitize technical API errors
          if (errMsg.toLowerCase().contains('status code') || errMsg.length > 150) {
            errMsg = 'The verification service is temporarily unavailable. Please try again later.';
          }
        }
        GkToast.show(context, message: errMsg, type: ToastType.error);
        return;
      }
    }

    // STEP 6: Create Card
    final accounts = ref.read(accountsStreamProvider).valueOrNull ?? [];
    final selectedAcc = accounts.where((a) => a.id == _selectedAccountId).firstOrNull;
    final derivedCategory = selectedAcc?.type ?? 'personal';
    
    final resolvedAccountId = selectedAcc?.id ?? (accounts.isNotEmpty ? accounts.first.id : user.uid);

    final cardId = await ref.read(cardNotifierProvider.notifier).createCard(
          accountId: resolvedAccountId,
          name: cardName,
          category: derivedCategory,
          isTrial: _cardType == 'trial',
          balanceLimit: 50000,
          currency: _cardCurrency,
        );

    if (cardId != null) {
      if (mounted) GkToast.show(context, message: 'Setting up your card...', type: ToastType.info);

      final pin = await _collectCardPin();
      if (pin == null) {
        if (!mounted) return;
        setState(() => _isLoading = false);
        GkToast.show(context,
            message: 'Card created but not yet activated. Open it from your cards list to set a PIN and activate.',
            type: ToastType.warning);
        context.pop();
        return;
      }

      final bridgecardSuccess = await ref.read(cardNotifierProvider.notifier).createBridgecard(
        cardId: cardId,
        pin: pin,
        cardCurrency: _cardCurrency,
      );

      if (!bridgecardSuccess) {
        if (!mounted) return;
        setState(() => _isLoading = false);
        GkToast.show(context,
            message: 'Card registered but activation failed. Please try again from your cards list or contact support.',
            type: ToastType.error);
        context.pop();
        return;
      }

      // Step 7: Apply rules
      // FIX #4: Re-read user at submission time to validate Sentinel access.
      // This prevents stale toggle state if trial expired mid-session.
      final currentUser = ref.read(userProfileProvider).valueOrNull;
      final hasSentinelNow = currentUser?.isSentinelPrime ?? false;

      if (_nightLockdown && hasSentinelNow) {
        await ref.read(cardNotifierProvider.notifier).createCardRule(cardId: cardId, type: 'time', subType: 'night_lockdown', value: true);
      }
      if (_instantBreachAlert && hasSentinelNow) {
        await ref.read(cardNotifierProvider.notifier).createCardRule(cardId: cardId, type: 'behavior', subType: 'instant_breach_alert', value: true);
        try {
          await FirebaseFunctions.instance.httpsCallable('sendCardNotification').call({
            'cardId': cardId, 'title': 'Breach Alert Armed', 'body': 'Your instant breach alert for $cardName is now active.', 'type': 'alert'
          });
        } catch (_) {}
      }
    }

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (cardId != null) {
      GkToast.show(context, message: 'Card created and activated successfully! 🎉', type: ToastType.success);
      context.pop();
    } else {
      GkToast.show(context, message: 'Failed to create card. Please try again.', type: ToastType.error);
    }
  }


  @override
  Widget build(BuildContext context) {
    ref.watch(walletProvider);
    final accountsAsync = ref.watch(accountsStreamProvider);
    final userAsync = ref.watch(userProfileProvider);
    final user = userAsync.valueOrNull;
    final needsRegistration = user != null && user.bridgecardCardholderId == null;
    final sysState = ref.watch(systemStateProvider).valueOrNull ?? SystemState.normal;

    final accounts = accountsAsync.valueOrNull;


    // Auto-select the only account if there's exactly one
    if (!_isLocked && accounts != null && accounts.length == 1 && _selectedAccountId == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _selectedAccountId = accounts.first.id);
      });
    }

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: Text(
          'Create Card',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800, fontSize: 20, color: AppColors.onSurface),
        ),
        backgroundColor: AppColors.surface,
        scrolledUnderElevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 140),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              

              // ── Main card form begins here ──
              Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_isLocked) ...[
                accountsAsync.when(
                  data: (accounts) {
                    final acc = accounts.where((a) => a.id == widget.accountId).firstOrNull;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const _FieldLabel('Client Profile'),
                        const SizedBox(height: AppSpacing.xs),
                        TextFormField(
                          initialValue: acc?.name ?? 'Loading...',
                          readOnly: true,
                          decoration: InputDecoration(
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                            filled: true,
                            fillColor: AppColors.surfaceContainerLowest,
                            suffixIcon: const Icon(Icons.lock_outline, size: 20),
                          ),
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 15, color: AppColors.onSurfaceVariant),
                        ),
                      ],
                    );
                  },
                  loading: () => Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text('Loading profile...', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.primary)),
                  ),
                  error: (_, __) => const SizedBox.shrink(),
                ),
                const SizedBox(height: AppSpacing.lg),
              ] else ...[
                const _FieldLabel('Select Client Profile'),
                const SizedBox(height: AppSpacing.xs),
                accountsAsync.when(
                  data: (accounts) {
                    if (accounts.isEmpty) return const SizedBox.shrink();
                    final validId = accounts.any((a) => a.id == _selectedAccountId)
                        ? _selectedAccountId
                        : accounts.first.id;
                    return InkWell(
                      onTap: () {
                        showModalBottomSheet(
                          context: context,
                          useRootNavigator: true,
                          backgroundColor: Colors.transparent,
                          isScrollControlled: true,
                          builder: (sheetContext) => Container(
                            margin: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                            decoration: BoxDecoration(
                              color: AppColors.surface,
                              borderRadius: BorderRadius.circular(28),
                            ),
                            padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: AppColors.outlineVariant, borderRadius: BorderRadius.circular(2)))),
                                const SizedBox(height: AppSpacing.lg),
                                Text('Select Client Profile', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontSize: 18, fontWeight: FontWeight.w800)),
                                const SizedBox(height: AppSpacing.md),
                                ...accounts.map((acc) => ListTile(
                                  onTap: () {
                                    setState(() => _selectedAccountId = acc.id);
                                    Navigator.pop(sheetContext);
                                  },
                                  contentPadding: EdgeInsets.zero,
                                  leading: const CircleAvatar(
                                    backgroundColor: AppColors.primaryContainer,
                                    child: Icon(Icons.account_balance_wallet, color: AppColors.primary, size: 20),
                                  ),
                                  title: Text(acc.name, style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                                  trailing: validId == acc.id ? const Icon(Icons.check_circle, color: AppColors.primary) : null,
                                )),
                              ],
                            ),
                          ),
                        );
                      },
                      borderRadius: BorderRadius.circular(12),
                      child: InputDecorator(
                        decoration: InputDecoration(
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                          filled: true,
                          fillColor: AppColors.surfaceContainerLowest,
                          prefixIcon: const Icon(Icons.account_balance_wallet_outlined, size: 20),
                          suffixIcon: const Icon(Icons.arrow_drop_down_rounded, size: 24),
                        ),
                        child: Text(
                          accounts.firstWhere((a) => a.id == validId, orElse: () => accounts.first).name,
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 15),
                        ),
                      ),
                    );
                  },
                  loading: () => const SizedBox(height: 56, child: Center(child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary))),
                  error: (e, _) => Text('Error loading accounts', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.error)),
                ),
                const SizedBox(height: AppSpacing.lg),
              ],

              const _FieldLabel('Card Name'),
              const SizedBox(height: AppSpacing.xs),
              TextFormField(
                controller: _cardNameCtrl,
                decoration: InputDecoration(
                  hintText: 'e.g. Hosting, Netflix, SaaS Tool',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                  filled: true,
                  fillColor: AppColors.surfaceContainerLowest,
                ),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Card name is required' : null,
              ),
              const SizedBox(height: AppSpacing.lg),

              const _FieldLabel('Card Currency'),
              const SizedBox(height: AppSpacing.xs),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'NGN', label: Text('Naira (NGN)')),
                  ButtonSegment(value: 'USD', label: Text('Dollar (USD)')),
                ],
                selected: {_cardCurrency},
                onSelectionChanged: (Set<String> newSelection) {
                  setState(() => _cardCurrency = newSelection.first);
                },
                style: ButtonStyle(
                  backgroundColor: WidgetStateProperty.resolveWith<Color>(
                    (Set<WidgetState> states) {
                      if (states.contains(WidgetState.selected)) {
                        return AppColors.primaryContainer;
                      }
                      return AppColors.surfaceContainerLowest;
                    },
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),

              const _FieldLabel('Card Type'),
              const SizedBox(height: AppSpacing.xs),
              _CardTypeOption(
                value: 'subscription',
                selectedValue: _cardType,
                title: 'Subscription Card',
                subtitle: 'For recurring payments',
                onChanged: (v) => setState(() => _cardType = v!),
              ),
              const SizedBox(height: AppSpacing.xs),
              _CardTypeOption(
                value: 'one_time',
                selectedValue: _cardType,
                title: 'One-Time Card',
                subtitle: 'Burner card for single use',
                onChanged: (v) => setState(() => _cardType = v!),
              ),
              const SizedBox(height: 28),

              const _FieldLabel('Protection Rules'),
              const SizedBox(height: AppSpacing.sm),

              _RuleRow(
                label: 'Night Lockdown',
                subtitle: 'Block 12:00 AM – 6:00 AM',
                child: Switch(
                  value: _nightLockdown && (user?.isSentinelPrime ?? false),
                  thumbIcon: WidgetStateProperty.resolveWith<Icon?>((Set<WidgetState> states) {
                    if (states.contains(WidgetState.selected)) {
                      return const Icon(Icons.check, color: AppColors.primary);
                    }
                    return const Icon(Icons.close, color: AppColors.surface);
                  }),
                  onChanged: (v) {
                    final user = ref.read(userProfileProvider).valueOrNull;
                    if (user != null && !user.isSentinelPrime) {
                      GkToast.show(context, message: '🚀 Sentinel Prime Required: Upgrade your plan to unlock Night Lockdown.', type: ToastType.warning);
                      return;
                    }
                    setState(() => _nightLockdown = v);
                  },
                ),
              ),
              const _Divider(),

              _RuleRow(
                label: 'Instant Breach Alert',
                subtitle: 'Push notification on breach',
                child: Switch(
                  value: _instantBreachAlert && (user?.isSentinelPrime ?? false),
                  thumbIcon: WidgetStateProperty.resolveWith<Icon?>((Set<WidgetState> states) {
                    if (states.contains(WidgetState.selected)) {
                      return const Icon(Icons.check, color: AppColors.primary);
                    }
                    return const Icon(Icons.close, color: AppColors.surface);
                  }),
                  onChanged: (v) {
                    final user = ref.read(userProfileProvider).valueOrNull;
                    if (user != null && !user.isSentinelPrime) {
                      GkToast.show(context, message: '🚀 Sentinel Prime Required: Upgrade your plan for Instant Breach Alerts.', type: ToastType.warning);
                      return;
                    }
                    setState(() => _instantBreachAlert = v);
                  },
                ),
              ),

              if (needsRegistration) ...[
                const SizedBox(height: 28),
                Row(
                  children: [
                    const Expanded(child: _FieldLabel('Billing Address')),
                    if (_hasProfileAddress)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('Use saved', style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 12, color: AppColors.primary, fontWeight: FontWeight.w600)),
                          const SizedBox(width: 4),
                          SizedBox(
                            height: 28,
                            child: Switch(
                              value: _useProfileAddress,
                              thumbIcon: WidgetStateProperty.resolveWith<Icon?>((states) {
                                if (states.contains(WidgetState.selected)) {
                                  return const Icon(Icons.check, color: AppColors.primary, size: 14);
                                }
                                return null;
                              }),
                              onChanged: (v) {
                                setState(() {
                                  _useProfileAddress = v;
                                  if (v) {
                                    _syncProfileAddress();
                                  } else {
                                    _addressCtrl.clear();
                                    _cityCtrl.clear();
                                    _stateCtrl.clear();
                                    _postalCodeCtrl.clear();
                                    _houseNumberCtrl.clear();
                                    _selectedState = null;
                                  }
                                });
                              },
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Please enter your complete street address (e.g. "123 Main Street, Phase 2"). A neighborhood name alone will cause verification to fail.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontSize: 12,
                    color: AppColors.outline,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                DropdownButtonFormField<String>(
                  initialValue: _country,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: 'Country',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                    filled: true,
                    fillColor: AppColors.surfaceContainerLowest,
                  ),
                  items: _kCardCountries
                      .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                      .toList(),
                  onChanged: (v) {
                     if (v != null) {
                       setState(() {
                         _country = v;
                         _selectedState = null;
                         _stateCtrl.clear();
                       });
                     }
                  },
                ),
                const SizedBox(height: AppSpacing.md),
                TextFormField(
                  controller: _addressCtrl,
                  decoration: InputDecoration(
                    hintText: 'Full Street Address (e.g., 123 Main St)',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                    filled: true,
                    fillColor: AppColors.surfaceContainerLowest,
                  ),
                  validator: (v) => needsRegistration && (v == null || v.trim().isEmpty) ? 'Street address is required' : null,
                ),
                const SizedBox(height: AppSpacing.md),
                Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: TextFormField(
                        controller: _cityCtrl,
                        decoration: InputDecoration(
                          hintText: 'City',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          filled: true,
                          fillColor: AppColors.surfaceContainerLowest,
                        ),
                        validator: (v) => needsRegistration && (v == null || v.trim().isEmpty) ? 'City required' : null,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      flex: 1,
                      child: _kCardStates.containsKey(_country)
                          ? DropdownButtonFormField<String>(
                              initialValue: _selectedState,
                              isExpanded: true,
                              decoration: InputDecoration(
                                hintText: 'State',
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                filled: true,
                                fillColor: AppColors.surfaceContainerLowest,
                              ),
                              items: (_kCardStates[_country] ?? [])
                                  .map((s) => DropdownMenuItem(value: s, child: Text(s, overflow: TextOverflow.ellipsis)))
                                  .toList(),
                              onChanged: (v) {
                                if (v != null) {
                                  setState(() {
                                    _selectedState = v;
                                    _stateCtrl.text = v;
                                  });
                                }
                              },
                              validator: (v) => needsRegistration && v == null ? 'State required' : null,
                            )
                          : TextFormField(
                              controller: _stateCtrl,
                              decoration: InputDecoration(
                                hintText: 'State',
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                filled: true,
                                fillColor: AppColors.surfaceContainerLowest,
                              ),
                              validator: (v) => needsRegistration && (v == null || v.trim().isEmpty) ? 'State required' : null,
                            ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: TextFormField(
                        controller: _houseNumberCtrl,
                        decoration: InputDecoration(
                          hintText: 'House/Apartment N°',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          filled: true,
                          fillColor: AppColors.surfaceContainerLowest,
                        ),
                        validator: (v) => needsRegistration && (v == null || v.trim().isEmpty) ? 'House No required' : null,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      flex: 1,
                      child: TextFormField(
                        controller: _postalCodeCtrl,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          hintText: 'Zip Code',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          filled: true,
                          fillColor: AppColors.surfaceContainerLowest,
                        ),
                        validator: (v) => needsRegistration && (v == null || v.trim().isEmpty) ? 'Zip code required' : null,
                      ),
                    ),
                  ],
                ),

              ],
              const SizedBox(height: AppSpacing.md),
              // Close the main form column
              ],
            ),
          ]),
        ),
      ),
      bottomNavigationBar: Container(
        padding: EdgeInsets.fromLTRB(
          20,
          16,
          20,
          MediaQuery.of(context).padding.bottom + 16,
        ),
        decoration: BoxDecoration(
          color: AppColors.surface,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.07),
              blurRadius: 20,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!sysState.isOperational)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: sysState.isLockedDown
                        ? const Color(0xFF3B0A0A)
                        : const Color(0xFF2D2000),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: sysState.isLockedDown
                          ? const Color(0xFFCF4444)
                          : const Color(0xFFD4A017),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        sysState.isLockedDown ? Icons.lock_rounded : Icons.warning_amber_rounded,
                        color: sysState.isLockedDown ? const Color(0xFFFF6B6B) : const Color(0xFFFFD166),
                        size: 16,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          sysState.bannerMessage,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: sysState.isLockedDown
                                ? const Color(0xFFFF6B6B)
                                : const Color(0xFFFFD166),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            GkButton(
              label: sysState.isOperational ? 'Create Card' : 'Cards Unavailable',
              icon: Icons.credit_card_rounded,
              isLoading: _isLoading,
              onPressed: sysState.isOperational ? _createCard : null,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Card Type Radio Option ────────────────────────────────────────────────────
class _CardTypeOption extends StatelessWidget {
  final String value;
  final String selectedValue;
  final String title;
  final String subtitle;
  final ValueChanged<String?> onChanged;

  const _CardTypeOption({
    required this.value,
    required this.selectedValue,
    required this.title,
    required this.subtitle,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final selected = value == selectedValue;
    return GestureDetector(
      onTap: () => onChanged(value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary.withValues(alpha: 0.06) : AppColors.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.outlineVariant.withValues(alpha: 0.6),
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              selected ? Icons.radio_button_checked : Icons.radio_button_off,
              color: selected ? AppColors.primary : AppColors.onSurfaceVariant,
              size: 20,
            ),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600,
                        fontSize: 14,
                        color: selected ? AppColors.primary : AppColors.onSurface,)),
                  Text(subtitle,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 12, color: AppColors.onSurfaceVariant)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Rule Row ─────────────────────────────────────────────────────────────────
class _RuleRow extends StatelessWidget {
  final String label;
  final String? subtitle;
  final Widget child;

  const _RuleRow({required this.label, this.subtitle, required this.child});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600, fontSize: 14, color: AppColors.onSurface)),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(subtitle!,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 12, color: AppColors.onSurfaceVariant)),
                ],
              ],
            ),
          ),
          child,
        ],
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) =>
      const Divider(height: 1, color: Color(0x18000000));
}

// ── Field Label ───────────────────────────────────────────────────────────────
class _FieldLabel extends StatelessWidget {
  final String text;
  const _FieldLabel(this.text);

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700,
          fontSize: 13,
          color: AppColors.onSurfaceVariant,
          letterSpacing: 0.2,),
      );
}

