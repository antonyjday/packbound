import 'package:flutter/material.dart';
import '../services/location_service.dart';

/// Shown once, before the OS permission dialog, so the user understands
/// *why* Convoy wants their location and *who* can see it before the
/// system prompt interrupts them. This is expected by both Apple and
/// Google review guidelines for apps requesting background location,
/// and it measurably improves grant rates versus a cold OS prompt.
///
/// Returns `true` via Navigator.pop if permission was granted, `false`
/// otherwise (user declined the explainer or the OS prompt).
class LocationPermissionScreen extends StatefulWidget {
  final String groupName;
  const LocationPermissionScreen({super.key, required this.groupName});

  @override
  State<LocationPermissionScreen> createState() =>
      _LocationPermissionScreenState();
}

class _LocationPermissionScreenState extends State<LocationPermissionScreen> {
  final _locationService = LocationService();
  bool _requesting = false;

  Future<void> _requestPermission() async {
    setState(() => _requesting = true);
    final granted = await _locationService.ensurePermission();
    if (!mounted) return;

    if (granted) {
      Navigator.pop(context, true);
    } else {
      setState(() => _requesting = false);
      _showDeniedDialog();
    }
  }

  void _showDeniedDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Location permission needed'),
        content: const Text(
          'Convoy can\'t share your position with the group without location '
          'access. You can turn it on in your device Settings whenever '
          'you\'re ready.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Not now'),
          ),
        ],
      ),
    );
  }

  Widget _bulletRow(IconData icon, String title, String subtitle) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: Colors.deepOrange),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(subtitle, style: TextStyle(color: Colors.grey[600])),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 16),
              const Icon(Icons.my_location, size: 56, color: Colors.deepOrange),
              const SizedBox(height: 16),
              Text(
                'Share your location with "${widget.groupName}"',
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 24),
              _bulletRow(
                Icons.groups,
                'Only your group can see you',
                'Your position is only visible to members of this convoy, never anyone else.',
              ),
              _bulletRow(
                Icons.timer_outlined,
                'Live, while you\'re sharing',
                'Updates happen in real time so the group can stay together on the road.',
              ),
              _bulletRow(
                Icons.pause_circle_outline,
                'You\'re always in control',
                'Stop sharing at any time from the map screen — the group stops seeing you immediately.',
              ),
              _bulletRow(
                Icons.smartphone,
                'Works in the background',
                'Your device will ask for "Always" access next so sharing keeps working while your phone is locked.',
              ),
              const Spacer(),
              FilledButton(
                onPressed: _requesting ? null : _requestPermission,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: _requesting
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Enable location sharing'),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Not now'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
