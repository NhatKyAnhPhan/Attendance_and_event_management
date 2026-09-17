import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Tương ứng với 3 font trong index.css:
/// - Nunito  → tiêu đề (h1..h6, .font-display)
/// - Inter   → nội dung (body)
/// - JetBrains Mono → mã lớp, mã sinh viên, số liệu (.font-mono, <code>)
class AppTextStyles {
  AppTextStyles._();

  // ----- Display / tiêu đề (Nunito, weight 700–800) -----
  static TextStyle displayLg(Color color) => GoogleFonts.nunito(
        fontSize: 24,
        fontWeight: FontWeight.w800,
        color: color,
        height: 1.2,
      );

  static TextStyle displayMd(Color color) => GoogleFonts.nunito(
        fontSize: 20,
        fontWeight: FontWeight.w800,
        color: color,
      );

  static TextStyle displaySm(Color color) => GoogleFonts.nunito(
        fontSize: 16,
        fontWeight: FontWeight.w700,
        color: color,
      );

  static TextStyle displayXs(Color color) => GoogleFonts.nunito(
        fontSize: 13,
        fontWeight: FontWeight.w800,
        color: color,
      );

  // ----- Body (Inter, weight 400–600) -----
  static TextStyle bodyLg(Color color) => GoogleFonts.inter(
        fontSize: 15,
        fontWeight: FontWeight.w500,
        color: color,
      );

  static TextStyle bodyMd(Color color) => GoogleFonts.inter(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        color: color,
      );

  static TextStyle bodySm(Color color) => GoogleFonts.inter(
        fontSize: 13,
        fontWeight: FontWeight.w400,
        color: color,
      );

  static TextStyle bodyXs(Color color) => GoogleFonts.inter(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        color: color,
      );

  static TextStyle label(Color color) => GoogleFonts.inter(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.4,
        color: color,
      );

  static TextStyle button(Color color) => GoogleFonts.inter(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: color,
      );

  // ----- Mono (JetBrains Mono) — mã lớp, mã SV, giờ -----
  static TextStyle mono(Color color, {double fontSize = 13}) =>
      GoogleFonts.jetBrainsMono(
        fontSize: fontSize,
        fontWeight: FontWeight.w600,
        color: color,
      );
}