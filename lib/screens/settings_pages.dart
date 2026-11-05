import 'dart:io';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../widgets/blousab_page.dart';
import '../widgets/blousab_visuals.dart';
import 'developer_chat_preview_screen.dart';

/// حجم نص الواجهة (يُطبَّق على التطبيق كله من MaterialApp.builder).
final ValueNotifier<double> blousabTextScale = ValueNotifier<double>(1.0);

// ------------------------------------------------------------------
// تعديل الملف الشخصي
// ------------------------------------------------------------------
class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({
    super.key,
    required this.name,
    required this.photoPath,
    required this.coverPath,
    required this.pickPhoto,
    required this.pickCover,
  });
  final String name;
  final String photoPath;
  final String coverPath;
  final Future<String?> Function() pickPhoto;
  final Future<String?> Function() pickCover;

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  late final TextEditingController _name = TextEditingController(text: widget.name);
  late String _photo = widget.photoPath;
  late String _cover = widget.coverPath;
  bool _photoPicked = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  bool _has(String p) => p.isNotEmpty && File(p).existsSync();

  void _save() {
    Navigator.pop(context, <String, Object?>{
      'name': _name.text.trim(),
      'photoPath': _photo,
      'coverPath': _cover,
      'photoWasPicked': _photoPicked,
    });
  }

  @override
  Widget build(BuildContext context) {
    return BlousabPage(
      title: 'تعديل الملف الشخصي',
      child: ListView(padding: const EdgeInsets.fromLTRB(14, 4, 14, 20), children: [
        SizedBox(
          height: 190,
          child: Stack(clipBehavior: Clip.none, alignment: Alignment.topCenter, children: [
            Container(
              height: 140,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFF3F7BFF), width: 1.4),
                gradient: BlousabVisuals.neon,
                image: _has(_cover) ? DecorationImage(image: FileImage(File(_cover)), fit: BoxFit.cover) : null,
              ),
              alignment: Alignment.topLeft,
              padding: const EdgeInsets.all(8),
              child: BlousabSquareIconButton(
                icon: Icons.image_rounded,
                size: 38,
                tooltip: 'تغيير الغلاف',
                onTap: () async {
                  final p = await widget.pickCover();
                  if (p != null) setState(() => _cover = p);
                },
              ),
            ),
            Positioned(
              bottom: 0,
              child: GestureDetector(
                onTap: () async {
                  final p = await widget.pickPhoto();
                  if (p != null) setState(() { _photo = p; _photoPicked = true; });
                },
                child: Stack(children: [
                  BlousabRingAvatar(
                    name: _name.text,
                    size: 104,
                    ring: 4,
                    photoPath: _photo,
                    child: _has(_photo) ? null : Container(color: const Color(0xFFE9E9EC), child: const Icon(Icons.person_rounded, size: 64, color: Color(0xFF14235A))),
                  ),
                  Positioned(
                    right: 0,
                    bottom: 2,
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(color: const Color(0xFF0A1334), shape: BoxShape.circle, border: Border.all(color: const Color(0xFF3FA2FF), width: 1.5)),
                      child: const Icon(Icons.photo_camera_rounded, color: Colors.white, size: 18),
                    ),
                  ),
                ]),
              ),
            ),
          ]),
        ),
        if (_has(_photo))
          Center(
            child: TextButton.icon(
              onPressed: () => setState(() { _photo = ''; _photoPicked = true; }),
              icon: const Icon(Icons.delete_outline_rounded),
              label: const Text('إزالة الصورة'),
            ),
          ),
        const BlousabSectionLabel('الاسم'),
        TextField(
          controller: _name,
          maxLength: 40,
          onChanged: (_) => setState(() {}),
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(labelText: 'اسم المستخدم', prefixIcon: Icon(Icons.person_outline_rounded)),
        ),
        const SizedBox(height: 14),
        BlousabPrimaryButton(label: 'حفظ التغييرات', icon: Icons.save_rounded, onTap: _save),
      ]),
    );
  }
}

// ------------------------------------------------------------------
// مساعد قراءة/كتابة سريع
// ------------------------------------------------------------------
Future<SharedPreferences> _p() => SharedPreferences.getInstance();

// ------------------------------------------------------------------
// الخصوصية والأمان
// ------------------------------------------------------------------
class PrivacySettingsPage extends StatefulWidget {
  const PrivacySettingsPage({super.key, required this.nearbyVisible, required this.onNearbyChanged, required this.onAppLock, required this.onAccountCode, required this.onBlocked});
  final bool nearbyVisible;
  final Future<void> Function(bool) onNearbyChanged;
  final Future<void> Function() onAppLock;
  final VoidCallback onAccountCode;
  final VoidCallback onBlocked;
  @override
  State<PrivacySettingsPage> createState() => _PrivacySettingsPageState();
}

class _PrivacySettingsPageState extends State<PrivacySettingsPage> {
  late bool _nearby = widget.nearbyVisible;
  bool _lock = false;

  @override
  void initState() {
    super.initState();
    _refreshLock();
  }

  Future<void> _refreshLock() async {
    final prefs = await _p();
    if (mounted) setState(() => _lock = prefs.getBool('blousab_app_lock_enabled') ?? false);
  }

  @override
  Widget build(BuildContext context) => BlousabPage(
        title: 'الخصوصية والأمان',
        child: ListView(padding: const EdgeInsets.fromLTRB(12, 4, 12, 20), children: [
          BlousabSettingsGroup(children: [
            BlousabSwitchRow(
              icon: Icons.visibility_rounded,
              title: 'مرئي للأجهزة القريبة',
              subtitle: 'السماح لمستخدمي بلوساب حولك بالعثور عليك',
              value: _nearby,
              onChanged: (v) async {
                setState(() => _nearby = v);
                await widget.onNearbyChanged(v);
              },
            ),
            BlousabSettingsRow(
              icon: Icons.lock_rounded,
              title: 'قفل التطبيق',
              subtitle: _lock ? 'مفعّل — اضغط لإدارته' : 'حماية بلوساب برمز PIN',
              onTap: () async {
                await widget.onAppLock();
                await _refreshLock();
              },
            ),
            BlousabSettingsRow(icon: Icons.qr_code_2_rounded, iconColor: const Color(0xFFB46CFF), title: 'رمز حسابي', subtitle: 'عرض معرّف حسابك', onTap: widget.onAccountCode),
            BlousabSettingsRow(icon: Icons.block_rounded, iconColor: const Color(0xFFFF3B4E), title: 'قائمة المحظورين', subtitle: 'إدارة المستخدمين المحظورين', onTap: widget.onBlocked),
          ]),
        ]),
      );
}

// ------------------------------------------------------------------
// إعدادات المحادثات
// ------------------------------------------------------------------
class ChatSettingsPage extends StatefulWidget {
  const ChatSettingsPage({super.key, required this.onConnectionTap});
  final Future<void> Function() onConnectionTap;
  @override
  State<ChatSettingsPage> createState() => _ChatSettingsPageState();
}

class _ChatSettingsPageState extends State<ChatSettingsPage> {
  double _font = 16;
  bool _time = true, _compact = false, _vibrate = true, _lan = true;
  String _wallpaper = 'night', _mode = 'bluetooth';
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await _p();
    if (!mounted) return;
    setState(() {
      _font = (prefs.getDouble('blousab_message_font_size') ?? 16).clamp(14, 22).toDouble();
      _time = prefs.getBool('blousab_show_message_time') ?? true;
      _compact = prefs.getBool('blousab_compact_bubbles') ?? false;
      _vibrate = prefs.getBool('blousab_vibrate_on_send') ?? true;
      _lan = prefs.getBool('blousab_lan_enabled') ?? true;
      _wallpaper = prefs.getString('wasl_chat_wallpaper') ?? 'night';
      _mode = prefs.getString('blousab_connection_mode') ?? 'bluetooth';
      _ready = true;
    });
  }

  Future<void> _setBool(String key, bool v) async => (await _p()).setBool(key, v);

  Widget _choice(String label, bool selected, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: selected ? const Color(0xFF133A9F) : const Color(0xFF0A1330),
            border: Border.all(color: selected ? const Color(0xFF3FA2FF) : const Color(0xFF2B48A8)),
          ),
          child: Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
        ),
      );

  @override
  Widget build(BuildContext context) {
    if (!_ready) return const BlousabPage(title: 'إعدادات المحادثات', child: Center(child: CircularProgressIndicator()));
    return BlousabPage(
      title: 'إعدادات المحادثات',
      child: ListView(padding: const EdgeInsets.fromLTRB(12, 4, 12, 20), children: [
        const BlousabSectionLabel('الرسائل'),
        BlousabSettingsGroup(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
            child: Column(children: [
              Row(children: [
                const Expanded(child: Text('حجم نص الرسائل', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800))),
                Text('${_font.round()}', style: const TextStyle(color: Colors.white)),
              ]),
              Slider(
                value: _font,
                min: 14,
                max: 22,
                divisions: 8,
                onChanged: (v) => setState(() => _font = v),
                onChangeEnd: (v) async => (await _p()).setDouble('blousab_message_font_size', v),
              ),
            ]),
          ),
          BlousabSwitchRow(icon: Icons.schedule_rounded, title: 'إظهار وقت الرسالة', value: _time, onChanged: (v) { setState(() => _time = v); _setBool('blousab_show_message_time', v); }),
          BlousabSwitchRow(icon: Icons.view_compact_rounded, title: 'فقاعات مضغوطة', value: _compact, onChanged: (v) { setState(() => _compact = v); _setBool('blousab_compact_bubbles', v); }),
          BlousabSwitchRow(icon: Icons.vibration_rounded, title: 'اهتزاز عند الإرسال', value: _vibrate, onChanged: (v) { setState(() => _vibrate = v); _setBool('blousab_vibrate_on_send', v); }),
        ]),
        const BlousabSectionLabel('خلفية المحادثة'),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final e in const {'night': 'داكن', 'mint': 'أخضر هادئ', 'cream': 'كريمي', 'plain': 'أبيض بسيط'}.entries)
            _choice(e.value, _wallpaper == e.key, () async {
              setState(() => _wallpaper = e.key);
              (await _p()).setString('wasl_chat_wallpaper', e.key);
            }),
        ]),
        const BlousabSectionLabel('الاتصال'),
        Wrap(spacing: 8, runSpacing: 8, children: [
          _choice('Bluetooth Classic', _mode == 'bluetooth', () async { setState(() => _mode = 'bluetooth'); (await _p()).setString('blousab_connection_mode', 'bluetooth'); }),
          _choice('Wi-Fi عبر نقطة اتصال', _mode == 'wifi', () async { setState(() => _mode = 'wifi'); (await _p()).setString('blousab_connection_mode', 'wifi'); }),
        ]),
        const SizedBox(height: 10),
        BlousabSettingsGroup(children: [
          BlousabSwitchRow(icon: Icons.wifi_rounded, title: 'الشبكة المحلية Wi-Fi', subtitle: 'لإرسال الرسائل للأجهزة على الشبكة نفسها', value: _lan, onChanged: (v) { setState(() => _lan = v); _setBool('blousab_lan_enabled', v); }),
          BlousabSettingsRow(icon: Icons.bluetooth_searching_rounded, title: 'تشغيل استقبال الاتصال', subtitle: _mode == 'wifi' ? 'تعليمات الاتصال عبر Wi-Fi' : 'بدء استقبال Bluetooth', onTap: widget.onConnectionTap),
          BlousabSettingsRow(
            icon: Icons.preview_rounded,
            iconColor: const Color(0xFF28C7FF),
            title: 'محادثة تجريبية (للمطور)',
            subtitle: 'معاينة شكل الرسائل دون اتصال',
            onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const DeveloperChatPreviewScreen())),
          ),
        ]),
        const SizedBox(height: 8),
        const Text('تُحفظ هذه الإعدادات على هذا الهاتف.', style: TextStyle(color: Color(0xFFA3B5DE), fontSize: 12)),
      ]),
    );
  }
}

// ------------------------------------------------------------------
// من يمكنه رؤية منشوراتك / قصصك
// ------------------------------------------------------------------
class VisibilitySettingsPage extends StatefulWidget {
  const VisibilitySettingsPage({super.key, required this.title, required this.prefKey, required this.noun});
  final String title;
  final String prefKey;
  final String noun;
  @override
  State<VisibilitySettingsPage> createState() => _VisibilitySettingsPageState();
}

class _VisibilitySettingsPageState extends State<VisibilitySettingsPage> {
  String _value = 'everyone';

  @override
  void initState() {
    super.initState();
    _p().then((p) { if (mounted) setState(() => _value = p.getString(widget.prefKey) ?? 'everyone'); });
  }

  Future<void> _set(String v) async {
    setState(() => _value = v);
    (await _p()).setString(widget.prefKey, v);
  }

  @override
  Widget build(BuildContext context) => BlousabPage(
        title: widget.title,
        child: ListView(padding: const EdgeInsets.fromLTRB(12, 4, 12, 20), children: [
          BlousabSectionLabel('من يمكنه رؤية ${widget.noun}؟'),
          BlousabSettingsGroup(children: [
            BlousabSettingsRow(
              icon: Icons.public_rounded,
              title: 'الجميع',
              subtitle: 'كل مستخدمي بلوساب القريبين',
              showChevron: false,
              onTap: () => _set('everyone'),
              trailing: Icon(_value == 'everyone' ? Icons.radio_button_checked : Icons.radio_button_off, color: const Color(0xFF3FD0FF)),
            ),
            BlousabSettingsRow(
              icon: Icons.groups_rounded,
              title: 'الأصدقاء فقط',
              subtitle: 'من قبلتَ صداقته فقط',
              showChevron: false,
              onTap: () => _set('friends'),
              trailing: Icon(_value == 'friends' ? Icons.radio_button_checked : Icons.radio_button_off, color: const Color(0xFF3FD0FF)),
            ),
          ]),
          const SizedBox(height: 8),
          Text('يسري الإعداد على ${widget.noun} الجديدة التي تنشرها بعد الآن.', style: const TextStyle(color: Color(0xFFA3B5DE), fontSize: 12.5)),
        ]),
      );
}

// ------------------------------------------------------------------
// اللغة والواجهة
// ------------------------------------------------------------------
class LanguageSettingsPage extends StatefulWidget {
  const LanguageSettingsPage({super.key});
  @override
  State<LanguageSettingsPage> createState() => _LanguageSettingsPageState();
}

class _LanguageSettingsPageState extends State<LanguageSettingsPage> {
  double _scale = blousabTextScale.value;

  @override
  Widget build(BuildContext context) => BlousabPage(
        title: 'اللغة والواجهة',
        child: ListView(padding: const EdgeInsets.fromLTRB(12, 4, 12, 20), children: [
          const BlousabSectionLabel('اللغة'),
          BlousabSettingsGroup(children: [
            BlousabSettingsRow(
              icon: Icons.language_rounded,
              title: 'العربية',
              subtitle: 'اللغة الوحيدة المتاحة حاليًا',
              showChevron: false,
              trailing: const Icon(Icons.check_circle_rounded, color: Color(0xFF3FD0FF)),
            ),
          ]),
          const BlousabSectionLabel('حجم النص في التطبيق'),
          Container(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
            decoration: blousabCardDecoration(radius: 18),
            child: Column(children: [
              Row(children: [
                const Expanded(child: Text('حجم النص', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800))),
                Text('${(_scale * 100).round()}%', style: const TextStyle(color: Colors.white)),
              ]),
              Slider(
                value: _scale,
                min: .85,
                max: 1.3,
                divisions: 9,
                onChanged: (v) => setState(() => _scale = v),
                onChangeEnd: (v) async {
                  blousabTextScale.value = v;
                  (await _p()).setDouble('blousab_ui_scale', v);
                },
              ),
            ]),
          ),
        ]),
      );
}

// ------------------------------------------------------------------
// قائمة المحظورين
// ------------------------------------------------------------------
class BlockedUsersPage extends StatefulWidget {
  const BlockedUsersPage({super.key});
  @override
  State<BlockedUsersPage> createState() => _BlockedUsersPageState();
}

class _BlockedUsersPageState extends State<BlockedUsersPage> {
  static const _prefix = 'blousab_blocked_peer_';
  List<String> _ids = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await _p();
    final ids = prefs.getKeys().where((k) => k.startsWith(_prefix) && (prefs.getBool(k) ?? false)).map((k) => k.substring(_prefix.length)).toList();
    if (mounted) setState(() { _ids = ids; _loading = false; });
  }

  Future<void> _unblock(String id) async {
    final prefs = await _p();
    await prefs.setBool('$_prefix$id', false);
    await _load();
  }

  @override
  Widget build(BuildContext context) => BlousabPage(
        title: 'قائمة المحظورين',
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _ids.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(26),
                      child: Text('لا يوجد مستخدمون محظورون. يمكنك حظر مستخدم من داخل المحادثة.', textAlign: TextAlign.center, style: TextStyle(color: Colors.white)),
                    ),
                  )
                : ListView(padding: const EdgeInsets.fromLTRB(12, 4, 12, 20), children: [
                    BlousabSettingsGroup(children: [
                      for (final id in _ids)
                        BlousabSettingsRow(
                          icon: Icons.block_rounded,
                          iconColor: const Color(0xFFFF3B4E),
                          title: 'مستخدم محظور',
                          subtitle: id,
                          showChevron: false,
                          trailing: TextButton(onPressed: () => _unblock(id), child: const Text('إلغاء الحظر')),
                        ),
                    ]),
                  ]),
      );
}
