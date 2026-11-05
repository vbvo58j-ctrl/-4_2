import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_compress/video_compress.dart';
import 'package:video_player/video_player.dart';

import '../services/local_network_service.dart';
import '../services/bluetooth_classic_service.dart' show BlousabEvent;
import '../widgets/blousab_visuals.dart';

/// Stories expire after 24 hours. Stories and reactions synchronize with peers
/// discovered on the same local Wi-Fi network through Blousab's TCP transport.
// A single network-synchronizing instance owns the LAN listener, while
// feed previews update from the shared local store without broadcasting twice.
final ValueNotifier<int> blousabStoryStoreVersion = ValueNotifier<int>(0);
/// Incremented by the shell header (+) to start creating a story.
final ValueNotifier<int> blousabCreateStoryRequest = ValueNotifier<int>(0);

class StoriesStrip extends StatefulWidget {
  final String userName;
  final String profilePhotoPath;
  final bool networkSync;
  final bool showcase;
  final VoidCallback? onAddPost;
  const StoriesStrip({super.key, required this.userName, required this.profilePhotoPath, this.networkSync = true, this.showcase = false, this.onAddPost});

  @override
  State<StoriesStrip> createState() => _StoriesStripState();
}

class _StoriesStripState extends State<StoriesStrip> {
  static const _storageKey = 'blousab_stories_v1';
  final ImagePicker _picker = ImagePicker();
  List<Map<String, dynamic>> _stories = [];
  bool _busy = false;
  StreamSubscription<BlousabEvent>? _networkSubscription;
  Timer? _storySyncTimer;
  final Set<String> _seenStoryUpdates = <String>{};
  String _myId = 'blousab-user';
  final PageController _pageController = PageController(viewportFraction: .8);
  int _page = 0;
  // المستخدم المحدد في شريط الدوائر. الفارغ = قصصي (تُعرض أولاً عند الدخول).
  String _selectedUserId = '';
  Set<String> _friendIds = <String>{};

  void _onCreateRequest() {
    if (widget.showcase && mounted) _createStory();
  }

  @override
  void initState() {
    super.initState();
    if (widget.showcase) blousabCreateStoryRequest.addListener(_onCreateRequest);
    _loadStories();
    blousabStoryStoreVersion.addListener(_onStoreChanged);
    _initializeStorySync();
  }

  void _onStoreChanged() {
    if (mounted) _loadStories();
  }

  @override
  void dispose() {
    blousabCreateStoryRequest.removeListener(_onCreateRequest);
    _pageController.dispose();
    blousabStoryStoreVersion.removeListener(_onStoreChanged);
    _networkSubscription?.cancel();
    _storySyncTimer?.cancel();
    super.dispose();
  }

  Future<void> _initializeStorySync() async {
    final prefs = await SharedPreferences.getInstance();
    _myId = prefs.getString('wasl_user_id') ?? 'blousab-user';
    if (!widget.networkSync) return;
    _networkSubscription = LocalNetworkService.instance.events.listen((event) {
      if (event.type == 'lanStarted' || event.type == 'peerDiscovered') { _requestStorySync(); }
      _onNetworkEvent(event);
    });
    // Periodic anti-entropy sync recovers stories missed while a peer was offline.
    _storySyncTimer?.cancel();
    _storySyncTimer = Timer.periodic(const Duration(seconds: 30), (_) => _requestStorySync());
    await _requestStorySync();
  }

  Future<void> _requestStorySync() async {
    try {
      if (LocalNetworkService.instance.isRunning) {
        await LocalNetworkService.instance.broadcastMessage(jsonEncode({
          'type': 'story_sync_request', 'requesterId': _myId,
          'createdAt': DateTime.now().millisecondsSinceEpoch,
        }));
      }
    } catch (_) {}
  }

  Future<void> _broadcastStory(Map<String, dynamic> story) async {
    try {
      if (!LocalNetworkService.instance.isRunning) return;
      final outgoing = Map<String, dynamic>.from(story);
      outgoing.remove('path');
      outgoing.remove('profilePhotoPath');
      final media = File(story['path']?.toString() ?? '');
      if (await media.exists()) {
        final bytes = await media.readAsBytes();
        // Avoid oversized packets on mobile LAN; compressed media is sent up to 4 MB.
        if (bytes.length > 4 * 1024 * 1024) {
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('حجم الوسائط أكبر من حد المزامنة المحلي (4 ميغابايت).')));
          return;
        }
        outgoing['mediaBase64'] = base64Encode(bytes);
      } else { return; }
      final profilePath = story['profilePhotoPath']?.toString() ?? '';
      if (profilePath.isNotEmpty) {
        try {
          final photo = File(profilePath);
          if (await photo.exists()) {
            final bytes = await photo.readAsBytes();
            if (bytes.length <= 100 * 1024) outgoing['profilePhotoBase64'] = base64Encode(bytes);
          }
        } catch (_) {}
      }
      await LocalNetworkService.instance.broadcastMessage(jsonEncode({'type': 'story_post', 'story': outgoing}));
    } catch (_) {}
  }

  Future<void> _broadcastStoryUpdate(Map<String, dynamic> story) async {
    try {
      if (!LocalNetworkService.instance.isRunning) return;
      await LocalNetworkService.instance.broadcastMessage(jsonEncode({
        'type': 'story_update', 'storyId': story['id'],
        'updateId': '${_myId}_${DateTime.now().microsecondsSinceEpoch}',
        'senderId': _myId,
        'likes': story['likes'] ?? <String>[],
        'viewers': story['viewers'] ?? <String>[],
        'replies': story['replies'] ?? <Map<String, dynamic>>[],
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
      }));
    } catch (_) {}
  }

  Future<void> _onNetworkEvent(BlousabEvent event) async {
    if (event.type != 'message' || event.message == null) return;
    try {
      final packet = jsonDecode(event.message!);
      if (packet is! Map) return;
      final type = packet['type']?.toString();
      if (type == 'story_delete') {
        final deletedId = packet['storyId']?.toString() ?? '';
        final index = _stories.indexWhere((s) => s['id']?.toString() == deletedId);
        if (index >= 0 && _stories[index]['userId']?.toString() == packet['ownerId']?.toString()) {
          final removed = _stories.removeAt(index);
          try { await File(removed['path'].toString()).delete(); } catch (_) {}
          await _saveStories();
          if (mounted) setState(() {});
        }
        return;
      }
      if (type == 'story_sync_request') {
        // Share all unexpired stories, including stories received from other peers.
        for (final story in List<Map<String, dynamic>>.from(_stories)) {
          await _broadcastStory(story);
        }
        return;
      }
      if (type == 'story_update') {
        final updateId = packet['updateId']?.toString() ?? '';
        if (updateId.isEmpty) return; // Do not relay legacy packets without a deduplication key.
        if (!_seenStoryUpdates.add(updateId)) return;
        final id = packet['storyId']?.toString() ?? '';
        final index = _stories.indexWhere((s) => s['id']?.toString() == id);
        if (index < 0) return;
        final updated = Map<String, dynamic>.from(_stories[index]);
        // Merge rather than replace snapshots so simultaneous likes/replies are not lost.
        final incomingUpdatedAt = (packet['updatedAt'] as num?)?.toInt() ?? 0;
        final currentUpdatedAt = (updated['socialUpdatedAt'] as num?)?.toInt() ?? 0;
        final incomingLikes = List<String>.from(packet['likes'] as List? ?? const []);
        final mergedReplies = <String, Map<String, dynamic>>{};
        for (final item in [...(updated['replies'] as List? ?? const []), ...(packet['replies'] as List? ?? const [])]) {
          if (item is Map) { final reply = Map<String, dynamic>.from(item); final rid = reply['id']?.toString() ?? jsonEncode(reply); mergedReplies[rid] = reply; }
        }
        // المشاهدون: اتحاد المعرّفات الفريدة (لا يُحتسب صاحب القصة ولا أي مشاهدة وهمية).
        final mergedViewers = <String>{
          ...List<String>.from(updated['viewers'] as List? ?? const []),
          ...List<String>.from(packet['viewers'] as List? ?? const []),
        }..remove(updated['userId']?.toString());
        updated['viewers'] = mergedViewers.toList();
        // Timestamped snapshots allow unlikes to propagate; replies are union-merged by ID.
        if (incomingUpdatedAt >= currentUpdatedAt) {
          updated['likes'] = incomingLikes;
          updated['socialUpdatedAt'] = incomingUpdatedAt;
        }
        updated['replies'] = mergedReplies.values.toList();
        _stories[index] = updated;
        await _saveStories();
        if (mounted) setState(() {});
        // Relay once to peers that did not receive the original update.
        try { if (LocalNetworkService.instance.isRunning) await LocalNetworkService.instance.broadcastMessage(jsonEncode(packet)); } catch (_) {}
        return;
      }
      if (type != 'story_post') return;
      final incoming = Map<String, dynamic>.from(packet['story'] as Map);
      if ((incoming['userId']?.toString() ?? '') == _myId) return;
      final created = (incoming['createdAt'] as num?)?.toInt() ?? 0;
      if (DateTime.now().millisecondsSinceEpoch - created >= const Duration(hours: 24).inMilliseconds) return;
      final existing = _stories.indexWhere((s) => s['id']?.toString() == incoming['id']?.toString());
      final encodedMedia = incoming.remove('mediaBase64')?.toString() ?? '';
      if (existing >= 0) {
        final current = Map<String, dynamic>.from(_stories[existing]);
        current['likes'] = List<String>.from(incoming['likes'] as List? ?? current['likes'] as List? ?? const []);
        current['viewers'] = <String>{
          ...List<String>.from(current['viewers'] as List? ?? const []),
          ...List<String>.from(incoming['viewers'] as List? ?? const []),
        }.toList();
        current['replies'] = List<Map<String, dynamic>>.from((incoming['replies'] as List? ?? current['replies'] as List? ?? const []).map((e) => Map<String, dynamic>.from(e as Map)));
        _stories[existing] = current;
        await _saveStories();
        if (mounted) setState(() {});
        return;
      }
      if (encodedMedia.isEmpty) return;
      final dir = await getApplicationDocumentsDirectory();
      final mediaDir = Directory('${dir.path}/blousab_stories');
      if (!await mediaDir.exists()) await mediaDir.create(recursive: true);
      final ext = incoming['mediaType'] == 'video' ? 'mp4' : 'jpg';
      final mediaFile = File('${mediaDir.path}/received_${incoming['id']}.$ext');
      await mediaFile.writeAsBytes(base64Decode(encodedMedia), flush: true);
      incoming['path'] = mediaFile.path;
      incoming['likes'] = List<String>.from(incoming['likes'] as List? ?? const []);
      incoming['viewers'] = List<String>.from(incoming['viewers'] as List? ?? const []);
      incoming['replies'] = List<Map<String, dynamic>>.from((incoming['replies'] as List? ?? const []).map((e) => Map<String, dynamic>.from(e as Map)));
      final photoData = incoming.remove('profilePhotoBase64')?.toString() ?? '';
      if (photoData.isNotEmpty) {
        try {
          final photo = File('${mediaDir.path}/profile_${incoming['userId']}.jpg');
          await photo.writeAsBytes(base64Decode(photoData), flush: true);
          incoming['profilePhotoPath'] = photo.path;
        } catch (_) {}
      }
      _stories.add(incoming);
      await _saveStories();
      if (mounted) setState(() => _stories.sort((a, b) => ((b['createdAt'] as num?)?.toInt() ?? 0).compareTo((a['createdAt'] as num?)?.toInt() ?? 0)));
      // Relay newly received stories so devices in a multi-peer LAN can converge.
      await _broadcastStory(incoming);
    } catch (_) {}
  }

  Future<void> _saveStories() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_storageKey, _stories.map(jsonEncode).toList());
    blousabStoryStoreVersion.value++;
  }

  Future<void> _loadStories() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_storageKey) ?? <String>[];
    _friendIds = (prefs.getStringList('blousab_accepted_friends_v1') ?? <String>[]).toSet();
    final loaded = <Map<String, dynamic>>[];
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final item in raw) {
      try {
        final map = Map<String, dynamic>.from(jsonDecode(item) as Map);
        final created = (map['createdAt'] as num?)?.toInt() ?? 0;
        final path = map['path']?.toString() ?? '';
        if (now - created < const Duration(hours: 24).inMilliseconds && File(path).existsSync()) {
          loaded.add(map);
        } else if (path.isNotEmpty) {
          try { await File(path).delete(); } catch (_) {}
        }
      } catch (_) {}
    }
    await prefs.setStringList(_storageKey, loaded.map(jsonEncode).toList());
    if (mounted) setState(() => _stories = loaded..sort((a, b) => ((b['createdAt'] as num?)?.toInt() ?? 0).compareTo((a['createdAt'] as num?)?.toInt() ?? 0)));
  }

  Future<void> _createStory() async {
    if (_busy) return;
    final prefsForIdentity = await SharedPreferences.getInstance();
    _myId = prefsForIdentity.getString('wasl_user_id') ?? _myId;
    final source = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(leading: const Icon(Icons.photo_library_outlined), title: const Text('اختيار صورة من المعرض'), onTap: () => Navigator.pop(ctx, 'image_gallery')),
        ListTile(leading: const Icon(Icons.photo_camera_outlined), title: const Text('التقاط صورة بالكاميرا'), onTap: () => Navigator.pop(ctx, 'image_camera')),
        ListTile(leading: const Icon(Icons.video_library_outlined), title: const Text('اختيار فيديو من المعرض'), onTap: () => Navigator.pop(ctx, 'video_gallery')),
        ListTile(leading: const Icon(Icons.videocam_outlined), title: const Text('تصوير فيديو'), onTap: () => Navigator.pop(ctx, 'video_camera')),
        const SizedBox(height: 8),
      ])),
    );
    if (source == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final isVideo = source.toString().startsWith('video_');
      final pickerSource = source.endsWith('camera') ? ImageSource.camera : ImageSource.gallery;
      final picked = isVideo
          ? await _picker.pickVideo(source: pickerSource, maxDuration: const Duration(seconds: 60))
          : await _picker.pickImage(source: pickerSource, imageQuality: 78, maxWidth: 1440);
      if (picked == null) return;
      final captionController = TextEditingController();
      final caption = await showDialog<String>(context: context, builder: (ctx) => AlertDialog(
        title: const Text('إضافة ستوري'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          ClipRRect(borderRadius: BorderRadius.circular(12), child: isVideo ? Container(height: 150, width: double.infinity, color: Colors.black87, child: const Center(child: Icon(Icons.play_circle_outline, color: Colors.white, size: 64))) : Image.file(File(picked.path), height: 150, width: double.infinity, fit: BoxFit.cover)),
          const SizedBox(height: 12),
          TextField(controller: captionController, maxLength: 180, maxLines: 2, decoration: const InputDecoration(labelText: 'اكتب تعليقًا (اختياري)', border: OutlineInputBorder())),
          const SizedBox(height: 4),
          Text(isVideo ? 'الفيديو سيُضغط لتقليل حجمه، والمدة القصوى 60 ثانية. تنتهي الحالة بعد 24 ساعة.' : 'ستُضغط الصورة لتسهيل تحميلها، وتنتهي الحالة بعد 24 ساعة.', style: TextStyle(fontSize: 12)),
        ]),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')), FilledButton(onPressed: () => Navigator.pop(ctx, captionController.text.trim()), child: const Text('نشر'))],
      ));
      captionController.dispose();
      if (caption == null) return;
      final dir = await getApplicationDocumentsDirectory();
      final storiesDir = Directory('${dir.path}/blousab_stories');
      if (!await storiesDir.exists()) await storiesDir.create(recursive: true);
      String target;
      if (isVideo) {
        // Compress video for easier transfer and playback; keep original as fallback.
        final compressed = await VideoCompress.compressVideo(picked.path, quality: VideoQuality.MediumQuality, deleteOrigin: false, includeAudio: true);
        final mediaFile = compressed?.file;
        final extension = mediaFile?.path.split('.').last ?? (picked.path.contains('.') ? picked.path.split('.').last : 'mp4');
        target = '${storiesDir.path}/story_${DateTime.now().millisecondsSinceEpoch}.$extension';
        await (mediaFile ?? File(picked.path)).copy(target);
      } else {
        target = '${storiesDir.path}/story_${DateTime.now().millisecondsSinceEpoch}.jpg';
        await File(picked.path).copy(target);
      }
      final story = <String, dynamic>{
        'id': DateTime.now().microsecondsSinceEpoch.toString(),
        'userId': _myId,
        'userName': widget.userName.isEmpty ? 'مستخدم بلوساب' : widget.userName,
        'profilePhotoPath': widget.profilePhotoPath,
        'path': target,
        'mediaType': isVideo ? 'video' : 'image',
        'caption': caption,
        'visibility': prefsForIdentity.getString('blousab_story_visibility') ?? 'everyone',
        'createdAt': DateTime.now().millisecondsSinceEpoch,
        'likes': <String>[],
        'viewers': <String>[],
        'replies': <Map<String, dynamic>>[],
      };
      final prefs = await SharedPreferences.getInstance();
      final current = prefs.getStringList(_storageKey) ?? <String>[];
      current.insert(0, jsonEncode(story));
      await prefs.setStringList(_storageKey, current);
      blousabStoryStoreVersion.value++;
      await _loadStories();
      if (mounted) setState(() { _selectedUserId = ''; _page = 0; });
      await _broadcastStory(story);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(isVideo ? 'تم نشر الحالة محليًا وإرسالها إلى أجهزة بلوساب المتاحة على الشبكة نفسها.' : 'تم نشر الحالة محليًا وإرسالها إلى أجهزة بلوساب المتاحة على الشبكة نفسها.')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذر إنشاء الستوري: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _openStory(Map<String, dynamic> story) {
    // المشاهدات الحقيقية فقط: معرّف فريد لكل مشاهد، ولا يُحتسب صاحب القصة.
    if (story['userId']?.toString() != _myId) {
      final viewers = List<String>.from(story['viewers'] as List? ?? const []);
      if (!viewers.contains(_myId)) {
        viewers.add(_myId);
        story['viewers'] = viewers;
        final viewIndex = _stories.indexWhere((s) => s['id']?.toString() == story['id']?.toString());
        if (viewIndex >= 0) _stories[viewIndex]['viewers'] = viewers;
        unawaited(_saveStories());
        unawaited(_broadcastStoryUpdate(story));
      }
    }
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => _StoryViewer(story: story, myId: _myId, myName: widget.userName, onUpdate: (updated) async {
      updated['socialUpdatedAt'] = DateTime.now().millisecondsSinceEpoch;
      final index = _stories.indexWhere((s) => s['id']?.toString() == updated['id']?.toString());
      if (index >= 0) _stories[index] = Map<String, dynamic>.from(updated);
      await _saveStories();
      await _broadcastStoryUpdate(updated);
      if (mounted) setState(() {});
    }, onDelete: () async {
      final prefs = await SharedPreferences.getInstance();
      final current = prefs.getStringList(_storageKey) ?? <String>[];
      current.removeWhere((raw) { try { return (jsonDecode(raw) as Map)['id']?.toString() == story['id']?.toString(); } catch (_) { return false; } });
      await prefs.setStringList(_storageKey, current);
      blousabStoryStoreVersion.value++;
      try { if (LocalNetworkService.instance.isRunning) { await LocalNetworkService.instance.broadcastMessage(jsonEncode({'type': 'story_delete', 'storyId': story['id'], 'ownerId': _myId})); } } catch (_) {}
      try { await File(story['path'].toString()).delete(); } catch (_) {}
      await _loadStories();
    })));
  }

  Widget _storyAvatar(Map<String, dynamic> story) {
    final profilePath = (story['profilePhotoPath'] ?? '').toString();
    if (profilePath.isNotEmpty && File(profilePath).existsSync()) {
      return Image.file(File(profilePath), fit: BoxFit.cover, errorBuilder: (_, __, ___) => _fallbackStoryAvatar(story));
    }
    // Legacy stories do not store a profile photo; use a media preview as a fallback.
    if (story['mediaType'] != 'video') {
      return Image.file(File(story['path'].toString()), fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _fallbackStoryAvatar(story));
    }
    return _fallbackStoryAvatar(story);
  }

  Widget _fallbackStoryAvatar(Map<String, dynamic> story) => ColoredBox(
    color: Theme.of(context).colorScheme.surfaceContainerHighest,
    child: Center(child: Icon(story['mediaType'] == 'video' ? Icons.play_arrow : Icons.person_outline,
      color: Theme.of(context).colorScheme.onSurfaceVariant, size: 28)),
  );

  // -------------------------------------------------------------------
  // Mockup UI: stories tab (strip card + story carousel)
  // -------------------------------------------------------------------
  String _storyAge(Map<String, dynamic> story) {
    final created = DateTime.fromMillisecondsSinceEpoch((story['createdAt'] as num?)?.toInt() ?? 0);
    final age = DateTime.now().difference(created);
    if (age.inMinutes < 1) return 'الآن';
    if (age.inHours > 0) return 'منذ ${age.inHours} س';
    return 'منذ ${age.inMinutes} د';
  }

  Future<void> _toggleStoryLike(Map<String, dynamic> story) async {
    final likes = List<String>.from(story['likes'] as List? ?? const []);
    if (likes.contains(_myId)) { likes.remove(_myId); } else { likes.add(_myId); }
    story['likes'] = likes;
    story['socialUpdatedAt'] = DateTime.now().millisecondsSinceEpoch;
    final index = _stories.indexWhere((s) => s['id']?.toString() == story['id']?.toString());
    if (index >= 0) _stories[index] = Map<String, dynamic>.from(story);
    if (mounted) setState(() {});
    await _saveStories();
    await _broadcastStoryUpdate(story);
  }

  bool _canSee(Map<String, dynamic> story) {
    final owner = story['userId']?.toString() ?? '';
    if (owner == _myId) return true;
    if ((story['visibility']?.toString() ?? 'everyone') == 'friends') return _friendIds.contains(owner);
    return true;
  }

  List<Map<String, dynamic>> get _visibleStories => _stories.where(_canSee).toList();

  List<Map<String, dynamic>> _storiesOf(String userId) =>
      _visibleStories.where((s) => (s['userId']?.toString() ?? '') == userId).toList();

  List<String> get _otherUserIds {
    final ids = <String>[];
    for (final s in _visibleStories) {
      final u = s['userId']?.toString() ?? '';
      if (u.isNotEmpty && u != _myId && !ids.contains(u)) ids.add(u);
    }
    return ids;
  }

  void _selectUser(String userId) {
    setState(() {
      _selectedUserId = userId == _myId ? '' : userId;
      _page = 0;
    });
    if (_pageController.hasClients) _pageController.jumpToPage(0);
  }

  Widget _glassPill(Widget child) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
    decoration: BoxDecoration(
      color: const Color(0x99091330),
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: const Color(0x553F7BFF)),
    ),
    child: child,
  );

  Widget _storyCard(Map<String, dynamic> story, bool active, int total) {
    final path = story['path'].toString();
    final isVideo = story['mediaType'] == 'video';
    final caption = (story['caption'] ?? '').toString();
    final likes = List<String>.from(story['likes'] as List? ?? const []);
    final liked = likes.contains(_myId);
    final views = List<String>.from(story['viewers'] as List? ?? const []).where((v) => v != story['userId']?.toString()).length;
    final name = (story['userName'] ?? 'مستخدم بلوساب').toString();
    final mine = story['userId']?.toString() == _myId;
    final int segments = total.clamp(1, 8).toInt();
    final int filled = _page.clamp(0, segments - 1).toInt();
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 200),
      opacity: active ? 1 : .55,
      child: Container(
        margin: EdgeInsets.symmetric(horizontal: 5, vertical: active ? 0 : 22),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: const Color(0xFF4F7BFF), width: 1.8),
          boxShadow: const [BoxShadow(color: Color(0x774F7BFF), blurRadius: 14), BoxShadow(color: Color(0x44B238FF), blurRadius: 18)],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: Stack(fit: StackFit.expand, children: [
            GestureDetector(
              onTap: () => _openStory(story),
              child: isVideo
                  ? Container(color: const Color(0xFF0B1536), child: const Center(child: Icon(Icons.play_circle_fill_rounded, color: Colors.white, size: 72)))
                  : BlousabKeepColors(child: Image.file(File(path), fit: BoxFit.cover, width: double.infinity, height: double.infinity,
                      errorBuilder: (_, __, ___) => Container(color: const Color(0xFF0B1536), child: const Center(child: Icon(Icons.broken_image_outlined, color: Colors.white54, size: 52))))),
            ),
            IgnorePointer(child: Container(
              height: 120,
              decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xCC050A1E), Color(0x00050A1E)])),
            )),
            Positioned(top: 10, left: 14, right: 14, child: Row(children: List.generate(segments, (i) => Expanded(child: Container(
              height: 4, margin: const EdgeInsets.symmetric(horizontal: 2),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(3),
                color: i == filled ? const Color(0xFF2D8CFF) : const Color(0x55FFFFFF),
                boxShadow: i == filled ? const [BoxShadow(color: Color(0xFF2D8CFF), blurRadius: 6)] : null,
              ),
            ))))),
            Positioned(top: 24, left: 12, right: 6, child: Directionality(
              textDirection: TextDirection.ltr,
              child: Row(children: [
                BlousabRingAvatar(name: name, size: 46, ring: 2.5, child: _storyAvatar(story)),
                const SizedBox(width: 10),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    Flexible(child: Text(name, textDirection: TextDirection.rtl, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800))),
                  ]),
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    Text(_storyAge(story), textDirection: TextDirection.rtl, style: const TextStyle(color: Color(0xFFD5DEFF), fontSize: 12.5)),
                    const SizedBox(width: 6),
                    const Icon(Icons.public, color: Color(0xFFD5DEFF), size: 15),
                  ]),
                ])),
                const Icon(Icons.more_vert, color: Colors.white, size: 26),
              ]),
            )),
            if (caption.isNotEmpty) Positioned(top: 112, left: 20, right: 20, child: IgnorePointer(child: Center(child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
              decoration: BoxDecoration(color: const Color(0xE6000000), borderRadius: BorderRadius.circular(6)),
              child: Text(caption, maxLines: 3, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800)),
            )))),
            Positioned(bottom: 12, left: 12, child: _glassPill(Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.visibility_outlined, color: Colors.white, size: 26),
              const SizedBox(width: 8),
              Text('$views', style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
            ]))),
            Positioned(bottom: 12, right: 12, child: _glassPill(Row(mainAxisSize: MainAxisSize.min, children: [
              GestureDetector(onTap: () => _openStory(story), child: const Icon(Icons.reply_rounded, color: Colors.white, size: 28)),
              const SizedBox(width: 16),
              GestureDetector(onTap: () => _openStory(story), child: const Icon(Icons.send_outlined, color: Colors.white, size: 26)),
              const SizedBox(width: 16),
              GestureDetector(
                onTap: () => _toggleStoryLike(story),
                child: Icon(liked ? Icons.favorite : Icons.favorite_border, color: liked ? const Color(0xFFFF3B5C) : Colors.white, size: 28)),
            ]))),
          ]),
        ),
      ),
    );
  }

  Widget _arrowButton(IconData icon, VoidCallback onTap) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: 44, height: 44,
      decoration: BoxDecoration(
        color: const Color(0xFF070F2C), shape: BoxShape.circle,
        border: Border.all(color: const Color(0xFF3F7BFF), width: 1.4),
        boxShadow: const [BoxShadow(color: Color(0x663F7BFF), blurRadius: 10)],
      ),
      child: Icon(icon, color: Colors.white, size: 30, textDirection: TextDirection.ltr),
    ),
  );

  Widget _buildShowcase(BuildContext context) {
    final mine = _storiesOf(_myId);
    final others = _otherUserIds;
    // إن اختفت قصص المستخدم المحدد (انتهت 24 ساعة) نعود إلى قصصي.
    final selected = (_selectedUserId.isNotEmpty && others.contains(_selectedUserId)) ? _selectedUserId : _myId;
    final shown = _storiesOf(selected);
    final myPhotoPath = widget.profilePhotoPath;

    Widget circleLabel(String text, bool isSelected) => Text(text,
        maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center,
        style: TextStyle(color: isSelected ? const Color(0xFF38D6FF) : Colors.white, fontSize: 12.5, fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600));

    Widget glow(bool isSelected, Widget child) => Container(
      decoration: BoxDecoration(shape: BoxShape.circle,
        boxShadow: isSelected ? const [BoxShadow(color: Color(0xAA38D6FF), blurRadius: 12, spreadRadius: 1)] : null),
      child: child);

    // الدائرة الأولى: «قصتك» دائماً.
    final myCircle = SizedBox(width: 76, child: GestureDetector(
      onTap: () { if (mine.isEmpty) { _createStory(); } else { _selectUser(_myId); } },
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Stack(clipBehavior: Clip.none, children: [
          glow(selected == _myId && mine.isNotEmpty, BlousabRingAvatar(name: widget.userName, photoPath: myPhotoPath, size: 60, ring: 2.5)),
          Positioned(right: -2, bottom: -1, child: GestureDetector(
            onTap: _createStory,
            child: Container(
              width: 24, height: 24,
              decoration: BoxDecoration(color: const Color(0xFF1F8BFF), shape: BoxShape.circle, border: Border.all(color: const Color(0xFF050A1C), width: 2)),
              child: _busy
                  ? const Padding(padding: EdgeInsets.all(5), child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.add, color: Colors.white, size: 16)),
          )),
        ]),
        const SizedBox(height: 5),
        circleLabel('قصتك', selected == _myId && mine.isNotEmpty),
      ]),
    ));

    final stripItems = <Widget>[
      myCircle,
      ...others.map((uid) {
        final userStories = _storiesOf(uid);
        final latest = userStories.first;
        final name = (latest['userName'] ?? 'مستخدم').toString();
        final isSelected = selected == uid;
        return SizedBox(width: 72, child: GestureDetector(
          onTap: () => _selectUser(uid),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            glow(isSelected, BlousabRingAvatar(name: name, size: 60, ring: 2.5, child: _storyAvatar(latest))),
            const SizedBox(height: 5),
            circleLabel(name, isSelected),
          ]),
        ));
      }),
    ];

    return Column(children: [
      Container(
        height: 106,
        margin: const EdgeInsets.fromLTRB(6, 0, 6, 10),
        padding: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          color: const Color(0xFF060C22),
          border: Border.all(color: const Color(0xFF3B63FF), width: 1.4),
          boxShadow: const [BoxShadow(color: Color(0x553B63FF), blurRadius: 12)],
        ),
        child: ListView(scrollDirection: Axis.horizontal, children: stripItems),
      ),
      Expanded(child: shown.isEmpty
        ? Center(child: Padding(padding: const EdgeInsets.all(28), child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.auto_stories_outlined, size: 60, color: Color(0xFF3FA2FF)),
            const SizedBox(height: 12),
            const Text('لا توجد قصص بعد', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            const Text('اضغط على «قصتك» أو زر + لإضافة قصة جديدة تصل إلى الأجهزة القريبة.', textAlign: TextAlign.center, style: TextStyle(color: Color(0xFFC6D0F2))),
          ])))
        : Stack(fit: StackFit.expand, children: [
            PageView.builder(
              controller: _pageController,
              itemCount: shown.length,
              onPageChanged: (i) => setState(() => _page = i),
              itemBuilder: (context, index) => _storyCard(shown[index], index == _page, shown.length),
            ),
            // أسهم التمرير بعد عكس الاتجاه: اليسار «<» والتالي، واليمين «>» والسابق.
            Positioned(left: 4, top: 0, bottom: 0, child: Center(child: _arrowButton(Icons.chevron_left_rounded, () {
              if (_page < shown.length - 1) _pageController.nextPage(duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
            }))),
            Positioned(right: 4, top: 0, bottom: 0, child: Center(child: _arrowButton(Icons.chevron_right_rounded, () {
              if (_page > 0) _pageController.previousPage(duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
            }))),
          ])),
      const SizedBox(height: 10),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.showcase) return _buildShowcase(context);
    final myPhoto = widget.profilePhotoPath.isNotEmpty && File(widget.profilePhotoPath).existsSync();
    return Container(
      height: 112,
      padding: const EdgeInsets.only(top: 8, bottom: 8),
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          if (widget.onAddPost != null)
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 10),
              child: GestureDetector(
                onTap: widget.onAddPost,
                child: Container(
                  width: 70,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    color: const Color(0xFF080F2A),
                    border: Border.all(color: const Color(0xFF2B48A8), width: 1.2),
                  ),
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Container(
                      width: 32, height: 32,
                      decoration: const BoxDecoration(shape: BoxShape.circle, gradient: LinearGradient(colors: [Color(0xFF1F9BFF), Color(0xFF2D6BFF)]),
                        boxShadow: [BoxShadow(color: Color(0x882D6BFF), blurRadius: 8)]),
                      child: const Icon(Icons.add_rounded, color: Colors.white, size: 24),
                    ),
                    const SizedBox(height: 6),
                    const Text('إضافة\nمنشور', textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontSize: 11.5, height: 1.1, fontWeight: FontWeight.w600)),
                  ]),
                ),
              ),
            )
          else
            SizedBox(width: 76, child: InkWell(onTap: () { final mine = _storiesOf(_myId); if (mine.isNotEmpty) { _openStory(mine.first); } else { _createStory(); } }, borderRadius: BorderRadius.circular(14), child: Column(children: [
              Stack(children: [
                Container(width: 62, height: 62, padding: const EdgeInsets.all(3), decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: const Color(0xFF38B5FF), width: 1.5)), child: CircleAvatar(backgroundImage: myPhoto ? FileImage(File(widget.profilePhotoPath)) : null, child: myPhoto ? null : const Icon(Icons.person_outline, size: 28))),
                Positioned(right: 0, bottom: 0, child: Material(color: Theme.of(context).colorScheme.primary, shape: CircleBorder(side: BorderSide(color: Theme.of(context).scaffoldBackgroundColor, width: 2)), child: InkWell(customBorder: const CircleBorder(), onTap: _createStory, child: const Padding(padding: EdgeInsets.all(2), child: Icon(Icons.add, size: 19, color: Colors.white)))),)
              ]),
              const SizedBox(height: 5),
              Text(_busy ? 'جارٍ التجهيز…' : 'قصتك', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
            ]))),
          ..._otherUserIds.map((uid) => _storiesOf(uid).first).map((story) => SizedBox(width: 78, child: InkWell(onTap: () => _openStory(story), borderRadius: BorderRadius.circular(14), child: Column(children: [
            BlousabRingAvatar(name: (story['userName'] ?? 'مستخدم').toString(), size: 64, ring: 2.8, child: _storyAvatar(story)),
            const SizedBox(height: 4),
            Text((story['userName'] ?? 'مستخدم').toString(), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w600)),
          ])))),
        ],
      ),
    );
  }
}

class _StoryViewer extends StatefulWidget {
  final Map<String, dynamic> story;
  final Future<void> Function() onDelete;
  final Future<void> Function(Map<String, dynamic>) onUpdate;
  final String myId;
  final String myName;
  const _StoryViewer({required this.story, required this.onDelete, required this.onUpdate, required this.myId, required this.myName});
  @override
  State<_StoryViewer> createState() => _StoryViewerState();
}

class _StoryViewerState extends State<_StoryViewer> {
  Timer? _timer;
  double _progress = 0;
  VideoPlayerController? _videoController;
  bool _videoReady = false;
  bool _videoFailed = false;
  bool _saving = false;
  StreamSubscription<BlousabEvent>? _storyEventSubscription;
  late Map<String, dynamic> _story;
  bool get _isOwner => _story['userId']?.toString() == widget.myId;
  List<String> get _likes => List<String>.from(_story['likes'] as List? ?? const []);
  List<Map<String, dynamic>> get _replies => List<Map<String, dynamic>>.from((_story['replies'] as List? ?? const []).map((e) => Map<String, dynamic>.from(e as Map)));
  bool get _isVideo => widget.story['mediaType'] == 'video';

  @override
  void initState() {
    super.initState();
    _story = Map<String, dynamic>.from(widget.story);
    _story['likes'] ??= <String>[];
    _story['replies'] ??= <Map<String, dynamic>>[];
    _storyEventSubscription = LocalNetworkService.instance.events.listen((event) {
      if (event.type != 'message' || event.message == null) return;
      try {
        final packet = jsonDecode(event.message!);
        if (packet is Map && packet['type'] == 'story_update' && packet['storyId']?.toString() == _story['id']?.toString()) {
          final incomingAt = (packet['updatedAt'] as num?)?.toInt() ?? 0;
          final currentAt = (_story['socialUpdatedAt'] as num?)?.toInt() ?? 0;
          if (incomingAt >= currentAt && mounted) {
            setState(() {
              _story['likes'] = List<String>.from(packet['likes'] as List? ?? const []);
              _story['socialUpdatedAt'] = incomingAt;
              final merged = <String, Map<String, dynamic>>{};
              for (final item in [...(_story['replies'] as List? ?? const []), ...(packet['replies'] as List? ?? const [])]) {
                if (item is Map) { final reply = Map<String, dynamic>.from(item); merged[reply['id']?.toString() ?? jsonEncode(reply)] = reply; }
              }
              _story['replies'] = merged.values.toList();
            });
          }
        }
      } catch (_) {}
    });
    if (_isVideo) {
      _videoController = VideoPlayerController.file(File(_story['path'].toString()))
        ..initialize().then((_) {
          if (!mounted) return;
          setState(() => _videoReady = true);
          _videoController!.setLooping(false);
          _videoController!.play();
        }).catchError((_) { if (mounted) setState(() => _videoFailed = true); });
    }
    _timer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      if (!mounted) return;
      if (_isVideo && _videoController != null && _videoController!.value.isInitialized) {
        final duration = _videoController!.value.duration.inMilliseconds;
        if (duration > 0) _progress = (_videoController!.value.position.inMilliseconds / duration).clamp(0.0, 1.0);
        if (_videoController!.value.position >= _videoController!.value.duration && !_videoController!.value.isPlaying) {
          Navigator.of(context).maybePop();
          return;
        }
      } else {
        _progress += 0.02;
        if (_progress >= 1) { Navigator.of(context).maybePop(); return; }
      }
      setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _storyEventSubscription?.cancel();
    _videoController?.dispose();
    super.dispose();
  }

  Future<void> _toggleLike() async {
    final likes = _likes;
    if (likes.contains(widget.myId)) { likes.remove(widget.myId); } else { likes.add(widget.myId); }
    setState(() => _story['likes'] = likes);
    await widget.onUpdate(_story);
  }

  Future<void> _replyToStory() async {
    final controller = TextEditingController();
    final text = await showDialog<String>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('الرد على القصة'),
      content: TextField(controller: controller, autofocus: true, maxLength: 300, decoration: const InputDecoration(hintText: 'اكتب ردك…')),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')), FilledButton(onPressed: () => Navigator.pop(ctx, controller.text.trim()), child: const Text('إرسال'))],
    ));
    controller.dispose();
    if (text == null || text.isEmpty) return;
    final replies = _replies;
    replies.add({'id': DateTime.now().microsecondsSinceEpoch.toString(), 'userId': widget.myId, 'userName': widget.myName.isEmpty ? 'مستخدم بلوساب' : widget.myName, 'text': text, 'createdAt': DateTime.now().millisecondsSinceEpoch});
    setState(() => _story['replies'] = replies);
    await widget.onUpdate(_story);
  }

  Future<void> _showReplies() async {
    final replies = _replies;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: SizedBox(
          height: 320,
          child: replies.isEmpty
              ? const Center(child: Text('لا توجد ردود بعد'))
              : ListView(
                  children: replies.map((r) => ListTile(
                    leading: const CircleAvatar(child: Icon(Icons.person_outline)),
                    title: Text(r['userName']?.toString() ?? 'مستخدم'),
                    subtitle: Text(r['text']?.toString() ?? ''),
                  )).toList(),
                ),
        ),
      ),
    );
  }

  Future<void> _saveStory() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final dir = await getApplicationDocumentsDirectory();
      final savedDir = Directory('${dir.path}/blousab_saved_statuses');
      if (!await savedDir.exists()) await savedDir.create(recursive: true);
      final source = File(_story['path'].toString());
      if (!await source.exists()) throw Exception('ملف الحالة غير موجود');
      final extension = source.path.contains('.') ? source.path.split('.').last : (_isVideo ? 'mp4' : 'jpg');
      final destination = '${savedDir.path}/status_${DateTime.now().millisecondsSinceEpoch}.$extension';
      await source.copy(destination);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تم حفظ الحالة داخل بلوساب: $destination')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذر تحميل الحالة: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final path = _story['path'].toString();
    final caption = (_story['caption'] ?? '').toString();
    final created = DateTime.fromMillisecondsSinceEpoch((_story['createdAt'] as num?)?.toInt() ?? 0);
    final age = DateTime.now().difference(created);
    Widget media;
    if (_isVideo) {
      media = _videoReady && _videoController != null
          ? GestureDetector(onTap: () { final c = _videoController!; setState(() => c.value.isPlaying ? c.pause() : c.play()); }, child: AspectRatio(aspectRatio: _videoController!.value.aspectRatio, child: VideoPlayer(_videoController!)))
          : _videoFailed
              ? const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.video_file_outlined, color: Colors.white, size: 52), SizedBox(height: 8), Text('تعذر تشغيل الفيديو', style: TextStyle(color: Colors.white))]))
              : const Center(child: CircularProgressIndicator(color: Colors.white));
    } else {
      media = Image.file(File(path), fit: BoxFit.contain, width: double.infinity, errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, color: Colors.white, size: 64));
    }
    return Scaffold(backgroundColor: Colors.black, body: SafeArea(child: Stack(fit: StackFit.expand, children: [
      Center(child: BlousabKeepColors(child: media)),
      Positioned.fill(child: Row(children: [Expanded(child: GestureDetector(behavior: HitTestBehavior.translucent, onTap: () => Navigator.pop(context))), Expanded(child: GestureDetector(behavior: HitTestBehavior.translucent, onTap: () => Navigator.pop(context)))])),
      Positioned(top: 10, left: 12, right: 12, child: Column(children: [
        ClipRRect(borderRadius: BorderRadius.circular(10), child: LinearProgressIndicator(value: _progress.clamp(0, 1), minHeight: 3, backgroundColor: Colors.white38, color: Colors.white)),
        const SizedBox(height: 12),
        Row(children: [const CircleAvatar(radius: 17, child: Icon(Icons.person_outline, size: 20)), const SizedBox(width: 8), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text((_story['userName'] ?? 'مستخدم بلوساب').toString(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)), Text(age.inMinutes < 1 ? 'الآن' : age.inHours > 0 ? 'منذ ${age.inHours} س' : 'منذ ${age.inMinutes} د', style: const TextStyle(color: Colors.white70, fontSize: 11))])),
          IconButton(onPressed: _saveStory, icon: Icon(_saving ? Icons.hourglass_top : Icons.download_outlined, color: Colors.white), tooltip: 'تحميل الحالة'),
          if (_isOwner) IconButton(onPressed: () async { await widget.onDelete(); if (mounted) Navigator.pop(context); }, icon: const Icon(Icons.delete_outline, color: Colors.white), tooltip: 'حذف الحالة'),
          IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close, color: Colors.white)),
        ]),
      ])),
      if (_isVideo && _videoReady) Positioned(bottom: 72, left: 0, right: 0, child: Center(child: IconButton(onPressed: () { final c = _videoController!; setState(() => c.value.isPlaying ? c.pause() : c.play()); }, icon: Icon(_videoController!.value.isPlaying ? Icons.pause_circle_filled : Icons.play_circle_fill, color: Colors.white, size: 54)))),
      if (caption.isNotEmpty) Positioned(bottom: 92, left: 20, right: 20, child: Text(caption, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 18, shadows: [Shadow(color: Colors.black87, blurRadius: 8)]))),
      Positioned(bottom: 18, left: 16, right: 16, child: Row(children: [
        IconButton(onPressed: _toggleLike, icon: Icon(_likes.contains(widget.myId) ? Icons.favorite : Icons.favorite_border, color: _likes.contains(widget.myId) ? Colors.redAccent : Colors.white)),
        Text('${_likes.length}', style: const TextStyle(color: Colors.white)),
        const SizedBox(width: 16),
        IconButton(onPressed: _replyToStory, icon: const Icon(Icons.reply_outlined, color: Colors.white)),
        Text('${_replies.length}', style: const TextStyle(color: Colors.white)),
        IconButton(onPressed: _showReplies, icon: const Icon(Icons.chat_bubble_outline, color: Colors.white), tooltip: 'عرض الردود'),
        const Spacer(),
        const Text('مزامنة الأجهزة على Wi-Fi نفسه', style: TextStyle(color: Colors.white70, fontSize: 10)),
      ])),
    ])));
  }
}
