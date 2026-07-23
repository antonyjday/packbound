import 'package:flutter/material.dart';

/// One preset quick-message option - see MapScreen's message button. Fixed,
/// canned phrases rather than free-text chat: covers most real convoy
/// communication needs (see README) for far less effort/scope than a full
/// chat feature would be.
class QuickMessagePreset {
  final String text;
  final IconData icon;
  const QuickMessagePreset(this.text, this.icon);
}

const quickMessagePresets = [
  QuickMessagePreset('Pulling over', Icons.local_parking),
  QuickMessagePreset('Need fuel', Icons.local_gas_station),
  QuickMessagePreset('Bathroom break', Icons.wc),
  QuickMessagePreset("I'm behind, go ahead", Icons.arrow_back),
  QuickMessagePreset('Wait for me', Icons.hourglass_bottom),
  QuickMessagePreset("I've lost you", Icons.help_outline),
  QuickMessagePreset('All good', Icons.check_circle_outline),
];

/// Looks up the icon for a received message's text, if it matches one of
/// the presets above - used to give the receiving side's alert the same
/// icon the sender picked from, rather than a generic one.
IconData? iconForQuickMessageText(String text) {
  for (final preset in quickMessagePresets) {
    if (preset.text == text) return preset.icon;
  }
  return null;
}
