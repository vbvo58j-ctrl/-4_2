import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:open_filex/open_filex.dart';

import '../models/blousab_message.dart';
import '../widgets/blousab_visuals.dart';
import '../services/message_store.dart';
import '../services/pending_message_store.dart';
import '../services/relay_queue_store.dart';
import '../services/relay_policy.dart';
import '../services/community_store.dart';
import '../services/local_network_service.dart';
import '../services/wifi_aware_service.dart';
import '../services/notification_service.dart';
import '../services/bluetooth_classic_service.dart';

class ChatScreen extends StatefulWidget {
final String conversationId;
final String title;
final String currentUserId;
final String currentUserName;
final String? initialPeerAddress;
final bool connectionAlreadyEstablished;
final Future<void> Function(BlousabMessage message)? onSendMessage;

const ChatScreen({
super.key,
required this.conversationId,
required this.title,
required this.currentUserId,
required this.currentUserName,
this.initialPeerAddress,
this.connectionAlreadyEstablished = false,
this.onSendMessage,
});

@override
State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
final MessageStore _store = MessageStore();
final CommunityStore _communityStore = CommunityStore();
final BluetoothClassicService _bluetooth =
BluetoothClassicService.instance;

final TextEditingController _textController =
TextEditingController();
final ScrollController _scrollController = ScrollController();

final Set<String> _receivedIds = <String>{};
final Map<String, Completer<void>> _pendingAcks = <String, Completer<void>>{};

List<BlousabMessage> _messages = [];
List<BlousabDevice> _devices = [];

StreamSubscription<BlousabEvent>? _subscription;
StreamSubscription<BlousabEvent>? _lanSubscription;
StreamSubscription<WifiAwareEvent>? _awareProfileSubscription;
Timer? _relayRetryTimer;
bool _relayRetryInProgress = false;

String? _selectedAddress;
String? _selectedWifiAddress;
String _connectionStatus = 'غير متصل';
String _profileCoverPath = '';
String _myProfilePhotoPath = '';
String _peerProfilePhotoPath = '';
String _peerDisplayName = '';
String _connectionMode = 'bluetooth';

bool _loading = true;
bool _sending = false;
bool _working = false;
bool _isCommunityConversation = false;
bool _peerBlocked = false;
double _messageFontSize = 16;
bool _showMessageTime = true;
bool _vibrateOnSend = true;
bool _compactBubbles = false;
String _chatWallpaper = 'night';

@override
void initState() {
super.initState();
NotificationService.activeConversationId = widget.conversationId;
SharedPreferences.getInstance().then((prefs) {
  if (!mounted) return;
  setState(() {
    _profileCoverPath = prefs.getString('wasl_profile_cover') ?? '';
    _myProfilePhotoPath = prefs.getString('wasl_profile_photo') ?? '';
    _connectionMode = prefs.getString('blousab_connection_mode') ?? 'bluetooth';
    final chatKey = 'blousab_chat_${widget.conversationId}_';
    final peerId = _peerIdFromConversation();
    _peerBlocked = peerId != null && (prefs.getBool('blousab_blocked_peer_$peerId') ?? false);
    _messageFontSize = (prefs.getDouble('${chatKey}font_size') ?? prefs.getDouble('blousab_message_font_size') ?? 16).clamp(14, 22).toDouble();
    _showMessageTime = prefs.getBool('${chatKey}show_time') ?? prefs.getBool('blousab_show_message_time') ?? true;
    _vibrateOnSend = prefs.getBool('${chatKey}vibrate') ?? prefs.getBool('blousab_vibrate_on_send') ?? true;
    _compactBubbles = prefs.getBool('${chatKey}compact') ?? prefs.getBool('blousab_compact_bubbles') ?? false;
    _chatWallpaper = prefs.getString('${chatKey}wallpaper') ?? prefs.getString('wasl_chat_wallpaper') ?? 'night';
  });
  _loadPeerProfile();
});
_selectedAddress = widget.initialPeerAddress;
_communityStore.findById(widget.conversationId).then((c) { if (mounted) setState(() => _isCommunityConversation = c != null); });
_loadMessages();
_listenToBluetooth();
_lanSubscription = LocalNetworkService.instance.events.listen(_handleBluetoothEvent);
_awareProfileSubscription = WifiAwareService.instance.events.listen(_handleWifiAwareProfileEvent);
_restoreLastConnection();
Future<void>.delayed(const Duration(seconds: 2), _retryPendingOutbox);
Future<void>.delayed(const Duration(seconds: 3), _retryRelayQueue);
_relayRetryTimer = Timer.periodic(const Duration(seconds: 20), (_) { if (mounted) _retryRelayQueue(); });
}

Future<void> _clearConversationMessages() async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('مسح محتوى الدردشة؟'),
      content: const Text('سيتم حذف الرسائل المحفوظة في هذه المحادثة من هذا الهاتف فقط. لن تُحذف من هاتف الطرف الآخر.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('مسح الدردشة')),
      ],
    ),
  );
  if (confirmed != true) return;
  await _store.clearMessages(widget.conversationId);
  if (!mounted) return;
  setState(() {
    _messages.clear();
    _receivedIds.clear();
  });
  _showNotice('تم مسح محتوى هذه الدردشة من هذا الهاتف.');
}

Future<void> _togglePeerBlock() async {
  final peerId = _peerIdFromConversation();
  if (peerId == null) {
    _showNotice('الحظر متاح للمحادثات الخاصة التي لها معرّف مستخدم.');
    return;
  }
  final nextBlocked = !_peerBlocked;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(nextBlocked ? 'حظر جهة الاتصال؟' : 'فك حظر جهة الاتصال؟'),
      content: Text(nextBlocked
          ? 'سيتم تجاهل الرسائل الواردة من هذا المستخدم على هذا الجهاز.'
          : 'سيُسمح باستقبال الرسائل من هذا المستخدم مجددًا.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(nextBlocked ? 'حظر' : 'فك الحظر')),
      ],
    ),
  );
  if (confirmed != true) return;
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool('blousab_blocked_peer_$peerId', nextBlocked);
  if (!mounted) return;
  setState(() => _peerBlocked = nextBlocked);
  _showNotice(nextBlocked ? 'تم حظر جهة الاتصال على هذا الجهاز.' : 'تم فك الحظر.');
}

Widget _wifiPeerAvatar(Map<String, String> peer) {
  final encoded = peer['photo'];
  if (encoded != null && encoded.isNotEmpty) {
    try {
      return CircleAvatar(
        radius: 25,
        backgroundImage: MemoryImage(base64Decode(encoded)),
        onBackgroundImageError: (_, __) {},
      );
    } catch (_) {}
  }
  final name = (peer['name'] ?? '').trim();
  return CircleAvatar(
    radius: 25,
    child: Text(name.isEmpty ? '؟' : name.characters.first),
  );
}

Future<void> _changeConnectionFlow() async {
  String role = 'join';
  final selectedRole = await showDialog<String>(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, setDialogState) => AlertDialog(
    title: const Text('تغيير اتصال المحادثة'),
    content: Column(mainAxisSize: MainAxisSize.min, children: [
      RadioListTile<String>(value: 'host', groupValue: role, title: const Text('منشئ الاتصال'), subtitle: const Text('شغّل نقطة الاتصال من إعدادات الهاتف أولًا'), onChanged: (v) => setDialogState(() => role = v!)),
      RadioListTile<String>(value: 'join', groupValue: role, title: const Text('مشترك / البحث عن المنشئ'), subtitle: const Text('اتصل بشبكة المنشئ ثم ابحث عن جهازه'), onChanged: (v) => setDialogState(() => role = v!)),
    ]),
    actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')), FilledButton(onPressed: () => Navigator.pop(ctx, role), child: const Text('متابعة'))],
  )));
  if (selectedRole == null) return;
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString('blousab_connection_mode', 'wifi');
  await prefs.setString('blousab_chat_${widget.conversationId}_wifi_role', selectedRole);
  try {
    await LocalNetworkService.instance.start(userId: widget.currentUserId, userName: widget.currentUserName);
  } catch (e) {
    if (mounted) _showNotice('تعذر تشغيل اكتشاف Wi-Fi: $e');
    return;
  }
  if (selectedRole == 'host') {
    if (mounted) { setState(() { _connectionMode = 'wifi'; _connectionStatus = 'منشئ Wi-Fi؛ انتظر انضمام الطرف الآخر'; }); _showNotice('شغّل نقطة الاتصال من إعدادات Android، ثم اطلب من الطرف الآخر الاتصال بها وفتح بلوساب.'); }
    return;
  }
  if (mounted) setState(() { _connectionMode = 'wifi'; _connectionStatus = 'جارٍ البحث عن منشئ الاتصال...'; });
  final awarePeers = <String, WifiAwarePeer>{
    for (final peer in WifiAwareService.instance.discoveredPeers)
      if (peer.userId != widget.currentUserId) peer.userId: peer,
  };
  StateSetter? updateAwareDialog;
  StreamSubscription<WifiAwareEvent>? awareSubscription;
  try {
    awareSubscription = WifiAwareService.instance.events.listen((event) {
      if (event.type == 'userFound' && event.peer != null && event.peer!.userId != widget.currentUserId) {
        awarePeers[event.peer!.userId] = event.peer!;
        updateAwareDialog?.call(() {});
      } else if (event.type == 'userLost' && event.peer != null) {
        awarePeers.remove(event.peer!.userId);
        updateAwareDialog?.call(() {});
      }
    });
    await WifiAwareService.instance.start(userId: widget.currentUserId, userName: widget.currentUserName);
  } catch (_) {
    // Wi-Fi Aware is optional; LAN discovery remains available on supported networks.
  }
  final chosen = await showDialog<String>(context: context, builder: (ctx) {
    return StatefulBuilder(builder: (ctx, setDialogState) {
      updateAwareDialog = setDialogState;
      final peers = LocalNetworkService.instance.discoveredPeers;
      return AlertDialog(
        title: const Text('مستخدمو بلوساب القريبون'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView(shrinkWrap: true, children: [
            if (awarePeers.isNotEmpty) ...[
              const Padding(padding: EdgeInsets.symmetric(vertical: 6), child: Text('اكتشاف Wi-Fi مباشر • دون راوتر أو شبكة مشتركة', style: TextStyle(fontWeight: FontWeight.bold))),
              ...awarePeers.values.map((peer) {
                final cachedPhoto = SharedPreferences.getInstance();
                return FutureBuilder<SharedPreferences>(
                  future: cachedPhoto,
                  builder: (context, snapshot) {
                    final prefs = snapshot.data;
                    final photoPath = prefs?.getString('blousab_peer_photo_${peer.userId}') ?? '';
                    final photoFile = photoPath.isNotEmpty ? File(photoPath) : null;
                    final hasPhoto = photoFile != null && photoFile.existsSync();
                    final cachedName = prefs?.getString('blousab_peer_name_id_${peer.userId}') ?? '';
                    final displayName = cachedName.trim().isNotEmpty ? cachedName.trim() : peer.userName;
                    return ListTile(
                      leading: CircleAvatar(
                        radius: 25,
                        backgroundImage: hasPhoto ? FileImage(photoFile!) : null,
                        child: hasPhoto ? null : Text(displayName.isEmpty ? '؟' : displayName.characters.first),
                      ),
                      title: Text(displayName),
                      subtitle: const Text('مستخدم بلوساب قريب'),
                      trailing: const Icon(Icons.wifi_tethering, color: Color(0xFF159B83)),
                    );
                  },
                );
              }),
            ],
            if (peers.isNotEmpty) ...[
              const Padding(padding: EdgeInsets.symmetric(vertical: 6), child: Text('أجهزة على الشبكة المحلية', style: TextStyle(fontWeight: FontWeight.bold))),
              ...peers.map((p) => ListTile(
                leading: _wifiPeerAvatar(p),
                title: Text((p['name'] ?? '').trim().isEmpty ? 'مستخدم بلوساب' : p['name']!.trim()),
                subtitle: const Text('مستخدم بلوساب قريب'),
                trailing: const Icon(Icons.wifi, color: Color(0xFF159B83)),
                onTap: () => Navigator.pop(ctx, p['address']),
              )),
            ],
            if (awarePeers.isEmpty && peers.isEmpty) const Padding(
              padding: EdgeInsets.all(12), child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.wifi_find, size: 36), SizedBox(height: 12),
                Text('جارٍ البحث عن مستخدمي بلوساب القريبين. تأكد من دعم الهاتف لتقنية Wi-Fi Aware ومنح الصلاحية.'),
              ]),
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إغلاق')),
          TextButton(onPressed: () => setDialogState(() {}), child: const Text('تحديث القائمة')),
        ],
      );
    });
  });
  await awareSubscription?.cancel();
  if (chosen != null && mounted) {
    await prefs.setString('blousab_last_wifi_peer_${widget.conversationId}', chosen);
    setState(() { _selectedWifiAddress = chosen; _connectionStatus = 'تم اختيار جهاز Wi-Fi: $chosen'; });
    _showNotice('تم اختيار الجهاز. ستُرسل الرسائل والملفات إليه فقط، بشرط بقائه ظاهرًا على الشبكة نفسها.');
  }
}

Future<void> _openConversationSettings() async {
  double fontSize = _messageFontSize;
  bool showTime = _showMessageTime;
  bool compact = _compactBubbles;
  bool vibrate = _vibrateOnSend;
  String wallpaper = _chatWallpaper;
  final result = await showDialog<Map<String, Object?>>(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, setDialogState) => AlertDialog(
    title: const Text('إعدادات هذه المحادثة'),
    content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
      ListTile(title: const Text('حجم الخط'), subtitle: Slider(value: fontSize, min: 14, max: 22, divisions: 4, label: fontSize.round().toString(), onChanged: (v) => setDialogState(() => fontSize = v))),
      SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('إظهار وقت الرسالة'), value: showTime, onChanged: (v) => setDialogState(() => showTime = v)),
      SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('فقاعات مضغوطة'), subtitle: const Text('تقليل المسافات حول الرسائل'), value: compact, onChanged: (v) => setDialogState(() => compact = v)),
      SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('اهتزاز عند الإرسال'), value: vibrate, onChanged: (v) => setDialogState(() => vibrate = v)),
      const SizedBox(height: 8),
      DropdownButtonFormField<String>(value: wallpaper, decoration: const InputDecoration(labelText: 'خلفية المحادثة'), items: const [DropdownMenuItem(value: 'mint', child: Text('تدرج هادئ')), DropdownMenuItem(value: 'plain', child: Text('أبيض بسيط')), DropdownMenuItem(value: 'dark', child: Text('داكن بلوساب'))], onChanged: (v) { if (v != null) setDialogState(() => wallpaper = v); }),
      const Divider(height: 24),
      ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.swap_horiz), title: const Text('تغيير الاتصال'), subtitle: const Text('اختيار منشئ Wi-Fi أو البحث عن جهاز منشئ محفوظ'), onTap: () { Navigator.pop(ctx); _changeConnectionFlow(); }),
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.delete_sweep_outlined, color: Colors.red),
        title: const Text('مسح محتوى الدردشة'),
        subtitle: const Text('حذف الرسائل من هذا الهاتف فقط'),
        onTap: () { Navigator.pop(ctx); _clearConversationMessages(); },
      ),
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(_peerBlocked ? Icons.person_add_alt_1 : Icons.block, color: _peerBlocked ? Colors.teal : Colors.red),
        title: Text(_peerBlocked ? 'فك الحظر' : 'حظر جهة الاتصال'),
        subtitle: Text(_peerBlocked ? 'السماح باستقبال الرسائل مجددًا' : 'تجاهل الرسائل الواردة من هذا المستخدم'),
        onTap: () { Navigator.pop(ctx); _togglePeerBlock(); },
      ),
      const SizedBox(height: 8), const Text('تُحفظ هذه الخيارات لهذه المحادثة فقط ولا تغيّر إعدادات المحادثات الأخرى.', style: TextStyle(fontSize: 12)),
    ])),
    actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')), FilledButton(onPressed: () => Navigator.pop(ctx, {'fontSize': fontSize, 'showTime': showTime, 'compact': compact, 'vibrate': vibrate, 'wallpaper': wallpaper}), child: const Text('حفظ'))],
  )));
  if (result == null) return;
  final prefs = await SharedPreferences.getInstance();
  final prefix = 'blousab_chat_${widget.conversationId}_';
  await prefs.setDouble('${prefix}font_size', result['fontSize'] as double);
  await prefs.setBool('${prefix}show_time', result['showTime'] as bool);
  await prefs.setBool('${prefix}compact', result['compact'] as bool);
  await prefs.setBool('${prefix}vibrate', result['vibrate'] as bool);
  await prefs.setString('${prefix}wallpaper', result['wallpaper'] as String);
  if (!mounted) return;
  setState(() { _messageFontSize = result['fontSize'] as double; _showMessageTime = result['showTime'] as bool; _compactBubbles = result['compact'] as bool; _vibrateOnSend = result['vibrate'] as bool; _chatWallpaper = result['wallpaper'] as String; });
}

Future<String?> _profilePhotoPayload() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final path = prefs.getString('wasl_profile_photo') ?? _myProfilePhotoPath;
    if (path.isEmpty) return null;
    final file = File(path);
    if (!await file.exists()) return null;
    final bytes = await file.readAsBytes();
    // Keep profile cards small enough for Bluetooth text packets.
    if (bytes.isEmpty || bytes.length > 100 * 1024) return null;
    return base64Encode(bytes);
  } catch (_) { return null; }
}

String? _peerIdFromConversation() {
  if (!widget.conversationId.startsWith('dm_')) return null;
  final ids = widget.conversationId.substring(3).split('_');
  final peers = ids.where((id) => id.isNotEmpty && id != widget.currentUserId).toList();
  return peers.isEmpty ? null : peers.first;
}

Future<void> _loadPeerProfile() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final peerId = _peerIdFromConversation();
    final address = widget.initialPeerAddress;
    final cachedName = peerId == null ? null : prefs.getString('blousab_peer_name_id_$peerId');
    final addressName = address == null ? null : prefs.getString('blousab_peer_name_$address');
    final photoPath = peerId == null ? null : prefs.getString('blousab_peer_photo_$peerId');
    if (!mounted) return;
    setState(() {
      _peerDisplayName = (cachedName?.isNotEmpty == true ? cachedName : addressName) ?? widget.title;
      _peerProfilePhotoPath = photoPath ?? '';
    });
  } catch (_) {}
}

Future<void> _handleWifiAwareProfileEvent(WifiAwareEvent event) async {
  final peer = event.peer;
  if (peer == null || peer.userId == widget.currentUserId) return;
  if (event.type == 'dataConnected') {
    try {
      final prefs = await SharedPreferences.getInstance();
      final photoPath = prefs.getString('wasl_profile_photo') ?? _myProfilePhotoPath;
      String? photo;
      if (photoPath.isNotEmpty) {
        final file = File(photoPath);
        if (await file.exists()) {
          final bytes = await file.readAsBytes();
          // Keep the profile card bounded; oversized originals are not sent here.
          if (bytes.length <= 90 * 1024) photo = base64Encode(bytes);
        }
      }
      await WifiAwareService.instance.sendPacket(
        peerId: peer.userId,
        payload: jsonEncode({
          'type': 'profile_card',
          'protocol': 'blousab-nearby-v1',
          'senderId': widget.currentUserId,
          'senderName': widget.currentUserName,
          if (photo != null) 'senderPhoto': photo,
        }),
      );
    } catch (_) {
      // Profile discovery remains available even if the optional photo transfer fails.
    }
  } else if (event.type == 'dataPacket' && event.payload != null) {
    try {
      final decoded = jsonDecode(event.payload!);
      if (decoded is Map && (decoded['type'] == 'profile_card' || decoded['type'] == 'profile_update')) {
        await _cachePeerProfile(decoded);
      }
    } catch (_) {}
  }
}

Future<void> _cachePeerProfile(Map packet) async {
  try {
    final senderId = packet['senderId']?.toString() ?? '';
    if (senderId.isEmpty || senderId == widget.currentUserId) return;
    final prefs = await SharedPreferences.getInstance();
    final senderName = packet['senderName']?.toString();
    if (senderName != null && senderName.trim().isNotEmpty) {
      await prefs.setString('blousab_peer_name_id_$senderId', senderName.trim());
    }
    final encoded = packet['senderPhoto']?.toString() ?? '';
    if (encoded.isNotEmpty && encoded.length <= 140000) {
      final bytes = base64Decode(encoded);
      final dir = await getApplicationDocumentsDirectory();
      final profileDir = Directory('${dir.path}/peer_profiles');
      if (!await profileDir.exists()) await profileDir.create(recursive: true);
      final file = File('${profileDir.path}/${senderId.replaceAll(RegExp(r"[^a-zA-Z0-9_-]"), "_")}.jpg');
      await file.writeAsBytes(bytes, flush: true);
      await prefs.setString('blousab_peer_photo_$senderId', file.path);
    }
    // A remote cover is optional and is never fetched from the Internet.
    final coverEncoded = packet['senderCover']?.toString() ?? '';
    if (coverEncoded.isNotEmpty && coverEncoded.length <= 84000) {
      try {
        final bytes = base64Decode(coverEncoded);
        if (bytes.isNotEmpty && bytes.length <= 60 * 1024) {
          final dir = await getApplicationDocumentsDirectory();
          final folder = Directory('${dir.path}/peer_profiles');
          await folder.create(recursive: true);
          final safeId = senderId.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
          final f = File('${folder.path}/${safeId}_cover.jpg');
          await f.writeAsBytes(bytes, flush: true);
          await prefs.setString('blousab_peer_cover_$senderId', f.path);
        }
      } catch (_) {}
    }
    if (!mounted) return;
    if (senderId == _peerIdFromConversation()) {
      setState(() {
        if (senderName != null && senderName.trim().isNotEmpty) _peerDisplayName = senderName.trim();
        final path = prefs.getString('blousab_peer_photo_$senderId');
        if (path != null) _peerProfilePhotoPath = path;
      });
    }
  } catch (_) {}
}

Future<void> _restoreLastConnection() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    if (widget.initialPeerAddress != null && widget.initialPeerAddress!.isNotEmpty) {
      await prefs.setString('blousab_last_device_${widget.conversationId}', widget.initialPeerAddress!);
      if (widget.connectionAlreadyEstablished) {
        if (mounted) setState(() {
          _selectedAddress = widget.initialPeerAddress;
          _connectionStatus = 'جاهز للمحادثة عبر البلوتوث';
        });
        final photo = await _profilePhotoPayload();
        await _bluetooth.sendMessage(address: widget.initialPeerAddress!, message: jsonEncode({'type': 'profile_card', 'protocol': 'blousab-nearby-v1', 'senderId': widget.currentUserId, 'senderName': widget.currentUserName, if (photo != null) 'senderPhoto': photo}));
        return; // The invitation flow already established the RFCOMM connection.
      }
      try {
        await _bluetooth.connect(widget.initialPeerAddress!);
        if (mounted) setState(() { _selectedAddress = widget.initialPeerAddress; _connectionStatus = 'متصل عبر البلوتوث'; });
      } catch (_) {
        if (mounted) setState(() => _connectionStatus = 'تعذر الاتصال؛ استخدم زر البلوتوث لإعادة المحاولة');
      }
      return;
    }
    final address = prefs.getString('blousab_last_device_${widget.conversationId}');
    if (address == null || address.isEmpty) return;
    if (!await _bluetooth.isSupported() || !await _bluetooth.requestPermissions()) return;
    if (!await _bluetooth.isEnabled()) return;
    if (mounted) setState(() => _connectionStatus = 'جارٍ إعادة الاتصال بالجهاز المحفوظ...');
    await _bluetooth.connect(address);
    if (mounted) setState(() => _selectedAddress = address);
  } catch (_) {
    if (mounted) setState(() => _connectionStatus = 'غير متصل؛ يمكنك إعادة الاتصال من زر البلوتوث');
  }
}

Future<void> _loadMessages() async {
try {
final messages =
await _store.getMessages(widget.conversationId);

  if (!mounted) return;

  setState(() {
    _messages = messages;
    _receivedIds.addAll(messages.map((m) => m.id));
    _loading = false;
  });

  _scrollToBottom();
} catch (_) {
  if (!mounted) return;
  setState(() => _loading = false);
  _showNotice('تعذر تحميل سجل الرسائل.');
}

}

void _listenToBluetooth() {
_subscription = _bluetooth.events.listen(
_handleBluetoothEvent,
onError: (Object error) {
if (!mounted) return;
setState(() {
_connectionStatus = 'خطأ في أحداث البلوتوث';
});
},
);
}

void _handleBluetoothEvent(BlousabEvent event) {
if (!mounted) return;
if (event.type == 'lanStarted' || event.type == 'peerDiscovered') { _retryPendingOutbox(); _retryRelayQueue(); return; }

switch (event.type) {
  case 'connected':
    setState(() {
      _selectedAddress = event.address ?? _selectedAddress;
      _connectionStatus =
          'متصل: ${event.name ?? 'جهاز'}';
    });
    if (event.address != null) { SharedPreferences.getInstance().then((p) => p.setString('blousab_last_device_${widget.conversationId}', event.address!)); }
    _showNotice('تم الاتصال بجهاز ${event.name ?? ''}');
    _retryPendingOutbox();
    _retryRelayQueue();
    break;

  case 'disconnected':
    if (_selectedAddress == event.address) {
      setState(() {
        _selectedAddress = null;
        _connectionStatus = 'انقطع الاتصال';
      });
    }
    break;

  case 'message':
    final raw = event.message;
    if (raw != null) {
      _handleIncomingMessage(raw, event.address);
    }
    break;

  case 'connectionError':
  case 'serverError':
    setState(() => _connectionStatus = 'حدث خطأ في الاتصال');
    _showNotice(event.message ?? 'تعذر الاتصال بالبلوتوث.');
    break;

  case 'serverStarted':
    setState(() {
      _connectionStatus = 'جاهز لاستقبال الاتصالات';
    });
    _retryPendingOutbox();
    _retryRelayQueue();
    break;

  case 'serverStopped':
    setState(() {
      _connectionStatus = 'الاستقبال متوقف';
    });
    break;
}

}

Future<void> _sendControlAck(String messageId, String conversationId, String? address, String recipientId, {String type = 'delivery_ack'}) async {
  if (address == null || address.isEmpty) return;
  final ack = jsonEncode({
    'type': type, 'ackFor': messageId,
    'conversationId': conversationId, 'senderId': widget.currentUserId,
    'recipientId': recipientId, 'senderName': widget.currentUserName,
    'sentAt': DateTime.now().toIso8601String(),
  });
  try {
    if (address.startsWith('lan:')) {
      await LocalNetworkService.instance.sendControlPacket(address: address, payload: ack);
    } else {
      await _bluetooth.sendMessage(address: address, message: ack);
    }
  } catch (_) { /* A duplicate delivery or reconnect can trigger another ACK. */ }
}


Future<void> _sendReadAck(String messageId, String conversationId, String? address, String recipientId) async {
  if (address == null || address.isEmpty || recipientId.isEmpty) return;
  final ack = jsonEncode({
    'type': 'read_ack', 'ackFor': messageId,
    'conversationId': conversationId, 'senderId': widget.currentUserId,
    'recipientId': recipientId, 'senderName': widget.currentUserName,
    'sentAt': DateTime.now().toIso8601String(),
  });
  try {
    if (address.startsWith('lan:')) {
      await LocalNetworkService.instance.sendControlPacket(address: address, payload: ack);
    } else {
      await _bluetooth.sendMessage(address: address, message: ack);
    }
  } catch (_) {
    // No read status is shown to the sender unless this ACK reaches it.
  }
}

Future<void> _retryPendingOutbox() async {
  if (!mounted) return;
  final entries = await PendingMessageStore.instance.list();
  for (final entry in entries) {
    if (!mounted) return;
    if (entry['conversationId']?.toString() != widget.conversationId) continue;
    final messageId = entry['messageId']?.toString() ?? '';
    final payload = entry['payload']?.toString() ?? '';
    if (messageId.isEmpty || payload.isEmpty) continue;
    final attempts = (entry['attempts'] as num? ?? 0).toInt();
    // Bounded automatic attempts per app launch; the durable entry remains for
    // the next launch/manual retry if no receiver ACK arrives.
    if (attempts >= 12) continue;
    await PendingMessageStore.instance.noteAttempt(messageId);
    try {
      await _transmitWithRetry(
        payload: payload,
        messageId: messageId,
        wifiMode: entry['wifiMode'] == true,
        isCommunity: entry['isCommunity'] == true,
        bluetoothAddress: entry['bluetoothAddress']?.toString(),
        wifiAddress: entry['wifiAddress']?.toString(),
      );
      await PendingMessageStore.instance.remove(messageId);
      await _store.markDelivered(widget.conversationId, messageId);
      if (mounted) {
        final refreshed = await _store.getMessages(widget.conversationId);
        setState(() => _messages = refreshed);
      }
    } catch (_) {
      // Keep it durable. A future app launch or explicit retry can try again.
    }
  }
}

Future<void> _retryRelayQueue() async {
  if (_relayRetryInProgress) return;
  _relayRetryInProgress = true;
  try {
  final rows = await RelayQueueStore.instance.list();
  for (final row in rows) {
    final id = row['id']?.toString() ?? '';
    final payload = row['payload']?.toString() ?? '';
    if (id.isEmpty || payload.isEmpty) continue;
    final attempts = (row['attempts'] as num? ?? 0).toInt();
    if (attempts >= 30) continue;
    // Exponential backoff prevents repeated storms and excess battery drain.
    final last = DateTime.tryParse(row['lastAttemptAt']?.toString() ?? '');
    final delaySeconds = (1 << (attempts > 6 ? 6 : attempts)) * 5;
    if (last != null && DateTime.now().difference(last) < Duration(seconds: delaySeconds)) continue;
    await RelayQueueStore.instance.noteAttempt(id);
    try {
      // Use best currently known next-hop first for private recipients.
      // If no delivery ACK follows, bounded flood remains the fallback.
      final forwarded = jsonDecode(payload);
      if (forwarded is Map) {
        final recipient = forwarded['recipientId']?.toString() ?? '';
        if (recipient.isNotEmpty && recipient != '*' && attempts < 2) {
          final rawPath = forwarded['relayPath'];
          final excluded = rawPath is List ? rawPath.map((e) => e.toString()).toSet() : <String>{};
          if (await LocalNetworkService.instance.trySendViaBestKnownRoute(
            recipientId: recipient, payload: payload, excludedIds: excluded)) {
            continue; // Socket write is not final delivery confirmation.
          }
        }
      }
      // Flood to currently reachable peers; durable ID dedupe and hop/age bounds
      // stop repeated loops. A relay write is NOT a recipient delivery ACK.
      var sent = false;
      try { if (LocalNetworkService.instance.isRunning && LocalNetworkService.instance.peerCount > 0) { await LocalNetworkService.instance.broadcastMessage(payload); sent = true; } } catch (_) {}
      try { await _bluetooth.broadcastMessage(payload); sent = true; } catch (_) {}
      if (!sent) continue;
    } catch (_) { /* Keep queued for a later peer/connectivity event. */ }
  }
  } finally { _relayRetryInProgress = false; }
}

Future<bool> _queueAndRelayIfNeeded(Map<dynamic, dynamic> decoded, String raw) async {
  final relay = decoded['relayEnabled'] == true || decoded['relay'] == true;
  if (!relay) return false;
  final id = decoded['id']?.toString() ?? decoded['messageId']?.toString() ?? '';
  final senderId = decoded['senderId']?.toString() ?? '';
  final recipientId = decoded['recipientId']?.toString() ?? '*';
  if (id.isEmpty || id.length > 160 || senderId.isEmpty || senderId.length > 256 ||
      senderId == widget.currentUserId || recipientId.isEmpty || recipientId.length > 256 ||
      utf8.encode(raw).length > RelayPolicy.maxPacketBytes) return false;
  final created = DateTime.tryParse(decoded['sentAt']?.toString() ?? decoded['createdAt']?.toString() ?? '');
  if (created == null || DateTime.now().difference(created) > RelayQueueStore.maxAge || created.isAfter(DateTime.now().add(const Duration(minutes: 5)))) return false;
  final hops = int.tryParse('${decoded['hopCount'] ?? decoded['hops'] ?? 0}') ?? 0;
  if (hops < 0 || hops >= 5) return false;
  if (decoded['relayPath'] != null && decoded['relayPath'] is! List) return false;
  final path = decoded['relayPath'] is List ? List<String>.from((decoded['relayPath'] as List).map((e)=>e.toString())) : <String>[];
  if (path.length > RelayPolicy.maxPathLength || path.toSet().length != path.length ||
      path.any((entry) => entry.isEmpty || entry.length > 256) ||
      path.contains(widget.currentUserId)) return false;
  final firstSeen = await RelayQueueStore.instance.markSeen(id);
  if (!firstSeen) return false;
  // The final recipient (or group recipient marker) processes the packet normally.
  if (recipientId == widget.currentUserId || recipientId == '*') {
    // Group packets are still relayed after local processing; the caller does not return early.
    if (recipientId == widget.currentUserId) return false;
  }
  final forwarded = Map<String,dynamic>.from(decoded.map((k,v)=>MapEntry(k.toString(),v)));
  forwarded['relayEnabled'] = true;
  forwarded['hopCount'] = hops + 1;
  forwarded['hops'] = hops + 1;
  forwarded['relayPath'] = [...path, widget.currentUserId];
  await RelayQueueStore.instance.enqueue(forwarded);
  // Try immediately; queue remains until TTL/limit so an intermediary never
  // mistakes a successful socket write for final recipient delivery.
  await _retryRelayQueue();
  return recipientId != '*' && recipientId != widget.currentUserId;
}

Future<void> _transmitWithRetry({
  required String payload,
  required String messageId,
  required bool wifiMode,
  required bool isCommunity,
  required String? bluetoothAddress,
  required String? wifiAddress,
}) async {
  final completer = Completer<void>();
  _pendingAcks[messageId] = completer;
  Object? lastError;
  var transportWriteSucceeded = false;
  try {
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        if (wifiMode) {
          if (isCommunity) {
            await LocalNetworkService.instance.broadcastMessage(payload);
            transportWriteSucceeded = true;
          } else {
            await LocalNetworkService.instance.sendMessageToPeer(address: wifiAddress!, payload: payload);
            transportWriteSucceeded = true;
          }
        } else if (isCommunity) {
          await _bluetooth.sendMessage(address: '*', message: payload);
            transportWriteSucceeded = true;
        } else {
          await _bluetooth.sendMessage(address: bluetoothAddress!, message: payload);
            transportWriteSucceeded = true;
        }
        await _store.markSent(widget.conversationId, messageId);
        if (mounted) {
          final refreshed = await _store.getMessages(widget.conversationId);
          setState(() => _messages = refreshed);
        }
      } catch (e) {
        lastError = e;
      }
      if (transportWriteSucceeded) await _store.markSent(widget.conversationId, messageId);
      // If a second path is configured, send the exact same message ID over it.
      // Receiver-side deduplication makes this safe when both paths arrive.
      try {
        if (wifiMode) {
          if (isCommunity) {
            await _bluetooth.broadcastMessage(payload);
            transportWriteSucceeded = true;
          } else if (bluetoothAddress != null && bluetoothAddress.isNotEmpty) {
            await _bluetooth.sendMessage(address: bluetoothAddress, message: payload);
            transportWriteSucceeded = true;
          }
        } else {
          if (isCommunity) {
            await LocalNetworkService.instance.broadcastMessage(payload);
          } else if (wifiAddress != null && wifiAddress.isNotEmpty) {
            await LocalNetworkService.instance.sendMessageToPeer(address: wifiAddress, payload: payload);
            transportWriteSucceeded = true;
          }
        }
      } catch (e) {
        lastError = e;
      }
      if (transportWriteSucceeded) await _store.markSent(widget.conversationId, messageId);
      try {
        await completer.future.timeout(const Duration(seconds: 4));
        return;
      } on TimeoutException {
        lastError ??= TimeoutException('لم يصل تأكيد استلام');
      }
    }
    throw StateError('لم يصل تأكيد استلام بعد 3 محاولات. آخر خطأ: $lastError');
  } finally {
    _pendingAcks.remove(messageId);
  }
}

Future<void> _handleIncomingMessage(
String raw,
String? address,
) async {
try {
final dynamic decoded = jsonDecode(raw);

  if (decoded is! Map) return;
  final incomingType = decoded['type']?.toString() ?? '';
  final shouldStopForRelay = await _queueAndRelayIfNeeded(decoded, raw);
  if (shouldStopForRelay) return;
  if (incomingType == 'delivery_ack' || incomingType == 'read_ack') {
    final ackFor = decoded['ackFor']?.toString() ?? '';
    if (incomingType == 'delivery_ack' && ackFor.isNotEmpty) { await RelayQueueStore.instance.remove(ackFor); }
    final recipientId = decoded['recipientId']?.toString() ?? '';
    final ackSender = decoded['senderId']?.toString() ?? '';
    final ackConversation = decoded['conversationId']?.toString() ?? '';
    final storedMessages = await _store.getMessages(widget.conversationId);
    final original = storedMessages.where((m) => m.id == ackFor && m.isMine && m.conversationId == widget.conversationId).toList();
    if (ackFor.isNotEmpty && recipientId == widget.currentUserId && ackConversation == widget.conversationId && ackSender.isNotEmpty && ackSender != widget.currentUserId && original.isNotEmpty) {
      if (incomingType == 'delivery_ack') {
        final pending = _pendingAcks[ackFor];
        if (pending != null && !pending.isCompleted) pending.complete();
        await _store.markDelivered(widget.conversationId, ackFor);
        await PendingMessageStore.instance.remove(ackFor);
      } else {
        await _store.markRead(widget.conversationId, ackFor);
      }
      if (mounted) {
        final refreshed = await _store.getMessages(widget.conversationId);
        setState(() => _messages = refreshed);
      }
    }
    return;
  }
  await _cachePeerProfile(decoded);
  if (incomingType == 'profile_card' || incomingType == 'profile_update' || incomingType == 'hello' || incomingType == 'hello_ack') return;

  final senderId = decoded['senderId']?.toString() ?? '';
  final senderName =
      decoded['senderName']?.toString() ?? 'مستخدم';
  final earlyMessageId = decoded['id']?.toString() ?? '';
  final earlyConversation = decoded['conversationId']?.toString() ?? '';
  if (earlyMessageId.isNotEmpty && _receivedIds.contains(earlyMessageId)) {
    await _sendControlAck(earlyMessageId, earlyConversation, address, senderId);
    await _sendControlAck(earlyMessageId, earlyConversation, address, senderId, type: 'read_ack');
    return;
  }
  final packetType = decoded['type']?.toString() ?? 'text';
  String text = decoded['text']?.toString() ?? '';
  String? attachmentPath;
  String? attachmentName;
  if (packetType == 'file') {
    attachmentName = decoded['fileName']?.toString() ?? 'ملف مستلم';
    final encoded = decoded['data']?.toString() ?? '';
    if (encoded.isEmpty || encoded.length > 6000000) return;
    final bytes = base64Decode(encoded);
    final dir = await getApplicationDocumentsDirectory();
    final safeName = attachmentName.replaceAll(RegExp(r'[^\w.\- ()\u0600-\u06FF]'), '_');
    final file = File('${dir.path}/received_${DateTime.now().millisecondsSinceEpoch}_$safeName');
    await file.writeAsBytes(bytes, flush: true);
    attachmentPath = file.path;
    text = '📎 $attachmentName';
  }
  final messageId = decoded['id']?.toString() ??
      '${DateTime.now().microsecondsSinceEpoch}_$senderId';

  final incomingConversation =
      decoded['conversationId']?.toString() ?? '';

  if ((text.trim().isEmpty && packetType != 'file') ||
      senderId.isEmpty ||
      senderId == widget.currentUserId) {
    return;
  }

  // تجاهل رسائل جهة الاتصال المحظورة على هذا الجهاز.
  final prefsForBlock = await SharedPreferences.getInstance();
  if (prefsForBlock.getBool('blousab_blocked_peer_$senderId') ?? false) return;

  // لا تعرض رسائل محادثة مختلفة في هذه المحادثة.
  if (incomingConversation.isNotEmpty &&
      incomingConversation != widget.conversationId) {
    return;
  }

  final localCommunity = await _communityStore.findById(widget.conversationId);
  if (localCommunity != null) {
    final sender = localCommunity.members.where((member) => member.id == senderId).toList();
    if (sender.isEmpty || sender.first.status.name != 'approved') return;
  }

  if (_receivedIds.contains(messageId)) { await _sendControlAck(messageId, widget.conversationId, address, senderId); await _sendControlAck(messageId, widget.conversationId, address, senderId, type: 'read_ack'); return; }

  final message = BlousabMessage(
    id: messageId,
    conversationId: widget.conversationId,
    senderId: senderId,
    senderName: senderName,
    text: text,
    sentAt: DateTime.tryParse(
          decoded['sentAt']?.toString() ?? '',
        )?.toLocal() ??
        DateTime.now(),
    isMine: false,
    attachmentPath: attachmentPath,
    attachmentName: attachmentName,
  );

  _receivedIds.add(messageId);

  await _store.saveMessage(message);
  await _sendControlAck(message.id, message.conversationId, address, senderId);
  await _sendControlAck(message.id, message.conversationId, address, senderId, type: 'read_ack');

  if (!mounted) return;

  setState(() {
    if (!_messages.any((item) => item.id == message.id)) _messages.add(message);
    _selectedAddress ??= address;
  });

  _scrollToBottom();
} catch (_) {
  _showNotice('تعذر قراءة الرسالة المستلمة.');
}

}

Future<void> _prepareBluetooth() async {
  // لا نعرض نتائج فحص Bluetooth العامة؛ فهي لا تثبت أن الجهاز يشغّل بلوساب.
  // نافذة البحث المعتمدة تعرض فقط إعلانات خدمة بلوساب عبر Wi-Fi Aware
  // أو رسائل اكتشاف LAN التي يصدرها تطبيق بلوساب نفسه.
  await _changeConnectionFlow();
}

Future<void> _showDevicePicker() async {
if (!mounted) return;

final device = await showModalBottomSheet<BlousabDevice>(
  context: context,
  builder: (sheetContext) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: _devices.isEmpty
            ? const Text(
                'لم يُعثر على أجهزة Bluetooth قريبة.\n'
                'تنبيه: هذه القائمة تعرض أجهزة بلوتوث عامة، ولا تثبت أن أصحابها يستخدمون بلوساب. استخدم بحث مستخدمي بلوساب عبر Wi-Fi للشبكة المحلية.',
                textAlign: TextAlign.center,
              )
            : ListView(
                shrinkWrap: true,
                children: [
                  const Text(
                    'أجهزة Bluetooth القريبة (غير مؤكدة)',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ..._devices.map(
                    (d) => ListTile(
                      leading: const Icon(Icons.bluetooth),
                      title: Text(d.name),
                      subtitle: const Text('جهاز Bluetooth — هوية بلوساب غير متحققة'),
                      onTap: () =>
                          Navigator.pop(sheetContext, d),
                    ),
                  ),
                ],
              ),
      ),
    );
  },
);

if (device == null || !mounted) return;

setState(() {
  _selectedAddress = device.address;
  _connectionStatus = 'جارٍ الاتصال بـ ${device.name}...';
});
final prefs = await SharedPreferences.getInstance();
await prefs.setString('blousab_last_device_${widget.conversationId}', device.address);

try {
  await _bluetooth.connect(device.address);
} on PlatformException catch (e) {
  if (mounted) {
    setState(() => _connectionStatus = 'فشل الاتصال');
  }
  _showNotice(e.message ?? 'تعذر الاتصال بالجهاز.');
} catch (_) {
  _showNotice('تعذر الاتصال بالجهاز.');
}

}

Future<void> _startListening() async {
if (_working) return;

setState(() => _working = true);

try {
  final supported = await _bluetooth.isSupported();

  if (!supported) {
    _showNotice('هذا الهاتف لا يدعم البلوتوث.');
    return;
  }

  final granted = await _bluetooth.requestPermissions();

  if (!granted) {
    _showNotice('امنح صلاحيات البلوتوث للتطبيق.');
    return;
  }

  if (!await _bluetooth.isEnabled()) {
    await _bluetooth.requestEnable();
    _showNotice('فعّل البلوتوث ثم حاول تشغيل الاستقبال.');
    return;
  }

  await _bluetooth.startServer();

  if (mounted) {
    setState(() {
      _connectionStatus = 'جارٍ تشغيل استقبال الرسائل...';
    });
  }
} on PlatformException catch (e) {
  _showNotice(e.message ?? 'تعذر تشغيل استقبال الرسائل.');
} catch (_) {
  _showNotice('حدث خطأ أثناء تشغيل الاستقبال.');
} finally {
  if (mounted) setState(() => _working = false);
}

}

Future<bool> _maySendToCurrentConversation() async {
  final community = await _communityStore.findById(widget.conversationId);
  if (community == null) return true;
  final member = community.members.where((item) => item.id == widget.currentUserId).toList();
  return member.isNotEmpty && member.first.status.name == 'approved';
}

Future<void> _broadcastGroupPayload(String payload) async {
  var sent = false;
  try {
    await _bluetooth.broadcastMessage(payload);
    sent = true;
  } catch (_) {}
  try {
    await LocalNetworkService.instance.broadcastMessage(payload);
    sent = true;
  } catch (_) {}
  if (!sent) {
    throw PlatformException(
      code: 'BROADCAST_FAILED',
      message: 'لا توجد أجهزة متصلة عبر البلوتوث أو الشبكة المحلية.',
    );
  }
}

Future<void> _sendMessage() async {
final text = _textController.text.trim();

if (text.isEmpty || _sending) return;
if (!await _maySendToCurrentConversation()) {
  _showNotice('لا يمكنك الإرسال لأن عضويتك غير مقبولة أو محظورة.');
  return;
}

final isCommunity = await _communityStore.findById(widget.conversationId) != null;
final prefs = await SharedPreferences.getInstance();
final wifiMode = prefs.getString('blousab_connection_mode') == 'wifi';
final address = _selectedAddress;
final wifiAddress = _selectedWifiAddress;

if (!isCommunity && wifiMode && (wifiAddress == null || wifiAddress.isEmpty)) {
  _showNotice('اختر جهازًا من قائمة أجهزة Wi-Fi أولًا.');
  return;
}
if (!isCommunity && !wifiMode && (address == null || address.isEmpty)) {
  _showNotice('اتصل بهاتف مقترن أولًا لإرسال الرسائل.');
  return;
}

setState(() => _sending = true);

final message = BlousabMessage(
  id: '${DateTime.now().microsecondsSinceEpoch}_${widget.currentUserId}',
  conversationId: widget.conversationId,
  senderId: widget.currentUserId,
  senderName: widget.currentUserName,
  text: text,
  sentAt: DateTime.now(),
  isMine: true,
  deliveryStatus: 'pending',
);

try {
  final senderPhoto = await _profilePhotoPayload();
  final payload = jsonEncode({
    'type': 'chat',
    'hops': 0,
    'hopCount': 0,
    'relay': true,
    'relayEnabled': isCommunity || _peerIdFromConversation() != null,
    'relayPath': <String>[],
    'recipientId': isCommunity ? '*' : (_peerIdFromConversation() ?? ''),
    'id': message.id,
    'conversationId': message.conversationId,
    'senderId': message.senderId,
    'senderName': message.senderName,
    if (senderPhoto != null) 'senderPhoto': senderPhoto,
    'text': message.text,
    'sentAt': message.sentAt.toIso8601String(),
    'createdAt': message.sentAt.toIso8601String(),
  });

  await _store.saveMessage(message);
  await PendingMessageStore.instance.enqueue({
    'messageId': message.id, 'conversationId': message.conversationId,
    'payload': payload, 'wifiMode': wifiMode, 'isCommunity': isCommunity,
    'bluetoothAddress': address, 'wifiAddress': wifiAddress,
  });
  await _transmitWithRetry(payload: payload, messageId: message.id,
    wifiMode: wifiMode, isCommunity: isCommunity,
    bluetoothAddress: address, wifiAddress: wifiAddress);

  if (widget.onSendMessage != null) {
    await widget.onSendMessage!(message);
  }

  if (!mounted) return;

  _receivedIds.add(message.id);
  final refreshedMessages = await _store.getMessages(widget.conversationId);
  setState(() { _messages = refreshedMessages; _textController.clear(); });

  _scrollToBottom();
  if (_vibrateOnSend) HapticFeedback.lightImpact();
} on PlatformException catch (e) {
  if (mounted) { final refreshed = await _store.getMessages(widget.conversationId); setState(() { _messages = refreshed; _textController.clear(); }); }
  _showNotice(e.message ?? 'حُفظت الرسالة محليًا لكن لم يتأكد استلامها.');
} catch (e) {
  if (mounted) { final refreshed = await _store.getMessages(widget.conversationId); setState(() { _messages = refreshed; _textController.clear(); }); }
  _showNotice('حُفظت الرسالة محليًا، لكن لم يصل تأكيد الاستلام. $e');
} finally {
  if (mounted) setState(() => _sending = false);
}

}

Future<void> _sendFile() async {
  if (_sending) return;
  if (!await _maySendToCurrentConversation()) {
    _showNotice('لا يمكنك إرسال الملفات لأن عضويتك غير مقبولة أو محظورة.');
    return;
  }
  final isCommunity = await _communityStore.findById(widget.conversationId) != null;
  final prefs = await SharedPreferences.getInstance();
  final wifiMode = prefs.getString('blousab_connection_mode') == 'wifi';
  final address = _selectedAddress;
  final wifiAddress = _selectedWifiAddress;
  if (!isCommunity && wifiMode && (wifiAddress == null || wifiAddress.isEmpty)) {
    _showNotice('اختر جهازًا من قائمة أجهزة Wi-Fi أولًا لإرسال الملف.');
    return;
  }
  if (!isCommunity && !wifiMode && (address == null || address.isEmpty)) {
    _showNotice('اتصل بجهاز مقترن أولًا لإرسال ملف.');
    return;
  }
  try {
    final result = await FilePicker.platform.pickFiles(withData: true, allowMultiple: false);
    if (result == null || result.files.isEmpty) return;
    final picked = result.files.single;
    final bytes = picked.bytes ?? (picked.path != null ? await File(picked.path!).readAsBytes() : null);
    if (bytes == null || bytes.isEmpty) {
      _showNotice('تعذر قراءة الملف المحدد.');
      return;
    }
    if (bytes.length > 4 * 1024 * 1024) {
      _showNotice('حجم الملف أكبر من 4 ميغابايت. اختر ملفًا أصغر لضمان نقله عبر البلوتوث.');
      return;
    }
    setState(() => _sending = true);
    final id = '${DateTime.now().microsecondsSinceEpoch}_${widget.currentUserId}';
    final dir = await getApplicationDocumentsDirectory();
    final safeName = picked.name.replaceAll(RegExp(r'[^\w.\- ()\u0600-\u06FF]'), '_');
    final localFile = File('${dir.path}/sent_${DateTime.now().millisecondsSinceEpoch}_$safeName');
    await localFile.writeAsBytes(bytes, flush: true);
    final message = BlousabMessage(
      id: id,
      conversationId: widget.conversationId,
      senderId: widget.currentUserId,
      senderName: widget.currentUserName,
      text: '📎 ${picked.name}',
      sentAt: DateTime.now(),
      isMine: true,
      deliveryStatus: 'pending',
      attachmentPath: localFile.path,
      attachmentName: picked.name,
    );
    final senderPhoto = await _profilePhotoPayload();
    final payload = jsonEncode({
      'type': 'file', 'hops': 0, 'relay': isCommunity,
      'id': id, 'conversationId': message.conversationId,
      'senderId': message.senderId, 'senderName': message.senderName,
      if (senderPhoto != null) 'senderPhoto': senderPhoto,
      'sentAt': message.sentAt.toIso8601String(), 'fileName': picked.name,
      'data': base64Encode(bytes),
    });
    await _store.saveMessage(message);
    await PendingMessageStore.instance.enqueue({
      'messageId': id, 'conversationId': message.conversationId,
      'payload': payload, 'wifiMode': wifiMode, 'isCommunity': isCommunity,
      'bluetoothAddress': address, 'wifiAddress': wifiAddress,
    });
    await _transmitWithRetry(payload: payload, messageId: id,
      wifiMode: wifiMode, isCommunity: isCommunity,
      bluetoothAddress: address, wifiAddress: wifiAddress);
    await PendingMessageStore.instance.remove(id);
    if (!mounted) return;
    _receivedIds.add(id);
    final refreshedMessages = await _store.getMessages(widget.conversationId);
    setState(() => _messages = refreshedMessages);
    _scrollToBottom();
    _showNotice('تم إرسال الملف عبر البلوتوث.');
  } on PlatformException catch (e) {
    _showNotice(e.message ?? 'تعذر إرسال الملف.');
  } catch (e) {
    _showNotice('تعذر إرسال الملف: $e');
  } finally {
    if (mounted) setState(() => _sending = false);
  }
}

Future<void> _openAttachment(BlousabMessage message) async {
  final path = message.attachmentPath;
  if (path == null || !File(path).existsSync()) {
    _showNotice('الملف غير موجود على هذا الجهاز.');
    return;
  }
  final result = await OpenFilex.open(path);
  if (result.type != ResultType.done) _showNotice('تعذر فتح الملف: ${result.message}');
}

void _scrollToBottom() {
WidgetsBinding.instance.addPostFrameCallback((_) {
  if (!_scrollController.hasClients) return;

  _scrollController.animateTo(
    _scrollController.position.maxScrollExtent,
    duration: const Duration(milliseconds: 250),
    curve: Curves.easeOut,
  );
});

}

void _showNotice(String text) {
if (!mounted) return;

ScaffoldMessenger.of(context)
  ..hideCurrentSnackBar()
  ..showSnackBar(SnackBar(content: Text(text)));

}

@override
void dispose() {
if (NotificationService.activeConversationId == widget.conversationId) {
  NotificationService.activeConversationId = null;
}
_subscription?.cancel();
_lanSubscription?.cancel();
_awareProfileSubscription?.cancel();
_relayRetryTimer?.cancel();
_textController.dispose();
_scrollController.dispose();
super.dispose();
}

String _clock12(DateTime time) {
  final t = time.toLocal();
  final h12 = t.hour % 12 == 0 ? 12 : t.hour % 12;
  return '${h12.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')} ${t.hour >= 12 ? 'م' : 'ص'}';
}

Widget _statusTicks(BlousabMessage message) {
  if (message.isRead) return const Icon(Icons.done_all_rounded, size: 19, color: Color(0xFF3FD0FF));
  if (message.isDelivered) return const Icon(Icons.done_all_rounded, size: 19, color: Color(0xFF9FB4E8));
  if (message.isSent) return const Icon(Icons.done_rounded, size: 19, color: Color(0xFF9FB4E8));
  return const Icon(Icons.schedule_rounded, size: 16, color: Color(0xFF9FB4E8));
}

Future<void> _pickEmoji() async {
  const emojis = ['😀', '😁', '😂', '🤣', '😊', '😍', '🥰', '😘', '😎', '🤔', '😢', '😭', '😡', '👍', '👌', '🙏', '👋', '❤️', '💙', '🔥', '🎉', '✨', '🌹', '☕'];
  final chosen = await showModalBottomSheet<String>(
    context: context,
    builder: (ctx) => SafeArea(child: Padding(
      padding: const EdgeInsets.all(16),
      child: Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.center, children: emojis.map((e) => GestureDetector(
        onTap: () => Navigator.pop(ctx, e),
        child: Container(width: 48, height: 48, alignment: Alignment.center, child: Text(e, style: const TextStyle(fontSize: 28))),
      )).toList()),
    )),
  );
  if (chosen == null) return;
  final value = _textController.value;
  final sel = value.selection;
  final start = sel.isValid ? sel.start : value.text.length;
  final end = sel.isValid ? sel.end : value.text.length;
  final text = value.text.replaceRange(start, end, chosen);
  _textController.value = TextEditingValue(text: text, selection: TextSelection.collapsed(offset: start + chosen.length));
}

Widget _buildChatHeader(BuildContext context) {
  final name = _peerDisplayName.isNotEmpty ? _peerDisplayName : widget.title;
  final online = _connectionStatus.contains('متصل') && !_connectionStatus.contains('غير');
  return Container(
    decoration: BoxDecoration(
      gradient: const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF060C24), Color(0xFF0A1236)]),
      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(26)),
      border: const Border(bottom: BorderSide(color: Color(0xFF4F63FF), width: 1.6)),
      boxShadow: const [BoxShadow(color: Color(0x884F63FF), blurRadius: 14), BoxShadow(color: Color(0x44B238FF), blurRadius: 18)],
    ),
    child: SafeArea(
      bottom: false,
      child: SizedBox(
        height: 74,
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Row(children: [
            const SizedBox(width: 6),
            IconButton(
              tooltip: 'العودة',
              icon: const Icon(Icons.arrow_back_rounded, color: Colors.white, size: 30),
              onPressed: () => Navigator.maybePop(context),
            ),
            BlousabRingAvatar(name: name, photoPath: _peerProfilePhotoPath, size: 56, ring: 2.5, online: online),
            const SizedBox(width: 12),
            Expanded(child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name, textDirection: TextDirection.rtl, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
              Text(_connectionStatus, textDirection: TextDirection.rtl, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Color(0xFFC6D0F2), fontSize: 14)),
            ])),
            IconButton(
              tooltip: 'مكالمة صوتية',
              onPressed: () => _showNotice('المكالمات الصوتية تحتاج إلى تنفيذ قناة صوت واختبارها بين هاتفين. الزر لا يبدأ مكالمة حية في هذه النسخة.'),
              icon: const Icon(Icons.call_rounded, color: Color(0xFFD5DEFF), size: 28),
            ),
            IconButton(
              tooltip: 'مكالمة فيديو',
              onPressed: () => _showNotice('مكالمات الفيديو تحتاج إلى تنفيذ قناة صوت وصورة واختبارها بين هاتفين. الزر لا يبدأ بثًا حيًا في هذه النسخة.'),
              icon: const Icon(Icons.videocam_rounded, color: Color(0xFFD5DEFF), size: 32),
            ),
            PopupMenuButton<String>(
              tooltip: 'خيارات المحادثة',
              icon: const Icon(Icons.more_vert_rounded, color: Color(0xFFD5DEFF), size: 28),
              onSelected: (value) {
                if (value == 'settings') _openConversationSettings();
                if (value == 'listen' && !_working) _startListening();
                if (value == 'connect' && !_working) _prepareBluetooth();
              },
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'settings', child: Text('إعدادات المحادثة')),
                const PopupMenuItem(value: 'listen', child: Text('تشغيل استقبال الرسائل')),
                const PopupMenuItem(value: 'connect', child: Text('الاتصال بجهاز قريب')),
              ],
            ),
            const SizedBox(width: 2),
          ]),
        ),
      ),
    ),
  );
}

Widget _buildMessageBubble(BuildContext context, BlousabMessage message) {
  final mine = message.isMine;
  final name = message.senderName.isNotEmpty ? message.senderName : (_peerDisplayName.isNotEmpty ? _peerDisplayName : widget.title);
  final isImage = message.attachmentPath != null &&
      RegExp(r'.*\.(png|jpe?g|gif|webp|bmp)$', caseSensitive: false).hasMatch(message.attachmentName ?? '');
  final timeText = _clock12(message.sentAt);
  final maxWidth = MediaQuery.of(context).size.width * 0.74;

  Widget timeBlock({bool overlay = false}) => Row(mainAxisSize: MainAxisSize.min, children: [
    if (_showMessageTime) Text(timeText, textDirection: TextDirection.rtl, style: const TextStyle(color: Color(0xFFC9D4FF), fontSize: 13.5)),
    if (mine) ...[const SizedBox(width: 4), _statusTicks(message)],
  ]);

  Widget content;
  if (isImage) {
    content = ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: Stack(children: [
        GestureDetector(
          onTap: () => _openAttachment(message),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: BlousabKeepColors(child: Image.file(File(message.attachmentPath!), width: maxWidth, fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Padding(padding: const EdgeInsets.all(12), child: Text(message.attachmentName ?? 'صورة', style: const TextStyle(color: Colors.white))))),
          ),
        ),
        Positioned(right: 10, bottom: 8, child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(color: const Color(0x66000000), borderRadius: BorderRadius.circular(10)),
          child: timeBlock(overlay: true),
        )),
      ]),
    );
  } else {
    Widget body;
    if (message.attachmentPath != null) {
      body = InkWell(
        onTap: () => _openAttachment(message),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.attach_file, color: Colors.white),
          const SizedBox(width: 6),
          Flexible(child: Text(message.attachmentName ?? message.text, style: TextStyle(color: Colors.white, fontSize: _messageFontSize))),
          const SizedBox(width: 6),
          const Icon(Icons.open_in_new, size: 16, color: Colors.white),
        ]),
      );
    } else {
      body = Text(message.text, style: TextStyle(color: Colors.white, fontSize: _messageFontSize + 1.5, height: 1.4));
    }
    content = ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          if (!mine && _isCommunityConversation)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(message.senderName, style: const TextStyle(color: Color(0xFF3FD0FF), fontWeight: FontWeight.w800, fontSize: 12)),
            ),
          Row(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end, children: [
            Flexible(child: body),
            const SizedBox(width: 16),
            timeBlock(),
          ]),
        ]),
      ),
    );
  }

  final bubbleDecoration = isImage
      ? BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: const Color(0xFF3F9BFF), width: 2),
          boxShadow: const [BoxShadow(color: Color(0x883F9BFF), blurRadius: 12), BoxShadow(color: Color(0x44B238FF), blurRadius: 14)],
        )
      : mine
          ? BoxDecoration(
              gradient: const LinearGradient(begin: Alignment.centerRight, end: Alignment.centerLeft, colors: [Color(0xFF1544E6), Color(0xFF2D5BFF), Color(0xFF3F4DFF)]),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: const Color(0xFF4FB0FF), width: 1.4),
              boxShadow: const [BoxShadow(color: Color(0x663F7BFF), blurRadius: 10)],
            )
          : BoxDecoration(
              color: const Color(0xFF111A3C),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(22), topRight: Radius.circular(22),
                bottomRight: Radius.circular(22), bottomLeft: Radius.circular(5)),
              border: Border.all(color: const Color(0xFF3A4C9A), width: 1.2),
            );

  final bubble = Container(
    padding: isImage ? const EdgeInsets.all(3) : EdgeInsets.symmetric(horizontal: 16, vertical: _compactBubbles ? 8 : 13),
    decoration: bubbleDecoration,
    child: content,
  );

  return Padding(
    padding: EdgeInsets.symmetric(vertical: _compactBubbles ? 4 : 7),
    child: Directionality(
      textDirection: TextDirection.ltr,
      child: mine
          ? Row(mainAxisAlignment: MainAxisAlignment.end, crossAxisAlignment: CrossAxisAlignment.end, children: [
              if (isImage) Padding(
                padding: const EdgeInsets.only(right: 12),
                child: GestureDetector(
                  onTap: () => _openAttachment(message),
                  child: Container(width: 44, height: 44,
                    decoration: BoxDecoration(color: const Color(0xFF0B1230), shape: BoxShape.circle, border: Border.all(color: const Color(0xFF2B3A80))),
                    child: const Icon(Icons.reply_rounded, color: Colors.white, size: 26)),
                ),
              ),
              Flexible(child: bubble),
            ])
          : Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              BlousabRingAvatar(name: name, photoPath: _peerProfilePhotoPath, size: 42, ring: 2),
              const SizedBox(width: 8),
              Flexible(child: bubble),
              const SizedBox(width: 40),
            ]),
    ),
  );
}

Widget _buildChatInput(BuildContext context) {
  return SafeArea(
    top: false,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(6, 6, 6, 8),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Expanded(child: Container(
            constraints: const BoxConstraints(minHeight: 56),
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(30),
              color: const Color(0xFF070E28),
              border: Border.all(color: const Color(0xFF5A63FF), width: 1.6),
              boxShadow: const [BoxShadow(color: Color(0x885A63FF), blurRadius: 12), BoxShadow(color: Color(0x44B238FF), blurRadius: 14)],
            ),
            child: Row(children: [
              IconButton(
                tooltip: 'الرموز التعبيرية',
                onPressed: _pickEmoji,
                icon: const Icon(Icons.sentiment_satisfied_alt_rounded, color: Color(0xFF8FB2FF), size: 30),
              ),
              Expanded(child: TextField(
                controller: _textController,
                minLines: 1,
                maxLines: 5,
                textDirection: TextDirection.rtl,
                textAlign: TextAlign.right,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _sendMessage(),
                style: const TextStyle(color: Colors.white, fontSize: 17),
                decoration: const InputDecoration(
                  hintText: 'اكتب رسالتك...',
                  hintStyle: TextStyle(color: Color(0xFFB4C3F0), fontSize: 18),
                  filled: false,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 14),
                ),
              )),
              IconButton(
                tooltip: 'إرسال ملف أو صورة',
                onPressed: _sending ? null : _sendFile,
                icon: const Icon(Icons.attach_file_rounded, color: Color(0xFF8FB2FF), size: 30),
              ),
              IconButton(
                tooltip: 'إرسال صورة',
                onPressed: _sending ? null : _sendFile,
                icon: const Icon(Icons.photo_camera_outlined, color: Color(0xFF8FB2FF), size: 30),
              ),
            ]),
          )),
          const SizedBox(width: 8),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: _textController,
            builder: (context, value, _) {
              final hasText = value.text.trim().isNotEmpty;
              return GestureDetector(
                onTap: _sending
                    ? null
                    : () {
                        if (hasText) {
                          _sendMessage();
                        } else {
                          _showNotice('الرسائل الصوتية غير متاحة في هذه النسخة.');
                        }
                      },
                child: Container(
                  width: 58, height: 58,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF1FA2FF), Color(0xFF3A6BFF), Color(0xFF9A3BFF)]),
                    boxShadow: [BoxShadow(color: Color(0x993A6BFF), blurRadius: 14)],
                  ),
                  child: _sending
                      ? const Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                      : Icon(hasText ? Icons.send_rounded : Icons.mic_rounded, color: Colors.white, size: 32),
                ),
              );
            },
          ),
        ]),
      ),
    ),
  );
}

@override
Widget build(BuildContext context) {
  final isDarkTheme = Theme.of(context).brightness == Brightness.dark;
  return Scaffold(
    backgroundColor: _chatWallpaper == 'dark' || _chatWallpaper == 'night' ? const Color(0xFF040813) : _chatWallpaper == 'plain' ? (isDarkTheme ? const Color(0xFF050916) : Colors.white) : (isDarkTheme ? const Color(0xFF0A1631) : const Color(0xFFEAF2FF)),
    body: BlousabChatWallpaper(child: Column(children: [
      _buildChatHeader(context),
      Expanded(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _messages.isEmpty
                ? const Center(child: Text('لا توجد رسائل بعد. ابدأ المحادثة.', style: TextStyle(color: Color(0xFFC6D0F2))))
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.fromLTRB(10, 12, 10, 10),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) => _buildMessageBubble(context, _messages[index]),
                  ),
      ),
      _buildChatInput(context),
    ])),
  );
}
}
