import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'screens/login.dart';

const kPrimaryGreen = Color(0xFF1E7145);
const kAccentGreen = Color(0xFF2F9E5B);
const kDarkText = Color(0xFF1B2B34);
const kLightGreenBg = Color(0xFFE8F4EC);

void main() {
  runApp(const GharSewaApp());
}

class GharSewaApp extends StatelessWidget {
  const GharSewaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'GharSewa',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: kPrimaryGreen,
          primary: kPrimaryGreen,
        ),
        scaffoldBackgroundColor: Colors.white,
        textTheme: GoogleFonts.workSansTextTheme(),
      ),
      home: const LoginPage(),
    );
  }
}