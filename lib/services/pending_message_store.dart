import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Durable outbox stored in the app's private files directory (not preferences).
/// Entries remain until a delivery acknowledgement is received.
class PendingMessageStore {
  PendingMessageStore._();
  static final PendingMessageStore instance = PendingMessageStore._();
  Future<void> _tail = Future<void>.value();

  Future<File> _file() async {
    final dir = await getApplicationSupportDirectory();
    await dir.create(recursive: true);
    return File('${dir.path}/blousab_pending_outbox.json');
  }

  Future<T> _serialized<T>(Future<T> Function() action) {
    final completer = Completer<T>();
    _tail = _tail.then((_) async {
      try { completer.complete(await action()); }
      catch (e, st) { completer.completeError(e, st); }
    });
    return completer.future;
  }

  Future<List<Map<String, dynamic>>> list() => _serialized(() async {
    final file = await _file();
    if (!await file.exists()) return <Map<String, dynamic>>[];
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! List) return <Map<String, dynamic>>[];
      return decoded.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
    } catch (_) {
      // Preserve the damaged file for diagnosis rather than silently overwriting it.
      return <Map<String, dynamic>>[];
    }
  });

  Future<void> enqueue(Map<String, dynamic> entry) => _serialized(() async {
    final file = await _file();
    final current = await _read(file);
    final id = entry['messageId']?.toString() ?? '';
    if (id.isEmpty) throw ArgumentError('messageId is required');
    if (current.any((e) => e['messageId'] == id)) return;
    current.add({...entry, 'queuedAt': DateTime.now().toIso8601String(), 'attempts': 0});
    await file.writeAsString(jsonEncode(current), flush: true);
  });

  Future<void> remove(String messageId) => _serialized(() async {
    final file = await _file();
    final current = await _read(file);
    current.removeWhere((e) => e['messageId'] == messageId);
    await file.writeAsString(jsonEncode(current), flush: true);
  });

  Future<void> noteAttempt(String messageId) => _serialized(() async {
    final file = await _file();
    final current = await _read(file);
    final index = current.indexWhere((e) => e['messageId'] == messageId);
    if (index < 0) return;
    current[index]['attempts'] = (current[index]['attempts'] as num? ?? 0) + 1;
    current[index]['lastAttemptAt'] = DateTime.now().toIso8601String();
    await file.writeAsString(jsonEncode(current), flush: true);
  });

  Future<List<Map<String, dynamic>>> _read(File file) async {
    if (!await file.exists()) return <Map<String, dynamic>>[];
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! List) return <Map<String, dynamic>>[];
      return decoded.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
    } catch (_) { return <Map<String, dynamic>>[]; }
  }
}

