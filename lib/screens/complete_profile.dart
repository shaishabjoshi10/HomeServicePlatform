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

  late final TextEditingController _permanentAddressController;
  late final TextEditingController _currentAddressController;
  late final TextEditingController _toleController;
  late final TextEditingController _wardNoController;
  late final TextEditingController _bioController;
  late final TextEditingController _citizenshipNumberController;
  late final TextEditingController _emailController;
  late final TextEditingController _alternativePhoneController;

  String? _maritalStatus;
  String? _city;
  String? _municipality;
  String? _serviceCategory;
  String? _experience;
  bool _sameAsPermanent = false;

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

    _permanentAddressController = TextEditingController(text: p.permanentAddress ?? '');
    _currentAddressController = TextEditingController(text: p.currentAddress ?? '');
    _toleController = TextEditingController(text: p.tole ?? '');
    _wardNoController = TextEditingController(text: p.wardNo?.toString() ?? '');
    _bioController = TextEditingController(text: p.bio ?? '');
    _citizenshipNumberController = TextEditingController(text: p.citizenshipNumber ?? '');
    _emailController = TextEditingController(text: p.alternativeEmail ?? '');
    _alternativePhoneController = TextEditingController(text: p.alternativePhone ?? '');

    _maritalStatus = p.maritalStatus;
    _city = p.city ?? _defaultCity;
    _municipality = p.municipality;
    _serviceCategory = p.serviceCategory;
    _experience = p.experience;
    _sameAsPermanent = p.permanentAddress != null && p.permanentAddress == p.currentAddress;
    _existingFrontUrl = p.citizenshipFrontUrl;
    _existingBackUrl = p.citizenshipBackUrl;

    _loadFormOptions();
  }

  Future<void> _loadFormOptions() async {
    final options = await ProviderService.getFormOptions();
    if (!mounted) return;
    setState(() {
      _options = options;
      // Keep an already-saved city/municipality even if either has since
      // fallen out of the predefined lists, so the dropdowns don't
      // silently blank out a value the provider already saved.
      var cities = _options.cities;
      var municipalitiesByCity = _options.municipalitiesByCity;

      if (_city != null && !cities.contains(_city)) {
        cities = [...cities, _city!];
      }
      if (_city != null && _municipality != null && !_options.municipalitiesFor(_city).contains(_municipality)) {
        municipalitiesByCity = {
          ...municipalitiesByCity,
          _city!: [...municipalitiesByCity[_city!] ?? const [], _municipality!],
        };
      }

      _options = ProfileFormOptions(
        serviceCategories: _options.serviceCategories,
        cities: cities,
        municipalitiesByCity: municipalitiesByCity,
        experienceRanges: _options.experienceRanges,
        maritalStatuses: _options.maritalStatuses,
      );
      _loadingOptions = false;
    });
  }

  @override
  void dispose() {
    _permanentAddressController.dispose();
    _currentAddressController.dispose();
    _toleController.dispose();
    _wardNoController.dispose();
    _bioController.dispose();
    _citizenshipNumberController.dispose();
    _emailController.dispose();
    _alternativePhoneController.dispose();
    super.dispose();
  }

  void _onSameAsPermanentChanged(bool? checked) {
    setState(() {
      _sameAsPermanent = checked ?? false;
      if (_sameAsPermanent) {
        _currentAddressController.text = _permanentAddressController.text;
      }
    });
  }

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

    setState(() {
      if (isFront) {
        _frontImage = File(picked.path);
      } else {
        _backImage = File(picked.path);
      }
    });
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
        maritalStatus: _maritalStatus,
        permanentAddress: _permanentAddressController.text.trim(),
        currentAddress: _currentAddressController.text.trim(),
        city: _city,
        municipality: _municipality,
        tole: _toleController.text.trim(),
        wardNo: int.tryParse(_wardNoController.text.trim()),
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
                _label('Marital Status'),
                DropdownButtonFormField<String>(
                  initialValue: _maritalStatus,
                  decoration: _fieldDecoration(hint: 'Select marital status', icon: Icons.people_outline_rounded),
                  items: _options.maritalStatuses
                      .map((m) => DropdownMenuItem(value: m, child: Text(_capitalize(m))))
                      .toList(),
                  onChanged: (v) => setState(() => _maritalStatus = v),
                ),
                const SizedBox(height: 16),
                _label('Address'),
                CheckboxListTile(
                  value: _sameAsPermanent,
                  onChanged: _onSameAsPermanentChanged,
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: EdgeInsets.zero,
                  activeColor: kPrimaryGreen,
                  dense: true,
                  title: const Text('Current address is same as permanent address', style: TextStyle(fontSize: 13)),
                ),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _label('Permanent Address'),
                          TextFormField(
                            controller: _permanentAddressController,
                            textCapitalization: TextCapitalization.words,
                            decoration: _fieldDecoration(hint: 'Enter your permanent address', icon: Icons.location_on_outlined),
                            validator: (v) => (v == null || v.trim().length < 3) ? 'Required' : null,
                            onChanged: (v) {
                              if (_sameAsPermanent) _currentAddressController.text = v;
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
                          _label('Current Address'),
                          TextFormField(
                            controller: _currentAddressController,
                            enabled: !_sameAsPermanent,
                            textCapitalization: TextCapitalization.words,
                            decoration: _fieldDecoration(hint: 'Enter your current address', icon: Icons.location_on_outlined),
                            validator: (v) => (v == null || v.trim().length < 3) ? 'Required' : null,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _label('City'),
                          DropdownButtonFormField<String>(
                            initialValue: _city,
                            decoration: _fieldDecoration(hint: 'Select city', icon: Icons.map_outlined),
                            items: _options.cities
                                .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                                .toList(),
                            onChanged: (v) => setState(() {
                              _city = v;
                              // Municipality options depend on the city — clear it
                              // unless it's still valid for the newly picked one.
                              if (!_options.municipalitiesFor(_city).contains(_municipality)) {
                                _municipality = null;
                              }
                            }),
                            validator: (v) => v == null ? 'Required' : null,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _label('Municipality'),
                          DropdownButtonFormField<String>(
                            initialValue: _municipality,
                            isExpanded: true,
                            decoration: _fieldDecoration(
                              hint: _city == null ? 'Select a city first' : 'Select municipality',
                              icon: Icons.location_city_outlined,
                            ),
                            items: _options
                                .municipalitiesFor(_city)
                                .map((m) => DropdownMenuItem(value: m, child: Text(m, overflow: TextOverflow.ellipsis)))
                                .toList(),
                            onChanged: _city == null ? null : (v) => setState(() => _municipality = v),
                            validator: (v) => v == null ? 'Required' : null,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _label('Tole'),
                          TextFormField(
                            controller: _toleController,
                            textCapitalization: TextCapitalization.words,
                            decoration: _fieldDecoration(hint: 'Enter your tole', icon: Icons.location_on_outlined),
                            validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _label('Ward No.'),
                          TextFormField(
                            controller: _wardNoController,
                            keyboardType: TextInputType.number,
                            decoration: _fieldDecoration(hint: 'Enter ward number', icon: Icons.tag),
                            validator: (v) {
                              final n = int.tryParse(v?.trim() ?? '');
                              if (n == null || n < 1 || n > 99) return 'Invalid';
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
                        subLabel: 'JPG, PNG - Max 5MB',
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
                        subLabel: 'JPG, PNG - Max 5MB',
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
                          Row(
                            children: const [
                              Text('Email ', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: kDarkText)),
                              Text('*', style: TextStyle(color: Colors.red)),
                            ],
                          ),
                          const SizedBox(height: 6),
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

  Widget _label(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(text, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: kDarkText)),
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

  String _capitalize(String s) => s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';
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
              child: Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: kDarkText)),
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