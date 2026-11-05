
import 'dart:async';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

class BlousabDevice {
  final String name;
  final String address;

  const BlousabDevice({required this.name, required this.address});

  factory BlousabDevice.fromMap(Map<dynamic, dynamic> map) {
    return BlousabDevice(
      name: map['name']?.toString() ?? 'جهاز',
      address: map['address']?.toString() ?? '',
    );
  }
}

class BlousabEvent {
  final String type;
  final String? address;
  final String? name;
  final String? message;

  const BlousabEvent({
    required this.type,
    this.address,
    this.name,
    this.message,
  });

  factory BlousabEvent.fromMap(Map<dynamic, dynamic> map) {
    return BlousabEvent(
      type: map['type']?.toString() ?? 'unknown',
      address: map['address']?.toString(),
      name: map['name']?.toString(),
      message: map['message']?.toString(),
    );
  }
}

class BluetoothClassicService {
  BluetoothClassicService._();

  static final BluetoothClassicService instance =
      BluetoothClassicService._();

  static const MethodChannel _methods =
      MethodChannel('com.blousab.messenger/bluetooth');

  static const EventChannel _events =
      EventChannel('com.blousab.messenger/events');

  Stream<BlousabEvent>? _stream;
  Future<List<BlousabDevice>>? _discoveryInFlight;

  Stream<BlousabEvent> get events {
    return _stream ??= _events.receiveBroadcastStream().map((event) {
      return BlousabEvent.fromMap(
        Map<dynamic, dynamic>.from(event as Map),
      );
    }).asBroadcastStream();
  }

  Future<bool> requestPermissions() async {
    final sdk = await getAndroidSdk();
    if (sdk >= 31) {
      // Permissions are requested once during first app setup. Later operations
      // only check their status and do not repeatedly show permission dialogs.
      final connect = await Permission.bluetoothConnect.status;
      final scan = await Permission.bluetoothScan.status;
      final advertise = await Permission.bluetoothAdvertise.status;
      return connect.isGranted && scan.isGranted && advertise.isGranted;
    }
    // Legacy Bluetooth connect/listen does not need a runtime permission.
    // Location permission is requested during first app setup for discovery.
    return true;
  }

  Future<int> getAndroidSdk() async =>
      await _methods.invokeMethod<int>('getAndroidSdk') ?? 0;

  Future<void> requestDiscoverable() async {
    await _ensurePermission();
    await _methods.invokeMethod<bool>('requestDiscoverable');
  }

  Future<void> startDiscovery() async {
    await _ensurePermission();
    if (await getAndroidSdk() < 31) {
      final location = await Permission.locationWhenInUse.status;
      if (!location.isGranted) {
        throw PlatformException(
          code: 'DISCOVERY_PERMISSION_DENIED',
          message: 'لم تُمنح صلاحية الموقع أثناء إعداد التطبيق الأولي؛ افتح أذونات أندرويد لتفعيلها.',
        );
      }
    }
    await _methods.invokeMethod<bool>('startDiscovery');
  }

  Future<void> cancelDiscovery() async {
    try { await _methods.invokeMethod<bool>('cancelDiscovery'); } catch (_) {}
  }

  /// Scans for nearby discoverable devices and includes already bonded devices.
  /// The user still chooses the target; the app validates the community code
  /// only after the RFCOMM connection is established.
  Future<List<BlousabDevice>> discoverNearbyDevices({
    Duration timeout = const Duration(seconds: 12),
  }) {
    // A single Android BluetoothAdapter scan is shared by concurrent callers.
    final ongoing = _discoveryInFlight;
    if (ongoing != null) return ongoing;
    final scan = _scanNearby(timeout);
    _discoveryInFlight = scan;
    scan.then<void>((_) { if (identical(_discoveryInFlight, scan)) _discoveryInFlight = null; },
      onError: (Object _) { if (identical(_discoveryInFlight, scan)) _discoveryInFlight = null; });
    return scan;
  }

  Future<List<BlousabDevice>> _scanNearby(Duration timeout) async {
    final found = <String, BlousabDevice>{};
    for (final device in await getPairedDevices()) {
      found[device.address] = device;
    }
    final subscription = events.listen((event) {
      if (event.type == 'deviceFound' && event.address != null) {
        found[event.address!] = BlousabDevice(
          name: event.name ?? 'جهاز بلوتوث',
          address: event.address!,
        );
      }
    });
    try {
      await startDiscovery();
      await Future<void>.delayed(timeout);
    } finally {
      await cancelDiscovery();
      await subscription.cancel();
    }
    return found.values.toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  }

  Future<void> _ensurePermission() async {
    if (!await requestPermissions()) {
      throw PlatformException(
        code: 'PERMISSION_DENIED',
        message: 'صلاحيات البلوتوث غير ممنوحة. افتح أذونات أندرويد لتفعيلها؛ لن يكرر بلوساب نافذة الطلب تلقائيًا.',
      );
    }
  }

  Future<bool> isSupported() async {
    return await _methods.invokeMethod<bool>('isSupported') ?? false;
  }

  Future<bool> isEnabled() async {
    await _ensurePermission();
    return await _methods.invokeMethod<bool>('isEnabled') ?? false;
  }

  Future<void> requestEnable() async {
    await _ensurePermission();
    await _methods.invokeMethod<bool>('requestEnable');
  }

  Future<List<BlousabDevice>> getPairedDevices() async {
    await _ensurePermission();

    final list = await _methods.invokeMethod<List<dynamic>>(
      'getPairedDevices',
    );

    return (list ?? []).map((item) {
      return BlousabDevice.fromMap(
        Map<dynamic, dynamic>.from(item as Map),
      );
    }).toList();
  }

  Future<void> startServer() async {
    await _ensurePermission();
    await _methods.invokeMethod<bool>('startServer');
  }

  Future<void> connect(String address) async {
    await _ensurePermission();

    await _methods.invokeMethod<bool>(
      'connect',
      {'address': address},
    );
  }

  Future<void> sendMessage({
    required String address,
    required String message,
  }) async {
    await _ensurePermission();

    final success = await _methods.invokeMethod<bool>(
      'sendMessage',
      {'address': address, 'message': message},
    );

    if (success != true) {
      throw PlatformException(
        code: 'SEND_FAILED',
        message: 'لم يؤكد البلوتوث إرسال الرسالة.',
      );
    }
  }


  Future<void> broadcastMessage(String message) async {
    await _ensurePermission();
    final success = await _methods.invokeMethod<bool>(
      'sendMessage',
      {'address': '*', 'message': message},
    );
    if (success != true) {
      throw PlatformException(
        code: 'BROADCAST_FAILED',
        message: 'تعذر إرسال الرسالة إلى الأجهزة المتصلة.',
      );
    }
  }

  Future<void> disconnect([String? address]) async {
    await _methods.invokeMethod<bool>(
      'disconnect',
      {if (address != null) 'address': address},
    );
  }

  Future<void> stopServer() async {
    await _methods.invokeMethod<bool>('stopServer');
  }
}