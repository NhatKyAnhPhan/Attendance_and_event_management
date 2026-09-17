import 'package:flutter/material.dart';

/// Bảng màu của app, ánh xạ 1-1 với các biến CSS trong `index.css`
/// (:root = light, .dark = dark). Dùng `AppColors.of(isDark)` để lấy
/// đúng bộ màu tương ứng với theme hiện tại.
class AppColors {
  final Color background;
  final Color foreground;
  final Color card;
  final Color cardForeground;
  final Color primary;
  final Color primaryForeground;
  final Color secondary;
  final Color secondaryForeground;
  final Color muted;
  final Color mutedForeground;
  final Color accent;
  final Color accentForeground;
  final Color border;
  final Color ring;
  final Color success;
  final Color successForeground;
  final Color warning;
  final Color warningForeground;
  final Color danger;
  final Color dangerForeground;
  final Color info;
  final Color infoForeground;

  const AppColors({
    required this.background,
    required this.foreground,
    required this.card,
    required this.cardForeground,
    required this.primary,
    required this.primaryForeground,
    required this.secondary,
    required this.secondaryForeground,
    required this.muted,
    required this.mutedForeground,
    required this.accent,
    required this.accentForeground,
    required this.border,
    required this.ring,
    required this.success,
    required this.successForeground,
    required this.warning,
    required this.warningForeground,
    required this.danger,
    required this.dangerForeground,
    required this.info,
    required this.infoForeground,
  });

  /// Tương ứng khối `:root` trong index.css
  static const light = AppColors(
    background: Color(0xFFF5F7FA),
    foreground: Color(0xFF111827),
    card: Color(0xFFFFFFFF),
    cardForeground: Color(0xFF111827),
    primary: Color(0xFF1E56A0),
    primaryForeground: Color(0xFFFFFFFF),
    secondary: Color(0xFFEEF2FF),
    secondaryForeground: Color(0xFF1E56A0),
    muted: Color(0xFFF1F5F9),
    mutedForeground: Color(0xFF6B7280),
    accent: Color(0xFF2563EB),
    accentForeground: Color(0xFFFFFFFF),
    border: Color(0xFFE2E8F0),
    ring: Color(0xFF1E56A0),
    success: Color(0xFF16A34A),
    successForeground: Color(0xFFFFFFFF),
    warning: Color(0xFFD97706),
    warningForeground: Color(0xFFFFFFFF),
    danger: Color(0xFFDC2626),
    dangerForeground: Color(0xFFFFFFFF),
    info: Color(0xFF0891B2),
    infoForeground: Color(0xFFFFFFFF),
  );

  /// Tương ứng khối `.dark` trong index.css
  static const dark = AppColors(
    background: Color(0xFF0F172A),
    foreground: Color(0xFFF1F5F9),
    card: Color(0xFF1E293B),
    cardForeground: Color(0xFFF1F5F9),
    primary: Color(0xFF3B82F6),
    primaryForeground: Color(0xFFFFFFFF),
    secondary: Color(0xFF1E3A5F),
    secondaryForeground: Color(0xFF93C5FD),
    muted: Color(0xFF1E293B),
    mutedForeground: Color(0xFF94A3B8),
    accent: Color(0xFF60A5FA),
    accentForeground: Color(0xFF0F172A),
    border: Color(0xFF334155),
    ring: Color(0xFF3B82F6),
    success: Color(0xFF22C55E),
    successForeground: Color(0xFFFFFFFF),
    warning: Color(0xFFF59E0B),
    warningForeground: Color(0xFFFFFFFF),
    danger: Color(0xFFEF4444),
    dangerForeground: Color(0xFFFFFFFF),
    info: Color(0xFF06B6D4),
    infoForeground: Color(0xFFFFFFFF),
  );

  static AppColors of(bool isDark) => isDark ? dark : light;

  /// Radius mặc định (tương ứng --radius: 10px)
  static const double radius = 10;
  static const double radiusSm = radius - 4;
  static const double radiusLg = radius + 4;
  static const double radiusXl = radius + 8;
}

/// Trạng thái điểm danh / badge — tương ứng .badge-present, .badge-late, ...
enum BadgeStatus { present, late, absent, pending, excused, blue }

/// Trả về [background, foreground] cho từng loại badge, theo light/dark.
List<Color> badgeColors(BadgeStatus status, bool isDark) {
  const light = <BadgeStatus, List<Color>>{
    BadgeStatus.present: [Color(0xFFDCFCE7), Color(0xFF15803D)],
    BadgeStatus.late: [Color(0xFFFEF3C7), Color(0xFF92400E)],
    BadgeStatus.absent: [Color(0xFFFEE2E2), Color(0xFF991B1B)],
    BadgeStatus.pending: [Color(0xFFE0F2FE), Color(0xFF0369A1)],
    BadgeStatus.excused: [Color(0xFFF3E8FF), Color(0xFF7E22CE)],
    BadgeStatus.blue: [Color(0xFFDBEAFE), Color(0xFF1D4ED8)],
  };
  const dark = <BadgeStatus, List<Color>>{
    BadgeStatus.present: [Color(0xFF14532D), Color(0xFF86EFAC)],
    BadgeStatus.late: [Color(0xFF451A03), Color(0xFFFCD34D)],
    BadgeStatus.absent: [Color(0xFF450A0A), Color(0xFFFCA5A5)],
    BadgeStatus.pending: [Color(0xFF0C4A6E), Color(0xFF7DD3FC)],
    BadgeStatus.excused: [Color(0xFF3B0764), Color(0xFFD8B4FE)],
    BadgeStatus.blue: [Color(0xFF1E3A5F), Color(0xFF93C5FD)],
  };
  return (isDark ? dark : light)[status]!;
}