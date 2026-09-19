import 'package:flutter/material.dart';
import '../main.dart';

/// The GharSewa logo mark, used everywhere the app currently shows the
/// green house icon as a stand-in brand mark: the login/signup screens and
/// the top bar of each home screen.
///
/// Reads from `assets/images/logo.png`. If that file is missing or hasn't
/// been registered under `flutter: assets:` in pubspec.yaml yet,
/// [errorBuilder] falls back to the original icon glyph instead of
/// crashing or leaving a blank gap, so the screen still renders correctly
/// while the asset is being set up.
class AppLogo extends StatelessWidget {
  final double size;

  const AppLogo({super.key, this.size = 56});

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/images/logo.png',
      width: size,
      height: size,
      errorBuilder: (_, __, ___) =>
          Icon(Icons.home_repair_service_rounded, color: kAccentGreen, size: size),
    );
  }
}
