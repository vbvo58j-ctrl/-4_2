
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/blousab_community.dart';
import '../widgets/blousab_visuals.dart';
import '../services/community_store.dart';
import '../services/bluetooth_classic_service.dart';
import '../services/message_store.dart';
import '../services/local_network_service.dart';
import '../models/blousab_message.dart';
import 'chat_screen.dart';
import 'blousab_ai_screen.dart';
import '../services/blousab_ai_service.dart';

/// Incremented by the shell when the header search button of another tab is tapped.
final ValueNotifier<int> blousabChatSearchRequest = ValueNotifier<int>(0);

class CommunitiesScreen extends StatefulWidget {
  const CommunitiesScreen({super.key, this.onNotifications, this.notificationCount = 0});
  final VoidCallback? onNotifications;
  final int notificationCount;

  @override
  State<CommunitiesScreen> createState() => _CommunitiesScreenState();
}

class _CommunitiesScreenState extends State<CommunitiesScreen> {
  final CommunityStore _store = CommunityStore();
  final BluetoothClassicService _bluetooth = BluetoothClassicService.instance;
  StreamSubscription<BlousabEvent>? _bluetoothSubscription;
  StreamSubscription<BlousabEvent>? _lanSubscription;
  final Set<String> _handledJoinRequests = <String>{};
  final Set<String> _relayedMessageIds = <String>{};
  final MessageStore _messageStore = MessageStore();

  List<BlousabCommunity> _communities = [];
  List<Map<String, String>> _directChats = [];
  bool _loading = true;
  String _userId = '';
  String _userName = '';
  String _searchQuery = '';
  bool _searchOpen = false;
  Map<String, BlousabMessage> _previews = <String, BlousabMessage>{};

  void _onSearchRequest() {
    if (mounted) setState(() => _searchOpen = true);
  }

  Future<void> _loadPreviews(List<Map<String, String>> chats, List<BlousabCommunity> communities) async {
    final out = <String, BlousabMessage>{};
    final ids = <String>[...chats.map((c) => c['conversationId'] ?? ''), ...communities.map((c) => c.id)];
    for (final id in ids) {
      if (id.isEmpty) continue;
      try {
        final messages = await _messageStore.getMessages(id);
        if (messages.isNotEmpty) out[id] = messages.last;
      } catch (_) {}
    }
    if (mounted) setState(() => _previews = out);
  }

  @override
  void initState() {
    super.initState();
    blousabChatSearchRequest.addListener(_onSearchRequest);
    _bluetoothSubscription = _bluetooth.events.listen(_handleBluetoothEvent);
    _lanSubscription = LocalNetworkService.instance.events.listen(_handleLanEvent);
    _initialize();
    BlousabAiService.instance.load();
  }

  Future<void> _initialize() async {
    final prefs = await SharedPreferences.getInstance();

    _userId = prefs.getString('wasl_user_id') ??
        DateTime.now().microsecondsSinceEpoch.toString();
    _userName = prefs.getString('wasl_user_name') ?? 'مستخدم بلوساب';

    await prefs.setString('wasl_user_id', _userId);
    await prefs.setString('wasl_user_name', _userName);

    if (prefs.getBool('blousab_lan_enabled') ?? true) {
      try {
        await LocalNetworkService.instance.start(userId: _userId, userName: _userName);
      } catch (_) { /* Wi-Fi transport can be unavailable; Bluetooth remains usable. */ }
    }

    // Start the RFCOMM listener once per app session so join requests can
    // reach the creator even before a chat screen is opened.
    try {
      if (await _bluetooth.requestPermissions() && await _bluetooth.isEnabled()) {
        await _bluetooth.startServer();
      }
    } catch (_) { /* The user can start Bluetooth from the toolbar. */ }

    await _reload();
  }

  Future<void> _reload() async {
    try {
      final result = await _store.getCommunities();
      final prefs = await SharedPreferences.getInstance();
      final rawChats = prefs.getStringList('blousab_direct_chats_v1') ?? <String>[];
      final chats = <Map<String, String>>[];
      for (final raw in rawChats) {
        try {
          final decoded = jsonDecode(raw);
          if (decoded is Map) chats.add(Map<String, String>.from(decoded.map((k, v) => MapEntry(k.toString(), v.toString()))));
        } catch (_) {}
      }
      if (!mounted) return;

      setState(() {
        _communities = result;
        _directChats = chats;
        _loading = false;
      });
      unawaited(_loadPreviews(chats, result));
    } catch (e) {
      if (!mounted) return;

      setState(() => _loading = false);
      _message('تعذر تحميل المجتمعات: $e');
    }
  }

  void _message(String text) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text)),
    );
  }

  Future<void> _saveDirectChat({
    required String conversationId,
    required String peerName,
    required String peerAddress,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final entries = prefs.getStringList('blousab_direct_chats_v1') ?? <String>[];
    final chats = <Map<String, String>>[];
    for (final raw in entries) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          final item = Map<String, String>.from(decoded.map((k, v) => MapEntry(k.toString(), v.toString())));
          if (item['conversationId'] != conversationId) chats.add(item);
        }
      } catch (_) {}
    }
    chats.insert(0, {
      'conversationId': conversationId,
      'peerName': peerName,
      'peerAddress': peerAddress,
    });
    if (chats.length > 100) chats.removeRange(100, chats.length);
    await prefs.setStringList('blousab_direct_chats_v1', chats.map(jsonEncode).toList());
    if (mounted) setState(() => _directChats = chats);
  }

  Future<void> _openDirectChat(Map<String, String> chat) async {
    await Navigator.push(context, MaterialPageRoute(
      builder: (_) => ChatScreen(
        conversationId: chat['conversationId']!,
        title: chat['peerName'] ?? 'محادثة فردية',
        currentUserId: _userId,
        currentUserName: _userName,
        initialPeerAddress: chat['peerAddress'],
      ),
    ));
    await _reload();
  }

  Future<void> _createCommunity() async {
    final controller = TextEditingController();

    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('إنشاء مجتمع'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 40,
          decoration: const InputDecoration(
            labelText: 'اسم المجتمع',
            hintText: 'مثال: مجتمع الأصدقاء',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(dialogContext, controller.text.trim()),
            child: const Text('إنشاء'),
          ),
        ],
      ),
    );

    controller.dispose();

    if (name == null || name.trim().isEmpty) return;

    try {
      final community = await _store.createCommunity(
        name: name,
        ownerId: _userId,
        ownerName: _userName,
      );

      await _reload();

      if (!mounted) return;

      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('تم إنشاء المجتمع محليًا'),
          content: SelectableText(
            'اسم المجتمع: ${community.name}\n\n'
            'رمز المجتمع:\n${community.joinCode}\n\n'
            'احتفظ بالرمز. مشاركة الرمز وحدها لا تنقل طلبات الانضمام '
            'بين الهواتف؛ يلزم ربطها بالبلوتوث.',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('حسنًا'),
            ),
          ],
        ),
      );
    } catch (e) {
      _message('تعذر إنشاء المجتمع: $e');
    }
  }

  Future<String?> _myProfilePhotoPayload() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final path = prefs.getString('wasl_profile_photo') ?? '';
      if (path.isEmpty) return null;
      final file = File(path);
      if (!await file.exists()) return null;
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty || bytes.length > 100 * 1024) return null;
      return base64Encode(bytes);
    } catch (_) { return null; }
  }

  Future<String?> _myProfileCoverPayload() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final path = prefs.getString('wasl_profile_cover') ?? '';
      if (path.isEmpty) return null;
      final bytes = await File(path).readAsBytes();
      return bytes.isNotEmpty && bytes.length <= 60 * 1024 ? base64Encode(bytes) : null;
    } catch (_) { return null; }
  }

  Future<void> _savePeerCover(Map packet) async {
    final id = packet['senderId']?.toString() ?? '';
    final encoded = packet['senderCover']?.toString() ?? '';
    if (id.isEmpty || id.length > 128 || encoded.isEmpty || encoded.length > 84000) return;
    try {
      final bytes = base64Decode(encoded);
      if (bytes.isEmpty || bytes.length > 60 * 1024) return;
      final dir = await getApplicationDocumentsDirectory();
      final folder = Directory('${dir.path}/peer_profiles');
      await folder.create(recursive: true);
      final safeId = id.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
      final coverFile = File('${folder.path}/${safeId}_cover.jpg');
      await coverFile.writeAsBytes(bytes, flush: true);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('blousab_peer_cover_$id', coverFile.path);
    } catch (_) {}
  }

  Future<void> _savePeerPhoto(Map packet) async {
    final senderId = packet['senderId']?.toString() ?? '';
    final encoded = packet['senderPhoto']?.toString() ?? '';
    if (senderId.isEmpty || encoded.isEmpty || encoded.length > 140000) return;
    try {
      final bytes = base64Decode(encoded);
      final dir = await getApplicationDocumentsDirectory();
      final profileDir = Directory('${dir.path}/peer_profiles');
      if (!await profileDir.exists()) await profileDir.create(recursive: true);
      final safeId = senderId.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
      final file = File('${profileDir.path}/$safeId.jpg');
      await file.writeAsBytes(bytes, flush: true);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('blousab_peer_photo_$senderId', file.path);
      final name = packet['senderName']?.toString() ?? '';
      if (name.trim().isNotEmpty) await prefs.setString('blousab_peer_name_id_$senderId', name.trim());
    } catch (_) {}
  }

  Future<void> _openCommunityOptions() async {
    final choice = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('المجتمعات'),
        content: const Text('يمكنك إنشاء مجتمع جديد أو الانضمام إلى مجتمع باستخدام رمزه.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('إلغاء'),
          ),
          OutlinedButton.icon(
            onPressed: () => Navigator.pop(dialogContext, 'join'),
            icon: const Icon(Icons.group_add_outlined),
            label: const Text('الانضمام لمجتمع'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(dialogContext, 'create'),
            icon: const Icon(Icons.add),
            label: const Text('إنشاء مجتمع'),
          ),
        ],
      ),
    );
    if (!mounted || choice == null) return;
    if (choice == 'create') {
      await _createCommunity();
    } else if (choice == 'join') {
      await _joinCommunity();
    }
  }

  Future<void> _openSubscription() async {
    final prefs = await SharedPreferences.getInstance();
    final currentPlan = prefs.getString('blousab_subscription_plan_v1') ?? 'free';
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, refreshDialog) => AlertDialog(
          title: const Text('اشتراك بلوساب'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(currentPlan == 'free' ? 'خطتك الحالية: مجانية' : 'الخطة المحددة: ${currentPlan == 'plus_monthly' ? 'بلوساب بلس - شهرية' : 'بلوساب بلس - سنوية'}'),
              const SizedBox(height: 12),
              const Text('بلوساب بلس', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              const Text('واجهة إدارة الاشتراك جاهزة، لكن الدفع الإلكتروني والتحقق من الاشتراك يحتاجان إلى ربط مزود دفع وخادم آمن.'),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () async {
                  await prefs.setString('blousab_subscription_plan_v1', 'plus_monthly');
                  if (ctx.mounted) Navigator.pop(ctx);
                  if (mounted) _message('تم حفظ اختيار الخطة الشهرية محليًا فقط؛ لم يتم الدفع أو تفعيل اشتراك مدفوع.');
                },
                child: const SizedBox(width: double.infinity, child: Text('اختيار الخطة الشهرية')),
              ),
              OutlinedButton(
                onPressed: () async {
                  await prefs.setString('blousab_subscription_plan_v1', 'plus_yearly');
                  if (ctx.mounted) Navigator.pop(ctx);
                  if (mounted) _message('تم حفظ اختيار الخطة السنوية محليًا فقط؛ لم يتم الدفع أو تفعيل اشتراك مدفوع.');
                },
                child: const SizedBox(width: double.infinity, child: Text('اختيار الخطة السنوية')),
              ),
              TextButton(
                onPressed: () async {
                  await prefs.setString('blousab_subscription_plan_v1', 'free');
                  if (ctx.mounted) Navigator.pop(ctx);
                  if (mounted) _message('تم الرجوع إلى الخطة المجانية.');
                },
                child: const Text('استخدام الخطة المجانية'),
              ),
            ],
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إغلاق'))],
        ),
      ),
    );
  }

  Future<void> _startPrivateChat() async {
    try {
      if (!await _bluetooth.requestPermissions()) {
        _message('لم تُمنح صلاحيات البلوتوث. فعّل صلاحيات الأجهزة القريبة من إعدادات أندرويد ثم أعد المحاولة.');
        return;
      }
      if (!await _bluetooth.isEnabled()) {
        await _bluetooth.requestEnable();
        _message('شغّل البلوتوث ثم أعد البحث عن مستخدمي بلوساب.');
        return;
      }
      if (!mounted) return;

      // Show a centered search window while scanning. Discovery only lists
      // devices; it does not connect to any device automatically.
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 28),
            child: Column(mainAxisSize: MainAxisSize.min, children: const [
              BlousabAnonymousUserIcon(size: 84),
              SizedBox(height: 14),
              Text('البحث عن مستخدمي بلوساب', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
              SizedBox(height: 8),
              Text('جارٍ فحص الأجهزة القريبة… لن يتم الاتصال بأي جهاز دون اختيارك.', textAlign: TextAlign.center),
              SizedBox(height: 18),
              CircularProgressIndicator(),
            ]),
          ),
        ),
      );
      final discovered = await _bluetooth.discoverNearbyDevices(timeout: const Duration(seconds: 8));
      if (mounted && Navigator.of(context, rootNavigator: true).canPop()) {
        Navigator.of(context, rootNavigator: true).pop();
      }
      if (!mounted) return;

      // Probe newly discovered devices as well as previously known peers.
      // A device is shown only after it answers the Blousab hello handshake;
      // this allows first-time/new users to appear without a prior pairing.
      final uniqueDevices = <String, BlousabDevice>{};
      for (final item in discovered) {
        if (item.address.trim().isNotEmpty) uniqueDevices.putIfAbsent(item.address, () => item);
      }
      final prefs = await SharedPreferences.getInstance();
      final myPhoto = await _myProfilePhotoPayload();
      final myCover = await _myProfileCoverPayload();
      // Limit probes so a crowded Bluetooth environment does not freeze the UI.
      // RFCOMM can be hardware-serialized; use a small batch, not unlimited sockets.
      final probeTargets = uniqueDevices.values.take(16).toList(growable: false);
      for (var offset = 0; offset < probeTargets.length; offset += 3) {
        final batch = probeTargets.skip(offset).take(3);
        await Future.wait(batch.map((item) async {
          final key = 'blousab_peer_id_${item.address}';
          final existingId = prefs.getString(key);
          if (existingId != null && existingId.isNotEmpty &&
              (prefs.getBool('blousab_peer_verified_${item.address}') ?? false)) return;
          try {
            await _bluetooth.connect(item.address).timeout(const Duration(seconds: 4));
            await _bluetooth.sendMessage(address: item.address, message: jsonEncode({
              'type': 'hello',
              'senderId': _userId,
              'senderName': _userName,
              if (myPhoto != null) 'senderPhoto': myPhoto,
              if (myCover != null) 'senderCover': myCover,
              'protocol': 'blousab-nearby-v1',
            })).timeout(const Duration(seconds: 3));
            for (var attempt = 0; attempt < 8; attempt++) {
              await Future<void>.delayed(const Duration(milliseconds: 250));
              if ((prefs.getString(key) ?? '').isNotEmpty &&
                  (prefs.getBool('blousab_peer_verified_${item.address}') ?? false)) break;
            }
          } catch (_) { /* Non-Blousab devices remain hidden. */ }
        }));
      }
      final candidates = uniqueDevices.values.where((item) {
        final verifiedId = prefs.getString('blousab_peer_id_${item.address}');
        return verifiedId != null && verifiedId.isNotEmpty && verifiedId != _userId && (prefs.getBool('blousab_peer_verified_${item.address}') ?? false);
      }).toList()
        ..sort((a, b) {
          final nameA = (prefs.getString('blousab_peer_name_${a.address}') ?? '').toLowerCase();
          final nameB = (prefs.getString('blousab_peer_name_${b.address}') ?? '').toLowerCase();
          return nameA.compareTo(nameB);
        });
      final device = await showDialog<BlousabDevice>(
        context: context,
        builder: (dialogContext) {
          final theme = Theme.of(dialogContext);
          return Dialog(
            backgroundColor: theme.colorScheme.surface,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
            child: SizedBox(
              width: 380,
              height: 440,
              child: Column(children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
                  child: Row(children: [
                    const Icon(Icons.person_search, color: Color(0xFF28C7FF), size: 28),
                    const SizedBox(width: 10),
                    Expanded(child: Text('مستخدمو بلوساب القريبون', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold))),
                    IconButton(tooltip: 'إغلاق', onPressed: () => Navigator.pop(dialogContext), icon: const Icon(Icons.close)),
                  ]),
                ),
                const Divider(height: 1),
                Expanded(child: candidates.isEmpty
                    ? Center(child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                          const BlousabAnonymousUserIcon(size: 84),
                          const SizedBox(height: 12),
                          const Text('لم يتم العثور على مستخدمي بلوساب المستجيبين', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w600)),
                          const SizedBox(height: 8),
                          Text('يتم فحص الأجهزة الجديدة تلقائيًا؛ لن يظهر إلا من يرد على تعريف بلوساب. شغّل بلوساب واجعل الظهور القريب مفعّلًا في الهاتف الآخر.', textAlign: TextAlign.center, style: theme.textTheme.bodySmall),
                        ]),
                      ))
                    : ListView.separated(
                        itemCount: candidates.length,
                        separatorBuilder: (_, __) => const Divider(height: 1, indent: 72),
                        itemBuilder: (context, index) {
                          final item = candidates[index];
                          final knownId = prefs.getString('blousab_peer_id_${item.address}');
                          final photoPath = knownId == null ? null : prefs.getString('blousab_peer_photo_$knownId');
                          final coverPath = knownId == null ? null : prefs.getString('blousab_peer_cover_$knownId');
                          final photoFile = photoPath == null ? null : File(photoPath);
                          final hasPhoto = photoFile != null && photoFile.existsSync();
                          final knownName = prefs.getString('blousab_peer_name_${item.address}');
                          final label = (knownName?.trim().isNotEmpty ?? false) ? knownName!.trim() : 'مستخدم بلوساب';
                          final isKnownBlousab = knownId != null && knownId.isNotEmpty;
                          final hasCover = coverPath != null && File(coverPath).existsSync();
                          return Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                            child: InkWell(
                              onTap: () => Navigator.pop(dialogContext, item),
                              borderRadius: BorderRadius.circular(11),
                              child: Container(
                                decoration: BlousabVisuals.panelDecoration(),
                                child: Column(children: [
                                  Container(height: 48, width: double.infinity,
                                    decoration: BoxDecoration(
                                      borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
                                      gradient: BlousabVisuals.neon,
                                      image: hasCover ? DecorationImage(image: FileImage(File(coverPath)), fit: BoxFit.cover) : null)),
                                  ListTile(
                                    leading: BlousabProfileAvatar(name: label, photoPath: hasPhoto ? photoFile!.path : null, radius: 23, online: true),
                                    title: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
                                    subtitle: const Text('مستخدم بلوساب • هوية غير موثقة', style: TextStyle(fontSize: 11)),
                                    trailing: Icon(Icons.bluetooth_connected, color: isKnownBlousab ? const Color(0xFF28C7FF) : Theme.of(context).colorScheme.onSurfaceVariant),
                                  ),
                                ]),
                              ),
                            ),
                          );
                        },
                      )),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(children: [
                    Expanded(child: OutlinedButton.icon(
                      onPressed: () => Navigator.pop(dialogContext),
                      icon: const Icon(Icons.close), label: const Text('إلغاء'),
                    )),
                    if (candidates.isEmpty) ...[
                      const SizedBox(width: 8),
                      Expanded(child: FilledButton.icon(
                        onPressed: () => Navigator.pop(dialogContext, const BlousabDevice(name: '', address: '__retry__')),
                        icon: const Icon(Icons.refresh), label: const Text('إعادة البحث'),
                      )),
                    ],
                  ]),
                ),
              ]),
            ),
          );
        },
      );
      if (device == null) return;
      if (device.address == '__retry__') {
        await _startPrivateChat();
        return;
      }

      // The peer was already validated during discovery. Refresh the profile
      // handshake before opening the private-chat invitation flow.
      final peerKey = 'blousab_peer_id_${device.address}';
      await _bluetooth.connect(device.address).timeout(const Duration(seconds: 6));
      await _bluetooth.sendMessage(address: device.address, message: jsonEncode({
        'type': 'hello', 'senderId': _userId, 'senderName': _userName,
        'protocol': 'blousab-nearby-v1',
        if (myPhoto != null) 'senderPhoto': myPhoto,
        if (myCover != null) 'senderCover': myCover,
      })).timeout(const Duration(seconds: 3));
      String? peerId;
      for (var i = 0; i < 12; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 250));
        peerId = prefs.getString(peerKey);
        if (peerId != null && peerId.isNotEmpty) break;
      }
      if (peerId == null || peerId.isEmpty || peerId == _userId) {
        _message('لم يتم التحقق من أن هذا الجهاز يستخدم بلوساب. لم تُرسل دعوة محادثة.');
        await _bluetooth.disconnect(device.address);
        return;
      }
      final peerName = prefs.getString('blousab_peer_name_${device.address}')?.trim();
      final selectedName = (peerName?.isNotEmpty ?? false) ? peerName! : device.name;
      final ids = <String>[_userId, peerId]..sort();
      final conversationId = 'dm_${ids[0]}_${ids[1]}';
      final responseKey = 'blousab_private_chat_response_${device.address}';
      await prefs.remove(responseKey);
      await _bluetooth.sendMessage(address: device.address, message: jsonEncode({
        'type': 'private_chat_invite', 'conversationId': conversationId,
        'senderId': _userId, 'senderName': _userName, 'recipientId': peerId,
      }));
      bool? accepted;
      for (var i = 0; i < 60; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 250));
        accepted = prefs.getBool(responseKey);
        if (accepted != null) break;
      }
      await prefs.remove(responseKey);
      if (accepted != true) {
        _message(accepted == false ? 'رفض الطرف الآخر المحادثة.' : 'لم يصل رد على دعوة المحادثة.');
        return;
      }
      await _saveDirectChat(conversationId: conversationId, peerName: selectedName, peerAddress: device.address);
      if (!mounted) return;
      await Navigator.push(context, MaterialPageRoute(builder: (_) => ChatScreen(
        conversationId: conversationId, title: selectedName,
        currentUserId: _userId, currentUserName: _userName,
        initialPeerAddress: device.address, connectionAlreadyEstablished: true,
      )));
    } on PlatformException catch (e) {
      _message(e.message ?? 'تعذر البحث أو بدء المحادثة. تحقق من صلاحيات الأجهزة القريبة والبلوتوث.');
    } catch (e) {
      _message('تعذر البحث أو بدء المحادثة: $e');
    }
  }

  Future<void> _joinCommunity() async {
    final codeController = TextEditingController();
    final nameController = TextEditingController(text: _userName);
    final data = await showDialog<Map<String, String>>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('الانضمام إلى مجتمع عبر البلوتوث'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: codeController,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(labelText: 'رمز المجتمع'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: nameController,
              decoration: const InputDecoration(labelText: 'اسمك داخل المجتمع'),
            ),
            const SizedBox(height: 8),
            const Text(
              'يجب أن يكون هاتف المنشئ قريبًا ومقترنًا من إعدادات Android مرة واحدة. '
              'سيصل طلبك إلى المنشئ ليقبله أو يرفضه.',
              style: TextStyle(fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('إلغاء')),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, {
              'code': codeController.text.trim().toUpperCase(),
              'name': nameController.text.trim(),
            }),
            child: const Text('متابعة'),
          ),
        ],
      ),
    );
    codeController.dispose();
    nameController.dispose();
    if (data == null) return;

    final code = data['code'] ?? '';
    final name = data['name'] ?? '';
    if (code.isEmpty || name.isEmpty) {
      _message('أدخل رمز المجتمع واسمك.');
      return;
    }

    try {
      if (!await _bluetooth.requestPermissions()) {
        _message('امنح صلاحيات البلوتوث أولًا.');
        return;
      }
      if (!await _bluetooth.isEnabled()) {
        await _bluetooth.requestEnable();
        _message('شغّل البلوتوث ثم أعد طلب الانضمام.');
        return;
      }
      _message('جارٍ البحث عن أجهزة بلوتوث قريبة لمدة قصيرة…');
      final devices = await _bluetooth.discoverNearbyDevices(
        timeout: const Duration(seconds: 10),
      );
      final prefs = await SharedPreferences.getInstance();
      final myPhoto = await _myProfilePhotoPayload();
      final myCover = await _myProfileCoverPayload();
      // Verify fresh devices through the Blousab application protocol before
      // presenting them. Plain Bluetooth names are never shown as users.
      for (final candidate in devices) {
        final identityKey = 'blousab_peer_id_${candidate.address}';
        if ((prefs.getString(identityKey) ?? '').isNotEmpty && (prefs.getBool('blousab_peer_verified_${candidate.address}') ?? false)) continue;
        try {
          await _bluetooth.connect(candidate.address).timeout(const Duration(seconds: 5));
          await _bluetooth.sendMessage(address: candidate.address, message: jsonEncode({
            'type': 'hello', 'senderId': _userId, 'senderName': _userName,
            if (myPhoto != null) 'senderPhoto': myPhoto,
            if (myCover != null) 'senderCover': myCover,
            'protocol': 'blousab-nearby-v1',
          })).timeout(const Duration(seconds: 3));
          for (var attempt = 0; attempt < 12; attempt++) {
            await Future<void>.delayed(const Duration(milliseconds: 250));
            if ((prefs.getString(identityKey) ?? '').isNotEmpty && (prefs.getBool('blousab_peer_verified_${candidate.address}') ?? false)) break;
          }
        } catch (_) {}
      }
      final verifiedDevices = devices.where((candidate) {
        final id = prefs.getString('blousab_peer_id_${candidate.address}') ?? '';
        return id.isNotEmpty && id != _userId && (prefs.getBool('blousab_peer_verified_${candidate.address}') ?? false);
      }).toList();
      if (verifiedDevices.isEmpty) {
        _message('لم نعثر على مستخدم بلوساب قريب. تأكد أن الطرف الآخر فتح بلوساب وفعّل الظهور للأجهزة القريبة.');
        return;
      }
      if (!mounted) return;
      final device = await showModalBottomSheet<BlousabDevice>(
        context: context,
        builder: (sheetContext) => SafeArea(
          child: SizedBox(
            height: 360,
            child: Column(
              children: [
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('اختر جهاز Bluetooth للاتصال', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
                Expanded(
                  child: ListView.builder(
                    itemCount: verifiedDevices.length,
                    itemBuilder: (_, index) {
                      final device = verifiedDevices[index];
                      final peerId = prefs.getString('blousab_peer_id_${device.address}') ?? '';
                      final peerName = prefs.getString('blousab_peer_name_${device.address}') ?? 'مستخدم بلوساب';
                      final photoPath = prefs.getString('blousab_peer_photo_$peerId');
                      final photoFile = photoPath == null ? null : File(photoPath);
                      final hasPhoto = photoFile != null && photoFile.existsSync();
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundImage: hasPhoto ? FileImage(photoFile!) : null,
                          child: hasPhoto ? null : const Icon(Icons.person),
                        ),
                        title: Text(peerName),
                        subtitle: const Text('مستخدم بلوساب'),
                        onTap: () => Navigator.pop(sheetContext, device),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      if (device == null) return;

      final verifiedPeerName = prefs.getString('blousab_peer_name_${device.address}')?.trim();
      _message('جارٍ الاتصال بمستخدم بلوساب ${verifiedPeerName?.isNotEmpty == true ? verifiedPeerName : 'القريب'}…');
      await _bluetooth.connect(device.address);
      await prefs.setString('wasl_user_name', name);
      _userName = name;
      await _bluetooth.sendMessage(
        address: device.address,
        message: jsonEncode({
          'type': 'join_request',
          'requestId': '${_userId}_${DateTime.now().microsecondsSinceEpoch}',
          'joinCode': code,
          'senderId': _userId,
          'senderName': name,
          'sentAt': DateTime.now().toIso8601String(),
        }),
      );
      _message('أُرسل طلب الانضمام. ستصل النتيجة عند رد المنشئ عبر البلوتوث.');
    } on PlatformException catch (e) {
      _message(e.message ?? 'تعذر الاتصال بهاتف المنشئ.');
    } catch (e) {
      _message('تعذر إرسال طلب الانضمام: $e');
    }
  }

  Future<void> _handleLanEvent(BlousabEvent event) async {
    if (event.type != 'message' || event.message == null) return;
    try {
      final packet = jsonDecode(event.message!);
      if (packet is! Map) return;
      final type = packet['type']?.toString();
      if (type == 'member_status' || type == 'community_rename' || type == 'member_rename') {
        await _handleBluetoothEvent(event);
        return;
      }
      if (packet['conversationId'] == null) return;
      await _relayAndPersistGroupPacket(
        Map<String, dynamic>.from(packet),
        event.address,
      );
    } catch (_) {}
  }

  Future<void> _handleBluetoothEvent(BlousabEvent event) async {
    if (event.type != 'message' || event.message == null) return;
    dynamic packet;
    try {
      packet = jsonDecode(event.message!);
    } catch (_) {
      return;
    }
    if (packet is! Map) return;
    final type = packet['type']?.toString();

    const protocol = 'blousab-nearby-v1';
    if (type == 'hello' || type == 'hello_ack' || type == 'profile_card' || type == 'profile_update') {
      // Never trust a Bluetooth name or an unversioned profile packet as proof
      // that the remote device is running Blousab.
      if (packet['protocol']?.toString() != protocol) return;
      final peerId = packet['senderId']?.toString().trim() ?? '';
      final peerName = packet['senderName']?.toString().trim() ?? '';
      if (peerId.isEmpty || peerName.isEmpty || peerId == _userId || event.address == null) return;
      final prefs = await SharedPreferences.getInstance();
      if (type == 'profile_card' || type == 'profile_update') {
        final verified = prefs.getBool('blousab_peer_verified_${event.address}') ?? false;
        if (!verified || prefs.getString('blousab_peer_id_${event.address}') != peerId) return;
      }
      await _savePeerPhoto(Map<String, dynamic>.from(packet));
      await _savePeerCover(Map<String, dynamic>.from(packet));
      await prefs.setString('blousab_peer_id_${event.address}', peerId);
      await prefs.setString('blousab_peer_name_${event.address}', peerName);
      await prefs.setBool('blousab_peer_verified_${event.address}', true);
      if (type == 'hello') {
        try {
          final myPhoto = await _myProfilePhotoPayload();
          final myCover = await _myProfileCoverPayload();
          await _bluetooth.sendMessage(
            address: event.address!,
            message: jsonEncode({
              'type': 'hello_ack',
              'senderId': _userId,
              'senderName': _userName,
              'protocol': protocol,
              if (myPhoto != null) 'senderPhoto': myPhoto,
              if (myCover != null) 'senderCover': myCover,
            }),
          );
        } catch (_) {}
      }
      return;
    }

    if (type == 'private_chat_response' && event.address != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(
        'blousab_private_chat_response_${event.address}',
        packet['accepted'] == true,
      );
      return;
    }

    if (type == 'private_chat_invite') {
      if (event.address == null || packet['recipientId']?.toString() != _userId) return;
      final senderId = packet['senderId']?.toString() ?? '';
      final senderName = packet['senderName']?.toString() ?? 'مستخدم';
      final conversationId = packet['conversationId']?.toString() ?? '';
      if (senderId.isEmpty || conversationId.isEmpty) return;
      final accepted = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('دعوة إلى محادثة فردية'),
          content: Text('يريد $senderName بدء محادثة خاصة معك عبر البلوتوث. هل تقبل؟'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('رفض')),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('قبول')),
          ],
        ),
      );
      if (event.address != null) {
        try {
          await _bluetooth.sendMessage(address: event.address!, message: jsonEncode({
            'type': 'private_chat_response', 'accepted': accepted == true,
            'senderId': _userId, 'senderName': _userName,
          }));
        } catch (_) {}
      }
      if (accepted == true && mounted) {
        await _saveDirectChat(conversationId: conversationId, peerName: senderName, peerAddress: event.address!);
        await Navigator.push(context, MaterialPageRoute(
          builder: (_) => ChatScreen(
            conversationId: conversationId,
            title: senderName,
            currentUserId: _userId,
            currentUserName: _userName,
            initialPeerAddress: event.address,
            connectionAlreadyEstablished: true,
          ),
        ));
      }
      return;
    }

    // The community page remains mounted underneath chat screens. It can
    // relay group packets across connected Bluetooth peers and persist them
    // even when the recipient has not opened that conversation.
    if (type == 'chat' || type == 'file' || packet['conversationId'] != null) {
      await _relayAndPersistGroupPacket(Map<String, dynamic>.from(packet), event.address);
    }

    if (type == 'join_response') {
      final accepted = packet['accepted'] == true;
      if (!accepted) {
        _message('رفض المنشئ طلب الانضمام: ${packet['reason'] ?? 'تم الرفض'}');
        return;
      }
      final rawCommunity = packet['community'];
      if (rawCommunity is! Map) return;
      try {
        await _store.saveJoinedCommunity(
          communityJson: Map<String, dynamic>.from(rawCommunity),
          localUserId: _userId,
          localUserName: _userName,
        );
        await _reload();
        _message('تم قبولك وحفظ المجتمع على هذا الهاتف.');
      } catch (e) {
        _message('وصلت الموافقة لكن تعذر حفظ المجتمع: $e');
      }
      return;
    }

    if (type == 'community_rename' || type == 'member_rename') {
      final communityId = packet['communityId']?.toString() ?? '';
      final ownerId = packet['ownerId']?.toString() ?? '';
      final community = await _store.findById(communityId);
      if (community == null || community.ownerId != ownerId) return;
      try {
        if (type == 'community_rename') {
          await _store.renameCommunity(
            communityId: communityId,
            ownerId: ownerId,
            newName: packet['newName']?.toString() ?? '',
          );
        } else {
          await _store.renameMember(
            communityId: communityId,
            ownerId: ownerId,
            memberId: packet['memberId']?.toString() ?? '',
            newName: packet['newName']?.toString() ?? '',
          );
        }
        await _reload();
      } catch (_) {}
      return;
    }

    if (type == 'member_status') {
      final communityId = packet['communityId']?.toString() ?? '';
      final ownerId = packet['ownerId']?.toString() ?? '';
      final memberId = packet['memberId']?.toString() ?? '';
      final statusName = packet['status']?.toString() ?? '';
      final community = await _store.findById(communityId);
      if (community == null || community.ownerId != ownerId || memberId.isEmpty) return;
      MemberStatus? status;
      for (final value in MemberStatus.values) {
        if (value.name == statusName) { status = value; break; }
      }
      final resolvedStatus = status;
      if (resolvedStatus == null || resolvedStatus == MemberStatus.pending) return;
      if (!community.members.any((member) => member.id == memberId)) return;
      try {
        await _store.setMemberStatus(
          communityId: communityId,
          ownerId: ownerId,
          memberId: memberId,
          status: resolvedStatus,
        );
        await _reload();
        if (memberId == _userId && resolvedStatus == MemberStatus.blocked) {
          _message('حظر منشئ المجتمع هذا الحساب من المشاركة.');
        }
      } catch (_) {}
      return;
    }

    if (type != 'join_request' || event.address == null) return;
    final requestId = packet['requestId']?.toString() ??
        '${event.address}_${packet['senderId']}';
    if (_handledJoinRequests.contains(requestId)) return;
    _handledJoinRequests.add(requestId);

    final code = packet['joinCode']?.toString() ?? '';
    final memberId = packet['senderId']?.toString() ?? '';
    final memberName = packet['senderName']?.toString() ?? 'عضو جديد';
    if (memberId.isEmpty || memberId == _userId) return;

    final community = await _store.findByJoinCode(code);
    if (community == null || community.ownerId != _userId) {
      try {
        await _bluetooth.sendMessage(
          address: event.address!,
          message: jsonEncode({'type': 'join_response', 'accepted': false, 'reason': 'رمز غير صحيح أو هذا الهاتف ليس المنشئ'}),
        );
      } catch (_) {}
      return;
    }

    final existing = community.members.where((m) => m.id == memberId).toList();
    if (existing.isNotEmpty && existing.first.status == MemberStatus.blocked) {
      await _sendJoinResponse(event.address!, accepted: false, reason: 'هذا الجهاز محظور');
      return;
    }
    if (existing.isEmpty) {
      await _store.requestJoin(joinCode: code, memberId: memberId, memberName: memberName);
    } else if (existing.first.status == MemberStatus.approved) {
      final latest = await _store.findById(community.id);
      if (latest != null) {
        await _sendJoinResponse(event.address!, accepted: true, community: latest);
      }
      return;
    }
    await _reload();
    if (!mounted) return;

    final approve = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('طلب انضمام جديد'),
        content: Text('$memberName يريد الانضمام إلى «${community.name}».\n\nرمز المجتمع صحيح. هل توافق على انضمامه؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('رفض')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('قبول')),
        ],
      ),
    );

    final status = approve == true ? MemberStatus.approved : MemberStatus.rejected;
    try {
      await _store.setMemberStatus(
        communityId: community.id,
        ownerId: _userId,
        memberId: memberId,
        status: status,
      );
      final latest = await _store.findById(community.id);
      if (approve == true && latest != null) {
        await _sendJoinResponse(event.address!, accepted: true, community: latest);
      } else {
        await _sendJoinResponse(event.address!, accepted: false, reason: 'رفض منشئ المجتمع الطلب');
      }
      await _reload();
    } catch (e) {
      _message('تعذر إكمال طلب الانضمام: $e');
    }
  }

  Future<void> _relayAndPersistGroupPacket(
    Map<String, dynamic> packet,
    String? sourceAddress,
  ) async {
    final conversationId = packet['conversationId']?.toString() ?? '';
    final messageId = packet['id']?.toString() ?? '';
    final senderId = packet['senderId']?.toString() ?? '';
    final senderName = packet['senderName']?.toString() ?? 'مستخدم';
    final type = packet['type']?.toString() ?? 'chat';
    if (conversationId.isEmpty || messageId.isEmpty || senderId.isEmpty) return;

    final community = await _store.findById(conversationId);
    if (community == null) return; // direct chats are never relayed
    final sender = community.members.where((m) => m.id == senderId).toList();
    if (sender.isEmpty || sender.first.status != MemberStatus.approved) return;

    // De-duplicate first; relayed packets keep the original message ID.
    final firstSeen = _relayedMessageIds.add(messageId);
    if (_relayedMessageIds.length > 2500) {
      _relayedMessageIds.remove(_relayedMessageIds.first);
    }

    String text = packet['text']?.toString() ?? '';
    String? attachmentPath;
    String? attachmentName;
    if (type == 'file') {
      attachmentName = packet['fileName']?.toString() ?? 'ملف مستلم';
      final encoded = packet['data']?.toString() ?? '';
      if (encoded.isEmpty || encoded.length > 6 * 1024 * 1024) return;
      try {
        final bytes = base64Decode(encoded);
        final directory = await getApplicationDocumentsDirectory();
        final safeName = attachmentName.replaceAll(RegExp(r'[^\w.\- ()\u0600-\u06FF]'), '_');
        final file = File('${directory.path}/relay_${messageId.hashCode}_$safeName');
        if (!await file.exists()) await file.writeAsBytes(bytes, flush: true);
        attachmentPath = file.path;
        text = '📎 $attachmentName';
      } catch (_) {
        return;
      }
    }

    final message = BlousabMessage(
      id: messageId,
      conversationId: conversationId,
      senderId: senderId,
      senderName: senderName,
      text: text,
      sentAt: DateTime.tryParse(packet['sentAt']?.toString() ?? '') ?? DateTime.now(),
      isMine: false,
      attachmentPath: attachmentPath,
      attachmentName: attachmentName,
    );
    await _messageStore.saveMessage(message);

    final hops = int.tryParse(packet['hops']?.toString() ?? '0') ?? 0;
    final shouldRelay = packet['relay'] == true &&
        firstSeen && senderId != _userId && hops < 4;
    if (shouldRelay) {
      final forwarded = Map<String, dynamic>.from(packet)..['hops'] = hops + 1;
      final encoded = jsonEncode(forwarded);
      try { await _bluetooth.broadcastMessage(encoded); } catch (_) {}
      try { await LocalNetworkService.instance.broadcastMessage(encoded); } catch (_) {}
      // If neither transport is available, the message remains saved locally.
    }
  }

  Future<void> _sendJoinResponse(
    String address, {
    required bool accepted,
    String? reason,
    BlousabCommunity? community,
  }) async {
    try {
      await _bluetooth.sendMessage(
        address: address,
        message: jsonEncode({
          'type': 'join_response',
          'accepted': accepted,
          'reason': reason,
          if (community != null) 'community': community.toJson(),
        }),
      );
    } catch (e) {
      _message('تم حفظ القرار لكن تعذر إرساله إلى الهاتف الآخر: $e');
    }
  }

  Future<void> _openCommunity(BlousabCommunity community) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CommunityDetailsScreen(
          communityId: community.id,
          userId: _userId,
          onChanged: _reload,
        ),
      ),
    );

    await _reload();
  }

  @override
  void dispose() {
    blousabChatSearchRequest.removeListener(_onSearchRequest);
    _bluetoothSubscription?.cancel();
    _lanSubscription?.cancel();
    super.dispose();
  }

  String _previewTime(DateTime t) {
    final now = DateTime.now();
    final local = t.toLocal();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(local.year, local.month, local.day);
    final diff = today.difference(day).inDays;
    if (diff <= 0) {
      return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
    }
    if (diff == 1) return 'أمس';
    if (diff < 7) {
      const names = ['الاثنين', 'الثلاثاء', 'الأربعاء', 'الخميس', 'الجمعة', 'السبت', 'الأحد'];
      return names[local.weekday - 1];
    }
    return '${local.day}/${local.month}/${local.year}';
  }

  String _previewText(BlousabMessage? m, String fallback) {
    if (m == null) return fallback;
    if (m.attachmentName != null && m.attachmentName!.isNotEmpty) return '📎 ${m.attachmentName}';
    return m.text;
  }

  Widget _chatRow({
    required Widget avatar,
    required String title,
    required String subtitle,
    String? time,
    bool verified = false,
    Widget? titleSuffix,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 60),
          padding: const EdgeInsets.fromLTRB(12, 5, 6, 5),
          decoration: blousabCardDecoration(radius: 18),
          child: Row(children: [
            avatar,
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Row(mainAxisSize: MainAxisSize.min, children: [
                Flexible(child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800))),
                if (verified) const Padding(padding: EdgeInsetsDirectional.only(start: 5), child: BlousabVerifiedBadge(size: 19)),
                if (titleSuffix != null) titleSuffix,
              ]),
              const SizedBox(height: 3),
              Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Color(0xFFC6D0F2), fontSize: 14.5)),
            ])),
            const SizedBox(width: 8),
            if (time != null) Text(time, style: const TextStyle(color: Color(0xFFC6D0F2), fontSize: 13.5)),
          ]),
        ),
      ),
    );
  }

  Widget _aiAvatar(bool ready) => BlousabAiAvatar(size: 58, dimmed: !ready);

  Future<void> _openAiInfo() async {
    await Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const BlousabAiScreen()));
    if (mounted) setState(() {});
  }

  /// محادثة Blousab AI المثبتة دائمًا في أعلى القائمة. شفافة وغير فعّالة قبل التحميل.
  Widget _aiRow() => ValueListenableBuilder<BlousabAiStatus>(
        valueListenable: BlousabAiService.instance.status,
        builder: (context, status, _) {
          final ready = status == BlousabAiStatus.ready;
          final subtitle = switch (status) {
            BlousabAiStatus.ready => 'مساعد الذكاء الاصطناعي المحلي',
            BlousabAiStatus.downloading => 'جارٍ التحميل… اضغط للمتابعة',
            BlousabAiStatus.notLoaded => 'مساعد الذكاء الاصطناعي المحلي • غير محمّل',
          };
          return Opacity(
            opacity: ready ? 1 : .55,
            child: _chatRow(
              avatar: _aiAvatar(ready),
              title: 'Blousab AI',
              titleSuffix: const Padding(padding: EdgeInsetsDirectional.only(start: 5), child: Icon(Icons.auto_awesome, color: Color(0xFFFFD84A), size: 19)),
              subtitle: subtitle,
              onTap: _openAiInfo,
            ),
          );
        },
      );

  @override
  Widget build(BuildContext context) {
    final directChats = _directChats.where((chat) => (chat['peerName'] ?? '').toLowerCase().contains(_searchQuery)).toList();
    final communities = _communities.where((community) => community.name.toLowerCase().contains(_searchQuery)).toList();
    final showAi = _searchQuery.isEmpty || 'blousab ai محادثة بلوساب ai'.contains(_searchQuery);
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: null,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                BlousabTopBar(
                  start: [
                    BlousabSquareIconButton(icon: Icons.add_rounded, tooltip: 'محادثة جديدة', onTap: _startPrivateChat),
                    const SizedBox(width: 4),
                    BlousabBell(count: widget.notificationCount, onTap: widget.onNotifications),
                  ],
                  end: [
                    BlousabSquareIconButton(
                      icon: _searchOpen ? Icons.close_rounded : Icons.search_rounded, size: 42, tooltip: 'بحث',
                      onTap: () => setState(() { _searchOpen = !_searchOpen; if (!_searchOpen) _searchQuery = ''; }),
                    ),
                  ],
                ),
                if (_searchOpen)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                    child: SizedBox(
                      height: 44,
                      child: TextField(
                        autofocus: true,
                        onChanged: (value) => setState(() => _searchQuery = value.trim().toLowerCase()),
                        style: const TextStyle(fontSize: 14, color: Colors.white),
                        decoration: const InputDecoration(
                          hintText: 'البحث في المحادثات والمجتمعات',
                          prefixIcon: Icon(Icons.search, size: 20),
                          isDense: true,
                        ),
                      ),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 2, 12, 12),
                  child: Row(children: [
                    Expanded(child: BlousabNeonPill(label: 'الانضمام إلى المجتمعات', icon: Icons.groups_rounded, color: const Color(0xFFB238FF), onTap: _openCommunityOptions)),
                    const SizedBox(width: 9),
                    Expanded(child: BlousabNeonPill(label: 'محادثة جديدة', icon: Icons.mark_chat_unread_rounded, color: const Color(0xFF28C7FF), onTap: _startPrivateChat)),
                    const SizedBox(width: 9),
                    Expanded(child: BlousabNeonPill(label: 'البحث عن مستخدمين', icon: Icons.person_search_rounded, color: const Color(0xFFFF9A1F), onTap: _startPrivateChat)),
                  ]),
                ),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: _reload,
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 14),
                      children: [
                        if (showAi) _aiRow(),
                        ...directChats.map((chat) {
                          final id = chat['conversationId'] ?? '';
                          final last = _previews[id];
                          final name = chat['peerName'] ?? 'محادثة فردية';
                          return _chatRow(
                            avatar: BlousabRingAvatar(name: name, size: 58, ring: 2.5, online: false),
                            title: name,
                            subtitle: _previewText(last, 'محادثة محلية • بلوساب'),
                            time: last == null ? null : _previewTime(last.sentAt),
                            onTap: () => _openDirectChat(chat),
                          );
                        }),
                        ...communities.map((community) {
                          final last = _previews[community.id];
                          final approved = community.members.where((m) => m.status == MemberStatus.approved).length;
                          final pending = community.members.where((m) => m.status == MemberStatus.pending).length;
                          return _chatRow(
                            avatar: BlousabRingAvatar(
                              name: community.name, size: 58, ring: 2.5,
                              child: Container(
                                decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF1D7BFF), Color(0xFF2B3FD6)])),
                                child: const Icon(Icons.groups_rounded, color: Colors.white, size: 34),
                              ),
                            ),
                            title: community.name,
                            titleSuffix: const Padding(padding: EdgeInsetsDirectional.only(start: 5), child: Icon(Icons.groups_rounded, color: Color(0xFF28A8FF), size: 19)),
                            subtitle: last != null
                                ? _previewText(last, '')
                                : 'الأعضاء المقبولون: $approved${pending > 0 ? ' • طلبات معلقة: $pending' : ''}',
                            time: last == null ? null : _previewTime(last.sentAt),
                            onTap: () => _openCommunity(community),
                          );
                        }),
                        if (directChats.isEmpty && communities.isEmpty && !showAi)
                          Padding(
                            padding: const EdgeInsets.only(top: 60),
                            child: Column(children: [
                              const Icon(Icons.forum_outlined, size: 58, color: Color(0xFFA9B8E8)),
                              const SizedBox(height: 12),
                              const Text('لا توجد نتائج مطابقة للبحث', textAlign: TextAlign.center, style: TextStyle(color: Colors.white)),
                            ]),
                          ),
                        if (directChats.isEmpty && communities.isEmpty && showAi && _searchQuery.isEmpty)
                          const Padding(
                            padding: EdgeInsets.only(top: 36),
                            child: Column(children: [
                              Icon(Icons.forum_outlined, size: 52, color: Color(0xFFA9B8E8)),
                              SizedBox(height: 10),
                              Text('ابدأ محادثة فردية أو أنشئ مجتمعًا جديدًا.', textAlign: TextAlign.center, style: TextStyle(color: Color(0xFFC6D0F2))),
                            ]),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }

}

class _CompactChatAction extends StatelessWidget {
  const _CompactChatAction({required this.icon, required this.label, required this.color, required this.onTap});
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 116,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        height: 30,
        padding: const EdgeInsets.symmetric(horizontal: 5),
        decoration: BoxDecoration(
          gradient: Theme.of(context).brightness == Brightness.dark
              ? LinearGradient(colors: [const Color(0xFF0B1D4A), color.withOpacity(.22)]) : null,
          color: Theme.of(context).brightness == Brightness.light ? Theme.of(context).colorScheme.surfaceContainerHighest : null,
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: color.withOpacity(.85), width: 1.05),
          boxShadow: [BoxShadow(color: color.withOpacity(.12), blurRadius: 8)],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: color),
            const SizedBox(width: 4),
            Flexible(child: Text(label, textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.onSurface))),
          ],
        ),
      ),
    ),
  );
}

class _HomeActionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _HomeActionTile({required this.icon, required this.label, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.surface,
    borderRadius: BorderRadius.circular(12),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: Theme.of(context).dividerColor.withOpacity(.25))),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Container(width: 54, height: 54, decoration: BoxDecoration(color: color.withOpacity(.12), borderRadius: BorderRadius.circular(18)), child: Icon(icon, color: color, size: 29)),
          const SizedBox(height: 9),
          Text(label, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
        ]),
      ),
    ),
  );
}

class CommunityDetailsScreen extends StatefulWidget {
  final String communityId;
  final String userId;
  final Future<void> Function() onChanged;

  const CommunityDetailsScreen({
    super.key,
    required this.communityId,
    required this.userId,
    required this.onChanged,
  });

  @override
  State<CommunityDetailsScreen> createState() =>
      _CommunityDetailsScreenState();
}

class _CommunityDetailsScreenState
    extends State<CommunityDetailsScreen> {
  final CommunityStore _store = CommunityStore();
  final BluetoothClassicService _bluetooth = BluetoothClassicService.instance;
  StreamSubscription<BlousabEvent>? _bluetoothSubscription;
  StreamSubscription<BlousabEvent>? _lanSubscription;
  final Set<String> _handledJoinRequests = <String>{};
  final Set<String> _relayedMessageIds = <String>{};
  final MessageStore _messageStore = MessageStore();
  BlousabCommunity? _community;
  bool _loading = true;

  bool get _isOwner => _community?.ownerId == widget.userId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final all = await _store.getCommunities();
      final matches = all.where(
        (c) => c.id == widget.communityId,
      );

      if (!mounted) return;

      setState(() {
        _community = matches.isEmpty ? null : matches.first;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _notify('تعذر تحميل المجتمع: $e');
    }
  }

  void _notify(String text) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text)),
    );
  }

  Future<void> _changeStatus(
    BlousabMember member,
    MemberStatus status,
  ) async {
    try {
      await _store.setMemberStatus(
        communityId: widget.communityId,
        ownerId: widget.userId,
        memberId: member.id,
        status: status,
      );

      final packet = jsonEncode({
        'type': 'member_status',
        'communityId': widget.communityId,
        'ownerId': widget.userId,
        'memberId': member.id,
        'memberName': member.name,
        'status': status.name,
      });
      try { await BluetoothClassicService.instance.broadcastMessage(packet); } catch (_) {}
      try { await LocalNetworkService.instance.broadcastMessage(packet); } catch (_) {}

      await _load();
      await widget.onChanged();

      _notify(
        status == MemberStatus.approved
            ? 'تم قبول العضو محليًا.'
            : status == MemberStatus.rejected
                ? 'تم رفض الطلب محليًا.'
                : 'تم حظر العضو محليًا.',
      );
    } catch (e) {
      _notify('تعذر تنفيذ العملية: $e');
    }
  }

  Future<void> _renameCommunity() async {
    final controller = TextEditingController(
      text: _community?.name ?? '',
    );

    final value = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('تغيير اسم المجتمع'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: 'الاسم الجديد'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(dialogContext, controller.text.trim()),
            child: const Text('حفظ'),
          ),
        ],
      ),
    );

    controller.dispose();

    if (value == null || value.trim().isEmpty) return;

    try {
      await _store.renameCommunity(
        communityId: widget.communityId,
        ownerId: widget.userId,
        newName: value,
      );
      final packet = jsonEncode({
        'type': 'community_rename',
        'communityId': widget.communityId,
        'ownerId': widget.userId,
        'newName': value,
      });
      try { await BluetoothClassicService.instance.broadcastMessage(packet); } catch (_) {}
      try { await LocalNetworkService.instance.broadcastMessage(packet); } catch (_) {}

      await _load();
      await widget.onChanged();
    } catch (e) {
      _notify('تعذر تغيير الاسم: $e');
    }
  }

  Future<void> _renameMember(BlousabMember member) async {
    final controller = TextEditingController(text: member.name);

    final value = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('تغيير اسم العضو'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: 'الاسم الجديد'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(dialogContext, controller.text.trim()),
            child: const Text('حفظ'),
          ),
        ],
      ),
    );

    controller.dispose();

    if (value == null || value.trim().isEmpty) return;

    try {
      await _store.renameMember(
        communityId: widget.communityId,
        ownerId: widget.userId,
        memberId: member.id,
        newName: value,
      );
      final packet = jsonEncode({
        'type': 'member_rename',
        'communityId': widget.communityId,
        'ownerId': widget.userId,
        'memberId': member.id,
        'newName': value,
      });
      try { await BluetoothClassicService.instance.broadcastMessage(packet); } catch (_) {}
      try { await LocalNetworkService.instance.broadcastMessage(packet); } catch (_) {}

      await _load();
    } catch (e) {
      _notify('تعذر تغيير اسم العضو: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final community = _community;

    return Scaffold(
      appBar: AppBar(
        title: Text(community?.name ?? 'تفاصيل المجتمع'),
        actions: [
          if (_isOwner)
            IconButton(
              onPressed: _renameCommunity,
              tooltip: 'تغيير اسم المجتمع',
              icon: const Icon(Icons.edit),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : community == null
              ? const Center(child: Text('المجتمع غير موجود.'))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.all(12),
                    children: [
Card(
  child: ListTile(
    leading: const CircleAvatar(
      child: Icon(Icons.chat_bubble_outline),
    ),
    title: const Text('محادثة المجتمع'),
    subtitle: const Text('افتح رسائل هذا المجتمع'),
    trailing: const Icon(Icons.chevron_left),
    onTap: () async {
      final prefs = await SharedPreferences.getInstance();

      final currentUserId =
          prefs.getString('wasl_user_id') ?? widget.userId;

      final currentUserName =
          prefs.getString('wasl_user_name') ?? 'مستخدم بلوساب';

      if (!context.mounted) return;

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ChatScreen(
            conversationId: widget.communityId,
            title: community.name,
            currentUserId: currentUserId,
            currentUserName: currentUserName,
          ),
        ),
      );
    },
  ),
),
const SizedBox(height: 8),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'رمز المجتمع',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 8),
                              SelectableText(
                                community.joinCode,
                                style: Theme.of(context)
                                    .textTheme
                                    .headlineSmall,
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                'الرمز محفوظ محليًا. مشاركة الرمز وحدها '
                                'لا تنقل الطلبات بين الأجهزة.',
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'الأعضاء والطلبات (${community.members.length})',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      ...community.members.map((member) {
                        final isPending =
                            member.status == MemberStatus.pending;
                        final statusLabel = switch (member.status) {
                          MemberStatus.pending => 'بانتظار الموافقة',
                          MemberStatus.approved => 'مقبول',
                          MemberStatus.rejected => 'مرفوض',
                          MemberStatus.blocked => 'محظور',
                        };

                        return Card(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 6,
                            ),
                            child: Column(
                              children: [
                                ListTile(
                                  leading: CircleAvatar(
                                    child: Icon(
                                      member.isOwner
                                          ? Icons.admin_panel_settings
                                          : Icons.person,
                                    ),
                                  ),
                                  title: Text(member.name),
                                  subtitle: Text(statusLabel),
                                  trailing: member.isOwner
                                      ? const Text('المنشئ')
                                      : _isOwner
                                          ? PopupMenuButton<String>(
                                              onSelected: (value) {
                                                if (value == 'rename') {
                                                  _renameMember(member);
                                                } else if (value == 'block') {
                                                  _changeStatus(
                                                    member,
                                                    MemberStatus.blocked,
                                                  );
                                                } else if (value ==
                                                    'approve') {
                                                  _changeStatus(
                                                    member,
                                                    MemberStatus.approved,
                                                  );
                                                } else if (value ==
                                                    'reject') {
                                                  _changeStatus(
                                                    member,
                                                    MemberStatus.rejected,
                                                  );
                                                }
                                              },
                                              itemBuilder: (_) => [
                                                if (isPending)
                                                  const PopupMenuItem(
                                                    value: 'approve',
                                                    child: Text('قبول الطلب'),
                                                  ),
                                                if (isPending)
                                                  const PopupMenuItem(
                                                    value: 'reject',
                                                    child: Text('رفض الطلب'),
                                                  ),
                                                if (member.status !=
                                                    MemberStatus.blocked)
                                                  const PopupMenuItem(
                                                    value: 'block',
                                                    child: Text('حظر العضو'),
                                                  ),
                                                const PopupMenuItem(
                                                  value: 'rename',
                                                  child: Text('تغيير الاسم'),
                                                ),
                                              ],
                                            )
                                          : null,
                                ),
                                if (_isOwner && isPending)
                                  Row(
                                    children: [
                                      Expanded(
                                        child: TextButton.icon(
                                          onPressed: () => _changeStatus(
                                            member,
                                            MemberStatus.rejected,
                                          ),
                                          icon: const Icon(Icons.close),
                                          label: const Text('رفض'),
                                        ),
                                      ),
                                      Expanded(
                                        child: FilledButton.icon(
                                          onPressed: () => _changeStatus(
                                            member,
                                            MemberStatus.approved,
                                          ),
                                          icon: const Icon(Icons.check),
                                          label: const Text('قبول'),
                                        ),
                                      ),
                                    ],
                                  ),
                              ],
                            ),
                          ),
                        );
                      }),
                    ],
                  ),
                ),
    );
  }
}