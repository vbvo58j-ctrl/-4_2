import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'screens/communities_screen.dart';
import 'screens/blousab_notifications_screen.dart';
import 'widgets/blousab_visuals.dart';
import 'screens/developer_chat_preview_screen.dart';
import 'screens/stories_strip.dart';
import 'screens/qr_screen.dart';
import 'screens/settings_pages.dart';
import 'widgets/blousab_page.dart';
import 'screens/public_feed_screen.dart';
import 'services/bluetooth_classic_service.dart';
import 'services/local_network_service.dart';
import 'services/wifi_aware_service.dart';
import 'services/notification_service.dart';

const String supportUrl = 'https://wsend.co/967737414884';

// Keeps pushed routes in sync with the user's saved appearance selection.
final ValueNotifier<bool> blousabDarkPreference = ValueNotifier<bool>(true);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    final prefs = await SharedPreferences.getInstance();
    blousabDarkPreference.value = (prefs.getString('wasl_background') ?? 'داكن') != 'فاتح';
    blousabTextScale.value = (prefs.getDouble('blousab_ui_scale') ?? 1.0).clamp(.85, 1.3).toDouble();
  } catch (_) {}
  blousabNightMode.value = blousabDarkPreference.value;
  blousabDarkPreference.addListener(() => blousabNightMode.value = blousabDarkPreference.value);
  try { await NotificationService.instance.initialize(); } catch (_) {}
  runApp(const BlousabApp());
}

// Visual-only palette adopted from the supplied Blousab screenshots.
// Network, persistence and native platform contracts are unchanged.
ThemeData buildBlousabTheme(bool dark) {
  const cyan = Color(0xFF24BFFF);
  const violet = Color(0xFFA34CFF);
  final background = dark ? const Color(0xFF050916) : const Color(0xFFF4F7FF);
  final surface = dark ? const Color(0xFF0C142B) : Colors.white;
  final text = dark ? const Color(0xFFF2F5FF) : const Color(0xFF172044);
  final muted = dark ? const Color(0xFFA3B5DE) : const Color(0xFF526084);
  final border = dark ? const Color(0xFF324A9A) : const Color(0xFFBFCDF2);
  final scheme = ColorScheme.fromSeed(
    seedColor: const Color(0xFF3577FF),
    brightness: dark ? Brightness.dark : Brightness.light,
  ).copyWith(
    primary: dark ? cyan : const Color(0xFF245FEA),
    onPrimary: Colors.white,
    primaryContainer: dark ? const Color(0xFF133A9F) : const Color(0xFFDDE7FF),
    onPrimaryContainer: dark ? Colors.white : const Color(0xFF082267),
    secondary: violet,
    surface: surface,
    onSurface: text,
    onSurfaceVariant: muted,
    outline: border,
    outlineVariant: border,
    surfaceContainerHighest: dark ? const Color(0xFF142147) : const Color(0xFFE9EEFC),
  );
  return ThemeData(
    colorScheme: scheme,
    brightness: dark ? Brightness.dark : Brightness.light,
    useMaterial3: true,
    fontFamily: 'sans-serif',
    scaffoldBackgroundColor: background,
    canvasColor: background,
    dividerColor: border.withOpacity(.55),
    appBarTheme: AppBarTheme(
      centerTitle: false,
      backgroundColor: background,
      foregroundColor: text,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      iconTheme: IconThemeData(color: dark ? cyan : scheme.primary, size: 20),
      titleTextStyle: TextStyle(color: text, fontSize: 17, fontWeight: FontWeight.w700),
    ),
    cardTheme: CardThemeData(
      color: surface,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      margin: const EdgeInsets.symmetric(vertical: 4),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: border.withOpacity(.95), width: 1.05),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: surface,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: TextStyle(color: text, fontSize: 19, fontWeight: FontWeight.w700),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: border, width: 1.2)),
      contentTextStyle: TextStyle(color: text),
    ),
    popupMenuTheme: PopupMenuThemeData(color: surface, surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: border))),
    bottomSheetTheme: BottomSheetThemeData(backgroundColor: surface, surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: const BorderRadius.vertical(top: Radius.circular(18)), side: BorderSide(color: border))),
    listTileTheme: ListTileThemeData(
      iconColor: dark ? cyan : scheme.primary, textColor: text, minLeadingWidth: 22,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
    chipTheme: ChipThemeData(
      shape: StadiumBorder(side: BorderSide(color: border)),
      backgroundColor: dark ? const Color(0xFF0D1940) : const Color(0xFFE8EFFF),
      selectedColor: dark ? const Color(0xFF1259D6) : const Color(0xFFC5D9FF),
      labelStyle: TextStyle(color: text, fontSize: 11),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3)),
    filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(
      backgroundColor: dark ? const Color(0xFF116EF5) : const Color(0xFF225CE2),
      foregroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 11))),
    outlinedButtonTheme: OutlinedButtonThemeData(style: OutlinedButton.styleFrom(
      foregroundColor: dark ? cyan : scheme.primary,
      side: BorderSide(color: border, width: 1.15),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)))),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) => states.contains(WidgetState.selected) ? cyan : muted),
      trackColor: WidgetStateProperty.resolveWith((states) => states.contains(WidgetState.selected) ? const Color(0xFF1249AB) : const Color(0xFF1C2442))),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: dark ? const Color(0xFF0A1330) : const Color(0xFFF9FBFF),
      labelStyle: TextStyle(color: muted),
      hintStyle: TextStyle(color: muted.withOpacity(.9)),
      prefixIconColor: cyan,
      suffixIconColor: cyan,
      contentPadding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(11), borderSide: BorderSide(color: border)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(11), borderSide: BorderSide(color: border)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(11), borderSide: BorderSide(color: dark ? cyan : scheme.primary, width: 1.6)),
    ),
    navigationBarTheme: NavigationBarThemeData(
      height: 67,
      backgroundColor: background,
      elevation: 0,
      indicatorColor: dark ? const Color(0xFF15399D) : const Color(0xFFDDE7FF),
      indicatorShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
      surfaceTintColor: Colors.transparent,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      labelTextStyle: WidgetStateProperty.resolveWith<TextStyle?>((states) {
        final selected = states.contains(WidgetState.selected);
        return TextStyle(
          color: selected ? scheme.primary : muted,
          fontSize: 10.5,
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
        );
      }),
      iconTheme: WidgetStateProperty.resolveWith<IconThemeData?>((states) {
        final selected = states.contains(WidgetState.selected);
        return IconThemeData(size: 20, color: selected ? scheme.primary : muted);
      }),
    ),
    snackBarTheme: SnackBarThemeData(backgroundColor: dark ? const Color(0xFF142552) : const Color(0xFF253B80), contentTextStyle: const TextStyle(color: Colors.white)),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: dark ? const Color(0xFF205BE2) : const Color(0xFF245FEA),
      foregroundColor: Colors.white,
    ),
  );
}

class BlousabApp extends StatelessWidget {
  const BlousabApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: blousabDarkPreference,
      builder: (context, useDark, _) => MaterialApp(
        title: 'بلوساب',
        debugShowCheckedModeBanner: false,
        // التصميم كله داكن؛ الوضع النهاري يُنتَج بمرشح لوني فوق التطبيق (انظر blousab_visuals.dart).
        theme: buildBlousabTheme(true),
        darkTheme: buildBlousabTheme(true),
        themeMode: ThemeMode.dark,
        builder: (context, child) => ValueListenableBuilder<double>(
          valueListenable: blousabTextScale,
          builder: (context, scale, _) {
            final mq = MediaQuery.of(context);
            Widget content = Directionality(
              textDirection: TextDirection.rtl,
              child: MediaQuery(
                data: mq.copyWith(textScaler: TextScaler.linear(scale)),
                child: child ?? const SizedBox.shrink(),
              ),
            );
            if (!useDark) content = ColorFiltered(colorFilter: blousabLightModeFilter, child: content);
            return AnnotatedRegion<SystemUiOverlayStyle>(
              value: useDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
              child: content,
            );
          },
        ),
        home: const BluetoothGate(),
      ),
    );
  }
}

class BluetoothGate extends StatefulWidget {
  const BluetoothGate({super.key});

  @override
  State<BluetoothGate> createState() => _BluetoothGateState();
}

class _BluetoothGateState extends State<BluetoothGate> {
  final BluetoothClassicService _bluetooth = BluetoothClassicService.instance;
  bool _checking = true;
  bool _supported = false;
  bool _enabled = false;
  bool _busy = false;
  String _status = 'جارٍ التحقق من البلوتوث…';

  @override
  void initState() {
    super.initState();
    _checkBluetooth();
  }

  Future<void> _checkBluetooth() async {
    if (mounted) setState(() { _checking = true; });
    try {
      final supported = await _bluetooth.isSupported();
      if (!supported) {
        if (mounted) setState(() {
          _supported = false;
          _enabled = false;
          _status = 'هذا الهاتف لا يدعم Bluetooth Classic.';
          _checking = false;
        });
        return;
      }
      final permissions = await _bluetooth.requestPermissions();
      if (!permissions) {
        if (mounted) setState(() {
          _supported = true;
          _enabled = false;
          _status = 'يلزم السماح بصلاحيات البلوتوث للمتابعة.';
          _checking = false;
        });
        return;
      }
      final enabled = await _bluetooth.isEnabled();
      if (!mounted) return;
      setState(() {
        _supported = true;
        _enabled = enabled;
        _status = enabled
            ? 'البلوتوث جاهز. يمكنك فتح بلوساب.'
            : 'شغّل البلوتوث للمتابعة إلى التطبيق.';
        _checking = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _status = 'تعذر التحقق من البلوتوث. تحقق من الصلاحيات ثم أعد المحاولة.';
        _checking = false;
      });
    }
  }

  Future<void> _enableBluetooth() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      if (!await _bluetooth.requestPermissions()) {
        _notice('لم تُمنح صلاحيات البلوتوث.');
        return;
      }
      if (!await _bluetooth.isEnabled()) {
        await _bluetooth.requestEnable();
        _notice('وافق على تشغيل البلوتوث في نافذة Android، ثم اضغط «إعادة التحقق».');
      }
      await Future<void>.delayed(const Duration(milliseconds: 500));
      await _checkBluetooth();
    } catch (e) {
      _notice('تعذر تشغيل البلوتوث: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _notice(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    // Do not block the whole app when Bluetooth is disabled: Wi-Fi mode and settings must remain accessible.
    return const BlousabShell();

    /* Legacy Bluetooth gate UI retained below for reference.
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 96,
                    height: 96,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(28),
                    ),
                    child: Icon(Icons.bluetooth, size: 54,
                      color: Theme.of(context).colorScheme.onPrimaryContainer),
                  ),
                  const SizedBox(height: 24),
                  Text('بلوساب', style: Theme.of(context).textTheme.headlineLarge?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  const Text('تواصل محلي عبر Bluetooth Classic', textAlign: TextAlign.center),
                  const SizedBox(height: 18),
                  Text(_status, textAlign: TextAlign.center),
                  const SizedBox(height: 24),
                  if (_checking || _busy) const CircularProgressIndicator(),
                  if (!_checking && !_enabled) ...[
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _supported ? _enableBluetooth : null,
                        icon: const Icon(Icons.bluetooth_searching),
                        label: const Text('تشغيل البلوتوث'),
                      ),
                    ),
                    TextButton(
                      onPressed: _busy ? null : _checkBluetooth,
                      child: const Text('إعادة التحقق'),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Text(
                    'لن تظهر واجهة المحادثات حتى يتم تفعيل البلوتوث.',
                    style: Theme.of(context).textTheme.bodySmall,
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    */
  }
}

class BlousabShell extends StatefulWidget {
  const BlousabShell({super.key});

  @override
  State<BlousabShell> createState() => _BlousabShellState();
}

class _BlousabShellState extends State<BlousabShell> with WidgetsBindingObserver {
  String _userName = 'مستخدم بلوساب';
  String _background = 'داكن';
  String _chatWallpaper = 'night';
  String _profilePhotoPath = ''; // صورة الملف الشخصي
  String _profileCoverPath = ''; // خلفية الملف الشخصي
  int _homeTabIndex = 0; // تبدأ الواجهة بالمحادثات
  bool _lanEnabled = true;
  bool _nearbyVisible = true;
  String _connectionMode = 'bluetooth';
  double _messageFontSize = 16;
  bool _showMessageTime = true;
  bool _vibrateOnSend = true;
  bool _compactBubbles = false;
  bool _appLockEnabled = false;
  bool _appLocked = false;
  bool _showSettings = false;
  String _userId = '';
  int _friendsCount = 0;
  int _notifCount = 0;
  int _notifSeen = 0;
  String _appLockPin = '';
  StreamSubscription<BlousabEvent>? _notificationBluetoothSubscription;
  StreamSubscription<BlousabEvent>? _notificationLanSubscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadSettings();
    _startNotificationListeners();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_appLockEnabled || _appLockPin.isEmpty) return;
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      if (mounted) setState(() => _appLocked = true);
    }
  }

  Future<void> _manageAppLock() async {
    final prefs = await SharedPreferences.getInstance();
    final currentPin = prefs.getString('blousab_app_lock_pin') ?? '';
    final pinController = TextEditingController();
    final confirmController = TextEditingController();
    final result = await showDialog<Map<String, String>?>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('قفل التطبيق'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(currentPin.isEmpty ? 'أنشئ رمزًا من 4 إلى 8 أرقام لقفل بلوساب.' : 'يمكنك تغيير رمز القفل أو إلغاء القفل من الزر أدناه.'),
          const SizedBox(height: 12),
          TextField(controller: pinController, keyboardType: TextInputType.number, obscureText: true, maxLength: 8, decoration: const InputDecoration(labelText: 'رمز القفل (4-8 أرقام)')),
          TextField(controller: confirmController, keyboardType: TextInputType.number, obscureText: true, maxLength: 8, decoration: const InputDecoration(labelText: 'تأكيد الرمز')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('رجوع')),
          if (currentPin.isNotEmpty)
            TextButton(
              onPressed: () => Navigator.pop(ctx, {'pin': ''}),
              child: const Text('إلغاء القفل'),
            ),
          FilledButton(onPressed: () {
            final pin = pinController.text.trim();
            final confirm = confirmController.text.trim();
            if (pin.isEmpty || pin.length < 4 || pin.length > 8 || !RegExp(r'^\d+$').hasMatch(pin) || pin != confirm) {
              ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('أدخل رمزًا من 4 إلى 8 أرقام وتأكد من تطابقه.'))); return;
            }
            Navigator.pop(ctx, {'pin': pin});
          }, child: const Text('حفظ'))],
      ),
    );
    pinController.dispose(); confirmController.dispose();
    if (result == null) return;
    final pin = result['pin'] ?? '';
    if (pin.isEmpty) {
      await prefs.remove('blousab_app_lock_pin');
      await prefs.setBool('blousab_app_lock_enabled', false);
      if (mounted) setState(() { _appLockEnabled = false; _appLockPin = ''; _appLocked = false; });
    } else {
      await prefs.setString('blousab_app_lock_pin', pin);
      await prefs.setBool('blousab_app_lock_enabled', true);
      if (mounted) setState(() { _appLockEnabled = true; _appLockPin = pin; _appLocked = false; });
    }
  }

  Future<void> _unlockApp() async {
    final controller = TextEditingController();
    final entered = await showDialog<String>(context: context, barrierDismissible: false, builder: (ctx) => AlertDialog(
      title: const Text('بلوساب مقفل'),
      content: TextField(controller: controller, autofocus: true, keyboardType: TextInputType.number, obscureText: true, decoration: const InputDecoration(labelText: 'أدخل رمز القفل')),
      actions: [FilledButton(onPressed: () => Navigator.pop(ctx, controller.text.trim()), child: const Text('فتح التطبيق'))],
    ));
    controller.dispose();
    if (entered == _appLockPin && mounted) setState(() => _appLocked = false);
    else if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('رمز القفل غير صحيح.')));
  }

  void _startNotificationListeners() {
    _notificationBluetoothSubscription = BluetoothClassicService.instance.events.listen((event) {
      if (event.type == 'message' && event.message != null) {
        _notifyForIncoming(event.message!);
      }
    });
    _notificationLanSubscription = LocalNetworkService.instance.events.listen((event) {
      if (event.type == 'message' && event.message != null) {
        _notifyForIncoming(event.message!);
      }
    });
  }

  Future<void> _notifyForIncoming(String raw) async {
    final prefs = await SharedPreferences.getInstance();
    final currentUserId = prefs.getString('wasl_user_id') ?? 'blousab-user';
    await NotificationService.instance.handleIncomingPayload(raw, currentUserId: currentUserId);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _notificationBluetoothSubscription?.cancel();
    _notificationLanSubscription?.cancel();
    super.dispose();
  }

  Future<void> _startBluetoothListener() async {
    try {
      await BluetoothClassicService.instance.startServer();
    } catch (_) {
      // The user can start listening from the Bluetooth action if Android
      // has just returned from the system permission/enable dialog.
    }
  }

  Future<void> _startNearbyVisibility() async {
    // Best-effort visibility: Android controls discoverability prompts/duration.
    try {
      final service = BluetoothClassicService.instance;
      if (await service.isSupported() && await service.isEnabled()) {
        await service.startServer();
        await service.requestDiscoverable();
      }
    } catch (_) {
      // Keep the app usable if Bluetooth permissions or system approval are missing.
    }
  }

  Future<void> _setNearbyVisibility(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('blousab_nearby_visible', enabled);
    if (!mounted) return;
    setState(() => _nearbyVisible = enabled);
    if (enabled) {
      await _startNearbyVisibility();
      final userId = prefs.getString('wasl_user_id') ?? 'blousab-user';
      try { await WifiAwareService.instance.start(userId: userId, userName: _userName); } catch (_) {}
      try {
        await LocalNetworkService.instance.start(userId: userId, userName: _userName);
      } catch (_) {}
    } else {
      try { await WifiAwareService.instance.stop(); } catch (_) {}
      try { await BluetoothClassicService.instance.stopServer(); } catch (_) {}
      try { await LocalNetworkService.instance.stop(); } catch (_) {}
    }
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _userName = prefs.getString('wasl_user_name') ?? 'مستخدم بلوساب';
      _background = prefs.getString('wasl_background') ?? 'داكن';
      _chatWallpaper = prefs.getString('wasl_chat_wallpaper') ?? 'night';
      _profilePhotoPath = prefs.getString('wasl_profile_photo') ?? '';
      _profileCoverPath = prefs.getString('wasl_profile_cover') ?? '';
      _lanEnabled = prefs.getBool('blousab_lan_enabled') ?? true;
      _nearbyVisible = prefs.getBool('blousab_nearby_visible') ?? true;
      _connectionMode = prefs.getString('blousab_connection_mode') ?? 'bluetooth';
      _messageFontSize = (prefs.getDouble('blousab_message_font_size') ?? 16).clamp(14, 22).toDouble();
      _showMessageTime = prefs.getBool('blousab_show_message_time') ?? true;
      _vibrateOnSend = prefs.getBool('blousab_vibrate_on_send') ?? true;
      _compactBubbles = prefs.getBool('blousab_compact_bubbles') ?? false;
      _appLockEnabled = prefs.getBool('blousab_app_lock_enabled') ?? false;
      _appLockPin = prefs.getString('blousab_app_lock_pin') ?? '';
      _appLocked = _appLockEnabled && _appLockPin.isNotEmpty;
    });
    blousabDarkPreference.value = _background != 'فاتح';
    await _refreshCounters(prefs);
    await _requestInitialPermissionsOnce(prefs);
    await _ensureBluetoothOnLaunch();
    if (_nearbyVisible) {
      await _startNearbyVisibility();
      final id = prefs.getString('wasl_user_id') ?? 'blousab-user';
      try { await WifiAwareService.instance.start(userId: id, userName: _userName); } catch (_) {}
    }
    if (_nearbyVisible && (_lanEnabled || _connectionMode == 'wifi')) {
      final id = prefs.getString('wasl_user_id') ?? 'blousab-user';
      try { await LocalNetworkService.instance.start(userId: id, userName: _userName); } catch (_) {}
    }
  }

  Future<void> _ensureBluetoothOnLaunch() async {
    try {
      final service = BluetoothClassicService.instance;
      if (!await service.isSupported()) return;
      // If permission was denied on the first-run request, do not keep prompting.
      final sdk = await service.getAndroidSdk();
      if (sdk >= 31) {
        final connect = await Permission.bluetoothConnect.status;
        final scan = await Permission.bluetoothScan.status;
        final advertise = await Permission.bluetoothAdvertise.status;
        if (!connect.isGranted || !scan.isGranted || !advertise.isGranted) return;
      }
      if (!await service.isEnabled()) {
        // Android displays its own approval dialog; apps cannot silently turn BT on.
        await service.requestEnable();
      }
      if (await service.isEnabled()) {
        await service.startServer();
      }
    } catch (_) {
      // Keep the rest of the app usable if the user declines or the device disallows it.
    }
  }

  /// Android runtime/special permissions are requested during first app setup,
  /// not from a persistent settings row. Android may still show system approval UI.
  Future<void> _requestInitialPermissionsOnce(SharedPreferences prefs) async {
    if (prefs.getBool('blousab_initial_permissions_attempted') == true) return;
    // Set first to prevent repeated prompts if Android pauses/recreates the app.
    await prefs.setBool('blousab_initial_permissions_attempted', true);
    try {
      final sdk = await BluetoothClassicService.instance.getAndroidSdk();
      if (sdk >= 31) {
        await <Permission>[
          Permission.bluetoothConnect,
          Permission.bluetoothScan,
          Permission.bluetoothAdvertise,
        ].request();
      } else if (sdk > 0 && sdk <= 30) {
        await Permission.locationWhenInUse.request();
      }
    } catch (_) {}
    try { await Permission.nearbyWifiDevices.request(); } catch (_) {}
    try { await Permission.notification.request(); } catch (_) {}
    // Overlay permission is special access: Android requires a separate user
    // confirmation screen, so this can never be silently granted at install.
    try {
      if (!await Permission.systemAlertWindow.isGranted) {
        await Permission.systemAlertWindow.request();
      }
    } catch (_) {}
  }

  Future<String?> _pickAndStoreProfilePhoto() async {
    try {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        imageQuality: 65,
        maxWidth: 640,
      );
      if (picked == null) return null;
      // Gallery providers may return temporary/cache paths. Copy the image
      // into the app's documents directory so the profile photo persists.
      final directory = await getApplicationDocumentsDirectory();
      final profileDirectory = Directory('${directory.path}/profile');
      if (!await profileDirectory.exists()) {
        await profileDirectory.create(recursive: true);
      }
      final extension = picked.path.contains('.')
          ? picked.path.substring(picked.path.lastIndexOf('.'))
          : '.jpg';
      final destination = File(
        '${profileDirectory.path}/profile_photo_${DateTime.now().microsecondsSinceEpoch}${extension.toLowerCase()}',
      );
      if (await destination.exists()) await destination.delete();
      await File(picked.path).copy(destination.path);
      return destination.path;
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تعذر اختيار الصورة. تحقق من صلاحية الوصول للصور ثم حاول مجددًا.')),
        );
      }
      return null;
    }
  }

  /// Optional cover asset; small enough to share only during a Blousab profile exchange.
  Future<String?> _pickAndStoreProfileCover() async {
    try {
      final selected = await ImagePicker().pickImage(
        source: ImageSource.gallery, imageQuality: 45, maxWidth: 720, maxHeight: 330);
      if (selected == null) return null;
      final directory = await getApplicationDocumentsDirectory();
      final folder = Directory('${directory.path}/profile');
      await folder.create(recursive: true);
      final target = File('${folder.path}/profile_cover_${DateTime.now().microsecondsSinceEpoch}.jpg');
      await File(selected.path).copy(target.path);
      return target.path;
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تعذر اختيار خلفية الملف الشخصي.')));
      return null;
    }
  }

  Future<void> _announceProfileUpdate({required String userId, required String userName}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final path = prefs.getString('wasl_profile_photo') ?? '';
      String? photo;
      String? cover;
      if (path.isNotEmpty) {
        final file = File(path);
        if (await file.exists()) {
          final bytes = await file.readAsBytes();
          if (bytes.isNotEmpty && bytes.length <= 100 * 1024) {
            photo = base64Encode(bytes);
          }
        }
      }
      final coverPath = prefs.getString('wasl_profile_cover') ?? '';
      if (coverPath.isNotEmpty) {
        try {
          final bytes = await File(coverPath).readAsBytes();
          if (bytes.isNotEmpty && bytes.length <= 60 * 1024) cover = base64Encode(bytes);
        } catch (_) {}
      }
      final packet = jsonEncode({
        'type': 'profile_update',
        'protocol': 'blousab-nearby-v1',
        if (cover != null) 'senderCover': cover,
        'senderId': userId,
        'senderName': userName,
        if (photo != null) 'senderPhoto': photo,
      });

      // Send updates to Bluetooth peers used in previous direct conversations.
      final addresses = <String>{};
      for (final key in prefs.getKeys()) {
        if (key.startsWith('blousab_last_device_dm_')) {
          final address = prefs.getString(key);
          if (address != null && address.isNotEmpty && !address.startsWith('lan:')) {
            addresses.add(address);
          }
        }
      }
      for (final address in addresses) {
        try {
          await BluetoothClassicService.instance.sendMessage(address: address, message: packet);
        } catch (_) {
          // A saved peer may be offline; the next handshake/message refreshes the profile.
        }
      }

      // Also publish to discovered peers on the same local Wi-Fi network.
      try {
        if (LocalNetworkService.instance.isRunning) {
          await LocalNetworkService.instance.broadcastMessage(packet);
        }
      } catch (_) {}
    } catch (_) {}
  }

  Future<void> _manageConnectivityPermissions() async {
    final messages = <String>[];
    try {
      final bluetoothStatuses = await <Permission>[
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
        Permission.bluetoothAdvertise,
      ].request();
      final bluetoothGranted = bluetoothStatuses.values.every((status) => status.isGranted);
      messages.add(bluetoothGranted
          ? 'صلاحيات البلوتوث: ممنوحة.'
          : 'بعض صلاحيات البلوتوث لم تُمنح؛ يمكنك السماح بها من إعدادات التطبيق.');
    } catch (_) {
      messages.add('تعذر طلب صلاحيات البلوتوث تلقائيًا على هذا الإصدار.');
    }
    try {
      final wifiStatus = await Permission.nearbyWifiDevices.request();
      messages.add(wifiStatus.isGranted
          ? 'صلاحية أجهزة Wi-Fi القريبة: ممنوحة.'
          : 'صلاحية أجهزة Wi-Fi القريبة غير ممنوحة أو غير مطلوبة على هذا الهاتف.');
    } catch (_) {
      // Permission is not available on every Android version.
    }
    // Battery optimization exemption is special Android access. Check it
    // through the native API and open Android's official consent screen.
    try {
      const batteryChannel = MethodChannel('com.blousab.messenger/battery');
      var exempt = await batteryChannel.invokeMethod<bool>('isIgnoringBatteryOptimizations') ?? false;
      if (!exempt && Platform.isAndroid) {
        messages.add('تحسينات البطارية: غير مستثنى.');
        // Keep this action explicit and user-initiated from the permissions dialog.
      } else {
        messages.add(exempt
            ? 'العمل دون قيود تحسينات البطارية: مفعّل.'
            : 'حالة تحسينات البطارية غير متاحة على هذا النظام.');
      }
    } catch (_) {
      messages.add('تعذر التحقق من حالة استثناء تحسينات البطارية.');
    }
    try {
      final overlay = await Permission.systemAlertWindow.status;
      if (!overlay.isGranted) {
        final result = await Permission.systemAlertWindow.request();
        messages.add(result.isGranted
            ? 'السماح بالظهور فوق التطبيقات الأخرى: مفعّل.'
            : 'لتفعيل الظهور فوق التطبيقات الأخرى، فعّله من صفحة إعدادات أندرويد التي فتحت.');
      } else {
        messages.add('السماح بالظهور فوق التطبيقات الأخرى: مفعّل بالفعل.');
      }
    } catch (_) {
      messages.add('افتح معلومات تطبيق بلوساب في إعدادات أندرويد لتفعيل الظهور فوق التطبيقات الأخرى.');
    }
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('صلاحيات بلوساب'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            for (final message in messages) Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text('• $message'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              icon: const Icon(Icons.battery_saver),
              label: const Text('إعدادات تحسين البطارية'),
              onPressed: () async {
                try {
                  const batteryChannel = MethodChannel('com.blousab.messenger/battery');
                  await batteryChannel.invokeMethod<bool>('requestIgnoreBatteryOptimizations');
                } catch (_) {
                  try { await openAppSettings(); } catch (_) {}
                }
              },
            ),
            const Text('بعد الرجوع من إعدادات أندرويد، افتح صفحة الصلاحيات مرة أخرى للتحقق من الحالة. هذا الاستثناء يساعد على استمرار العمل في الخلفية لكنه لا يلغي جميع قيود النظام.'),
          ]),
        ),
        actions: [
          TextButton(onPressed: () async { Navigator.pop(dialogContext); await openAppSettings(); }, child: const Text('إعدادات التطبيق')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('تم')),
        ],
      ),
    );
  }

  Future<void> _openSettings() async {
    final nameController = TextEditingController(text: _userName);
    String selectedBackground = _background;
    String selectedWallpaper = _chatWallpaper;
    String selectedPhotoPath = _profilePhotoPath;
    String selectedCoverPath = _profileCoverPath;
    bool photoWasPicked = false;
    bool selectedLan = _lanEnabled;
    bool selectedNearbyVisible = _nearbyVisible;
    String selectedMode = _connectionMode;
    double selectedFontSize = _messageFontSize;
    bool selectedShowTime = _showMessageTime;
    bool selectedVibrate = _vibrateOnSend;
    bool selectedCompact = _compactBubbles;
    final result = await showDialog<Map<String, Object?>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => Theme(
        // Rebuild the entire settings theme when the user changes appearance.
        // Builder below ensures Theme.of(context) reads this theme, not the page theme.
        data: buildBlousabTheme(true),
        child: Builder(
          builder: (context) => AlertDialog(
          insetPadding: EdgeInsets.zero,
          constraints: const BoxConstraints.expand(),
          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
          elevation: 0,
          backgroundColor: Theme.of(context).colorScheme.surface,
          titlePadding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
          contentPadding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          actionsPadding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          title: Row(children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(Icons.settings_outlined, color: Theme.of(context).colorScheme.onPrimaryContainer),
            ),
            const SizedBox(width: 12),
            const Expanded(child: Text('الإعدادات', style: TextStyle(fontWeight: FontWeight.bold))),
            IconButton(
              tooltip: 'إغلاق الإعدادات',
              onPressed: () => Navigator.pop(dialogContext),
              icon: const Icon(Icons.close),
            ),
          ]),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.45),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFF327BFF), width: 1.15),
                  ),
                  child: Column(children: [
                    Container(
                      height: 90, width: double.infinity,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(9),
                        border: Border.all(color: const Color(0xFF3982FF)),
                        gradient: BlousabVisuals.neon,
                        image: selectedCoverPath.isNotEmpty && File(selectedCoverPath).existsSync()
                          ? DecorationImage(image: FileImage(File(selectedCoverPath)), fit: BoxFit.cover) : null,
                      ),
                      child: Align(alignment: Alignment.bottomLeft, child: TextButton.icon(
                        onPressed: () async {
                          final chosen = await _pickAndStoreProfileCover();
                          if (chosen != null) setDialogState(() => selectedCoverPath = chosen);
                        },
                        icon: const Icon(Icons.image_outlined, size: 15),
                        label: const Text('تغيير خلفية الملف'),
                        style: TextButton.styleFrom(foregroundColor: Colors.white,
                          backgroundColor: const Color(0xB3081744)),
                      )),
                    ),
                    const SizedBox(height: 8),
                    GestureDetector(
                      onTap: () async {
                        final path = await _pickAndStoreProfilePhoto();
                        if (path != null) setDialogState(() { selectedPhotoPath = path; photoWasPicked = true; });
                      },
                      child: Stack(alignment: Alignment.bottomRight, children: [
                        CircleAvatar(
                          radius: 43,
                          backgroundColor: Theme.of(context).colorScheme.primary.withOpacity(0.15),
                          backgroundImage: selectedPhotoPath.isNotEmpty && File(selectedPhotoPath).existsSync() ? FileImage(File(selectedPhotoPath)) : null,
                          child: selectedPhotoPath.isEmpty || !File(selectedPhotoPath).existsSync() ? const Icon(Icons.person, size: 48) : null,
                        ),
                        CircleAvatar(radius: 14, child: const Icon(Icons.camera_alt, size: 16)),
                      ]),
                    ),
                    const SizedBox(height: 8),
                    Text(nameController.text.trim().isEmpty ? 'مستخدم بلوساب' : nameController.text.trim(), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
                    const SizedBox(height: 3),
                    Text('اضغط على الصورة لتغييرها', style: Theme.of(context).textTheme.bodySmall),
                    if (selectedPhotoPath.isNotEmpty)
                      TextButton.icon(onPressed: () => setDialogState(() => selectedPhotoPath = ''), icon: const Icon(Icons.delete_outline), label: const Text('إزالة الصورة')),
                  ]),
                ),
                TextField(
                  controller: nameController,
                  maxLength: 40,
                  decoration: const InputDecoration(
                    labelText: 'اسم المستخدم',
                    prefixIcon: Icon(Icons.person_outline),
                  ),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: selectedBackground,
                  decoration: const InputDecoration(
                    labelText: 'مظهر التطبيق',
                    prefixIcon: Icon(Icons.palette_outlined),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'افتراضي', child: Text('هوية بلوساب الداكنة (افتراضي)')),
                    DropdownMenuItem(value: 'فاتح', child: Text('فاتح')),
                    DropdownMenuItem(value: 'داكن', child: Text('داكن')),
                  ],
                  onChanged: (value) {
                    if (value != null) setDialogState(() => selectedBackground = value);
                  },
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: selectedWallpaper,
                  decoration: const InputDecoration(
                    labelText: 'خلفية المحادثة',
                    prefixIcon: Icon(Icons.wallpaper_outlined),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'mint', child: Text('أخضر هادئ')),
                    DropdownMenuItem(value: 'cream', child: Text('كريمي')),
                    DropdownMenuItem(value: 'plain', child: Text('أبيض بسيط')),
                    DropdownMenuItem(value: 'night', child: Text('داكن')),
                  ],
                  onChanged: (value) { if (value != null) setDialogState(() => selectedWallpaper = value); },
                ),
                const SizedBox(height: 8),
                Card(
                  child: SwitchListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    secondary: const Icon(Icons.visibility_outlined),
                    title: const Text('مرئي للأجهزة التي حولك', style: TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: const Text('تشغيل الظهور التلقائي عبر Bluetooth والشبكة المحلية عند فتح بلوساب. قد يطلب Android موافقة إضافية.'),
                    value: selectedNearbyVisible,
                    onChanged: (value) => setDialogState(() => selectedNearbyVisible = value),
                  ),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: selectedMode,
                  decoration: const InputDecoration(
                    labelText: 'طريقة الاتصال الأساسية',
                    prefixIcon: Icon(Icons.compare_arrows),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'bluetooth', child: Text('Bluetooth Classic')),
                    DropdownMenuItem(value: 'wifi', child: Text('Wi-Fi عبر نقطة اتصال')),
                  ],
                  onChanged: (value) { if (value != null) setDialogState(() => selectedMode = value); },
                ),
                if (selectedMode == 'wifi')
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text('شغّل نقطة الاتصال من إعدادات Android في الهاتف المنشئ، ثم صِل الهاتف الآخر بها. يجب أن يكون الهاتفان على الشبكة نفسها. لا يستطيع التطبيق تشغيل نقطة الاتصال تلقائيًا على كل الأجهزة.', style: TextStyle(fontSize: 12)),
                  ),
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Row(children: [Icon(Icons.chat_bubble_outline), SizedBox(width: 8), Text('تخصيص المحادثات', style: TextStyle(fontWeight: FontWeight.bold))]),
                      const SizedBox(height: 8),
                      Row(children: [const Expanded(child: Text('حجم نص الرسائل')), Text('${selectedFontSize.round()}')]),
                      Slider(value: selectedFontSize, min: 14, max: 22, divisions: 8, label: '${selectedFontSize.round()}', onChanged: (value) => setDialogState(() => selectedFontSize = value)),
                      SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('إظهار وقت الرسالة'), subtitle: const Text('عرض وقت الإرسال أسفل كل رسالة'), value: selectedShowTime, onChanged: (value) => setDialogState(() => selectedShowTime = value)),
                      SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('فقاعات مضغوطة'), subtitle: const Text('عرض رسائل أكثر على الشاشة'), value: selectedCompact, onChanged: (value) => setDialogState(() => selectedCompact = value)),
                      SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('اهتزاز خفيف عند الإرسال'), subtitle: const Text('اهتزاز محلي عند إرسال الرسالة بنجاح'), value: selectedVibrate, onChanged: (value) => setDialogState(() => selectedVibrate = value)),
                    ]),
                  ),
                ),
                const SizedBox(height: 8),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: selectedLan,
                  title: const Text('استخدام الشبكة المحلية Wi-Fi'),
                  subtitle: const Text('لإرسال رسائل المجتمعات إلى الأجهزة على شبكة Wi-Fi نفسها.'),
                  onChanged: (value) { if (value != null) setDialogState(() => selectedLan = value); },
                ),
                const SizedBox(height: 8),
                const SizedBox(height: 8),
                Card(child: ListTile(leading: const Icon(Icons.bluetooth_searching), title: const Text('تشغيل استقبال الاتصال'), subtitle: Text(selectedMode == 'wifi' ? 'تعليمات الاتصال عبر Wi-Fi' : 'بدء استقبال Bluetooth وجعل الهاتف مرئيًا'), trailing: const Icon(Icons.chevron_left), onTap: _handleConnectionTap)),
                const SizedBox(height: 8),
                Card(child: ListTile(leading: const Icon(Icons.lock_outline), title: const Text('قفل التطبيق'), subtitle: Text(_appLockEnabled ? 'القفل مفعّل — اضغط لإدارته' : 'حماية بلوساب برمز PIN'), trailing: const Icon(Icons.chevron_left), onTap: _manageAppLock)),
                const SizedBox(height: 10),
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.preview_outlined, color: Color(0xFF28C7FF)),
                    title: const Text('محادثة وهمية تجريبية (للمطور)', style: TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: const Text('معاينة واجهة المحادثة وتجربة شكل الرسائل دون اتصال'),
                    trailing: const Icon(Icons.chevron_left),
                    onTap: () {
                      Navigator.of(context).push(MaterialPageRoute<void>(
                        builder: (_) => const DeveloperChatPreviewScreen(),
                      ));
                    },
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF9800),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: ListTile(
                      leading: const Icon(Icons.support_agent, color: Colors.blue, size: 30),
                      title: const Text('التواصل مع المطور', style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold)),
                      subtitle: const Text('للاقتراحات والمساعدة', style: TextStyle(color: Colors.blue)),
                      trailing: const Icon(Icons.open_in_new, color: Colors.blue),
                      onTap: _openSupport,
                    ),
                  ),
                ),
                const SizedBox(height: 8),

                const Text(
                  'تُحفظ هذه الإعدادات على هذا الهاتف. لا تُزامَن تلقائيًا مع الأجهزة الأخرى.',
                  style: TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),
          actions: [
            Row(children: [
              Expanded(child: OutlinedButton.icon(
                onPressed: () => Navigator.pop(dialogContext),
                icon: const Icon(Icons.close),
                label: const Text('إلغاء'),
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
              )),
              const SizedBox(width: 12),
              Expanded(child: FilledButton.icon(
                onPressed: () => Navigator.pop(dialogContext, {
                  'name': nameController.text.trim(),
                  'background': selectedBackground,
                  'wallpaper': selectedWallpaper,
                  'photoPath': selectedPhotoPath,
                  'coverPath': selectedCoverPath,
                  'photoWasPicked': photoWasPicked,
                  'lanEnabled': selectedLan,
                  'nearbyVisible': selectedNearbyVisible,
                  'connectionMode': selectedMode,
                  'messageFontSize': selectedFontSize,
                  'showMessageTime': selectedShowTime,
                  'vibrateOnSend': selectedVibrate,
                  'compactBubbles': selectedCompact,
                }),
                icon: const Icon(Icons.save_outlined),
                label: const Text('حفظ التغييرات'),
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
              )),
            ]),
          ],
          ),
        ),
        ),
      ),
    );
    nameController.dispose();
    if (result == null) return;
    final enteredName = (result['name'] as String? ?? '').trim();
    final cleanName = enteredName.isEmpty ? 'مستخدم بلوساب' : enteredName;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('wasl_user_name', cleanName);
    await prefs.setString('wasl_background', result['background'] as String);
    await prefs.setString('wasl_chat_wallpaper', result['wallpaper'] as String? ?? 'mint');
    final photoPath = result['photoPath'] as String? ?? '';
    if (photoPath.isEmpty) { await prefs.remove('wasl_profile_photo'); } else { await prefs.setString('wasl_profile_photo', photoPath); }
    final coverPath = result['coverPath'] as String? ?? '';
    if (coverPath.isEmpty) { await prefs.remove('wasl_profile_cover'); }
    else { await prefs.setString('wasl_profile_cover', coverPath); }
    final lanEnabled = result['lanEnabled'] as bool? ?? true;
    final nearbyVisible = result['nearbyVisible'] as bool? ?? true;
    await prefs.setBool('blousab_lan_enabled', lanEnabled);
    await prefs.setBool('blousab_nearby_visible', nearbyVisible);
    final connectionMode = result['connectionMode'] as String? ?? 'bluetooth';
    await prefs.setString('blousab_connection_mode', connectionMode);
    final messageFontSize = (result['messageFontSize'] as double? ?? 16).clamp(14, 22).toDouble();
    final showMessageTime = result['showMessageTime'] as bool? ?? true;
    final vibrateOnSend = result['vibrateOnSend'] as bool? ?? true;
    final compactBubbles = result['compactBubbles'] as bool? ?? false;
    await prefs.setDouble('blousab_message_font_size', messageFontSize);
    await prefs.setBool('blousab_show_message_time', showMessageTime);
    await prefs.setBool('blousab_vibrate_on_send', vibrateOnSend);
    await prefs.setBool('blousab_compact_bubbles', compactBubbles);
    final userId = prefs.getString('wasl_user_id') ?? 'blousab-user';
    if (nearbyVisible && (lanEnabled || connectionMode == 'wifi')) {
      try {
        await LocalNetworkService.instance.start(userId: userId, userName: cleanName);
      } catch (_) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تعذر تشغيل الشبكة المحلية. تحقق من اتصال Wi-Fi.')));
      }
    } else {
      await LocalNetworkService.instance.stop();
    }
    if (!nearbyVisible) {
      try { await BluetoothClassicService.instance.stopServer(); } catch (_) {}
    } else {
      await _startNearbyVisibility();
    }
    final oldPhotoPath = _profilePhotoPath;
    if ((result['photoWasPicked'] as bool? ?? false) || oldPhotoPath != photoPath ||
        _profileCoverPath != coverPath || _userName != cleanName) {
      await _announceProfileUpdate(userId: userId, userName: cleanName);
    }
    if (!mounted) return;
    setState(() {
      _userName = cleanName;
      _background = result['background'] as String;
      _chatWallpaper = result['wallpaper'] as String? ?? 'mint';
      _profilePhotoPath = photoPath;
      _profileCoverPath = coverPath;
      _lanEnabled = lanEnabled;
      _nearbyVisible = nearbyVisible;
      _connectionMode = connectionMode;
      _messageFontSize = messageFontSize;
      _showMessageTime = showMessageTime;
      _vibrateOnSend = vibrateOnSend;
      _compactBubbles = compactBubbles;
    });
    blousabDarkPreference.value = _background != 'فاتح';
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(!nearbyVisible ? 'تم حفظ الإعدادات وإيقاف الظهور للأجهزة القريبة.' : (connectionMode == 'wifi' ? 'تم حفظ الإعدادات. تأكد من اتصال الهاتفين بالشبكة نفسها.' : 'تم حفظ الإعدادات على هذا الهاتف.'))));
  }

  Future<void> _openSupport() async {
    // Try the WhatsApp app first, then its official HTTPS deep link.
    final targets = <Uri>[
      Uri.parse('whatsapp://send?phone=967737414884'),
      Uri.parse('https://wa.me/967737414884'),
      Uri.parse('https://api.whatsapp.com/send?phone=967737414884'),
      Uri.parse(supportUrl),
    ];
    for (final uri in targets) {
      try {
        final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
        if (opened) return;
      } catch (_) {
        // Continue to the next compatible WhatsApp link.
      }
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر فتح واتساب. ثبّت التطبيق أو تأكد من اتصال الإنترنت.')),
      );
    }
  }

  // ---------------------------------------------------------------------
  // Mockup UI: profile + settings
  // ---------------------------------------------------------------------
  static const Color _muted = Color(0xFFA9B8E8);

  int get _unreadNotifications => _notifCount > _notifSeen ? _notifCount - _notifSeen : 0;

  String _compactCount(int n) => n >= 1000 ? '${(n / 1000).toStringAsFixed(1)}K' : '$n';

  String get _handle {
    final name = _userName.trim();
    if (name.isNotEmpty && RegExp(r'^[A-Za-z0-9 _.\-]+$').hasMatch(name)) {
      return '@${name.toLowerCase().replaceAll(RegExp(r'[ .\-]+'), '_')}';
    }
    final id = _userId.isEmpty ? '000000' : (_userId.length > 6 ? _userId.substring(_userId.length - 6) : _userId);
    return '@blousab_$id';
  }

  void _toast(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _refreshCounters([SharedPreferences? existing]) async {
    final prefs = existing ?? await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _userId = prefs.getString('wasl_user_id') ?? '';
      _friendsCount = (prefs.getStringList('blousab_accepted_friends_v1') ?? const <String>[]).length;
      _notifCount = (prefs.getStringList('blousab_notifications_v1') ?? const <String>[]).length;
      _notifSeen = prefs.getInt('blousab_notifications_seen_v1') ?? 0;
    });
  }

  Future<void> _changeProfilePhotoQuick() async {
    final path = await _pickAndStoreProfilePhoto();
    if (path == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('wasl_profile_photo', path);
    final id = prefs.getString('wasl_user_id') ?? 'blousab-user';
    if (mounted) setState(() => _profilePhotoPath = path);
    try { await _announceProfileUpdate(userId: id, userName: _userName); } catch (_) {}
  }

  Future<void> _changeCoverQuick() async {
    final path = await _pickAndStoreProfileCover();
    if (path == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('wasl_profile_cover', path);
    final id = prefs.getString('wasl_user_id') ?? 'blousab-user';
    if (mounted) setState(() => _profileCoverPath = path);
    try { await _announceProfileUpdate(userId: id, userName: _userName); } catch (_) {}
    _toast('تم تغيير صورة الغلاف.');
  }

  Future<void> _setDarkPreference(bool dark) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('wasl_background', dark ? 'داكن' : 'فاتح');
    if (!mounted) return;
    setState(() => _background = dark ? 'داكن' : 'فاتح');
    blousabDarkPreference.value = dark;
  }

  Future<void> _showAccountCode() async {
    await showDialog<void>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('رمز حسابي'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        SelectableText(_handle, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        SelectableText(_userId.isEmpty ? '—' : _userId, style: const TextStyle(fontSize: 12, color: _muted)),
        const SizedBox(height: 10),
        const Text('شارك هذا المعرّف مع أصدقائك للعثور عليك داخل بلوساب.', textAlign: TextAlign.center, style: TextStyle(fontSize: 12)),
      ]),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('حسنًا'))],
    ));
  }

  Future<void> _confirmClearChats() async {
    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('مسح محتوى المحادثات؟'),
      content: const Text('ستُحذف جميع الرسائل المحفوظة على هذا الهاتف. لن تُحذف قوائم المحادثات والمجتمعات.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('مسح')),
      ],
    ));
    if (ok != true) return;
    final prefs = await SharedPreferences.getInstance();
    for (final key in prefs.getKeys().where((k) => k.startsWith('wasl_messages_')).toList()) {
      await prefs.remove(key);
    }
    _toast('تم مسح محتوى المحادثات.');
  }

  Future<void> _confirmDeleteAccount() async {
    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('حذف الحساب نهائيًا؟'),
      content: const Text('سيتم حذف بياناتك وإعداداتك ورسائلك من هذا الهاتف وإغلاق التطبيق. لا يمكن التراجع عن هذا الإجراء.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: const Color(0xFFE5304A)),
          onPressed: () => Navigator.pop(ctx, true), child: const Text('حذف نهائيًا')),
      ],
    ));
    if (ok != true) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    _toast('تم حذف الحساب من هذا الهاتف.');
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    await SystemNavigator.pop();
  }

  Future<void> _showBlockedList() async {
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const BlockedUsersPage()));
  }

  Future<void> _showAbout() async {
    await showDialog<void>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('حول بلوساب'),
      content: const Text('بلوساب — شبكة اجتماعية محلية تعمل بدون إنترنت.\nالإصدار 1.0.0'),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('حسنًا'))],
    ));
  }

  // Row used by both the profile info card and the settings groups. The
  // supplied mockup lays these rows out left-to-right (icon on the left,
  // chevron on the right) while the text itself stays Arabic.
  Widget _mockRow({
    required Widget leading,
    required String title,
    required String subtitle,
    Widget? trailing,
    VoidCallback? onTap,
    double titleSize = 17,
    double vertical = 11,
  }) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 14, vertical: vertical),
          child: Row(children: [
            SizedBox(width: 38, child: Center(child: leading)),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text(title, textDirection: TextDirection.rtl, style: TextStyle(color: Colors.white, fontSize: titleSize, fontWeight: FontWeight.w800, height: 1.2)),
              const SizedBox(height: 2),
              Text(subtitle, textDirection: TextDirection.rtl, style: const TextStyle(color: _muted, fontSize: 13, height: 1.2)),
            ])),
            trailing ?? const Icon(Icons.chevron_right_rounded, color: Color(0xFFB9C8FF), size: 30),
          ]),
        ),
      ),
    );
  }

  Widget _mockGroup(List<Widget> rows) {
    final children = <Widget>[];
    for (int i = 0; i < rows.length; i++) {
      children.add(rows[i]);
      if (i != rows.length - 1) {
        children.add(Container(height: 1, margin: const EdgeInsets.symmetric(horizontal: 12), color: const Color(0xFF1E2F6B)));
      }
    }
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF0B1536), Color(0xFF080F2A)]),
        border: Border.all(color: const Color(0xFF2D4BB8), width: 1.3),
        boxShadow: const [BoxShadow(color: Color(0x442D6BFF), blurRadius: 10)],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: children),
    );
  }

  Widget _statBox(String label, int value) => Container(
    width: 104, height: 66,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(15),
      gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF0B1A55), Color(0xFF1A0E47)]),
      border: Border.all(color: const Color(0xFF8E45FF), width: 1.4),
      boxShadow: const [BoxShadow(color: Color(0x668E45FF), blurRadius: 10)],
    ),
    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Text(label, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
      const SizedBox(height: 2),
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        const Icon(Icons.groups_rounded, color: Color(0xFF3FA2FF), size: 24),
        const SizedBox(width: 5),
        Text(_compactCount(_friendsCount), style: const TextStyle(color: Colors.white, fontSize: 21, fontWeight: FontWeight.w800)),
      ]),
    ]),
  );

  Widget _profileTabButton({required IconData icon, required String label, required bool selected, required VoidCallback onTap}) => Expanded(
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.all(3),
        decoration: selected ? BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          gradient: const LinearGradient(colors: [Color(0xFF0F4DD8), Color(0xFF1B2F9A)]),
          border: Border.all(color: const Color(0xFF3FA2FF), width: 1.4),
          boxShadow: const [BoxShadow(color: Color(0x883FA2FF), blurRadius: 10)],
        ) : null,
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, color: selected ? const Color(0xFF3FD0FF) : const Color(0xFF8FB2FF), size: 24),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: selected ? FontWeight.w800 : FontWeight.w600)),
        ]),
      ),
    ),
  );

  Widget _buildProfileTab(BuildContext context) {
    if (_showSettings) return _buildSettingsPage(context);
    final hasPhoto = _profilePhotoPath.isNotEmpty && File(_profilePhotoPath).existsSync();
    return Stack(children: [
      const Positioned(top: 0, left: 0, right: 0, child: BlousabWaveBackground(height: 330)),
      Column(children: [
        BlousabTopBar(
          titleWidget: const BlousabGlowTitle('ملفي الشخصي', size: 27),
          start: [BlousabBell(count: _unreadNotifications, onTap: _openNotifications)],
          end: [GestureDetector(
            onTap: () => setState(() => _showSettings = true),
            child: const SizedBox(width: 40, height: 40, child: Icon(Icons.settings_rounded, color: Color(0xFF3FA2FF), size: 34)),
          )],
        ),
        Expanded(child: ListView(padding: const EdgeInsets.fromLTRB(14, 0, 14, 14), children: [
          SizedBox(height: 178, child: Stack(alignment: Alignment.center, children: [
            Positioned(left: 0, top: 36, child: _statBox('المتابعون', _friendsCount)),
            Positioned(right: 0, top: 36, child: _statBox('المتابَعون', _friendsCount)),
            Positioned(top: 4, child: SizedBox(width: 150, height: 150, child: Stack(clipBehavior: Clip.none, children: [
              Container(
                width: 150, height: 150, padding: const EdgeInsets.all(4),
                decoration: const BoxDecoration(shape: BoxShape.circle,
                  gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF28C7FF), Color(0xFF2D6BFF), Color(0xFFB238FF)]),
                  boxShadow: [BoxShadow(color: Color(0x992D6BFF), blurRadius: 18), BoxShadow(color: Color(0x55B238FF), blurRadius: 24)]),
                child: ClipOval(child: Container(
                  color: const Color(0xFFE9E9EC),
                  child: hasPhoto
                    ? BlousabKeepColors(child: Image.file(File(_profilePhotoPath), fit: BoxFit.cover, width: 142, height: 142))
                    : const Icon(Icons.person_rounded, size: 90, color: Color(0xFF14235A)),
                )),
              ),
              Positioned(right: 2, bottom: 6, child: GestureDetector(
                onTap: _changeProfilePhotoQuick,
                child: Container(width: 34, height: 34,
                  decoration: BoxDecoration(color: const Color(0xFF0A1334), shape: BoxShape.circle,
                    border: Border.all(color: const Color(0xFF3FA2FF), width: 1.5)),
                  child: const Icon(Icons.photo_camera_rounded, color: Colors.white, size: 19)),
              )),
            ]))),
          ])),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            const BlousabVerifiedBadge(size: 24),
            const SizedBox(width: 6),
            Flexible(child: Text(_userName, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white, fontSize: 25, fontWeight: FontWeight.w800))),
          ]),
          const SizedBox(height: 2),
          Center(child: Text(_handle, textDirection: TextDirection.ltr, style: const TextStyle(color: Color(0xFFB4C3F0), fontSize: 15))),
          const SizedBox(height: 8),
          const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Text('أهلاً وسهلاً بكم في بلُوساب', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
            SizedBox(width: 8),
            Icon(Icons.favorite_rounded, color: Color(0xFF2F9BFF), size: 22),
          ]),
          const Center(child: Text('معاً نبني مجتمعاً أقوى', style: TextStyle(color: Color(0xFFD5DEFF), fontSize: 14.5))),
          const SizedBox(height: 14),
          Container(
            height: 52,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              color: const Color(0xFF070F2C),
              border: Border.all(color: const Color(0xFF5A3BFF), width: 1.4),
              boxShadow: const [BoxShadow(color: Color(0x665A3BFF), blurRadius: 10)],
            ),
            child: Row(children: [
              _profileTabButton(icon: Icons.grid_view_rounded, label: 'المنشورات', selected: false, onTap: () { blousabFeedShowAllRequest.value++; setState(() => _homeTabIndex = 1); }),
              _profileTabButton(icon: Icons.add_circle_outline_rounded, label: 'القصص', selected: false, onTap: () => setState(() => _homeTabIndex = 2)),
              _profileTabButton(icon: Icons.person_rounded, label: 'المعلومات', selected: true, onTap: () {}),
            ]),
          ),
          const SizedBox(height: 14),
          _mockGroup([
            _mockRow(leading: const Icon(Icons.person_rounded, color: Color(0xFFB46CFF), size: 38), title: 'معلومات الحساب', subtitle: 'الاسم، المستخدم، رقم الهاتف', onTap: _openEditProfile),
            _mockRow(leading: const Icon(Icons.image_rounded, color: Color(0xFF2D8CFF), size: 38), title: 'صورة الغلاف', subtitle: 'تغيير صورة الغلاف', onTap: _changeCoverQuick),
            _mockRow(leading: const Icon(Icons.palette_rounded, color: Color(0xFFB46CFF), size: 38), title: 'السمة', subtitle: _background == 'فاتح' ? 'الوضع النهاري' : 'الوضع الليلي',
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.nightlight_round, color: Color(0xFF3FD0FF), size: 30),
                const SizedBox(width: 6),
                const Icon(Icons.chevron_right_rounded, color: Color(0xFFB9C8FF), size: 30),
              ]), onTap: () => _setDarkPreference(_background == 'فاتح')),
            _mockRow(leading: const Icon(Icons.verified_user_rounded, color: Color(0xFF2BE36B), size: 38), title: 'الحالة', subtitle: _nearbyVisible ? 'متصل الآن' : 'غير مرئي للأجهزة القريبة',
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                Container(width: 13, height: 13, decoration: BoxDecoration(color: _nearbyVisible ? const Color(0xFF22E56A) : const Color(0xFF7C88B0), shape: BoxShape.circle,
                  boxShadow: _nearbyVisible ? const [BoxShadow(color: Color(0x9922E56A), blurRadius: 8)] : null)),
                const SizedBox(width: 10),
                const Icon(Icons.chevron_right_rounded, color: Color(0xFFB9C8FF), size: 30),
              ]), onTap: () => _setNearbyVisibility(!_nearbyVisible)),
            _mockRow(leading: const Icon(Icons.qr_code_2_rounded, color: Color(0xFF9FB4FF), size: 38), title: 'رمز QR الخاص بي', subtitle: 'عرض الرمز ومسح رموز الأصدقاء', onTap: _openQr),
          ]),
          const SizedBox(height: 14),
          GestureDetector(
            onTap: _openEditProfile,
            child: Container(
              height: 52,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                gradient: const LinearGradient(colors: [Color(0xFF0B2E7A), Color(0xFF101B5C), Color(0xFF2B1470)]),
                border: Border.all(color: const Color(0xFF3FA2FF), width: 1.5),
                boxShadow: const [BoxShadow(color: Color(0x773FA2FF), blurRadius: 12)],
              ),
              child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(Icons.edit_rounded, color: Color(0xFFD59BFF), size: 24),
                SizedBox(width: 8),
                Text('تعديل الملف الشخصي', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
              ]),
            ),
          ),
        ])),
      ]),
    ]);
  }

  Widget _sectionTitle(String text, Color color) => Padding(
    padding: const EdgeInsets.fromLTRB(6, 14, 6, 7),
    child: Align(alignment: AlignmentDirectional.centerStart, child: Text(text, style: TextStyle(color: color, fontSize: 18, fontWeight: FontWeight.w800))),
  );

  Widget _buildSettingsPage(BuildContext context) {
    const cyan = Color(0xFF28C7FF);
    const pink = Color(0xFFFF4FD8);
    const violet = Color(0xFFB46CFF);
    const magenta = Color(0xFFE23CFF);
    final isDark = _background != 'فاتح';
    return Stack(children: [
      const Positioned(top: 0, left: 0, right: 0, child: BlousabWaveBackground(height: 140)),
      Column(children: [
        BlousabTopBar(
          titleWidget: const BlousabGlowTitle('الإعدادات', size: 27),
          start: [BlousabBell(count: _unreadNotifications, onTap: _openNotifications)],
          end: [GestureDetector(
            onTap: () => setState(() => _showSettings = false),
            child: const SizedBox(width: 40, height: 40, child: Icon(Icons.arrow_back_rounded, color: Colors.white, size: 32)),
          )],
        ),
        Expanded(child: ListView(padding: const EdgeInsets.fromLTRB(12, 0, 12, 14), children: [
          _sectionTitle('الحساب', cyan),
          _mockGroup([
            _mockRow(leading: const Icon(Icons.person_rounded, color: Color(0xFF2D9CFF), size: 36), title: 'الخصوصية والأمان', subtitle: 'من يمكنه رؤية معلوماتك؟', titleSize: 16, vertical: 9, onTap: _openPrivacy),
            _mockRow(leading: const Icon(Icons.lock_rounded, color: Color(0xFF2D9CFF), size: 36), title: 'قفل التطبيق', subtitle: 'حماية إضافية لتطبيق بلوساب', titleSize: 16, vertical: 9,
              trailing: Switch(value: _appLockEnabled, onChanged: (_) => _manageAppLock()), onTap: _manageAppLock),
            _mockRow(leading: const Icon(Icons.verified_user_rounded, color: Color(0xFF2BE36B), size: 36), title: 'حذف الحساب', subtitle: 'إزالة حسابك نهائياً', titleSize: 16, vertical: 9, onTap: _confirmDeleteAccount),
          ]),
          _sectionTitle('المحادثات', pink),
          _mockGroup([
            _mockRow(leading: const Icon(Icons.chat_bubble_rounded, color: Color(0xFF2D9CFF), size: 36), title: 'إعدادات المحادثات', subtitle: 'الظهور، الإشعارات، الخلفية', titleSize: 16, vertical: 9, onTap: _openChatSettings),
            _mockRow(leading: const Icon(Icons.cleaning_services_rounded, color: Color(0xFFFFB23F), size: 36), title: 'مسح محتوى المحادثات', subtitle: 'حذف جميع المحادثات', titleSize: 16, vertical: 9, onTap: _confirmClearChats),
            _mockRow(leading: const Icon(Icons.block_rounded, color: Color(0xFFFF3B4E), size: 36), title: 'قائمة المحظورين', subtitle: 'إدارة المستخدمين المحظورين', titleSize: 16, vertical: 9, onTap: _showBlockedList),
          ]),
          _sectionTitle('المنشورات والقصص', violet),
          _mockGroup([
            _mockRow(leading: const Icon(Icons.image_rounded, color: Color(0xFF2D9CFF), size: 36), title: 'إعدادات المنشورات', subtitle: 'من يمكنه رؤية منشوراتك؟', titleSize: 16, vertical: 9, onTap: () => _openVisibility('إعدادات المنشورات', 'blousab_posts_visibility', 'منشوراتك')),
            _mockRow(leading: const Icon(Icons.donut_large_rounded, color: Color(0xFFB46CFF), size: 36), title: 'إعدادات القصص', subtitle: 'من يمكنه رؤية قصصك؟', titleSize: 16, vertical: 9, onTap: () => _openVisibility('إعدادات القصص', 'blousab_story_visibility', 'قصصك')),
          ]),
          _sectionTitle('إعدادات عامة', magenta),
          _mockGroup([
            _mockRow(leading: const Icon(Icons.notifications_rounded, color: Color(0xFF2D9CFF), size: 36), title: 'الإشعارات', subtitle: 'إدارة تنبيهات بلوساب', titleSize: 16, vertical: 9, onTap: _openNotifications),
            _mockRow(leading: const Icon(Icons.language_rounded, color: Color(0xFF2D9CFF), size: 36), title: 'اللغة والواجهة', subtitle: 'تغيير اللغة أو الشكل', titleSize: 16, vertical: 7, onTap: _openLanguage),
            _mockRow(leading: const Icon(Icons.palette_rounded, color: Color(0xFF2D9CFF), size: 36), title: 'المظهر', subtitle: 'الوضع الليلي أو النهاري', titleSize: 16, vertical: 7,
              trailing: Container(
                padding: const EdgeInsets.fromLTRB(6, 2, 2, 2),
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(20), color: const Color(0xFF0A1744), border: Border.all(color: const Color(0xFF3F5BD8))),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.nightlight_round, color: Color(0xFF3FD0FF), size: 22),
                  Switch(value: isDark, onChanged: _setDarkPreference),
                ]),
              ), onTap: () => _setDarkPreference(!isDark)),
            _mockRow(leading: const Icon(Icons.info_outline_rounded, color: Color(0xFF2D9CFF), size: 36), title: 'حول بلوساب', subtitle: 'الإصدار 1.0.0', titleSize: 16, vertical: 7, onTap: _showAbout),
          ]),
          const SizedBox(height: 10),
          GestureDetector(
            onTap: _openSupport,
            child: Container(
              height: 60,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                gradient: const LinearGradient(colors: [Color(0xFF2A1604), Color(0xFF3A1F05)]),
                border: Border.all(color: const Color(0xFFFF9A1F), width: 1.6),
                boxShadow: const [BoxShadow(color: Color(0x88FF9A1F), blurRadius: 12)],
              ),
              child: Directionality(textDirection: TextDirection.ltr, child: Row(children: [
                const SizedBox(width: 14),
                const Icon(Icons.mail_rounded, color: Color(0xFFFF9A1F), size: 36),
                const SizedBox(width: 12),
                const Expanded(child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.center, children: [
                  Text('التواصل مع المطور', textDirection: TextDirection.rtl, style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
                  Text('للدعم أو الإبلاغ عن مشكلة', textDirection: TextDirection.rtl, style: TextStyle(color: Color(0xFFFFD9A8), fontSize: 12)),
                ])),
                const Icon(Icons.chevron_right_rounded, color: Color(0xFFFFB866), size: 30),
                const SizedBox(width: 6),
              ])),
            ),
          ),
        ])),
      ]),
    ]);
  }

  Future<void> _openEditProfile() async {
    final result = await Navigator.of(context).push<Map<String, Object?>>(MaterialPageRoute(
      builder: (_) => EditProfileScreen(
        name: _userName,
        photoPath: _profilePhotoPath,
        coverPath: _profileCoverPath,
        pickPhoto: _pickAndStoreProfilePhoto,
        pickCover: _pickAndStoreProfileCover,
      ),
    ));
    if (result == null) return;
    final entered = ((result['name'] as String?) ?? '').trim();
    final cleanName = entered.isEmpty ? 'مستخدم بلوساب' : entered;
    final photoPath = (result['photoPath'] as String?) ?? '';
    final coverPath = (result['coverPath'] as String?) ?? '';
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('wasl_user_name', cleanName);
    if (photoPath.isEmpty) { await prefs.remove('wasl_profile_photo'); } else { await prefs.setString('wasl_profile_photo', photoPath); }
    if (coverPath.isEmpty) { await prefs.remove('wasl_profile_cover'); } else { await prefs.setString('wasl_profile_cover', coverPath); }
    final userId = prefs.getString('wasl_user_id') ?? 'blousab-user';
    final changed = (result['photoWasPicked'] as bool? ?? false) || _profilePhotoPath != photoPath || _profileCoverPath != coverPath || _userName != cleanName;
    if (changed) {
      try { await _announceProfileUpdate(userId: userId, userName: cleanName); } catch (_) {}
    }
    if (!mounted) return;
    setState(() { _userName = cleanName; _profilePhotoPath = photoPath; _profileCoverPath = coverPath; });
    _toast('تم حفظ الملف الشخصي.');
  }

  Future<void> _reloadSimpleSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _chatWallpaper = prefs.getString('wasl_chat_wallpaper') ?? 'night';
      _lanEnabled = prefs.getBool('blousab_lan_enabled') ?? true;
      _connectionMode = prefs.getString('blousab_connection_mode') ?? 'bluetooth';
      _messageFontSize = (prefs.getDouble('blousab_message_font_size') ?? 16).clamp(14, 22).toDouble();
      _showMessageTime = prefs.getBool('blousab_show_message_time') ?? true;
      _vibrateOnSend = prefs.getBool('blousab_vibrate_on_send') ?? true;
      _compactBubbles = prefs.getBool('blousab_compact_bubbles') ?? false;
    });
    final id = prefs.getString('wasl_user_id') ?? 'blousab-user';
    if (_nearbyVisible && (_lanEnabled || _connectionMode == 'wifi')) {
      try { await LocalNetworkService.instance.start(userId: id, userName: _userName); } catch (_) {}
    } else {
      try { await LocalNetworkService.instance.stop(); } catch (_) {}
    }
  }

  Future<void> _openPrivacy() async {
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => PrivacySettingsPage(
      nearbyVisible: _nearbyVisible,
      onNearbyChanged: _setNearbyVisibility,
      onAppLock: _manageAppLock,
      onAccountCode: _showAccountCode,
      onBlocked: _showBlockedList,
    )));
    await _reloadSimpleSettings();
  }

  Future<void> _openChatSettings() async {
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ChatSettingsPage(onConnectionTap: _handleConnectionTap)));
    await _reloadSimpleSettings();
  }

  void _openVisibility(String title, String key, String noun) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => VisibilitySettingsPage(title: title, prefKey: key, noun: noun)));
  }

  void _openLanguage() {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const LanguageSettingsPage()));
  }

  void _openQr({bool scan = false}) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => BlousabQrScreen(userId: _userId, userName: _userName, startOnScan: scan)));
  }

  Future<void> _handleConnectionTap() async {
    if (_connectionMode == 'wifi') {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('الاتصال عبر Wi-Fi'),
          content: const Text('تأكد من اتصال الهاتفين بالشبكة المحلية نفسها، ثم افتح البحث عن مستخدمين أو مجتمع.'),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('حسنًا'))],
        ),
      );
      return;
    }
    final service = BluetoothClassicService.instance;
    try {
      final enabled = await service.isEnabled();
      if (!enabled) {
        await service.requestEnable();
      } else {
        await service.startServer();
        await service.requestDiscoverable();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('بدأ استقبال البلوتوث. وافق على جعل الهاتف مرئيًا للأجهزة القريبة لمدة 5 دقائق للانضمام الأول.')),
          );
        }
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذر تشغيل استقبال البلوتوث: $e')));
    }
  }

  Future<void> _openNotifications() async {
    await Navigator.push(context, MaterialPageRoute<void>(
      builder: (_) => const BlousabNotificationsScreen()));
    final prefs = await SharedPreferences.getInstance();
    final total = (prefs.getStringList('blousab_notifications_v1') ?? const <String>[]).length;
    await prefs.setInt('blousab_notifications_seen_v1', total);
    await _refreshCounters(prefs);
  }

  @override
  Widget build(BuildContext context) {
    if (_appLocked && _appLockEnabled && _appLockPin.isNotEmpty) {
      return Scaffold(
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.lock_outline, size: 72),
                    const SizedBox(height: 18),
                    const Text(
                      'بلوساب مقفل',
                      style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    const Text('أدخل رمز القفل للمتابعة', textAlign: TextAlign.center),
                    const SizedBox(height: 18),
                    FilledButton.icon(
                      onPressed: _unlockApp,
                      icon: const Icon(Icons.lock_open),
                      label: const Text('فتح التطبيق'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }
    const isDark = true; // main screens follow the supplied dark neon mockups
    return Theme(
      data: buildBlousabTheme(isDark),
      // Read the updated theme in every descendant, not the outer page context.
      child: Builder(builder: (context) => Scaffold(
        backgroundColor: const Color(0xFF040813),
        body: BlousabScreenFrame(
          child: SafeArea(
            bottom: false,
            child: Column(
              children: [
                if (_homeTabIndex == 2)
                  BlousabTopBar(
                    start: [
                      BlousabSquareIconButton(icon: Icons.add_rounded, tooltip: 'إضافة قصة', onTap: () => blousabCreateStoryRequest.value++),
                      const SizedBox(width: 4),
                      BlousabBell(count: _unreadNotifications, onTap: _openNotifications),
                    ],
                    end: [
                      BlousabSquareIconButton(
                        icon: Icons.search_rounded, size: 42, tooltip: 'بحث',
                        onTap: () { setState(() => _homeTabIndex = 0); blousabChatSearchRequest.value++; },
                      ),
                    ],
                  ),
                Expanded(
                  child: IndexedStack(
                    index: _homeTabIndex,
                    children: [
                      CommunitiesScreen(onNotifications: _openNotifications, notificationCount: _unreadNotifications),
                      PublicFeedScreen(userName: _userName, profilePhotoPath: _profilePhotoPath),
                      StoriesStrip(userName: _userName, profilePhotoPath: _profilePhotoPath, showcase: true),
                      _buildProfileTab(context),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        bottomNavigationBar: Container(
          color: const Color(0xFF040813),
          child: SafeArea(
            top: false,
            child: BlousabBottomNav(
              index: _homeTabIndex,
              onChanged: (index) {
                setState(() {
                  if (index == 3 && _homeTabIndex == 3) _showSettings = false;
                  _homeTabIndex = index;
                });
                _refreshCounters();
              },
            ),
          ),
        ),
      )),
    );
  }
}