import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  // 主色调
  static const Color primary = Color(0xFF6C63FF);
  static const Color primaryDark = Color(0xFF4A42D0);
  static const Color accent = Color(0xFF00D4AA);
  static const Color danger = Color(0xFFFF5252);
  static const Color warning = Color(0xFFFFB74D);
  static const Color success = Color(0xFF4CAF50);

  // 背景
  static const Color bgDark = Color(0xFF0F0F1A);
  static const Color bgCard = Color(0xFF1A1A2E);
  static const Color bgCardHover = Color(0xFF1E1E35);
  static const Color border = Color(0xFF2A2A45);

  // 文本
  static const Color textPrimary = Color(0xFFF0F0FF);
  static const Color textSecondary = Color(0xFF8888AA);
  static const Color textMuted = Color(0xFF555570);

  // 状态颜色
  static Color statusColor(String status) {
    switch (status) {
      case 'online':
        return success;
      case 'offline':
        return danger;
      default:
        return warning;
    }
  }

  // 亮色主题 (高亮白 + 玻璃质感)
  static final Color bgLight = const Color(0xFFF7F8FA);
  static final Color bgCardLight = const Color(0xFFFFFFFF);
  static final Color borderLight = const Color(0xFFE2E8F0);
  static final Color textPrimaryLight = const Color(0xFF1E293B);
  static final Color textSecondaryLight = const Color(0xFF64748B);
  static final Color textMutedLight = const Color(0xFF94A3B8);

  static ThemeData get lightTheme => ThemeData(
        brightness: Brightness.light,
        scaffoldBackgroundColor: bgLight,
        primaryColor: primary,
        colorScheme: const ColorScheme.light(
          primary: primary,
          secondary: accent,
          surface: Colors.white,
          error: danger,
          onPrimary: Colors.white,
          onSurface: Color(0xFF1E293B), // textPrimaryLight
        ),
        textTheme: GoogleFonts.interTextTheme(ThemeData.light().textTheme).apply(
          bodyColor: textPrimaryLight,
          displayColor: textPrimaryLight,
        ),
        appBarTheme: AppBarTheme(
          backgroundColor: bgLight,
          elevation: 0,
          centerTitle: false,
          titleTextStyle: GoogleFonts.inter(
            color: textPrimaryLight,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
          iconTheme: IconThemeData(color: textSecondaryLight),
        ),
        cardTheme: CardTheme(
          color: bgCardLight,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: borderLight, width: 1),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: bgCardLight,
          labelStyle: TextStyle(color: textSecondaryLight),
          hintStyle: TextStyle(color: textMutedLight),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: borderLight),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: borderLight),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: primary, width: 2),
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: primary,
            foregroundColor: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            textStyle: GoogleFonts.inter(
              fontWeight: FontWeight.w600,
              fontSize: 15,
            ),
          ),
        ),
        dividerTheme: DividerThemeData(color: borderLight, space: 1),
      );

  static ThemeData get darkTheme => ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: bgDark,
        primaryColor: primary,
        colorScheme: const ColorScheme.dark(
          primary: primary,
          secondary: accent,
          surface: bgCard,
          error: danger,
          onPrimary: Colors.white,
          onSurface: textPrimary,
        ),
        textTheme: GoogleFonts.interTextTheme(ThemeData.dark().textTheme).apply(
          bodyColor: textPrimary,
          displayColor: textPrimary,
        ),
        appBarTheme: AppBarTheme(
          backgroundColor: bgDark,
          elevation: 0,
          centerTitle: false,
          titleTextStyle: GoogleFonts.inter(
            color: textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
          iconTheme: const IconThemeData(color: textSecondary),
        ),
        cardTheme: CardTheme(
          color: bgCard,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: border, width: 1),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: bgCard,
          labelStyle: const TextStyle(color: textSecondary),
          hintStyle: const TextStyle(color: textMuted),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: primary, width: 2),
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: primary,
            foregroundColor: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            textStyle: GoogleFonts.inter(
              fontWeight: FontWeight.w600,
              fontSize: 15,
            ),
          ),
        ),
        dividerTheme: const DividerThemeData(color: border, space: 1),
      );
}
