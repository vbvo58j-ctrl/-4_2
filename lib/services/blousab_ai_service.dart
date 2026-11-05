import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// حجم نموذج Blousab AI. الأحجام تقريبية وليست مواصفات نهائية؛ الحجم الفعلي
/// واستهلاك الذاكرة يعتمدان على النموذج وإعدادات التشغيل.
class BlousabAiTier {
  const BlousabAiTier({
    required this.id,
    required this.label,
    required this.approxGb,
    required this.description,
    this.downloadUrl = '',
    this.sha256Hex = '',
  });

  final String id;
  final String label;
  final double approxGb;
  final String description;

  /// رابط ملف النموذج لهذا الحجم. اتركه فارغًا حتى تحدد مصدر النموذج؛
  /// عندها يعرض التطبيق رسالة واضحة بدل أن يبدأ تنزيلًا وهميًا.
  final String downloadUrl;

  /// بصمة SHA-256 المتوقعة للملف (للتحقق من سلامته بعد التنزيل).
  final String sha256Hex;

  int get approxBytes => (approxGb * 1024 * 1024 * 1024).round();
  String get sizeLabel => approxGb < 1 ? '${(approxGb * 1024).round()} MB' : '${approxGb.toStringAsFixed(approxGb == approxGb.roundToDouble() ? 0 : 1)} GB';
}

/// ⚙️ إعداد مصادر النماذج: ضع روابط التنزيل والبصمات هنا.
const List<BlousabAiTier> blousabAiTiers = <BlousabAiTier>[
  BlousabAiTier(id: 'light', label: 'خفيف', approxGb: 0.5, description: 'أخف استهلاكًا، مناسب للأجهزة محدودة الذاكرة'),
  BlousabAiTier(id: 'medium', label: 'متوسط', approxGb: 1, description: 'توازن جيد بين السرعة والجودة'),
  BlousabAiTier(id: 'balanced', label: 'متوازن', approxGb: 2, description: 'إجابات أفضل مع استهلاك ذاكرة أعلى'),
  BlousabAiTier(id: 'advanced', label: 'متقدم', approxGb: 3, description: 'أعلى جودة، للأجهزة ذات الذاكرة الكبيرة'),
];

enum BlousabAiStatus { notLoaded, downloading, ready }

class BlousabAiMemoryInfo {
  const BlousabAiMemoryInfo({required this.totalRam, required this.availRam, required this.freeStorage});
  final int totalRam;
  final int availRam;
  final int freeStorage;
}

/// واجهة محرك التشغيل المحلي. اربط هنا مكتبة الاستدلال (مثل llama.cpp أو
/// MediaPipe LLM) عبر [BlousabAiService.engine]. إلى أن يُربط محرك،
/// تُعيد المحادثة رسالة توضيحية بدل ردود مختلَقة.
abstract class BlousabAiEngine {
  Future<void> load(String modelPath);
  Future<String> reply(String prompt, {List<Map<String, String>> history});
  Future<void> dispose();
}

class BlousabAiCancelled implements Exception {
  @override
  String toString() => 'تم إلغاء التحميل';
}

class BlousabAiService {
  BlousabAiService._();
  static final BlousabAiService instance = BlousabAiService._();

  static const _channel = MethodChannel('com.blousab.messenger/device_info');
  static const _kStatus = 'blousab_ai_status_v1';
  static const _kTier = 'blousab_ai_tier_v1';
  static const _kPath = 'blousab_ai_model_path_v1';

  /// يُضبط عند ربط محرك استدلال حقيقي.
  BlousabAiEngine? engine;

  final ValueNotifier<BlousabAiStatus> status = ValueNotifier<BlousabAiStatus>(BlousabAiStatus.notLoaded);
  final ValueNotifier<double> progress = ValueNotifier<double>(0);
  final ValueNotifier<String> progressText = ValueNotifier<String>('');
  String tierId = '';
  String modelPath = '';

  HttpClient? _client;
  bool _cancelRequested = false;
  bool _loadedOnce = false;

  BlousabAiTier? get currentTier {
    for (final t in blousabAiTiers) {
      if (t.id == tierId) return t;
    }
    return null;
  }

  Future<void> load() async {
    if (_loadedOnce) return;
    _loadedOnce = true;
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_kStatus) ?? 'notLoaded';
    tierId = prefs.getString(_kTier) ?? '';
    modelPath = prefs.getString(_kPath) ?? '';
    if (saved == 'ready' && modelPath.isNotEmpty && await File(modelPath).exists()) {
      status.value = BlousabAiStatus.ready;
    } else {
      // لا يوجد نموذج مكتمل (أو حُذف الملف): تعود المحادثة لوضع غير مفعّل.
      status.value = BlousabAiStatus.notLoaded;
      await prefs.setString(_kStatus, 'notLoaded');
    }
  }

  Future<BlousabAiMemoryInfo?> memoryInfo() async {
    try {
      final map = await _channel.invokeMapMethod<String, dynamic>('memoryInfo');
      if (map == null) return null;
      return BlousabAiMemoryInfo(
        totalRam: (map['totalRam'] as num?)?.toInt() ?? 0,
        availRam: (map['availRam'] as num?)?.toInt() ?? 0,
        freeStorage: (map['freeStorage'] as num?)?.toInt() ?? 0,
      );
    } catch (_) {
      return null;
    }
  }

  /// يعيد نصًا تحذيريًا إن كانت الموارد غير كافية، أو null إن كانت كافية.
  /// [blocking] تصبح true عندما لا تكفي مساحة التخزين (لا يمكن المتابعة).
  Future<({String? warning, bool blocking})> checkResources(BlousabAiTier tier) async {
    final info = await memoryInfo();
    if (info == null) return (warning: null, blocking: false);
    if (info.freeStorage > 0 && info.freeStorage < (tier.approxBytes * 1.15)) {
      return (warning: 'مساحة التخزين الحرة غير كافية لتنزيل النموذج «${tier.label}» (${tier.sizeLabel}).', blocking: true);
    }
    // تقدير حذر: يحتاج التشغيل إلى ذاكرة أكبر من حجم الملف.
    if (info.totalRam > 0 && info.totalRam < tier.approxBytes * 2.5) {
      return (
        warning: 'ذاكرة الجهاز (${(info.totalRam / 1073741824).toStringAsFixed(1)} GB) قد لا تكفي لتشغيل النموذج «${tier.label}» بسلاسة. يُنصح باختيار حجم أصغر.',
        blocking: false,
      );
    }
    return (warning: null, blocking: false);
  }

  Future<File> _targetFile(BlousabAiTier tier) async {
    final dir = await getApplicationSupportDirectory();
    final folder = Directory('${dir.path}/blousab_ai');
    if (!await folder.exists()) await folder.create(recursive: true);
    return File('${folder.path}/model_${tier.id}.bin');
  }

  bool tierHasSource(BlousabAiTier tier) => tier.downloadUrl.trim().isNotEmpty;

  /// ينزّل النموذج مع نسبة التقدم، ثم يتحقق من سلامة الملف (SHA-256) قبل التفعيل.
  Future<void> downloadAndActivate(BlousabAiTier tier) async {
    if (status.value == BlousabAiStatus.downloading) return;
    if (!tierHasSource(tier)) {
      throw StateError('لم يُضبط مصدر تنزيل لهذا الحجم بعد. أضف الرابط والبصمة في blousab_ai_service.dart.');
    }
    _cancelRequested = false;
    progress.value = 0;
    progressText.value = 'جارٍ الاتصال…';
    status.value = BlousabAiStatus.downloading;
    final target = await _targetFile(tier);
    final partial = File('${target.path}.part');
    try {
      final client = HttpClient()..connectionTimeout = const Duration(seconds: 20);
      _client = client;
      final request = await client.getUrl(Uri.parse(tier.downloadUrl));
      final response = await request.close();
      if (response.statusCode != 200) {
        throw HttpException('تعذر التنزيل (رمز ${response.statusCode})');
      }
      final total = response.contentLength > 0 ? response.contentLength : tier.approxBytes;
      final sink = partial.openWrite();
      var received = 0;
      try {
        await for (final chunk in response) {
          if (_cancelRequested) throw BlousabAiCancelled();
          sink.add(chunk);
          received += chunk.length;
          progress.value = (received / total).clamp(0.0, 1.0).toDouble();
          progressText.value = '${(received / 1048576).toStringAsFixed(0)} MB من ${(total / 1048576).toStringAsFixed(0)} MB';
        }
        await sink.flush();
      } finally {
        await sink.close();
      }
      if (_cancelRequested) throw BlousabAiCancelled();

      progressText.value = 'جارٍ التحقق من سلامة الملف…';
      final expected = tier.sha256Hex.trim().toLowerCase();
      if (expected.isNotEmpty) {
        final digest = await sha256.bind(partial.openRead()).first;
        if (digest.toString().toLowerCase() != expected) {
          throw const FormatException('فشل التحقق من سلامة الملف. أُلغي التحميل.');
        }
      } else {
        throw const FormatException('لا توجد بصمة تحقق لهذا النموذج، لذلك لن يُفعَّل.');
      }
      if (await target.exists()) await target.delete();
      await partial.rename(target.path);

      final prefs = await SharedPreferences.getInstance();
      tierId = tier.id;
      modelPath = target.path;
      await prefs.setString(_kTier, tierId);
      await prefs.setString(_kPath, modelPath);
      await prefs.setString(_kStatus, 'ready');
      try {
        await engine?.load(modelPath);
      } catch (_) {}
      progress.value = 1;
      status.value = BlousabAiStatus.ready;
    } catch (e) {
      try {
        if (await partial.exists()) await partial.delete();
      } catch (_) {}
      status.value = BlousabAiStatus.notLoaded;
      if (_cancelRequested || e is BlousabAiCancelled) throw BlousabAiCancelled();
      rethrow;
    } finally {
      _client?.close(force: true);
      _client = null;
    }
  }

  void cancelDownload() {
    _cancelRequested = true;
    try {
      _client?.close(force: true);
    } catch (_) {}
  }

  /// يحذف النموذج الحالي ويعيد المحادثة إلى حالة «غير محمّل».
  Future<void> deleteModel() async {
    try {
      await engine?.dispose();
    } catch (_) {}
    if (modelPath.isNotEmpty) {
      try {
        final f = File(modelPath);
        if (await f.exists()) await f.delete();
      } catch (_) {}
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kStatus, 'notLoaded');
    await prefs.remove(_kPath);
    await prefs.remove(_kTier);
    modelPath = '';
    tierId = '';
    status.value = BlousabAiStatus.notLoaded;
  }

  Future<String> reply(String prompt, List<Map<String, String>> history) async {
    final e = engine;
    if (e == null) {
      return 'تم تحميل النموذج وحفظه على هذا الهاتف، لكن محرك التشغيل المحلي لم يُربط بعد في هذا الإصدار، لذلك لا أستطيع توليد ردود الآن.';
    }
    return e.reply(prompt, history: history);
  }
}
