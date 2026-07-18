import 'package:flutter/material.dart';
import '../models/location_point.dart';

class ConvoyStatusList extends StatelessWidget {
  final List<LocationPoint> points;
  final String currentUserId;
  final void Function(LocationPoint point)? onSelect;

  const ConvoyStatusList({
    super.key,
    required this.points,
    required this.currentUserId,
    this.onSelect,
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
        final color = _statusColor(p.status);

        return ListTile(
          leading: Stack(
            children: [
              const CircleAvatar(child: Icon(Icons.person)),
              Positioned(
                right: 0,
                bottom: 0,
                child: Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                ),
              ),
            ],
          ),
          title: Text(isMe ? '${p.displayName} (you)' : p.displayName),
          subtitle: Text('${_statusLabel(p.status)} · ${p.lastSeenLabel}'),
          trailing: p.status == SignalStatus.lost
              ? const Icon(Icons.signal_cellular_connected_no_internet_0_bar,
                  color: Colors.red)
              : null,
          onTap: onSelect == null ? null : () => onSelect!(p),
        );
      },
    );
  }
}
