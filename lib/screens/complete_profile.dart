import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../main.dart';
import '../models/provider_profile.dart';
import '../services/api_config.dart';
import '../services/provider_service.dart';

/// A single scrollable verification form — Personal Information,
/// Professional Information, Documents, and Alternative Details — each
/// shown as a numbered section, with one "Continue" button at the bottom
/// that saves everything at once.
class CompleteProfilePage extends StatefulWidget {
  final String accessToken;
  final ProviderProfile currentProfile;

  const CompleteProfilePage({
    super.key,
    required this.accessToken,
    required this.currentProfile,
  });

  @override
  State<CompleteProfilePage> createState() => _CompleteProfilePageState();
}

class _CompleteProfilePageState extends State<CompleteProfilePage> {
  final _formKey = GlobalKey<FormState>();

  bool _loadingOptions = true;
  bool _isSaving = false;
  String? _errorMessage;
  ProfileFormOptions _options = ProfileFormOptions.fallback;

  late final TextEditingController _bioController;
  late final TextEditingController _citizenshipNumberController;
  late final TextEditingController _emailController;
  late final TextEditingController _alternativePhoneController;
  late final TextEditingController _dateOfBirthController;

  DateTime? _dateOfBirth;
  String? _serviceCategory;
  String? _experience;

  final _picker = ImagePicker();
  File? _frontImage;
  File? _backImage;
  String? _existingFrontUrl;
  String? _existingBackUrl;

  static const _defaultCity = 'Kathmandu';

  @override
  void initState() {
    super.initState();
    final p = widget.currentProfile;

    _bioController = TextEditingController(text: p.bio ?? '');
    _citizenshipNumberController = TextEditingController(text: p.citizenshipNumber ?? '');
    _emailController = TextEditingController(text: p.alternativeEmail ?? '');
    _alternativePhoneController = TextEditingController(text: p.alternativePhone ?? '');

    _dateOfBirth = p.dateOfBirth;
    _dateOfBirthController = TextEditingController(text: _formatDate(_dateOfBirth));
    _serviceCategory = p.serviceCategory;
    _experience = p.experience;
    _existingFrontUrl = p.citizenshipFrontUrl;
    _existingBackUrl = p.citizenshipBackUrl;

    _loadFormOptions();
  }

  String _formatDate(DateTime? d) {
    if (d == null) return '';
    return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  Future<void> _pickDateOfBirth() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _dateOfBirth ?? DateTime(now.year - 18, now.month, now.day),
      firstDate: DateTime(now.year - 100),
      lastDate: DateTime(now.year - 18, now.month, now.day),
      helpText: 'Select date of birth',
    );
    if (picked == null) return;
    setState(() {
      _dateOfBirth = picked;
      _dateOfBirthController.text = _formatDate(picked);
    });
  }

  Future<void> _loadFormOptions() async {
    final options = await ProviderService.getFormOptions();
    if (!mounted) return;
    setState(() {
      _options = options;
      _loadingOptions = false;
    });
  }

  @override
  void dispose() {
    _bioController.dispose();
    _citizenshipNumberController.dispose();
    _emailController.dispose();
    _alternativePhoneController.dispose();
    _dateOfBirthController.dispose();
    super.dispose();
  }


  static const _allowedImageExtensions = {'.jpg', '.jpeg', '.png'};
  static const _maxImageBytes = 5 * 1024 * 1024; // 5 MB per file

  Future<void> _pickImage({required bool isFront}) async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Take a photo'),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from gallery'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null) return;

    final picked = await _picker.pickImage(source: source, imageQuality: 85);
    if (picked == null) return;

    final ext = picked.path.contains('.') ? '.${picked.path.split('.').last.toLowerCase()}' : '';
    if (!_allowedImageExtensions.contains(ext)) {
      _showUploadError('Allowed formats: JPG, JPEG, PNG.');
      return;
    }

    final file = File(picked.path);
    if (await file.length() > _maxImageBytes) {
      _showUploadError('Maximum size: 5 MB per file.');
      return;
    }

    setState(() {
      if (isFront) {
        _frontImage = file;
      } else {
        _backImage = file;
      }
    });
  }

  void _showUploadError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  bool get _hasFrontDocument => _frontImage != null || _existingFrontUrl != null;
  bool get _hasBackDocument => _backImage != null || _existingBackUrl != null;

  Future<void> _handleContinue() async {
    setState(() => _errorMessage = null);

    final formOk = _formKey.currentState!.validate();
    final docsOk = _hasFrontDocument && _hasBackDocument;

    if (!formOk || !docsOk) {
      setState(() {
        _errorMessage = !docsOk
            ? 'Upload both the front and back of your citizenship.'
            : 'Please fix the highlighted fields.';
      });
      return;
    }

    setState(() => _isSaving = true);

    try {
      await ProviderService.updateMyProfile(
        accessToken: widget.accessToken,
        dateOfBirth: _dateOfBirth,
        serviceCategory: _serviceCategory,
        bio: _bioController.text.trim(),
        experience: _experience,
        citizenshipNumber: _citizenshipNumberController.text.trim(),
        alternativeEmail: _emailController.text.trim(),
        alternativePhone: _alternativePhoneController.text.trim().isEmpty
            ? null
            : _alternativePhoneController.text.trim(),
      );

      if (_frontImage != null || _backImage != null) {
        await ProviderService.uploadCitizenshipDocuments(
          accessToken: widget.accessToken,
          front: _frontImage,
          back: _backImage,
        );
      }

      if (!mounted) return;
      Navigator.pop(context, true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile submitted for verification.')),
      );
    } on ProviderServiceException catch (e) {
      setState(() => _errorMessage = e.message);
    } catch (_) {
      setState(() => _errorMessage = 'Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kLightGreenBg,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Complete Your Profile'),
        backgroundColor: kLightGreenBg,
        foregroundColor: kDarkText,
        elevation: 0,
        centerTitle: false,
      ),
      body: _loadingOptions
          ? const Center(child: CircularProgressIndicator(color: kPrimaryGreen))
          : Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          children: [
            if (_errorMessage != null) _buildErrorBanner(),
            _SectionCard(
              number: 1,
              icon: Icons.person_outline_rounded,
              title: 'Personal Information',
              children: [
                _label('City'),
                TextFormField(
                  initialValue: _defaultCity,
                  enabled: false,
                  decoration: _fieldDecoration(hint: 'City', icon: Icons.map_outlined),
                ),
                const SizedBox(height: 16),
                _label('Date of Birth'),
                TextFormField(
                  controller: _dateOfBirthController,
                  readOnly: true,
                  onTap: _pickDateOfBirth,
                  decoration: _fieldDecoration(hint: 'Select your date of birth', icon: Icons.cake_outlined),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
              ],
            ),
            const SizedBox(height: 16),
            _SectionCard(
              number: 2,
              icon: Icons.work_outline_rounded,
              title: 'Professional Information',
              children: [
                _label('Service Category'),
                DropdownButtonFormField<String>(
                  initialValue: _serviceCategory,
                  decoration: _fieldDecoration(hint: 'Select service category', icon: Icons.grid_view_rounded),
                  items: _options.serviceCategories
                      .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                      .toList(),
                  onChanged: (v) => setState(() => _serviceCategory = v),
                  validator: (v) => v == null ? 'Select a service category' : null,
                ),
                const SizedBox(height: 16),
                _label('Additional Information / Bio'),
                TextFormField(
                  controller: _bioController,
                  maxLines: 4,
                  maxLength: 500,
                  decoration: _fieldDecoration(hint: 'Tell us about yourself, your skills, and what you do...', icon: Icons.description_outlined),
                  validator: (v) => (v == null || v.trim().length < 10) ? 'Write at least a couple of sentences' : null,
                ),
                const SizedBox(height: 4),
                _label('Experience'),
                DropdownButtonFormField<String>(
                  initialValue: _experience,
                  decoration: _fieldDecoration(hint: 'Select experience', icon: Icons.event_outlined),
                  items: _options.experienceRanges
                      .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                      .toList(),
                  onChanged: (v) => setState(() => _experience = v),
                  validator: (v) => v == null ? 'Select your experience' : null,
                ),
              ],
            ),
            const SizedBox(height: 16),
            _SectionCard(
              number: 3,
              icon: Icons.description_outlined,
              title: 'Documents',
              children: [
                _label('Citizenship No.'),
                TextFormField(
                  controller: _citizenshipNumberController,
                  decoration: _fieldDecoration(hint: 'Enter citizenship number', icon: Icons.badge_outlined),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: _DocumentTile(
                        label: 'Citizenship Photo (Front View)',
                        subLabel: 'JPG, JPEG, PNG - Max 5MB',
                        file: _frontImage,
                        existingUrl: _existingFrontUrl != null ? '$apiBaseUrl$_existingFrontUrl' : null,
                        onTap: () => _pickImage(isFront: true),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _DocumentTile(
                        label: 'Citizenship Photo (Back View)',
                        subLabel: 'JPG, JPEG, PNG - Max 5MB',
                        file: _backImage,
                        existingUrl: _existingBackUrl != null ? '$apiBaseUrl$_existingBackUrl' : null,
                        onTap: () => _pickImage(isFront: false),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),
            _SectionCard(
              number: 4,
              icon: Icons.phone_outlined,
              title: 'Alternative Details',
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _label('Email', required: true),
                          TextFormField(
                            controller: _emailController,
                            keyboardType: TextInputType.emailAddress,
                            decoration: _fieldDecoration(hint: 'Enter your email address', icon: Icons.email_outlined),
                            validator: (v) {
                              final value = v?.trim() ?? '';
                              if (value.isEmpty) return 'Email is required';
                              if (!RegExp(r'^[\w.\-+]+@[\w\-]+\.[a-zA-Z]{2,}$').hasMatch(value)) {
                                return 'Enter a valid email';
                              }
                              return null;
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _label('Alternative Phone Number'),
                          TextFormField(
                            controller: _alternativePhoneController,
                            keyboardType: TextInputType.phone,
                            decoration: _fieldDecoration(hint: 'Enter alternative phone number (Optional)', icon: Icons.phone_outlined),
                            validator: (v) {
                              final value = v?.trim() ?? '';
                              if (value.isEmpty) return null;
                              final digits = value.replaceAll(RegExp(r'[^0-9]'), '');
                              if (digits.length < 7) return 'Enter a valid phone number';
                              return null;
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _isSaving ? null : _handleContinue,
              style: ElevatedButton.styleFrom(
                backgroundColor: kPrimaryGreen,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: _isSaving
                  ? const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              )
                  : const Text('Continue', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            ),
          ),
        ),
      ),
    );
  }

  /// Fixed-height, single-line label used above form fields. Capped to one
  /// line (with ellipsis) and given a constant height so that when two of
  /// these sit side by side in a Row — e.g. "Email" next to "Alternative
  /// Phone Number" — neither label's text length can push the field below
  /// it down further than the other, which is what was causing the
  /// verification form's boxes to drift out of alignment.
  Widget _label(String text, {bool required = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: SizedBox(
        height: 18,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Flexible(
              child: Text(
                text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: kDarkText),
              ),
            ),
            if (required) const Text(' *', style: TextStyle(color: Colors.red, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorBanner() {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.red.shade200),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: Colors.red.shade700, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(_errorMessage!, style: TextStyle(color: Colors.red.shade700, fontSize: 13)),
          ),
        ],
      ),
    );
  }

  InputDecoration _fieldDecoration({required String hint, required IconData icon}) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: Colors.grey.shade500, fontSize: 13),
      prefixIcon: Icon(icon, color: kPrimaryGreen, size: 20),
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      disabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey.shade200),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: kPrimaryGreen),
      ),
    );
  }

}

/// A numbered section card matching the "1 / 2 / 3 / 4" verification-form
/// mockup: a light-green header strip with a filled circular number badge
/// and an icon, followed by a white content panel.
class _SectionCard extends StatelessWidget {
  final int number;
  final IconData icon;
  final String title;
  final List<Widget> children;

  const _SectionCard({
    required this.number,
    required this.icon,
    required this.title,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            color: kLightGreenBg,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 14,
                  backgroundColor: kPrimaryGreen,
                  child: Text(
                    '$number',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ),
                const SizedBox(width: 10),
                Icon(icon, color: kPrimaryGreen, size: 20),
                const SizedBox(width: 8),
                Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: kDarkText)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
          ),
        ],
      ),
    );
  }
}

class _DocumentTile extends StatelessWidget {
  final String label;
  final String subLabel;
  final File? file;
  final String? existingUrl;
  final VoidCallback onTap;

  const _DocumentTile({
    required this.label,
    required this.subLabel,
    required this.onTap,
    this.file,
    this.existingUrl,
  });

  @override
  Widget build(BuildContext context) {
    final hasImage = file != null || existingUrl != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.image_outlined, size: 16, color: Colors.grey.shade600),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: kDarkText),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: DottedBorderBox(
            child: SizedBox(
              height: 120,
              width: double.infinity,
              child: hasImage
                  ? Stack(
                fit: StackFit.expand,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: file != null
                        ? Image.file(file!, fit: BoxFit.cover)
                        : Image.network(existingUrl!, fit: BoxFit.cover),
                  ),
                  Positioned(
                    right: 6,
                    bottom: 6,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(color: kPrimaryGreen, shape: BoxShape.circle),
                      child: const Icon(Icons.edit, size: 14, color: Colors.white),
                    ),
                  ),
                ],
              )
                  : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: const BoxDecoration(color: kPrimaryGreen, shape: BoxShape.circle),
                    child: const Icon(Icons.camera_alt_outlined, color: Colors.white, size: 18),
                  ),
                  const SizedBox(height: 8),
                  Text('Tap to upload ${label.contains('Front') ? 'front' : 'back'} side',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
                  const SizedBox(height: 2),
                  Text('($subLabel)', style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// A lightweight dashed-border container to match the upload tiles in the
/// mockup, without pulling in an extra package for one border style.
class DottedBorderBox extends StatelessWidget {
  final Widget child;
  const DottedBorderBox({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _DashedBorderPainter(color: kPrimaryGreen.withValues(alpha: 0.4)),
      child: Padding(padding: const EdgeInsets.all(8), child: child),
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  final Color color;
  _DashedBorderPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.4
      ..style = PaintingStyle.stroke;

    final rrect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, size.width, size.height),
      const Radius.circular(12),
    );

    const dashWidth = 6.0;
    const dashSpace = 4.0;
    final path = Path()..addRRect(rrect);

    for (final metric in path.computeMetrics()) {
      double distance = 0;
      while (distance < metric.length) {
        final next = distance + dashWidth;
        canvas.drawPath(metric.extractPath(distance, next), paint);
        distance = next + dashSpace;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedBorderPainter oldDelegate) => oldDelegate.color != color;
}