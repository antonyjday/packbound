import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import '../models/group.dart';
import '../utils/brand_colors.dart';
import '../utils/invite_link.dart';

class InviteScreen extends StatelessWidget {
  final ConvoyGroup group;
  const InviteScreen({super.key, required this.group});

  void _copyCode(BuildContext context) {
    Clipboard.setData(ClipboardData(text: group.inviteCode));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Invite code copied')),
    );
  }

  void _shareInvite(BuildContext context) {
    final link = buildInviteLink(group.inviteCode);
    SharePlus.instance.share(
      ShareParams(
        text: 'Join my convoy "${group.name}" on Packbound!\n\n'
            'Tap to join: $link\n\n'
            'Or open the app and enter code: ${group.inviteCode}',
        subject: 'Join "${group.name}" on Packbound',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final link = buildInviteLink(group.inviteCode);

    return Scaffold(
      appBar: AppBar(title: const Text('Invite to trip')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              Text(
                group.name,
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Anyone who scans this or enters the code joins your trip.',
                style: TextStyle(color: Colors.grey[600]),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: QrImageView(
                  data: link,
                  size: 220,
                  backgroundColor: Colors.white,
                ),
              ),
              const SizedBox(height: 24),
              GestureDetector(
                onTap: () => _copyCode(context),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  decoration: BoxDecoration(
                    color: BrandColors.coral.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: BrandColors.coral.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        group.inviteCode,
                        style: GoogleFonts.ibmPlexMono(
                          fontSize: 24,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 4,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Icon(Icons.copy, size: 20, color: BrandColors.coral),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Tap the code to copy',
                style: TextStyle(fontSize: 12, color: Colors.grey[500]),
              ),
              const Spacer(),
              Text(
                'Invite expires ${_formatExpiry(group.inviteExpiresAt.toDate())}',
                style: TextStyle(fontSize: 12, color: Colors.grey[500]),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => _shareInvite(context),
                  icon: const Icon(Icons.ios_share),
                  label: const Text('Share invite'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatExpiry(DateTime expiry) {
    final now = DateTime.now();
    final diff = expiry.difference(now);
    if (diff.isNegative) return 'already expired';
    if (diff.inHours < 1) return 'in ${diff.inMinutes}m';
    if (diff.inHours < 24) return 'in ${diff.inHours}h';
    return 'in ${diff.inDays}d';
  }
}
