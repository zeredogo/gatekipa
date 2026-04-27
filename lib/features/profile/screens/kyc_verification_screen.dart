import 'dart:io';
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

    setState(() => _isLoading = true);

    try {
      final uid = FirebaseAuth.instance.currentUser?.uid ?? 'unknown';
      final timestamp = DateTime.now().millisecondsSinceEpoch;

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

      // Call verification function with uploaded document URLs and ID number
      final result = await FirebaseFunctions.instance
          .httpsCallable('verifyKyc')
          .call({
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
        // Invalidate user profile to refresh KYC status
        ref.invalidate(userProfileProvider);
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
      String msg = e.message ?? 'Verification failed. Please try again.';
      if (msg.toLowerCase().contains('status code') || msg.toLowerCase().contains('internal') || msg.length > 120) {
        msg = 'The verification service is temporarily unavailable. Please try again later.';
      }
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
          style: GoogleFonts.manrope(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: AppColors.onSurface,
          ),
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
                const SizedBox(height: 24),
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
                  style: GoogleFonts.manrope(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: AppColors.onSurface,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  isVerified
                      ? 'Your identity has been fully verified. You have full access to all Gatekipa vault features.'
                      : 'Please verify your identity to unlock all features, including virtual cards.',
                  style: GoogleFonts.inter(
                    fontSize: 15,
                    color: AppColors.onSurfaceVariant,
                    height: 1.5,
                  ),
                  textAlign: TextAlign.center,
                ),
                  if (!isVerified)
                    Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // ── Country Dropdown ──
                          Text(
                            'Country',
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AppColors.onSurfaceVariant,
                            ),
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
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AppColors.onSurfaceVariant,
                            ),
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
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: AppColors.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Please provide your BVN or NIN.',
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                color: AppColors.outline,
                                height: 1.4,
                              ),
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
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: AppColors.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Upload a clear photo of your National ID, Passport, etc.',
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                color: AppColors.outline,
                                height: 1.4,
                              ),
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
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AppColors.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Take a clear selfie with your front camera. Ensure your face is well-lit and visible.',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              color: AppColors.outline,
                              height: 1.4,
                            ),
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
                        label: 'Contact Support for Adjustments',
                        onPressed: () {
                          // Redirect to support or show support info
                          GkToast.show(context, message: 'Please contact support@gatekipa.com to adjust your KYC information.', type: ToastType.info);
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
                      style: GoogleFonts.inter(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: isCompleted ? AppColors.primary : AppColors.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: AppColors.outline,
                      ),
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

