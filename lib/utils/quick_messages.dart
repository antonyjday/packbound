import 'package:flutter/material.dart';
import '../models/trip_type.dart';

/// One preset quick-message option - see MapScreen's message button. Fixed,
/// canned phrases rather than free-text chat: covers most real convoy
/// communication needs (see README) for far less effort/scope than a full
/// chat feature would be.
class QuickMessagePreset {
  final String text;
  final IconData icon;
  const QuickMessagePreset(this.text, this.icon);
}

// Shared across every trip type - regardless of how the group is getting
// there, these apply.
const _commonPresets = [
  QuickMessagePreset("I'm behind, go ahead", Icons.arrow_back),
  QuickMessagePreset('Wait for me', Icons.hourglass_bottom),
  QuickMessagePreset("I've lost you", Icons.help_outline),
  QuickMessagePreset('All good', Icons.check_circle_outline),
];

const _carPresets = [
  QuickMessagePreset('Pulling over', Icons.local_parking),
  QuickMessagePreset('Need fuel', Icons.local_gas_station),
  QuickMessagePreset('Bathroom break', Icons.wc),
  ..._commonPresets,
];

const _trainPresets = [
  QuickMessagePreset('Missed the train', Icons.train),
  QuickMessagePreset('On the train', Icons.directions_railway),
  QuickMessagePreset('Changing platforms', Icons.swap_horiz),
  QuickMessagePreset('Running late', Icons.schedule),
  ..._commonPresets,
];

const _bicyclePresets = [
  QuickMessagePreset('Flat tire', Icons.build),
  QuickMessagePreset('Need a break', Icons.pause_circle_outline),
  ..._commonPresets,
];

const _walkPresets = [
  QuickMessagePreset('Need a break', Icons.pause_circle_outline),
  QuickMessagePreset('Bathroom break', Icons.wc),
  ..._commonPresets,
];

/// The quick-message presets relevant to how the group is getting there -
/// e.g. "Need fuel" doesn't make sense for a walk, "Missed the train"
/// doesn't make sense for a drive. See MapScreen's quick-message sheet.
List<QuickMessagePreset> quickMessagePresetsFor(TripType tripType) {
  switch (tripType) {
    case TripType.car:
      return _carPresets;
    case TripType.train:
      return _trainPresets;
    case TripType.bicycle:
      return _bicyclePresets;
    case TripType.walk:
      return _walkPresets;
  }
}

/// Looks up the icon for a received message's text, if it matches one of
/// the presets above - used to give the receiving side's alert the same
/// icon the sender picked from, rather than a generic one. Searches every
/// trip type's presets rather than just the current group's, since older
/// messages may have been sent under a since-changed trip type.
IconData? iconForQuickMessageText(String text) {
  for (final presets in [_carPresets, _trainPresets, _bicyclePresets, _walkPresets]) {
    for (final preset in presets) {
      if (preset.text == text) return preset.icon;
    }
  }
  return null;
}
