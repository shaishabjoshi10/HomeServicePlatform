import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';

import '../main.dart';

/// A circular, tappable profile-picture avatar used by both the customer
/// and provider home screens.
///
/// Tapping it lets the user take a photo with the camera or choose one
/// from the gallery, preview it, and save it. All of the picking,
/// permission-handling, previewing, uploading, and error-handling logic
/// lives here — callers just supply the current [imageUrl] (a full,
/// absolute URL, or null) and an [uploadPicture] function that does the
/// role-specific network upload (customer vs. provider).
class ProfilePictureAvatar extends StatefulWidget {
  /// Full URL of the current picture (e.g. '$apiBaseUrl/uploads/...'), or
  /// null if none is set yet.
  final String? imageUrl;

  /// Radius of the avatar circle.
  final double radius;

  /// Icon shown when there's no picture yet.
  final IconData placeholderIcon;

  /// Performs the actual upload for the signed-in user's role and returns
  /// the new relative picture URL (e.g. '/uploads/profile_pictures/...')
  /// on success, or throws on failure. Throw an exception whose
  /// `toString()` is a user-facing message (the existing
  /// ProfileServiceException / ProviderServiceException both do this).
  final Future<String?> Function(File file) uploadPicture;

  /// Called with the new relative picture URL once an upload succeeds, so
  /// the parent screen can update its own state.
  final ValueChanged<String?> onPictureUpdated;

  const ProfilePictureAvatar({
    super.key,
    required this.imageUrl,
    required this.uploadPicture,
    required this.onPictureUpdated,
    this.radius = 26,
    this.placeholderIcon = Icons.person_rounded,
  });

  @override
  State<ProfilePictureAvatar> createState() => _ProfilePictureAvatarState();
}

class _ProfilePictureAvatarState extends State<ProfilePictureAvatar> {
  final _picker = ImagePicker();
  bool _busy = false;

  static const _allowedExtensions = {'.jpg', '.jpeg', '.png'};
  static const _maxImageBytes = 5 * 1024 * 1024; // 5 MB — matches server limit

  Future<void> _handleTap() async {
    if (_busy) return;

    final source = await _chooseSource();
    if (source == null || !mounted) return;

    final permitted = await _ensurePermission(source);
    if (!permitted || !mounted) return;

    XFile? picked;
    try {
      picked = await _picker.pickImage(
        source: source,
        imageQuality: 85,
        maxWidth: 1080,
      );
    } on PlatformException catch (e) {
      _handlePickerException(e, source);
      return;
    } catch (_) {
      _showMessage(
        'Could not open the ${source == ImageSource.camera ? 'camera' : 'gallery'}. Please try again.',
      );
      return;
    }
    if (picked == null || !mounted) return;

    final ext = picked.path.contains('.') ? '.${picked.path.split('.').last.toLowerCase()}' : '';
    if (!_allowedExtensions.contains(ext)) {
      _showMessage('Allowed formats: JPG, JPEG, PNG.');
      return;
    }

    final file = File(picked.path);
    final length = await file.length();
    if (length == 0) {
      _showMessage('That image could not be read. Please try another one.');
      return;
    }
    if (length > _maxImageBytes) {
      _showMessage('Maximum size: 5 MB.');
      return;
    }

    final confirmed = await _previewAndConfirm(file);
    if (confirmed != true || !mounted) return;

    await _upload(file);
  }

  Future<ImageSource?> _chooseSource() {
    return showModalBottomSheet<ImageSource>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined, color: kPrimaryGreen),
              title: const Text('Take a photo'),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined, color: kPrimaryGreen),
              title: const Text('Choose from gallery'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
  }

  /// Requests the relevant OS permission before invoking the picker, and
  /// offers a way to open Settings if it's been permanently denied. If the
  /// permission_handler plugin can't resolve a status for some reason, we
  /// let the picker itself try — it will surface its own PlatformException,
  /// which _handlePickerException below still catches.
  Future<bool> _ensurePermission(ImageSource source) async {
    final permission = source == ImageSource.camera ? Permission.camera : Permission.photos;

    var permissionStatus = await permission.status;
    if (permissionStatus.isGranted || permissionStatus.isLimited) return true;

    if (permissionStatus.isDenied) {
      permissionStatus = await permission.request();
      if (permissionStatus.isGranted || permissionStatus.isLimited) return true;
    }

    if (!mounted) return false;

    if (permissionStatus.isPermanentlyDenied || permissionStatus.isRestricted) {
      final wantsSettings = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(source == ImageSource.camera ? 'Camera access needed' : 'Photo access needed'),
          content: Text(
            source == ImageSource.camera
                ? 'Camera access is currently off for GharSewa. Enable it in Settings to take a profile photo.'
                : 'Photo library access is currently off for GharSewa. Enable it in Settings to choose a profile photo.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Open Settings'),
            ),
          ],
        ),
      );
      if (wantsSettings == true) await openAppSettings();
      return false;
    }

    _showMessage(
      source == ImageSource.camera
          ? 'Camera permission is required to take a photo.'
          : 'Photo library permission is required to choose a photo.',
    );
    return false;
  }

  void _handlePickerException(PlatformException e, ImageSource source) {
    final code = e.code.toLowerCase();
    if (code.contains('denied') || code.contains('permission')) {
      _showMessage(
        'Permission was denied. Enable ${source == ImageSource.camera ? 'camera' : 'photo library'} '
            'access in your device Settings to continue.',
      );
    } else {
      _showMessage('Something went wrong opening the ${source == ImageSource.camera ? 'camera' : 'gallery'}.');
    }
  }

  Future<bool?> _previewAndConfirm(File file) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Preview your photo',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: kDarkText),
              ),
              const SizedBox(height: 16),
              ClipOval(
                child: Image.file(file, width: 160, height: 160, fit: BoxFit.cover),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: kPrimaryGreen,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Save', style: TextStyle(fontWeight: FontWeight.w600)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _upload(File file) async {
    setState(() => _busy = true);
    try {
      final newUrl = await widget.uploadPicture(file);
      if (!mounted) return;
      widget.onPictureUpdated(newUrl);
      _showMessage('Profile picture updated.');
    } catch (e) {
      if (!mounted) return;
      _showMessage(e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.radius * 2;
    return GestureDetector(
      onTap: _handleTap,
      child: SizedBox(
        width: size + 6,
        height: size + 6,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            CircleAvatar(
              radius: widget.radius,
              backgroundColor: kLightGreenBg,
              backgroundImage: widget.imageUrl != null ? NetworkImage(widget.imageUrl!) : null,
              onBackgroundImageError: widget.imageUrl != null ? (_, _) {} : null,
              child: widget.imageUrl == null
                  ? Icon(widget.placeholderIcon, color: kPrimaryGreen, size: widget.radius)
                  : null,
            ),
            if (_busy)
              Positioned.fill(
                child: DecoratedBox(
                  decoration: const BoxDecoration(color: Colors.black38, shape: BoxShape.circle),
                  child: Center(
                    child: SizedBox(
                      width: widget.radius * 0.8,
                      height: widget.radius * 0.8,
                      child: const CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    ),
                  ),
                ),
              ),
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  color: kPrimaryGreen,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                ),
                child: const Icon(Icons.camera_alt_rounded, size: 13, color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }
}