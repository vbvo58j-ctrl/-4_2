import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../services/local_network_service.dart';
import '../widgets/blousab_page.dart';
import '../widgets/blousab_visuals.dart';

/// رمز QR حقيقي للحساب + ماسح كاميرا لإضافة الأصدقاء.
/// الصيغة: blousab://add?id=<المعرّف>&name=<الاسم>
class BlousabQrScreen extends StatefulWidget {
  const BlousabQrScreen({super.key, required this.userId, required this.userName, this.startOnScan = false});
  final String userId;
  final String userName;
  final bool startOnScan;

  static String buildPayload(String id, String name) =>
      Uri(scheme: 'blousab', host: 'add', queryParameters: {'id': id, 'name': name}).toString();

  @override
  State<BlousabQrScreen> createState() => _BlousabQrScreenState();
}

class _BlousabQrScreenState extends State<BlousabQrScreen> {
  late int _tab = widget.startOnScan ? 1 : 0;

  Widget _tabButton(int index, IconData icon, String label) {
    final selected = _tab == index;
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => _tab = index),
        child: Container(
          height: 46,
          margin: const EdgeInsets.all(3),
          decoration: selected
              ? BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  gradient: const LinearGradient(colors: [Color(0xFF0F4DD8), Color(0xFF1B2F9A)]),
                  border: Border.all(color: const Color(0xFF3FA2FF), width: 1.4),
                  boxShadow: const [BoxShadow(color: Color(0x883FA2FF), blurRadius: 10)],
                )
              : null,
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon, color: selected ? const Color(0xFF3FD0FF) : const Color(0xFF8FB2FF), size: 22),
            const SizedBox(width: 6),
            Text(label,
                style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: selected ? FontWeight.w800 : FontWeight.w600)),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => BlousabPage(
        title: 'رمز QR',
        child: Column(children: [
          Container(
            height: 54,
            margin: const EdgeInsets.fromLTRB(14, 4, 14, 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              color: const Color(0xFF070F2C),
              border: Border.all(color: const Color(0xFF5A3BFF), width: 1.4),
              boxShadow: const [BoxShadow(color: Color(0x665A3BFF), blurRadius: 10)],
            ),
            child: Row(children: [
              _tabButton(0, Icons.qr_code_2_rounded, 'رمزي'),
              _tabButton(1, Icons.qr_code_scanner_rounded, 'مسح رمز'),
            ]),
          ),
          Expanded(
            child: _tab == 0
                ? _MyCodeView(userId: widget.userId, userName: widget.userName)
                : _ScanView(userId: widget.userId, userName: widget.userName),
          ),
        ]),
      );
}

class _MyCodeView extends StatelessWidget {
  const _MyCodeView({required this.userId, required this.userName});
  final String userId;
  final String userName;

  @override
  Widget build(BuildContext context) {
    if (userId.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('لم يُنشأ معرّف حسابك بعد. افتح بلوساب مرة أخرى وانتظر لحظات ثم أعد المحاولة.',
              textAlign: TextAlign.center, style: TextStyle(color: Colors.white)),
        ),
      );
    }
    final payload = BlousabQrScreen.buildPayload(userId, userName);
    return ListView(padding: const EdgeInsets.fromLTRB(18, 6, 18, 20), children: [
      Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: const LinearGradient(colors: [Color(0xFF0B1A55), Color(0xFF1A0E47)]),
          border: Border.all(color: const Color(0xFF8E45FF), width: 1.4),
          boxShadow: const [BoxShadow(color: Color(0x668E45FF), blurRadius: 14)],
        ),
        child: Column(children: [
          Text(userName.isEmpty ? 'مستخدم بلوساب' : userName,
              style: const TextStyle(color: Colors.white, fontSize: 21, fontWeight: FontWeight.w800)),
          const SizedBox(height: 14),
          BlousabKeepColors(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
              child: QrImageView(
                data: payload,
                version: QrVersions.auto,
                size: 230,
                backgroundColor: Colors.white,
                errorCorrectionLevel: QrErrorCorrectLevel.M,
              ),
            ),
          ),
          const SizedBox(height: 14),
          const Text('دع صديقك يمسح هذا الرمز من «مسح رمز» لإرسال طلب صداقة إليك.',
              textAlign: TextAlign.center, style: TextStyle(color: Color(0xFFC6D0F2), fontSize: 13.5)),
        ]),
      ),
      const SizedBox(height: 14),
      BlousabSettingsGroup(children: [
        BlousabSettingsRow(
          icon: Icons.copy_rounded,
          iconColor: const Color(0xFFB46CFF),
          title: 'نسخ معرّف الحساب',
          subtitle: userId,
          onTap: () async {
            await Clipboard.setData(ClipboardData(text: userId));
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم نسخ المعرّف.')));
            }
          },
        ),
      ]),
    ]);
  }
}

class _ScanView extends StatefulWidget {
  const _ScanView({required this.userId, required this.userName});
  final String userId;
  final String userName;
  @override
  State<_ScanView> createState() => _ScanViewState();
}

class _ScanViewState extends State<_ScanView> {
  final MobileScannerController _controller = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
    detectionSpeed: DetectionSpeed.noDuplicates,
  );
  bool _handling = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _toast(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_handling) return;
    String? raw;
    for (final barcode in capture.barcodes) {
      if (barcode.rawValue != null && barcode.rawValue!.isNotEmpty) {
        raw = barcode.rawValue;
        break;
      }
    }
    if (raw == null) return;
    _handling = true;
    try {
      final uri = Uri.tryParse(raw);
      if (uri == null || uri.scheme != 'blousab' || uri.host != 'add') {
        _toast('هذا الرمز ليس رمز حساب بلوساب.');
        await Future<void>.delayed(const Duration(seconds: 2));
        return;
      }
      final id = uri.queryParameters['id']?.trim() ?? '';
      final name = (uri.queryParameters['name']?.trim().isNotEmpty ?? false) ? uri.queryParameters['name']!.trim() : 'مستخدم بلوساب';
      if (id.isEmpty) {
        _toast('رمز غير صالح.');
        await Future<void>.delayed(const Duration(seconds: 2));
        return;
      }
      if (id == widget.userId) {
        _toast('هذا رمز حسابك أنت.');
        await Future<void>.delayed(const Duration(seconds: 2));
        return;
      }
      await _controller.stop();
      if (!mounted) return;
      final send = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('إضافة صديق'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            BlousabRingAvatar(name: name, size: 64),
            const SizedBox(height: 10),
            Text(name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(id, style: const TextStyle(fontSize: 11), textDirection: TextDirection.ltr),
            const SizedBox(height: 10),
            const Text('سيُرسل طلب صداقة عبر الشبكة المحلية. لن تُفتح المحادثة قبل الموافقة.',
                textAlign: TextAlign.center, style: TextStyle(fontSize: 12.5)),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('إرسال الطلب')),
          ],
        ),
      );
      if (send == true) {
        final packet = jsonEncode({
          'type': 'friend_request',
          'requestId': '${widget.userId}_${DateTime.now().microsecondsSinceEpoch}',
          'senderId': widget.userId,
          'senderName': widget.userName,
          'recipientId': id,
          'createdAt': DateTime.now().millisecondsSinceEpoch,
        });
        try {
          if (!LocalNetworkService.instance.isRunning) throw StateError('no network');
          await LocalNetworkService.instance.broadcastMessage(packet);
          _toast('أُرسل طلب الصداقة إلى $name. سيظهر عنده عند اتصاله بالشبكة نفسها.');
        } catch (_) {
          _toast('تعذر إرسال الطلب الآن. يجب أن يكون الجهازان على الشبكة المحلية نفسها.');
        }
      }
      if (mounted) await _controller.start();
    } finally {
      _handling = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 16),
      child: Column(children: [
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: const Color(0xFF3F7BFF), width: 1.8),
              boxShadow: const [BoxShadow(color: Color(0x774F7BFF), blurRadius: 14)],
            ),
            clipBehavior: Clip.antiAlias,
            child: BlousabKeepColors(
              child: MobileScanner(
                controller: _controller,
                onDetect: _onDetect,
                errorBuilder: (context, error, child) => Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.no_photography_outlined, color: Colors.white70, size: 52),
                      const SizedBox(height: 12),
                      const Text('تعذر تشغيل الكاميرا. تأكد من منح بلوساب إذن الكاميرا من إعدادات أندرويد.',
                          textAlign: TextAlign.center, style: TextStyle(color: Colors.white)),
                    ]),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        const Text('وجّه الكاميرا نحو رمز QR الخاص بصديقك.',
            style: TextStyle(color: Color(0xFFC6D0F2), fontSize: 14)),
      ]),
    );
  }
}
