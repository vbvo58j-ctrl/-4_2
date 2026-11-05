import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/blousab_ai_service.dart';
import '../widgets/blousab_page.dart';
import '../widgets/blousab_visuals.dart';

/// أيقونة Blousab AI: شعار B مقصوص دون النص + شارة AI صغيرة في الأسفل.
class BlousabAiAvatar extends StatelessWidget {
  const BlousabAiAvatar({super.key, this.size = 58, this.dimmed = false});
  final double size;
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    final badgeW = size * .46;
    return Opacity(
      opacity: dimmed ? .5 : 1,
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(clipBehavior: Clip.none, alignment: Alignment.center, children: [
          BlousabRingAvatar(
            name: 'ب',
            size: size,
            ring: 2.5,
            child: Container(
              color: const Color(0xFF02050F),
              child: Image.asset(
                'assets/branding/blousab_b_mark.png',
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const Center(
                  child: Text('B', style: TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w900)),
                ),
              ),
            ),
          ),
          Positioned(
            bottom: -size * .04,
            child: Container(
              width: badgeW,
              height: size * .27,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(size * .09),
                gradient: const LinearGradient(colors: [Color(0xFF2D8CFF), Color(0xFFB238FF)]),
                border: Border.all(color: const Color(0xFF050916), width: 1.6),
                boxShadow: const [BoxShadow(color: Color(0x882D8CFF), blurRadius: 6)],
              ),
              child: Text('AI',
                  style: TextStyle(color: Colors.white, fontSize: size * .17, fontWeight: FontWeight.w900, height: 1)),
            ),
          ),
        ]),
      ),
    );
  }
}

class BlousabAiScreen extends StatefulWidget {
  const BlousabAiScreen({super.key});
  @override
  State<BlousabAiScreen> createState() => _BlousabAiScreenState();
}

class _BlousabAiScreenState extends State<BlousabAiScreen> {
  static const _chatKey = 'blousab_ai_chat_v1';
  final BlousabAiService _service = BlousabAiService.instance;
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();
  final List<Map<String, String>> _messages = <Map<String, String>>[];
  bool _thinking = false;

  @override
  void initState() {
    super.initState();
    _service.load();
    _loadChat();
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _loadChat() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_chatKey) ?? const <String>[];
    final loaded = <Map<String, String>>[];
    for (final item in raw) {
      try {
        final map = jsonDecode(item) as Map;
        loaded.add({'role': map['role'].toString(), 'text': map['text'].toString()});
      } catch (_) {}
    }
    if (mounted) setState(() => _messages..clear()..addAll(loaded));
  }

  Future<void> _saveChat() async {
    final prefs = await SharedPreferences.getInstance();
    final tail = _messages.length > 100 ? _messages.sublist(_messages.length - 100) : _messages;
    await prefs.setStringList(_chatKey, tail.map(jsonEncode).toList());
  }

  void _toast(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _info(String title, String body) => showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(title),
          content: Text(body),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('حسنًا'))],
        ),
      );

  Future<BlousabAiTier?> _pickTier() async {
    var selected = blousabAiTiers[1];
    return showModalBottomSheet<BlousabAiTier>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('اختر حجم نموذج Blousab AI',
                  style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              const Text('اختر ما يناسب ذاكرة جهازك. يُحمَّل النموذج مرة واحدة ثم يعمل دون إنترنت.',
                  style: TextStyle(fontSize: 13)),
              const SizedBox(height: 10),
              ...blousabAiTiers.map((tier) => RadioListTile<String>(
                    value: tier.id,
                    groupValue: selected.id,
                    onChanged: (_) => setSheet(() => selected = tier),
                    title: Text('${tier.label} — ${tier.sizeLabel} تقريبًا', style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text(tier.description),
                  )),
              const SizedBox(height: 4),
              const Text('الأحجام تقريبية وليست نهائية؛ الحجم الفعلي واستهلاك الذاكرة يعتمدان على النموذج وإعدادات التشغيل.',
                  style: TextStyle(fontSize: 12)),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء'))),
                const SizedBox(width: 10),
                Expanded(child: FilledButton(onPressed: () => Navigator.pop(ctx, selected), child: const Text('موافق'))),
              ]),
            ]),
          ),
        ),
      ),
    );
  }

  Future<void> _startDownloadFlow() async {
    final tier = await _pickTier();
    if (tier == null || !mounted) return;

    final check = await _service.checkResources(tier);
    if (!mounted) return;
    if (check.warning != null) {
      if (check.blocking) {
        await _info('لا يمكن بدء التنزيل', check.warning!);
        return;
      }
      final proceed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('تنبيه الذاكرة'),
          content: Text(check.warning!),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('اختيار حجم آخر')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('متابعة رغم ذلك')),
          ],
        ),
      );
      if (proceed != true) return;
    }

    if (!_service.tierHasSource(tier)) {
      await _info('مصدر النموذج غير مضبوط',
          'لم يُحدَّد رابط تنزيل للنموذج «${tier.label}» في هذا الإصدار، لذلك لن يبدأ أي تنزيل. أضف رابط الملف وبصمته (SHA-256) في lib/services/blousab_ai_service.dart ثم أعد البناء.');
      return;
    }

    try {
      await _service.downloadAndActivate(tier);
      _toast('اكتمل التحميل والتحقق. Blousab AI جاهز.');
    } on BlousabAiCancelled {
      _toast('تم إلغاء التحميل.');
    } catch (e) {
      if (mounted) await _info('تعذر إكمال التحميل', e.toString());
    }
  }

  Future<void> _changeOrDelete(String action) async {
    if (action == 'delete') {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('حذف النموذج؟'),
          content: const Text('سيُحذف ملف النموذج من هذا الهاتف وتعود المحادثة إلى حالة «غير محمّل». يمكنك إعادة تحميل أي حجم لاحقًا.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('حذف')),
          ],
        ),
      );
      if (ok == true) {
        await _service.deleteModel();
        _toast('تم حذف النموذج.');
      }
    } else if (action == 'change') {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('تغيير النموذج'),
          content: const Text('سيُحذف النموذج الحالي ثم تختار حجمًا آخر لتحميله.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('متابعة')),
          ],
        ),
      );
      if (ok == true) {
        await _service.deleteModel();
        if (mounted) await _startDownloadFlow();
      }
    } else if (action == 'clear') {
      setState(() => _messages.clear());
      await _saveChat();
    }
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _thinking) return;
    _input.clear();
    setState(() {
      _messages.add({'role': 'user', 'text': text});
      _thinking = true;
    });
    _scrollDown();
    String answer;
    try {
      answer = await _service.reply(text, List<Map<String, String>>.from(_messages));
    } catch (e) {
      answer = 'تعذر توليد الرد: $e';
    }
    if (!mounted) return;
    setState(() {
      _messages.add({'role': 'ai', 'text': answer});
      _thinking = false;
    });
    await _saveChat();
    _scrollDown();
  }

  void _scrollDown() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent + 80, duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
      }
    });
  }

  // ---------------------------------------------------------------- views
  Widget _notLoadedView() => Opacity(
        opacity: .85,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(22),
            child: Container(
              padding: const EdgeInsets.all(22),
              decoration: blousabCardDecoration(radius: 22),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const BlousabAiAvatar(size: 92, dimmed: true),
                const SizedBox(height: 14),
                const Text('Blousab AI', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                const Text('مساعد الذكاء الاصطناعي المحلي', style: TextStyle(color: Color(0xFFC6D0F2))),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFFFF9A1F)),
                  ),
                  child: const Text('غير محمّل', style: TextStyle(color: Color(0xFFFFB866), fontWeight: FontWeight.w700)),
                ),
                const SizedBox(height: 14),
                const Text('هذه المحادثة غير مفعّلة حتى تحميل نموذج الذكاء الاصطناعي.',
                    textAlign: TextAlign.center, style: TextStyle(color: Colors.white)),
                const SizedBox(height: 18),
                BlousabPrimaryButton(label: 'اضغط هنا لتحميل Blousab AI', icon: Icons.download_rounded, onTap: _startDownloadFlow),
              ]),
            ),
          ),
        ),
      );

  Widget _downloadingView() => Center(
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Container(
            padding: const EdgeInsets.all(22),
            decoration: blousabCardDecoration(radius: 22),
            child: ValueListenableBuilder<double>(
              valueListenable: _service.progress,
              builder: (context, value, _) => Column(mainAxisSize: MainAxisSize.min, children: [
                const BlousabAiAvatar(size: 84),
                const SizedBox(height: 14),
                Text('جارٍ تحميل Blousab AI  ${(value * 100).round()}%',
                    style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(value: value <= 0 ? null : value, minHeight: 9),
                ),
                const SizedBox(height: 8),
                ValueListenableBuilder<String>(
                  valueListenable: _service.progressText,
                  builder: (_, text, __) => Text(text, style: const TextStyle(color: Color(0xFFC6D0F2), fontSize: 13)),
                ),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: _service.cancelDownload,
                  icon: const Icon(Icons.close_rounded),
                  label: const Text('إلغاء التحميل'),
                ),
              ]),
            ),
          ),
        ),
      );

  Widget _bubble(Map<String, String> m) {
    final mine = m['role'] == 'user';
    return Align(
      alignment: mine ? AlignmentDirectional.centerEnd : AlignmentDirectional.centerStart,
      child: Container(
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * .78),
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: mine ? const LinearGradient(colors: [Color(0xFF1B6BFF), Color(0xFF6B3BFF)]) : null,
          color: mine ? null : const Color(0xFF0C1740),
          border: Border.all(color: mine ? const Color(0xFF3FA2FF) : const Color(0xFF2B48A8)),
        ),
        child: SelectableText(m['text'] ?? '', style: const TextStyle(color: Colors.white, fontSize: 15.5, height: 1.4)),
      ),
    );
  }

  Widget _chatView() => Column(children: [
        Expanded(
          child: _messages.isEmpty && !_thinking
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('اكتب سؤالك لبدء المحادثة. تتم المعالجة على هاتفك دون إنترنت.',
                        textAlign: TextAlign.center, style: TextStyle(color: Color(0xFFC6D0F2))),
                  ),
                )
              : ListView(
                  controller: _scroll,
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                  children: [
                    ..._messages.map(_bubble),
                    if (_thinking)
                      const Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: Padding(
                          padding: EdgeInsets.all(8),
                          child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4)),
                        ),
                      ),
                  ],
                ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 4, 10, 10),
          child: Row(children: [
            Expanded(
              child: TextField(
                controller: _input,
                minLines: 1,
                maxLines: 4,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _send(),
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'اسأل Blousab AI…',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(22)),
                  enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(22), borderSide: const BorderSide(color: Color(0xFF3858BD))),
                ),
              ),
            ),
            const SizedBox(width: 8),
            BlousabSquareIconButton(icon: Icons.send_rounded, size: 46, tooltip: 'إرسال', onTap: _thinking ? null : _send),
          ]),
        ),
      ]);

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<BlousabAiStatus>(
        valueListenable: _service.status,
        builder: (context, status, _) => BlousabPage(
          title: 'Blousab AI',
          actions: [
            if (status == BlousabAiStatus.ready)
              PopupMenuButton<String>(
                tooltip: 'خيارات',
                icon: const Icon(Icons.more_vert_rounded, color: Color(0xFF28C7FF), size: 30),
                onSelected: _changeOrDelete,
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'clear', child: Text('مسح المحادثة')),
                  PopupMenuItem(value: 'change', child: Text('تغيير النموذج')),
                  PopupMenuItem(value: 'delete', child: Text('حذف النموذج')),
                ],
              )
            else
              const SizedBox(width: 38),
          ],
          child: switch (status) {
            BlousabAiStatus.ready => _chatView(),
            BlousabAiStatus.downloading => _downloadingView(),
            BlousabAiStatus.notLoaded => _notLoadedView(),
          },
        ),
      );
}
