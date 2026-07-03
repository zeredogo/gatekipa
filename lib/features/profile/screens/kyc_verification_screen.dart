import 'dart:io';
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/gk_button.dart';
import '../../../core/widgets/gk_toast.dart';
import '../../../core/constants/routes.dart';
import '../../auth/providers/auth_provider.dart';

// ── Comprehensive country list for global users ──
const List<String> _kCountries = [
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

// ── States/provinces per country (key countries) ──
const Map<String, List<String>> _kStates = {
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
  'United States': ['California', 'Texas', 'Florida', 'New York', 'Illinois', 'Pennsylvania', 'Ohio', 'Georgia', 'Michigan', 'North Carolina', 'New Jersey', 'Virginia', 'Washington', 'Arizona', 'Massachusetts', 'Tennessee', 'Indiana', 'Maryland', 'Missouri', 'Wisconsin', 'Colorado', 'Minnesota', 'South Carolina', 'Alabama', 'Louisiana', 'Kentucky', 'Oregon', 'Oklahoma', 'Connecticut', 'Utah', 'Iowa', 'Nevada', 'Arkansas', 'Mississippi', 'Kansas', 'Other'],
  'United Kingdom': ['England', 'Scotland', 'Wales', 'Northern Ireland'],
  'Canada': ['Ontario', 'Quebec', 'British Columbia', 'Alberta', 'Manitoba', 'Saskatchewan', 'Nova Scotia', 'New Brunswick', 'Newfoundland', 'Prince Edward Island'],
  'India': ['Maharashtra', 'Karnataka', 'Tamil Nadu', 'Delhi', 'Uttar Pradesh', 'Gujarat', 'West Bengal', 'Telangana', 'Rajasthan', 'Kerala', 'Other'],
};

class KycVerificationScreen extends ConsumerStatefulWidget {
  const KycVerificationScreen({super.key});

  @override
  ConsumerState<KycVerificationScreen> createState() => _KycVerificationScreenState();
}

class _KycVerificationScreenState extends ConsumerState<KycVerificationScreen> {
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;
  File? _documentProofFile;
  File? _selfieFile;
  String _selectedCountry = 'Nigeria';
  String? _selectedState;

  final _idNumberController = TextEditingController();

  @override
  void dispose() {
    _idNumberController.dispose();
    super.dispose();
  }

  Future<void> _pickDocumentProof() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (picked != null) {
      setState(() => _documentProofFile = File(picked.path));
      if (mounted) {
        GkToast.show(context, message: 'Document captured successfully', type: ToastType.success);
      }
    }
  }

  Future<void> _takeLivenessCheck() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.camera, imageQuality: 80, preferredCameraDevice: CameraDevice.front);
    if (picked != null) {
      setState(() => _selfieFile = File(picked.path));
      if (mounted) {
        GkToast.show(context, message: 'Selfie captured successfully', type: ToastType.success);
      }
    }
  }

  Future<String?> _uploadFile(File file, String path) async {
    try {
      final ref = FirebaseStorage.instance.ref().child(path);
      await ref.putFile(file);
      return await ref.getDownloadURL();
    } catch (e) {
      debugPrint('Upload error: $e');
      return null;
    }
  }

  Future<void> _verifyIdentity() async {
    if (!_formKey.currentState!.validate()) return;
    if (_isLoading) return;

    if (_selectedCountry == 'Nigeria') {
      if (_idNumberController.text.trim().isEmpty) {
        GkToast.show(context, message: 'Please enter your NIN, BVN, Driver\'s License or Passport Number', type: ToastType.error);
        return;
      }
    } else {
      if (_documentProofFile == null) {
        GkToast.show(context, message: 'Please upload a document proof (e.g. National ID, Passport)', type: ToastType.error);
        return;
      }
    }

    if (_selfieFile == null) {
      GkToast.show(context, message: 'Please complete the liveness check by taking a selfie', type: ToastType.error);
      return;
    }

    if (_selectedState == null) {
      GkToast.show(context, message: 'Please select your state / province', type: ToastType.error);
      return;
    }

    // ── Idempotency guard ───────────────────────────────────────────────────
    // If the user is already verified (e.g. from a previous attempt that timed
    // out client-side but succeeded server-side), navigate immediately instead
    // of calling the function again.
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final existingDoc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
    if ((existingDoc.data()?['kycStatus'] == 'verified' || existingDoc.data()?['kycStatus'] == 'approved') && mounted) {
      GkToast.show(context, message: 'Your identity is already verified! 🎉', type: ToastType.success);
      ref.invalidate(userProfileProvider);
      if (context.canPop()) {
        context.pop();
      } else {
        context.go(Routes.dashboard);
      }
      return;
    }

    setState(() => _isLoading = true);

    try {
      final timestamp = DateTime.now().millisecondsSinceEpoch;

      if (!mounted) return;
      GkToast.show(context, message: 'Uploading data...', type: ToastType.info);
      
      String? docUrl;
      if (_documentProofFile != null) {
        docUrl = await _uploadFile(_documentProofFile!, 'kyc/$uid/document_proof_$timestamp.jpg');
      }
      
      final selfieUrl = await _uploadFile(_selfieFile!, 'kyc/$uid/liveness_selfie_$timestamp.jpg');

      if (selfieUrl == null || (_selectedCountry != 'Nigeria' && docUrl == null)) {
        if (mounted) {
          GkToast.show(context, message: 'Failed to upload required documents. Please try again.', type: ToastType.error);
        }
        return;
      }

      // Call verification function — 120s timeout handles slow African connections
      // without producing false "failed" errors that encourage unnecessary retries.
      final callable = FirebaseFunctions.instance
          .httpsCallable('verifyKyc', options: HttpsCallableOptions(timeout: const Duration(seconds: 120)));
      final result = await callable.call({
        'documentUrl': docUrl,
        'selfieUrl': selfieUrl,
        'country': _selectedCountry,
        'state': _selectedState,
        'idNumber': _idNumberController.text.trim(),
      });

      if (!mounted) return;
      final dataMap = result.data as Map<dynamic, dynamic>;
      if (dataMap['success'] == true) {
        GkToast.show(context, message: 'Identity verified successfully! 🎉', type: ToastType.success);
        ref.invalidate(userProfileProvider);
        // Wait briefly for the Firestore stream to propagate before navigating.
        // This prevents the screen from rebuilding with stale "unverified" state.
        await Future.delayed(const Duration(milliseconds: 600));
        if (mounted) {
          if (context.canPop()) {
            context.pop();
          } else {
            context.go(Routes.dashboard);
          }
        }
      } else {
        GkToast.show(context, message: 'Verification failed. Please try again.', type: ToastType.error);
      }
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      // If the function timed out client-side, it may have succeeded server-side.
      // Check Firestore directly before showing an error to the user.
      if (e.code == 'deadline-exceeded' || e.message?.toLowerCase().contains('timeout') == true) {
        final checkDoc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
        final serverStatus = checkDoc.data()?['kycStatus'];
        if ((serverStatus == 'verified' || serverStatus == 'approved') && mounted) {
          GkToast.show(context, message: 'Identity verified successfully! 🎉', type: ToastType.success);
          ref.invalidate(userProfileProvider);
          await Future.delayed(const Duration(milliseconds: 600));
          if (mounted) {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go(Routes.dashboard);
            }
          }
          return;
        }
      }
      String msg = e.message ?? 'Verification failed. Please try again.';
      if (msg.toLowerCase().contains('status code') || msg.toLowerCase().contains('internal') || msg.length > 120) {
        msg = 'The verification service is temporarily unavailable. Please try again later.';
      }
      if (!mounted) return;
      GkToast.show(context, message: msg, type: ToastType.error);
    } catch (e) {
      if (!mounted) return;
      GkToast.show(context, message: 'Could not complete verification. Try again.', type: ToastType.error);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  List<String> _getStatesForCountry(String country) {
    return _kStates[country] ?? ['N/A — Enter manually'];
  }

  @override
  Widget build(BuildContext context) {
    final userAsync = ref.watch(userProfileProvider);

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: Text(
          'Identity Verification',
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
      body: userAsync.when(
        data: (user) {
          if (user == null) return const SizedBox.shrink();
          final isVerified = user.kycStatus == 'verified' || user.kycStatus == 'approved';

          return SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              24, 24, 24, MediaQuery.of(context).padding.bottom + 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Step 3 of 3',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: AppColors.primary,
                            )),
                    Text('Identity',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: AppColors.onSurfaceVariant,
                            )),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(100),
                  child: const LinearProgressIndicator(
                    value: 0.85,
                    minHeight: 6,
                    backgroundColor: AppColors.surfaceContainer,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(height: 32),
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: isVerified
                        ? AppColors.primary.withValues(alpha: 0.1)
                        : Colors.orange.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    isVerified ? Icons.verified_user_rounded : Icons.pending_actions_rounded,
                    size: 64,
                    color: isVerified ? AppColors.primary : Colors.orange,
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  isVerified ? 'Verification Complete' : 'Verification Pending',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: AppColors.onSurface,),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  isVerified
                      ? 'Your identity has been fully verified. You have full access to all Gatekipa vault features.'
                      : 'Please verify your identity to unlock all features, including virtual cards.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 15,
                    color: AppColors.onSurfaceVariant,
                    height: 1.5,),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),

                // ── KYC Progress Stepper ─────────────────────────────────
                _KycStepper(status: user.kycStatus),

                const SizedBox(height: 24),

                  if (!isVerified)
                    Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // ── Country Dropdown ──
                          Text(
                            'Country',
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AppColors.onSurfaceVariant,),
                          ),
                          const SizedBox(height: 8),
                          DropdownButtonFormField<String>(
                            initialValue: _selectedCountry,
                            isExpanded: true,
                            decoration: _inputDecoration(hint: 'Select country'),
                            items: _kCountries.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                            onChanged: (v) {
                              if (v != null) {
                                setState(() {
                                  _selectedCountry = v;
                                  _selectedState = null; // reset state on country change
                                });
                              }
                            },
                          ),
                          const SizedBox(height: 16),

                          // ── State / Province Dropdown ──
                          Text(
                            'State / Province',
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AppColors.onSurfaceVariant,),
                          ),
                          const SizedBox(height: 8),
                          DropdownButtonFormField<String>(
                            initialValue: _selectedState,
                            isExpanded: true,
                            decoration: _inputDecoration(hint: 'Select state / province'),
                            items: _getStatesForCountry(_selectedCountry)
                                .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                                .toList(),
                            onChanged: (v) {
                              if (v != null) setState(() => _selectedState = v);
                            },
                            validator: (v) => v == null ? 'Please select a state / province' : null,
                          ),
                          const SizedBox(height: 16),



                          const SizedBox(height: 16),

                          if (_selectedCountry == 'Nigeria') ...[
                            Text(
                              'Identification Number',
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: AppColors.onSurfaceVariant,),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Please provide your BVN or NIN.',
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 12,
                                color: AppColors.outline,
                                height: 1.4,),
                            ),
                            const SizedBox(height: 8),
                            TextFormField(
                              controller: _idNumberController,
                              keyboardType: TextInputType.text,
                              textCapitalization: TextCapitalization.characters,
                              decoration: _inputDecoration(
                                hint: 'Enter your ID number',
                                prefixIcon: const Icon(Icons.badge_rounded, color: AppColors.outlineVariant),
                              ),
                              validator: (v) {
                                if (_selectedCountry == 'Nigeria' && (v == null || v.trim().isEmpty)) {
                                  return 'Please enter an ID number';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 16),
                          ],

                          if (_selectedCountry != 'Nigeria') ...[
                            // ── Document Proof Upload ──
                            Text(
                              'Document Proof',
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: AppColors.onSurfaceVariant,),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Upload a clear photo of your National ID, Passport, etc.',
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 12,
                                color: AppColors.outline,
                                height: 1.4,),
                            ),
                            const SizedBox(height: 8),
                            _DocumentUploadCard(
                              icon: Icons.upload_file_rounded,
                              title: _documentProofFile != null ? 'Document Uploaded ✓' : 'Upload Document',
                              subtitle: _documentProofFile != null
                                  ? 'Tap to re-upload'
                                  : 'Tap here to capture image',
                              isCompleted: _documentProofFile != null,
                              onTap: _pickDocumentProof,
                            ),
                            const SizedBox(height: 16),
                          ],

                          // ── Liveness Check (Selfie) ──
                          Text(
                            'Liveness Check',
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AppColors.onSurfaceVariant,),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Take a clear selfie with your front camera. Ensure your face is well-lit and visible.',
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 12,
                              color: AppColors.outline,
                              height: 1.4,),
                          ),
                          const SizedBox(height: 8),
                          _DocumentUploadCard(
                            icon: Icons.camera_front_rounded,
                            title: _selfieFile != null ? 'Selfie Captured ✓' : 'Take Selfie',
                            subtitle: _selfieFile != null
                                ? 'Tap to retake'
                                : 'Front camera liveness verification',
                            isCompleted: _selfieFile != null,
                            onTap: _takeLivenessCheck,
                          ),
                          const SizedBox(height: 24),

                          GkButton(
                            label: 'Verify Identity',
                            isLoading: _isLoading,
                            onPressed: _verifyIdentity,
                          ),
                        ],
                      ),
                    )
                  else
                    Padding(
                      padding: const EdgeInsets.only(top: 24.0),
                      child: GkButton(
                        label: 'Go to Dashboard',
                        onPressed: () {
                          if (context.canPop()) {
                            context.pop();
                          } else {
                            context.go(Routes.dashboard);
                          }
                        },
                      ),
                    ),
              ],
            ),
          );
        },
        loading: () => const Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
        error: (e, _) => const Center(child: Text('Failed to load data. Please pull to refresh.')),
      ),
    );
  }

  InputDecoration _inputDecoration({
    required String hint,
    Widget? prefixIcon,
  }) {
    return InputDecoration(
      hintText: hint,
      prefixIcon: prefixIcon,
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
    );
  }
}

// ── Document Upload Card ────────────────────────────────────────────────────
class _DocumentUploadCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool isCompleted;
  final VoidCallback onTap;

  const _DocumentUploadCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.isCompleted,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isCompleted
          ? AppColors.primary.withValues(alpha: 0.06)
          : AppColors.surfaceBright,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isCompleted
                  ? AppColors.primary.withValues(alpha: 0.3)
                  : AppColors.outlineVariant.withValues(alpha: 0.3),
              width: 1.5,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: isCompleted
                      ? AppColors.primary.withValues(alpha: 0.15)
                      : AppColors.outline.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  isCompleted ? Icons.check_circle_rounded : icon,
                  color: isCompleted ? AppColors.primary : AppColors.outline,
                  size: 24,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: isCompleted ? AppColors.primary : AppColors.onSurface,),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 12,
                        color: AppColors.outline,),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: AppColors.outline,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── KYC Progress Stepper ──────────────────────────────────────────────────────
class _KycStepper extends StatelessWidget {
  final String status;
  const _KycStepper({required this.status});

  int get _activeStep {
    switch (status.toLowerCase()) {
      case 'none':
      case '':           return 0;
      case 'pending':
      case 'submitted':
      case 'processing': return 1;
      case 'verified':
      case 'approved':   return 2;
      default:           return 0;
    }
  }

  static const _steps = [
    (icon: Icons.upload_file_rounded,   label: 'ID Submitted'),
    (icon: Icons.manage_search_rounded, label: 'Under Review'),
    (icon: Icons.verified_user_rounded, label: 'Verified'),
  ];

  @override
  Widget build(BuildContext context) {
    final active = _activeStep;
    return Row(
      children: _steps.asMap().entries.map((entry) {
        final i     = entry.key;
        final step  = entry.value;
        final isDone    = i < active;
        final isCurrent = i == active;
        final Color stepColor = isDone
            ? AppColors.tertiary
            : isCurrent
                ? AppColors.primary
                : AppColors.outlineVariant;

        return Expanded(
          child: Row(
            children: [
              Expanded(
                child: Column(
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      width: 40, height: 40,
                      decoration: BoxDecoration(
                        color: isDone
                            ? AppColors.tertiary.withValues(alpha: 0.12)
                            : isCurrent
                                ? AppColors.primary.withValues(alpha: 0.1)
                                : AppColors.surfaceContainer,
                        shape: BoxShape.circle,
                        border: Border.all(color: stepColor,
                            width: isCurrent ? 2 : 1),
                      ),
                      child: Icon(
                        isDone ? Icons.check_rounded : step.icon,
                        size: 18, color: stepColor,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      step.label,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            fontSize: 10,
                            fontWeight: isCurrent
                                ? FontWeight.w700 : FontWeight.w500,
                            color: stepColor,
                          ),
                    ),
                  ],
                ),
              ),
              if (i < _steps.length - 1)
                Expanded(
                  child: Container(
                    height: 2,
                    margin: const EdgeInsets.only(bottom: 22),
                    color: i < active
                        ? AppColors.tertiary.withValues(alpha: 0.4)
                        : AppColors.outlineVariant.withValues(alpha: 0.3),
                  ),
                ),
            ],
          ),
        );
      }).toList(),
    );
  }
}
