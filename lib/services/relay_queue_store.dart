import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

/// Durable, bounded store for relay packets and IDs already seen by this device.
/// It stores opaque payloads; end-to-end encryption must be applied by the sender.
class RelayQueueStore {
  RelayQueueStore._();
  static final RelayQueueStore instance = RelayQueueStore._();
  static const maxEntries = 500;
  static const maxSeen = 5000;
  static const maxAge = Duration(hours: 24);
  Future<void> _tail = Future<void>.value();

  Future<File> _file(String name) async {
    final dir = await getApplicationSupportDirectory();
    await dir.create(recursive: true);
    return File('${dir.path}/$name');
  }
  Future<T> _serial<T>(Future<T> Function() action) {
    final c = Completer<T>();
    _tail = _tail.then((_) async { try { c.complete(await action()); } catch (e, st) { c.completeError(e, st); } });
    return c.future;
  }
  Future<List<Map<String,dynamic>>> _read(File f) async {
    if (!await f.exists()) return [];
    try { final d=jsonDecode(await f.readAsString()); if (d is List) return d.whereType<Map>().map((e)=>Map<String,dynamic>.from(e)).toList(); } catch (_) {}
    return [];
  }
  Future<bool> markSeen(String id) => _serial(() async {
    if (id.isEmpty) return false;
    final f=await _file('blousab_relay_seen.json'); final rows=await _read(f);
    if (rows.any((e)=>e['id']==id)) return false;
    rows.add({'id':id,'at':DateTime.now().toIso8601String()});
    final cutoff=DateTime.now().subtract(maxAge);
    rows.removeWhere((e){ final d=DateTime.tryParse('${e['at']}'); return d==null || d.isBefore(cutoff); });
    if (rows.length>maxSeen) rows.removeRange(0,rows.length-maxSeen);
    await f.writeAsString(jsonEncode(rows),flush:true); return true;
  });
  Future<void> enqueue(Map<String,dynamic> packet) => _serial(() async {
    final id='${packet['id'] ?? ''}'; if(id.isEmpty) return;
    final f=await _file('blousab_relay_queue.json'); final rows=await _read(f);
    if(rows.any((e)=>e['id']==id)) return;
    rows.add({'id':id,'payload':jsonEncode(packet),'queuedAt':DateTime.now().toIso8601String(),'attempts':0});
    if(rows.length>maxEntries) rows.removeRange(0,rows.length-maxEntries);
    await f.writeAsString(jsonEncode(rows),flush:true);
  });
  Future<List<Map<String,dynamic>>> list() => _serial(() async {
    final f=await _file('blousab_relay_queue.json'); final rows=await _read(f); final cutoff=DateTime.now().subtract(maxAge);
    rows.removeWhere((e){ final d=DateTime.tryParse('${e['queuedAt']}'); return d==null || d.isBefore(cutoff); });
    await f.writeAsString(jsonEncode(rows),flush:true); return rows;
  });
  Future<void> noteAttempt(String id) => _serial(() async {
    final f=await _file('blousab_relay_queue.json'); final rows=await _read(f); final i=rows.indexWhere((e)=>e['id']==id); if(i<0)return;
    rows[i]['attempts']=(rows[i]['attempts'] as num? ?? 0)+1; rows[i]['lastAttemptAt']=DateTime.now().toIso8601String();
    await f.writeAsString(jsonEncode(rows),flush:true);
  });
  Future<void> remove(String id) => _serial(() async {
    final f=await _file('blousab_relay_queue.json'); final rows=await _read(f); rows.removeWhere((e)=>e['id']==id); await f.writeAsString(jsonEncode(rows),flush:true);
  });
}
