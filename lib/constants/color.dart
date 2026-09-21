import 'package:flutter/material.dart';

/// Freeboard-style palette with red + white brand.
class AppColors {
  static const Color primary = Color(0xFFC62828);
  static const Color primaryDark = Color(0xFF8E0000);
  static const Color primaryLight = Color(0xFFE53935);

  static const Color accent = Color(0xFFEF5350);
  static const Color success = Color(0xFF10B981);
  static const Color warning = Color(0xFFF59E0B);
  static const Color danger = Color(0xFFEF4444);
  static const Color info = Color(0xFF3B82F6);

  static const Color background = Color(0xFFF8FAFC);
  static const Color card = Color(0xFFFFFFFF);
  static const Color textPrimary = Color(0xFF0F172A);
  static const Color textSecondary = Color(0xFF64748B);
  static const Color border = Color(0xFFE2E8F0);
  static const Color shimmer = Color(0xFFEFF1F5);

  static const LinearGradient primaryGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF8E0000), Color(0xFFC62828), Color(0xFFE53935)],
    stops: [0.0, 0.5, 1.0],
  );

  static const LinearGradient successGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF34D399), Color(0xFF059669)],
  );
}

// Backwards-compatible aliases used across the app
const Color kMainColor = AppColors.primary;
const Color kPrimaryDark = AppColors.primaryDark;
const Color kPrimaryContainer = Color(0xFFFFEBEE);
const Color kBackgroundColor = AppColors.background;
const Color kSurfaceColor = AppColors.card;
const Color kCardColor = AppColors.card;
const Color kBorderColor = AppColors.border;
const Color kBlackColor = AppColors.textPrimary;
const Color kDarkGreyColor = AppColors.textSecondary;
const Color kWhiteColor = Colors.white;
const Color kTransparent = Colors.transparent;
const Color kOnlineColor = AppColors.success;
const Color kMovingColor = Color(0xFF16A34A);
const Color kIdleColor = AppColors.info;
const Color kOfflineColor = AppColors.danger;
const Color kUnknownColor = Color(0xFF9E9E9E);
const Color kAccentColor = AppColors.primary;
const Color kAccentDark = AppColors.primaryDark;
const Color kRedColor = AppColors.danger;
const Color kErrorColor = AppColors.danger;
const Color kSuccessColor = AppColors.success;
const Color kWarningColor = AppColors.warning;
const Color kGradient1 = AppColors.primary;
const Color kGradient2 = AppColors.primaryDark;
