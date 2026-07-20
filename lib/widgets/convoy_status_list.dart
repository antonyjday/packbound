import 'package:flutter/material.dart';
import '../models/location_point.dart';
import '../utils/member_colors.dart';

class ConvoyStatusList extends StatelessWidget {
  final List<LocationPoint> points;
  final String currentUserId;
  final bool isOwner;
  final void Function(LocationPoint point)? onSelect;
  final void Function(LocationPoint point)? onRemove;

  const ConvoyStatusList({
    super.key,
    required this.points,
    required this.currentUserId,
    this.isOwner = false,
    this.onSelect,
    this.onRemove,
  });

  Color _statusColor(SignalStatus status) {
    switch (status) {
      case SignalStatus.live:
        return Colors.green;
      case SignalStatus.weak:
        return Colors.amber;
      case SignalStatus.lost:
        return Colors.red;
    }
  }

  String _statusLabel(SignalStatus status) {
    switch (status) {
      case SignalStatus.live:
        return 'Live';
      case SignalStatus.weak:
        return 'Weak signal';
      case SignalStatus.lost:
        return 'Signal lost';
    }
  }

  @override
  Widget build(BuildContext context) {
    final sorted = [...points]
      ..sort((a, b) => a.status.index.compareTo(b.status.index));
    // Same set of user ids in, same hue assignment out - stays in sync with
    // the map's markers without needing the map to hand this a precomputed
    // map, as long as both are built from the same group's points.
    final memberHues = markerHuesForUsers(points.map((p) => p.userId));

    if (sorted.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Text('No one is sharing their location yet.'),
      );
    }

    return ListView.separated(
      shrinkWrap: true,
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: sorted.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final p = sorted[i];
        final isMe = p.userId == currentUserId;
        final statusColor = _statusColor(p.status);
        // Same color this member's map marker uses - lets you match a
        // roster row to its pin on the map at a glance, without tapping
        // markers one by one to find out who's who.
        final memberColor = colorForMarkerHue(memberHues[p.userId]!);

        return ListTile(
          leading: Stack(
            children: [
              CircleAvatar(
                backgroundColor: memberColor,
                child: const Icon(Icons.person, color: Colors.white),
              ),
              Positioned(
                right: 0,
                bottom: 0,
                child: Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: statusColor,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                ),
              ),
            ],
          ),
          title: Text(isMe ? '${p.displayName} (you)' : p.displayName),
          subtitle: Text('${_statusLabel(p.status)} · ${p.lastSeenLabel}'),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (p.status == SignalStatus.lost)
                const Padding(
                  padding: EdgeInsets.only(right: 4),
                  child: Icon(Icons.signal_cellular_connected_no_internet_0_bar,
                      color: Colors.red),
                ),
              // Owner-only, and never for their own row - there's no
              // owner-transfer flow, so an owner "removing" themselves
              // would just orphan the group.
              if (isOwner && !isMe && onRemove != null)
                IconButton(
                  icon: const Icon(Icons.person_remove, color: Colors.red),
                  tooltip: 'Remove from convoy',
                  onPressed: () => onRemove!(p),
                ),
            ],
          ),
          onTap: onSelect == null ? null : () => onSelect!(p),
        );
      },
    );
  }
}
