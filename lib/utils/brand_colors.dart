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
  // Deliberate exception to "four colours, no more" - "Start trip" needs
  // an unambiguous go/start signal that none of the four above carry
  // (teal is closest, but already means something else - live/active
  // status elsewhere in the app).
  static const green = Color(0xFF2E9E5B);
}
