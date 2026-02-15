import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  // Base colors
  static const Color background = Color(0xFF0A0E21);
  static const Color surface = Color(0xFF1C1F33);
  static const Color surfaceLight = Color(0xFF252A40);

  // Primary accent
  static const Color primary = Color(0xFF6C63FF);
  static const Color accent = Color(0xFF00D9FF);

  // Tuning feedback
  static const Color inTune = Color(0xFF00E676);
  static const Color sharp = Color(0xFFFF9100);
  static const Color flat = Color(0xFFFF5252);

  // Text
  static const Color textPrimary = Color(0xFFFFFFFF);
  static const Color textSecondary = Color(0xFF8D8E98);
  static const Color textDim = Color(0xFF4C4F5E);

  // Needle / gauge
  static const Color needleDefault = Color(0xFF8D8E98);
  static const Color gaugeTrack = Color(0xFF2A2D3E);

  /// Returns the appropriate color based on how many cents off the pitch is.
  static Color getTuningColor(double centsDiff) {
    final absCents = centsDiff.abs();
    if (absCents <= 5) return inTune;
    if (centsDiff > 0) return sharp;
    return flat;
  }
}
