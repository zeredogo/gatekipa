import 'package:cloud_functions/cloud_functions.dart';

// lib/features/cards/screens/card_creation_screen.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'package:gatekipa/core/constants/app_constants.dart';
import 'package:gatekipa/core/constants/routes.dart';
import 'package:gatekipa/core/theme/app_colors.dart';
import 'package:gatekipa/core/widgets/gk_button.dart';
import 'package:gatekipa/core/widgets/gk_toast.dart';
import 'package:gatekipa/features/accounts/providers/account_provider.dart';
import 'package:gatekipa/features/cards/providers/card_provider.dart';
import 'package:gatekipa/features/wallet/providers/wallet_provider.dart';
import 'package:gatekipa/features/auth/providers/auth_provider.dart';
import 'package:gatekipa/core/theme/app_spacing.dart';


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
  final _fixedAmountCtrl = TextEditingController();
  final _maxChargesCtrl = TextEditingController();

  final _addressCtrl = TextEditingController();
  final _cityCtrl = TextEditingController();
  final _stateCtrl = TextEditingController();
  final _postalCodeCtrl = TextEditingController();
  final _houseNumberCtrl = TextEditingController();

  String _cardType = 'subscription';
  bool _nightLockdown = true;
  bool _instantBreachAlert = true;
  bool _isLoading = false;

  String _cardCurrency = 'NGN';
  String _country = 'Nigeria';
  String _idType = 'Passport';
  final _idNumberCtrl = TextEditingController();
  File? _idImageFile;
  File? _selfieImageFile;

  String? _selectedAccountId;

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
    });
  }

  @override
  void dispose() {
    _cardNameCtrl.dispose();
    _fixedAmountCtrl.dispose();
    _maxChargesCtrl.dispose();
    _addressCtrl.dispose();
    _cityCtrl.dispose();
    _stateCtrl.dispose();
    _postalCodeCtrl.dispose();
    _houseNumberCtrl.dispose();
    _idNumberCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickImage(bool isSelfie) async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.camera, imageQuality: 70);
    if (pickedFile != null) {
      setState(() {
        if (isSelfie) {
          _selfieImageFile = File(pickedFile.path);
        } else {
          _idImageFile = File(pickedFile.path);
        }
      });
    }
  }

  Future<String?> _uploadImage(File file, String path) async {
    try {
      final ref = FirebaseStorage.instance.ref().child(path);
      await ref.putFile(file);
      return await ref.getDownloadURL();
    } catch (e) {
      debugPrint('Upload error: $e');
      return null;
    }
  }

  Future<void> _createCard() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedAccountId == null) {
      GkToast.show(context, message: 'Please select an account', type: ToastType.error);
      return;
    }

    final wallet = ref.read(walletProvider).valueOrNull;
    if (wallet == null || wallet.balance <= 0) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppColors.surface,
          title: Text(
            'Insufficient Funds',
            style: Theme.of(ctx).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
          content: Text(
            'You have no funds available. Please top up your vault to proceed with card creation.',
            style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(color: AppColors.onSurfaceVariant),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel', style: TextStyle(color: AppColors.outline)),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                context.push(Routes.addFunds);
              },
              child: const Text('Add Funds', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      );
      return;
    }

    if (_cardCurrency == 'USD' && (wallet.balance) < 8000) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppColors.surface,
          title: Text('Insufficient Funds for USD Card', style: Theme.of(ctx).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
          content: Text('Bridgecard requires a minimum \\\$5 (approx ₦8,000) pre-fund to cover USD card creation and maintenance.', style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(color: AppColors.onSurfaceVariant)),
          actions: [
             TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel', style: TextStyle(color: AppColors.outline))),
             TextButton(onPressed: () {
                Navigator.pop(ctx);
                context.push(Routes.addFunds);
              }, child: const Text('Add Funds', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold))),
          ],
        )
      );
      return;
    }

    setState(() => _isLoading = true);

    final user = ref.read(userProfileProvider).valueOrNull;
    if (user != null && user.bridgecardCardholderId == null) {
      if (_country == 'Nigeria' && !user.hasBvn) {
        setState(() => _isLoading = false);
        GkToast.show(context, message: 'Please complete your BVN registration first.', type: ToastType.error);
        return;
      }
      
      if (_country != 'Nigeria' && (_idImageFile == null || _selfieImageFile == null || _idNumberCtrl.text.isEmpty)) {
        setState(() => _isLoading = false);
        GkToast.show(context, message: 'Global KYC requires an ID number, ID photo, and Selfie.', type: ToastType.error);
        return;
      }

      String? uploadedIdUrl;
      String? uploadedSelfieUrl;
      
      if (_country != 'Nigeria') {
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        if (_idImageFile != null) {
          uploadedIdUrl = await _uploadImage(_idImageFile!, 'kyc/${user.uid}/id_$timestamp.jpg');
        }
        if (_selfieImageFile != null) {
          uploadedSelfieUrl = await _uploadImage(_selfieImageFile!, 'kyc/${user.uid}/selfie_$timestamp.jpg');
        }
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
        idType: _country != 'Nigeria' ? _idType : null,
        idNo: _country != 'Nigeria' ? _idNumberCtrl.text.trim() : null,
        idImage: uploadedIdUrl,
        selfieImage: uploadedSelfieUrl,
      );

      if (!regSuccess) {
        if (!mounted) return;
        setState(() => _isLoading = false);
        GkToast.show(context, message: 'Failed to verify billing address and identity with Bridgecard.', type: ToastType.error);
        return;
      }
    }

    final cardName =
        _cardNameCtrl.text.trim().isNotEmpty ? _cardNameCtrl.text.trim() : 'New Virtual Card';

    final fixedAmt =
        double.tryParse(_fixedAmountCtrl.text.replaceAll(RegExp(r'[^0-9.]'), '')) ?? 0;
    final maxCharges = int.tryParse(_maxChargesCtrl.text.trim()) ?? 0;

    final accounts = ref.read(accountsStreamProvider).valueOrNull ?? [];
    final selectedAcc = accounts.where((a) => a.id == _selectedAccountId).firstOrNull;
    final derivedCategory = selectedAcc?.type ?? 'personal';

    final cardId = await ref.read(cardNotifierProvider.notifier).createCard(
          accountId: selectedAcc?.id ?? accounts.first.id,
          name: cardName,
          category: derivedCategory,
          isTrial: _cardType == 'trial',
          balanceLimit: fixedAmt > 0 ? fixedAmt : 50000,
          currency: _cardCurrency,
        );

    if (cardId != null) {
      if (fixedAmt > 0) {
        await ref.read(cardNotifierProvider.notifier).createCardRule(
              cardId: cardId,
              type: 'spend',
              subType: 'max_per_txn',
              value: fixedAmt,
            );
      }
      if (maxCharges > 0) {
        await ref.read(cardNotifierProvider.notifier).createCardRule(
              cardId: cardId,
              type: 'behavior',
              subType: 'max_charges', // matches ruleEngine.js 'max_charges' case
              value: maxCharges,
            );
      }
      if (_nightLockdown) {
        await ref.read(cardNotifierProvider.notifier).createCardRule(
              cardId: cardId,
              type: 'time',
              subType: 'night_lockdown', // matches ruleEngine.js 'night_lockdown' case
              value: true,
            );
      }
      if (_instantBreachAlert) {
        await ref.read(cardNotifierProvider.notifier).createCardRule(
              cardId: cardId,
              type: 'behavior',
              subType: 'instant_breach_alert',
              value: true,
            );

        // Notify the backend to dispatch the confirmation push — keeps all
        // notification writes server-side through the established pipeline.
        try {
          await FirebaseFunctions.instance
              .httpsCallable('sendCardNotification')
              .call({
            'cardId': cardId,
            'title': 'Breach Alert Armed',
            'body': 'Your instant breach alert for $cardName is now active.',
            'type': 'alert',
          });
        } catch (_) {
          // Non-critical: card was created successfully; notification failure is silent
        }
      }
    }

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (cardId != null) {
      GkToast.show(context, message: 'Card created successfully!', type: ToastType.success);
      context.pop();
    } else {
      GkToast.show(context, message: 'Failed to create card. Please try again.', type: ToastType.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(walletProvider); // keeps the wallet fresh
    final accountsAsync = ref.watch(accountsStreamProvider);
    final userAsync = ref.watch(userProfileProvider);
    final user = userAsync.valueOrNull;
    final needsRegistration = user != null && user.bridgecardCardholderId == null;

    if (user != null && (user.planTier == 'none' || user.planTier.isEmpty)) {
      return Scaffold(
        backgroundColor: AppColors.surface,
        appBar: AppBar(
          title: Text('Select a Plan', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800, fontSize: 20)),
          backgroundColor: AppColors.surface,
        ),
        body: _PlanSelectionView(user: user),
      );
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
              // ── Account selector / locked banner ────────────────────────
              if (_isLocked) ...[
                // Wireframe ③ — Green locked banner
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
                // Wireframe ④ — Select Account dropdown
                const _FieldLabel('Select Client Profile'),
                const SizedBox(height: AppSpacing.xs),
                accountsAsync.when(
                  data: (accounts) {
                    if (accounts.isEmpty) {
                      return Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceContainerLowest,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.outlineVariant),
                        ),
                        child: Text(
                          'No profiles found. Create a client profile first.',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.onSurfaceVariant),
                        ),
                      );
                    }
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

              // ── Card Name ───────────────────────────────────────────────
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

              // ── Card Currency ───────────────────────────────────────────
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

              // ── Card Type — radio list ─────────────────────────────────
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

              // ── Rules ───────────────────────────────────────────────────
              const _FieldLabel('Rules'),
              const SizedBox(height: AppSpacing.sm),

              // Fixed Amount
              _RuleRow(
                label: 'Fixed Amount',
                child: SizedBox(
                  width: 120,
                  child: TextFormField(
                    controller: _fixedAmountCtrl,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.end,
                    decoration: InputDecoration(
                      prefixText: '₦ ',
                      isDense: true,
                      hintText: 'Enter amount',
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ),
              ),
              const _Divider(),

              // Max Charges
              _RuleRow(
                label: 'Max Charges',
                child: SizedBox(
                  width: 80,
                  child: TextFormField(
                    controller: _maxChargesCtrl,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.end,
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: '∞',
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ),
              ),
              const _Divider(),

              // Night Lockdown
              _RuleRow(
                label: 'Night Lockdown',
                subtitle: 'Block 12:00 AM – 6:00 AM',
                child: Switch(
                  value: _nightLockdown,
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

              // Instant Breach Alert
              _RuleRow(
                label: 'Instant Breach Alert',
                subtitle: 'Push notification on breach',
                child: Switch(
                  value: _instantBreachAlert,
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
                const _FieldLabel('Billing Address (Required for Verification)'),
                const SizedBox(height: AppSpacing.sm),
                // ── Country Dropdown ──
                DropdownButtonFormField<String>(
                  initialValue: _country,
                  decoration: InputDecoration(
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                    filled: true,
                    fillColor: AppColors.surfaceContainerLowest,
                  ),
                  items: const [
                    DropdownMenuItem(value: 'Nigeria', child: Text('Nigeria')),
                    DropdownMenuItem(value: 'Ghana', child: Text('Ghana')),
                    DropdownMenuItem(value: 'Kenya', child: Text('Kenya')),
                    DropdownMenuItem(value: 'South Africa', child: Text('South Africa')),
                    DropdownMenuItem(value: 'Uganda', child: Text('Uganda')),
                    DropdownMenuItem(value: 'Zambia', child: Text('Zambia')),
                    DropdownMenuItem(value: 'Zimbabwe', child: Text('Zimbabwe')),
                    DropdownMenuItem(value: 'Rwanda', child: Text('Rwanda')),
                    DropdownMenuItem(value: 'Tanzania', child: Text('Tanzania')),
                    DropdownMenuItem(value: 'Egypt', child: Text('Egypt')),
                    DropdownMenuItem(value: 'Other/Global', child: Text('Other/Global')),
                  ],
                  onChanged: (v) {
                     if (v != null) setState(() => _country = v);
                  },
                ),
                const SizedBox(height: AppSpacing.md),
                TextFormField(
                  controller: _addressCtrl,
                  decoration: InputDecoration(
                    hintText: 'Street Address',
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
                      child: TextFormField(
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
                
                if (_country != 'Nigeria') ...[
                  const SizedBox(height: 28),
                  const _FieldLabel('Global KYC Requirements'),
                  const SizedBox(height: AppSpacing.sm),
                  DropdownButtonFormField<String>(
                    initialValue: _idType,
                    decoration: InputDecoration(
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                      filled: true,
                      fillColor: AppColors.surfaceContainerLowest,
                    ),
                    items: const [
                      DropdownMenuItem(value: 'Passport', child: Text('International Passport')),
                      DropdownMenuItem(value: 'National ID', child: Text('National ID')),
                      DropdownMenuItem(value: 'Drivers License', child: Text('Drivers License')),
                    ],
                    onChanged: (v) {
                       if (v != null) setState(() => _idType = v);
                    },
                  ),
                  const SizedBox(height: AppSpacing.md),
                  TextFormField(
                    controller: _idNumberCtrl,
                    decoration: InputDecoration(
                      hintText: 'Document Number',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                      filled: true,
                      fillColor: AppColors.surfaceContainerLowest,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _pickImage(false),
                          icon: Icon(Icons.credit_card, size: 20, color: _idImageFile != null ? AppColors.primary : AppColors.outline),
                          label: Text(_idImageFile != null ? 'ID Captured' : 'Upload ID', style: TextStyle(color: _idImageFile != null ? AppColors.primary : AppColors.onSurface)),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _pickImage(true),
                          icon: Icon(Icons.face, size: 20, color: _selfieImageFile != null ? AppColors.primary : AppColors.outline),
                          label: Text(_selfieImageFile != null ? 'Selfie Captured' : 'Take Selfie', style: TextStyle(color: _selfieImageFile != null ? AppColors.primary : AppColors.onSurface)),
                        ),
                      ),
                    ],
                  ),
                ],
              ],

              const SizedBox(height: AppSpacing.md),
            ],
          ),
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
        child: GkButton(
          label: 'Create Card',
          icon: Icons.credit_card_rounded,
          isLoading: _isLoading,
          onPressed: _createCard,
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


class _PlanSelectionView extends ConsumerStatefulWidget {
  final dynamic user; // UserModel
  const _PlanSelectionView({required this.user});
  @override
  ConsumerState<_PlanSelectionView> createState() => _PlanSelectionViewState();
}

class _PlanSelectionViewState extends ConsumerState<_PlanSelectionView> {
  bool _isLoading = false;

  Future<void> _purchasePlan(String planId, int cost) async {
    final user = widget.user;
    final uid = user?.uid as String?;
    final email = user?.email as String?;

    if (uid == null || email == null) {
      GkToast.show(context, message: 'Please complete your profile first.', type: ToastType.error);
      return;
    }

    final wallet = ref.read(walletProvider).valueOrNull;
    final currentBalance = wallet?.balance ?? 0.0;
    final canPayFromVault = currentBalance >= cost;

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetCtx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: AppColors.outlineVariant, borderRadius: BorderRadius.circular(2)))),
              const SizedBox(height: 24),
              Text('Select Payment Method', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              Text('How would you like to pay for this plan?', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.onSurfaceVariant)),
              const SizedBox(height: 24),

              // Vault Option
              InkWell(
                onTap: () {
                  Navigator.pop(sheetCtx);
                  if (canPayFromVault) {
                    _payFromVault(planId);
                  } else {
                    GkToast.show(context, message: 'Insufficient funds in vault.', type: ToastType.error);
                  }
                },
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    border: Border.all(color: canPayFromVault ? AppColors.primary : AppColors.outlineVariant),
                    borderRadius: BorderRadius.circular(16),
                    color: canPayFromVault ? AppColors.primaryContainer.withValues(alpha: 0.1) : AppColors.surfaceContainerLowest,
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.account_balance_wallet_rounded, color: canPayFromVault ? AppColors.primary : AppColors.outline, size: 28),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Pay from Vault', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700, color: canPayFromVault ? AppColors.onSurface : AppColors.outline)),
                            Text('Balance: ₦${currentBalance.toStringAsFixed(2)}', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.onSurfaceVariant)),
                          ],
                        ),
                      ),
                      if (!canPayFromVault)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(color: AppColors.errorContainer, borderRadius: BorderRadius.circular(8)),
                          child: Text('Insufficient', style: TextStyle(color: AppColors.error, fontSize: 10, fontWeight: FontWeight.bold)),
                        )
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Bank / Paystack Option
              InkWell(
                onTap: () {
                  Navigator.pop(sheetCtx);
                  _payWithPaystack(planId, cost, uid, email);
                },
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    border: Border.all(color: AppColors.outlineVariant),
                    borderRadius: BorderRadius.circular(16),
                    color: AppColors.surfaceContainerLowest,
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.credit_card_rounded, color: AppColors.primary, size: 28),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Pay with Bank / Card', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                            Text('Via secure checkout', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.onSurfaceVariant)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _payFromVault(String planId) async {
    setState(() => _isLoading = true);
    try {
      final callable = FirebaseFunctions.instance.httpsCallable('purchasePlanFromVault');
      await callable.call({'plan': planId});
      if (mounted) {
        GkToast.show(context,
            message: '${planId[0].toUpperCase()}${planId.substring(1)} Plan Activated! 🎉',
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

  Future<void> _payWithPaystack(String planId, int cost, String uid, String email) async {
    final reference = 'GTK-PLAN-${uid.substring(0, 6)}-${DateTime.now().millisecondsSinceEpoch}';
    final amountInKobo = cost * 100;

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _PlanPaystackCheckout(
          planId: planId,
          planName: planId[0].toUpperCase() + planId.substring(1),
          amountInNgn: cost.toDouble(),
          email: email,
          uid: uid,
          reference: reference,
          onPaymentSuccess: (String paidReference) async {
            setState(() => _isLoading = true);
            try {
              final callable = FirebaseFunctions.instance.httpsCallable('purchasePlan');
              await callable.call({'plan': planId, 'reference': paidReference});
              if (mounted) {
                GkToast.show(context,
                    message: '${planId[0].toUpperCase()}${planId.substring(1)} Plan Activated! 🎉',
                    type: ToastType.success);
              }
            } catch (e) {
              if (mounted) {
                GkToast.show(context, message: 'Activation failed: $e', type: ToastType.error);
              }
            } finally {
              if (mounted) setState(() => _isLoading = false);
            }
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: AppColors.primary));
    }
    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: () async {
        ref.invalidate(userProfileProvider);
        await Future.delayed(const Duration(milliseconds: 800));
      },
      child: ListView(
        padding: const EdgeInsets.only(left: 20, right: 20, top: 20, bottom: 140),
        children: [
          Text(
            'Initialize your Account',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Text(
            'Select a baseline subscription tier to start issuing cards. This is a one-time deduction.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.onSurfaceVariant),
          ),
          const SizedBox(height: 24),
          _buildPlanCard('Instant Plan', 'free', 700, ['1 Card Included', 'Basic Rules'], false),
          const SizedBox(height: 16),
          _buildPlanCard('Activation Plan', 'activation', 1400, ['2 Cards Included', 'Basic Rules', 'No limits on top-ups'], false),
          const SizedBox(height: 16),
          _buildPlanCard('Sentinel Prime', 'premium', 2000, [
            'Smart Alert (breach, activity)',
            'Savings insight',
            'Team Access',
            'Client Profile management',
            'Night blocks',
            'Geofencing',
            'Advanced Rules',
            'Priority Protection',
            'Scan for subscription patterns',
          ], true),
          const SizedBox(height: 16),
          _buildPlanCard('Business Plan', 'business', 5000, ['5 Cards Included', 'Priority Protection', 'Team Access'], false),
        ],
      ),
    );
  }

  Widget _buildPlanCard(String name, String id, int price, List<String> features, bool isPopular) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: isPopular ? AppColors.primary : AppColors.outlineVariant),
        color: isPopular ? AppColors.primary.withValues(alpha: 0.05) : AppColors.surfaceContainerLowest,
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isPopular)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(12)),
              child: const Text('RECOMMENDED', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
            ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(name, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
              Text('₦$price', style: Theme.of(context).textTheme.titleLarge?.copyWith(color: AppColors.primary, fontWeight: FontWeight.w800)),
            ],
          ),
          const SizedBox(height: 16),
          ...features.map((f) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                const Icon(Icons.check_circle, color: AppColors.primary, size: 16),
                const SizedBox(width: 8),
                Expanded(child: Text(f, style: Theme.of(context).textTheme.bodyMedium)),
              ],
            ),
          )),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                backgroundColor: isPopular ? AppColors.primary : Colors.transparent,
                foregroundColor: isPopular ? Colors.white : AppColors.primary,
                side: const BorderSide(color: AppColors.primary),
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () => _purchasePlan(id, price),
              child: Text('Select $name', style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Plan Paystack Checkout ─────────────────────────────────────────────────────
/// A dedicated Paystack WebView checkout for plan purchases.
/// Passes metadata.plan so the webhook can route the payment to plan activation.
class _PlanPaystackCheckout extends StatefulWidget {
  final String planId;
  final String planName;
  final double amountInNgn;
  final String email;
  final String uid;
  final String reference;
  final Future<void> Function(String reference) onPaymentSuccess;

  const _PlanPaystackCheckout({
    required this.planId,
    required this.planName,
    required this.amountInNgn,
    required this.email,
    required this.uid,
    required this.reference,
    required this.onPaymentSuccess,
  });

  @override
  State<_PlanPaystackCheckout> createState() => _PlanPaystackCheckoutState();
}

class _PlanPaystackCheckoutState extends State<_PlanPaystackCheckout> {
  late final WebViewController _controller;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    final amountInKobo = (widget.amountInNgn * 100).toInt();

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onPageFinished: (_) => setState(() => _isLoading = false),
        onNavigationRequest: (req) {
          if (req.url.startsWith('gatekipa://payment-success')) {
            final uri = Uri.parse(req.url);
            final ref = uri.queryParameters['reference'] ?? widget.reference;
            Navigator.pop(context);
            widget.onPaymentSuccess(ref);
            return NavigationDecision.prevent;
          }
          if (req.url.startsWith('gatekipa://payment-cancelled')) {
            Navigator.pop(context);
            return NavigationDecision.prevent;
          }
          return NavigationDecision.navigate;
        },
      ))
      ..loadHtmlString(_buildHtml(amountInKobo));
  }

  String _buildHtml(int amountInKobo) {
    final planLabel = widget.planName;
    final amountNgn = (amountInKobo / 100).toStringAsFixed(0);
    return '''
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
  <title>Secure Payment</title>
  <script src="https://js.paystack.co/v1/inline.js"></script>
  <style>
    * { margin: 0; padding: 0; box-sizing: border-box; }
    body {
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
      background: #f8fafc;
      display: flex;
      flex-direction: column;
      align-items: center;
      justify-content: center;
      min-height: 100vh;
      padding: 24px;
    }
    .card {
      background: white;
      border-radius: 20px;
      padding: 32px 24px;
      text-align: center;
      box-shadow: 0 4px 24px rgba(0,0,0,0.08);
      width: 100%;
      max-width: 400px;
    }
    .shield { font-size: 48px; margin-bottom: 16px; }
    h1 { font-size: 22px; font-weight: 800; color: #1a6b47; margin-bottom: 4px; }
    .plan-badge {
      display: inline-block;
      background: #e8f5ee;
      color: #1a6b47;
      border-radius: 20px;
      padding: 4px 14px;
      font-size: 13px;
      font-weight: 700;
      margin: 8px 0 12px;
    }
    p { font-size: 14px; color: #6b7280; margin-bottom: 4px; }
    .amount { font-size: 36px; font-weight: 800; color: #1a6b47; margin: 16px 0; }
    .btn {
      display: inline-block;
      background: #1a6b47;
      color: white;
      border: none;
      border-radius: 12px;
      padding: 16px 32px;
      font-size: 16px;
      font-weight: 700;
      cursor: pointer;
      width: 100%;
      margin-top: 16px;
    }
    .btn:active { opacity: 0.85; }
    .lock { font-size: 12px; color: #9ca3af; margin-top: 16px; }
  </style>
</head>
<body>
  <div class="card">
    <div class="shield">🛡️</div>
    <h1>Gatekipa</h1>
    <div class="plan-badge">$planLabel Plan</div>
    <p>One-time plan activation fee</p>
    <div class="amount">₦$amountNgn</div>
    <p style="font-size:13px;color:#4b5563">${widget.email}</p>
    <button class="btn" onclick="payWithPaystack()">Pay Securely</button>
    <div class="lock">🔒 Secured by Westgate Stratagem · PCI DSS compliant</div>
  </div>

  <script>
    function payWithPaystack() {
      var handler = PaystackPop.setup({
        key: '${AppConstants.paystackPublicKey}',
        email: '${widget.email}',
        amount: $amountInKobo,
        currency: 'NGN',
        ref: '${widget.reference}',
        metadata: {
          uid: '${widget.uid}',
          plan: '${widget.planId}',
          custom_fields: [
            { display_name: 'Plan', variable_name: 'plan', value: '$planLabel' }
          ]
        },
        onClose: function() {
          window.location.href = 'gatekipa://payment-cancelled';
        },
        callback: function(response) {
          window.location.href = 'gatekipa://payment-success?reference=' + response.reference;
        }
      });
      handler.openIframe();
    }

    window.onload = function() {
      setTimeout(payWithPaystack, 300);
    };
  </script>
</body>
</html>
''';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: Text('Activate ${widget.planName} Plan',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800, color: AppColors.primary)),
        leading: const BackButton(color: AppColors.onSurface),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Row(children: [
              const Icon(Icons.lock_rounded, size: 14, color: AppColors.outline),
              const SizedBox(width: 4),
              Text('Westgate Stratagem',
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(fontSize: 12, color: AppColors.outline)),
            ]),
          ),
        ],
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_isLoading)
            const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: AppColors.primary),
                  SizedBox(height: 16),
                  Text('Loading secure checkout…'),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
