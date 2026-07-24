import 'package:flutter/material.dart';

/// Packbound's brand palette (see branding/packbound-brand-guide.html) -
/// "four colours, no more". Not to be confused with member_colors.dart's
/// marker hues, which are a separate, wider palette constrained by what the
/// Maps SDK's default marker icons can tint to.
class BrandColors {
  BrandColors._();

  static const ink = Color(0xFF241E45);
  // Slightly darker/less saturated than the brand guide's raw logo coral
  // (#FF5A5F) - that value works fine for the small app icon/wordmark, but
  // read as too bright/jarring filling large UI areas (buttons, FABs).
  static const coral = Color(0xFFE65156);
  static const teal = Color(0xFF17BEBB);
  static const amber = Color(0xFFFFC145);
  static const surface = Color(0xFFF6F4FF);
}
