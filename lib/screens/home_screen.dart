import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/group_service.dart';
import '../services/deep_link_service.dart';
import 'map_screen.dart';
import 'scan_qr_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _groupService = GroupService();
  final _authService = AuthService();
  final _groupNameController = TextEditingController();
  final _inviteCodeController = TextEditingController();
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    // Catches a link tapped while this screen is already visible.
    DeepLinkService.instance.pendingInviteCode.addListener(_onPendingInvite);
    // Catches a link that launched the app cold, after the auth gate in
    // main.dart has already routed here by the time this frame renders.
    WidgetsBinding.instance.addPostFrameCallback((_) => _onPendingInvite());
  }

  @override
  void dispose() {
    DeepLinkService.instance.pendingInviteCode.removeListener(_onPendingInvite);
    super.dispose();
  }

  void _onPendingInvite() {
    final code = DeepLinkService.instance.pendingInviteCode.value;
    if (code == null || code.isEmpty || _loading) return;
    DeepLinkService.instance.clearPending();
    _inviteCodeController.text = code;
    _joinGroup(code: code);
  }

  Future<void> _scanQr() async {
    final code = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const ScanQrScreen()),
    );
    if (code != null && code.isNotEmpty) {
      _inviteCodeController.text = code;
      _joinGroup(code: code);
    }
  }

  Future<void> _createGroup() async {
    if (_groupNameController.text.trim().isEmpty) return;
    setState(() => _loading = true);
    try {
      final group = await _groupService.createGroup(
        name: _groupNameController.text.trim(),
        ownerId: _authService.uid!,
      );
      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => MapScreen(group: group)),
        );
      }
    } catch (e) {
      _showError(e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// [code] lets this be called from the manual text field, a scanned
  /// QR, or a tapped deep link - all three end up here.
  Future<void> _joinGroup({String? code}) async {
    final inviteCode = (code ?? _inviteCodeController.text).trim();
    if (inviteCode.isEmpty) return;
    setState(() => _loading = true);
    try {
      final group = await _groupService.joinGroupByInviteCode(
        inviteCode: inviteCode,
        userId: _authService.uid!,
      );
      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => MapScreen(group: group)),
        );
      }
    } catch (e) {
      _showError(e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showError(Object e) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(e.toString())));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Convoy'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: _authService.signOut,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const Text('Start a new convoy', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          TextField(
            controller: _groupNameController,
            decoration: const InputDecoration(
              labelText: 'Group name (e.g. "Road trip to Denver")',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _loading ? null : _createGroup,
            child: const Text('Create group'),
          ),
          const SizedBox(height: 40),
          const Divider(),
          const SizedBox(height: 24),
          const Text('Join an existing convoy', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          TextField(
            controller: _inviteCodeController,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(
              labelText: 'Invite code',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _loading ? null : () => _joinGroup(),
                  child: const Text('Join group'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _loading ? null : _scanQr,
                  icon: const Icon(Icons.qr_code_scanner),
                  label: const Text('Scan QR'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
