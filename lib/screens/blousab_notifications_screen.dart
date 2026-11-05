import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../widgets/blousab_page.dart';
import '../widgets/blousab_visuals.dart';

/// In-app local notification history. The list contains only observed incoming
/// events, never sample/fabricated notifications or message plaintext.
class BlousabNotificationsScreen extends StatefulWidget {
  const BlousabNotificationsScreen({super.key});
  @override
  State<BlousabNotificationsScreen> createState() => _BlousabNotificationsScreenState();
}

class _BlousabNotificationsScreenState extends State<BlousabNotificationsScreen> {
  static const _enabledKey = 'blousab_notifications_enabled';
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  bool _enabled = true;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final prefs = await SharedPreferences.getInstance();
    final rows = prefs.getStringList('blousab_notifications_v1') ?? [];
    final loaded = <Map<String, dynamic>>[];
    for (final row in rows) {
      try {
        final json = jsonDecode(row);
        if (json is Map) loaded.add(Map<String, dynamic>.from(json));
      } catch (_) {}
    }
    if (mounted) {
      setState(() {
        _items = loaded;
        _enabled = prefs.getBool(_enabledKey) ?? true;
        _loading = false;
      });
    }
  }

  Future<void> _setEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledKey, value);
    if (mounted) setState(() => _enabled = value);
  }

  Future<void> _clear() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('مسح سجل الإشعارات؟'),
        content: const Text('سيُمسح سجل الإشعارات المحلي فقط؛ ستبقى الرسائل والمحادثات محفوظة.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('مسح السجل')),
        ],
      ),
    );
    if (ok != true) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('blousab_notifications_v1');
    await _refresh();
  }

  String _stamp(String raw) {
    final at = DateTime.tryParse(raw);
    if (at == null) return '';
    final local = at.toLocal();
    return '${local.day}/${local.month}  ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }

  Widget _empty() => Center(
        child: Padding(
          padding: const EdgeInsets.all(25),
          child: Column(mainAxisSize: MainAxisSize.min, children: const [
            Icon(Icons.notifications_none_rounded, size: 64, color: Color(0xFF3FA2FF)),
            SizedBox(height: 12),
            Text('لا توجد إشعارات بعد', style: TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w800)),
            SizedBox(height: 7),
            Text('ستظهر هنا الرسائل الواردة التي رصدها التطبيق أثناء تشغيله.',
                textAlign: TextAlign.center, style: TextStyle(color: Color(0xFFC6D0F2))),
          ]),
        ),
      );

  Widget _tile(Map<String, dynamic> item) {
    final sender = item['sender']?.toString() ?? 'مستخدم بلوساب';
    final isFile = item['type'] == 'file';
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: blousabCardDecoration(radius: 18),
      child: Row(children: [
        BlousabRingAvatar(name: sender, size: 50, ring: 2.3),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(sender,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
            const SizedBox(height: 3),
            Row(children: [
              Icon(isFile ? Icons.attach_file_rounded : Icons.chat_bubble_outline_rounded, size: 15, color: const Color(0xFF3FA2FF)),
              const SizedBox(width: 5),
              Flexible(
                child: Text(isFile ? 'ملف وارد عبر بلوساب' : 'رسالة واردة عبر بلوساب',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Color(0xFFC6D0F2), fontSize: 13.5)),
              ),
            ]),
          ]),
        ),
        Text(_stamp(item['at']?.toString() ?? ''), style: const TextStyle(color: Color(0xFFA3B5DE), fontSize: 12)),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) => BlousabPage(
        title: 'الإشعارات',
        actions: [
          BlousabSquareIconButton(icon: Icons.refresh_rounded, tooltip: 'تحديث', onTap: _refresh),
          const SizedBox(width: 6),
          BlousabSquareIconButton(
            icon: Icons.delete_outline_rounded,
            tooltip: 'مسح السجل',
            color: const Color(0xFFFF6B8B),
            onTap: _items.isEmpty ? null : _clear,
          ),
        ],
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(padding: const EdgeInsets.fromLTRB(12, 4, 12, 16), children: [
                BlousabSettingsGroup(children: [
                  BlousabSwitchRow(
                    icon: Icons.notifications_active_rounded,
                    title: 'إشعارات الرسائل',
                    subtitle: 'إظهار تنبيه عند وصول رسالة أو ملف جديد',
                    value: _enabled,
                    onChanged: _setEnabled,
                  ),
                ]),
                const SizedBox(height: 14),
                if (_items.isEmpty) SizedBox(height: 360, child: _empty()) else ..._items.map(_tile),
              ]),
      );
}
