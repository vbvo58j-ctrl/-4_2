package com.plosap.myapp

import android.Manifest
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothServerSocket
import android.bluetooth.BluetoothSocket
import android.content.Intent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.IntentFilter
import android.net.Uri
import android.net.wifi.aware.WifiAwareManager
import android.net.wifi.aware.WifiAwareSession
import android.net.wifi.aware.PublishConfig
import android.net.wifi.aware.SubscribeConfig
import android.net.wifi.aware.DiscoverySession
import android.net.wifi.aware.PublishDiscoverySession
import android.net.wifi.aware.SubscribeDiscoverySession
import android.net.wifi.aware.WifiAwareNetworkSpecifier
import android.net.wifi.aware.WifiAwareNetworkInfo
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.net.wifi.aware.AttachCallback
import android.net.wifi.aware.DiscoverySessionCallback
import android.net.wifi.aware.PeerHandle
import android.provider.Settings
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.BufferedReader
import java.io.InputStreamReader
import java.io.OutputStreamWriter
import java.io.PrintWriter
import java.io.DataInputStream
import java.io.DataOutputStream
import java.net.InetSocketAddress
import java.net.ServerSocket
import java.net.Socket
import java.security.MessageDigest
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

class MainActivity : FlutterActivity() {
    companion object {
        private const val METHODS = "com.blousab.messenger/bluetooth"
        private const val EVENTS = "com.blousab.messenger/events"
        private const val SERVICE_NAME = "BlousabRFCOMM"
        private val SERVICE_UUID: UUID =
            UUID.fromString("f0e1d2c3-b4a5-4678-9012-123456789abc")
    }

    private val executor = Executors.newCachedThreadPool()
    private val wifiAwareManager: WifiAwareManager?
        get() = getSystemService(Context.WIFI_AWARE_SERVICE) as? WifiAwareManager
    @Volatile private var wifiAwareSession: WifiAwareSession? = null
    @Volatile private var wifiPublishSession: PublishDiscoverySession? = null
    @Volatile private var wifiSubscribeSession: SubscribeDiscoverySession? = null
    @Volatile private var wifiAwareEventSink: EventChannel.EventSink? = null
    private val pendingWifiAwareEvents = java.util.concurrent.ConcurrentLinkedQueue<Map<String, Any>>()
    @Volatile private var wifiAwareStarted = false
    @Volatile private var wifiAwareStarting = false
    @Volatile private var wifiAwareIdentity = ""
    @Volatile private var wifiAwareUserId = ""
    private val awareNetworkCallbacks = ConcurrentHashMap<String, ConnectivityManager.NetworkCallback>()
    private val awareSockets = ConcurrentHashMap<String, Socket>()
    private val awareWriters = ConcurrentHashMap<String, DataOutputStream>()
    private val awareServers = ConcurrentHashMap<String, ServerSocket>()
    private val awareNetworks = ConcurrentHashMap<String, Network>()
    private val awareConnecting = ConcurrentHashMap.newKeySet<String>()
    private val awareRetryCounts = ConcurrentHashMap<String, Int>()
    private val awareSubscribeHandles = ConcurrentHashMap<String, PeerHandle>()
    private val awarePublishHandles = ConcurrentHashMap<String, PeerHandle>()
    private val awareSocketOpening = ConcurrentHashMap.newKeySet<String>()
    private val awareConnectRequests = ConcurrentHashMap.newKeySet<String>()
    private val awareReconnectScheduled = ConcurrentHashMap.newKeySet<String>()
    private val awarePort = 39773
    private val awareMaxPacketBytes = 1024 * 1024
    private val wifiAwarePeers = ConcurrentHashMap<PeerHandle, Pair<String, String>>()
    private val mainHandler = Handler(Looper.getMainLooper())
    private val serverRunning = AtomicBoolean(false)
    private val sockets = ConcurrentHashMap<String, BluetoothSocket>()
    private val writers = ConcurrentHashMap<String, PrintWriter>()
    private val discovered = ConcurrentHashMap<String, BluetoothDevice>()
    @Volatile private var discoveryReceiver: BroadcastReceiver? = null

    @Volatile private var eventSink: EventChannel.EventSink? = null
    @Volatile private var serverSocket: BluetoothServerSocket? = null

    private val adapter: BluetoothAdapter?
        get() = BluetoothAdapter.getDefaultAdapter()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENTS)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    eventSink = events
                }
                override fun onCancel(arguments: Any?) {
                    eventSink = null
                }
            })

        // معلومات الذاكرة والتخزين لميزة Blousab AI (التحقق قبل تنزيل النموذج).
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.blousab.messenger/device_info")
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "memoryInfo" -> {
                            val am = getSystemService(Context.ACTIVITY_SERVICE) as android.app.ActivityManager
                            val info = android.app.ActivityManager.MemoryInfo()
                            am.getMemoryInfo(info)
                            val stat = android.os.StatFs(filesDir.absolutePath)
                            result.success(mapOf(
                                "totalRam" to info.totalMem,
                                "availRam" to info.availMem,
                                "freeStorage" to stat.availableBytes
                            ))
                        }
                        else -> result.notImplemented()
                    }
                } catch (e: Exception) {
                    result.error("DEVICE_INFO", e.message ?: "تعذر قراءة معلومات الجهاز", null)
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.blousab.messenger/battery")
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "isIgnoringBatteryOptimizations" -> {
                            result.success(if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                                val powerManager = getSystemService(Context.POWER_SERVICE) as android.os.PowerManager
                                powerManager.isIgnoringBatteryOptimizations(packageName)
                            } else true)
                        }
                        "requestIgnoreBatteryOptimizations" -> {
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                                val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS)
                                    .setData(Uri.parse("package:$packageName"))
                                if (intent.resolveActivity(packageManager) != null) startActivity(intent)
                                else startActivity(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS))
                            }
                            result.success(true)
                        }
                        else -> result.notImplemented()
                    }
                } catch (e: Exception) {
                    result.error("BATTERY_SETTINGS", e.message ?: "تعذر فتح إعدادات البطارية", null)
                }
            }

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, "com.blousab.messenger/wifi_aware_events")
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    wifiAwareEventSink = events
                    // The app may start discovery before a screen subscribes. Replay
                    // queued peer events so the first nearby users are not lost.
                    while (true) {
                        val pending = pendingWifiAwareEvents.poll() ?: break
                        events?.success(pending)
                    }
                }
                override fun onCancel(arguments: Any?) { wifiAwareEventSink = null }
            })

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.blousab.messenger/wifi_aware")
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "getAndroidSdk" -> result.success(Build.VERSION.SDK_INT)
                        "isSupported" -> result.success(Build.VERSION.SDK_INT >= 26 && wifiAwareManager != null && packageManager.hasSystemFeature("android.hardware.wifi.aware"))
                        "isAvailable" -> result.success(Build.VERSION.SDK_INT >= 26 && wifiAwareManager?.isAvailable == true)
                        "start" -> {
                            val userId = call.argument<String>("userId") ?: "blousab-user"
                            val userName = call.argument<String>("userName") ?: "مستخدم بلوساب"
                            startWifiAware(userId, userName, result)
                        }
                        "stop" -> { stopWifiAware(); result.success(true) }
                        "sendPacket" -> {
                            val peerId = call.argument<String>("peerId") ?: ""
                            val payload = call.argument<String>("payload") ?: ""
                            executor.execute {
                                try {
                                    sendWifiAwarePacket(peerId, payload)
                                    mainHandler.post { result.success(true) }
                                } catch (e: Exception) {
                                    mainHandler.post { result.error("WIFI_AWARE_SEND", e.message ?: "تعذر إرسال الحزمة عبر Wi-Fi Aware", null) }
                                }
                            }
                        }
                        "connectedPeers" -> result.success(awareSockets.keys.toList())
                        else -> result.notImplemented()
                    }
                } catch (e: SecurityException) {
                    wifiAwareStarting = false
                    result.error("WIFI_AWARE_PERMISSION", e.message ?: "صلاحية Wi-Fi القريب غير متاحة", null)
                } catch (e: Exception) {
                    wifiAwareStarting = false
                    result.error("WIFI_AWARE_ERROR", e.message ?: "تعذر تشغيل اكتشاف Wi-Fi المباشر", null)
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHODS)
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "isSupported" -> result.success(adapter != null)
                        "getAndroidSdk" -> result.success(Build.VERSION.SDK_INT)
                        "isEnabled" -> {
                            if (!hasConnectPermission()) {
                                result.error("PERMISSION", "امنح صلاحية البلوتوث أولاً", null)
                            } else result.success(adapter?.isEnabled == true)
                        }
                        "requestEnable" -> {
                            if (!hasConnectPermission()) {
                                result.error("PERMISSION", "امنح صلاحية البلوتوث أولاً", null)
                            } else {
                                startActivity(Intent(BluetoothAdapter.ACTION_REQUEST_ENABLE))
                                result.success(true)
                            }
                        }
                        "requestDiscoverable" -> {
                            if (!hasConnectPermission() || !hasAdvertisePermission()) {
                                result.error("PERMISSION", "صلاحية إظهار البلوتوث للأجهزة القريبة غير متاحة", null)
                            } else {
                                startActivity(Intent(BluetoothAdapter.ACTION_REQUEST_DISCOVERABLE).putExtra(BluetoothAdapter.EXTRA_DISCOVERABLE_DURATION, 300))
                                result.success(true)
                            }
                        }
                        "startDiscovery" -> {
                            if (!hasConnectPermission() || !hasScanPermission()) {
                                result.error("PERMISSION", "صلاحيات البحث عن أجهزة البلوتوث غير متاحة", null)
                            } else {
                                startDiscovery(result)
                            }
                        }
                        "cancelDiscovery" -> {
                            try { adapter?.cancelDiscovery() } catch (_: Exception) {}
                            result.success(true)
                        }
                        "getPairedDevices" -> {
                            if (!hasConnectPermission()) {
                                result.error("PERMISSION", "صلاحية البلوتوث غير متاحة", null)
                            } else {
                                val devices = adapter?.bondedDevices?.map {
                                    mapOf("name" to (it.name ?: "جهاز"), "address" to it.address)
                                } ?: emptyList<Map<String, String>>()
                                result.success(devices)
                            }
                        }
                        "startServer" -> {
                            if (!hasConnectPermission()) result.error("PERMISSION", "صلاحية البلوتوث غير متاحة", null)
                            else startServer(result)
                        }
                        "connect" -> {
                            if (!hasConnectPermission()) {
                                result.error("PERMISSION", "صلاحية البلوتوث غير متاحة", null)
                            } else {
                                val address = call.argument<String>("address")
                                if (address.isNullOrBlank()) result.error("ADDRESS", "عنوان الجهاز مطلوب", null)
                                else connect(address, result)
                            }
                        }
                        "sendMessage" -> {
                            val address = call.argument<String>("address")
                            val message = call.argument<String>("message")
                            if (address.isNullOrBlank() || message == null) {
                                result.error("ARGUMENT", "بيانات الرسالة ناقصة", null)
                            } else {
                                executor.execute {
                                    try {
                                        val targets = if (address == "*") writers.entries.toList() else {
                                            val writer = writers[address]
                                                ?: throw IllegalStateException("الجهاز غير متصل")
                                            listOf(java.util.AbstractMap.SimpleEntry(address, writer))
                                        }
                                        if (targets.isEmpty()) throw IllegalStateException("لا توجد أجهزة متصلة")
                                        var sent = 0
                                        var lastError: Exception? = null
                                        for ((peerAddress, writer) in targets) {
                                            try {
                                                synchronized(writer) {
                                                    writer.println(message)
                                                    writer.flush()
                                                    if (writer.checkError()) throw java.io.IOException("فشل الإرسال")
                                                }
                                                sent++
                                            } catch (e: Exception) {
                                                lastError = e
                                                closePeer(peerAddress)
                                            }
                                        }
                                        if (sent == 0) throw (lastError ?: java.io.IOException("فشل الإرسال"))
                                        mainHandler.post { result.success(true) }
                                    } catch (e: Exception) {
                                        mainHandler.post {
                                            result.error("SEND", e.message ?: "فشل إرسال الرسالة", null)
                                        }
                                    }
                                }
                            }
                        }
                        "disconnect" -> {
                            val address = call.argument<String>("address")
                            if (address.isNullOrBlank()) closeAll() else closePeer(address)
                            result.success(true)
                        }
                        "stopServer" -> {
                            stopServer()
                            result.success(true)
                        }
                        else -> result.notImplemented()
                    }
                } catch (e: SecurityException) {
                    result.error("PERMISSION", e.message ?: "صلاحية البلوتوث غير متاحة", null)
                } catch (e: Exception) {
                    result.error("NATIVE_ERROR", e.message ?: "حدث خطأ في البلوتوث", null)
                }
            }
    }

    private fun hasWifiAwarePermission(): Boolean = if (Build.VERSION.SDK_INT >= 33) {
        ContextCompat.checkSelfPermission(this, Manifest.permission.NEARBY_WIFI_DEVICES) == PackageManager.PERMISSION_GRANTED
    } else {
        ContextCompat.checkSelfPermission(this, Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED
    }

    private fun emitWifiAware(type: String, userId: String? = null, userName: String? = null, message: String? = null) {
        val event = mutableMapOf<String, Any>("type" to type)
        userId?.let { event["userId"] = it }
        userName?.let { event["userName"] = it }
        message?.let { event["message"] = it }
        mainHandler.post {
            val sink = wifiAwareEventSink
            if (sink != null) {
                sink.success(event)
            } else if (type != "dataPacket") {
                // Keep discovery/status events while no Flutter listener is attached.
                // Media frames are intentionally not queued in memory; feed reconciliation
                // requests any missed content after the UI reconnects.
                if (pendingWifiAwareEvents.size >= 100) pendingWifiAwareEvents.poll()
                pendingWifiAwareEvents.offer(event)
            }
        }
    }

    private fun startWifiAware(userId: String, userName: String, result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < 26) {
            result.error("WIFI_AWARE_UNSUPPORTED", "يتطلب Wi-Fi Aware أندرويد 8 أو أحدث", null); return
        }
        val manager = wifiAwareManager
        if (manager == null || !packageManager.hasSystemFeature("android.hardware.wifi.aware")) {
            result.error("WIFI_AWARE_UNSUPPORTED", "هذا الهاتف لا يدعم Wi-Fi Aware", null); return
        }
        if (!hasWifiAwarePermission()) {
            result.error("WIFI_AWARE_PERMISSION", "امنح صلاحية الأجهزة القريبة عبر Wi-Fi أولاً", null); return
        }
        if (!manager.isAvailable) {
            result.error("WIFI_AWARE_UNAVAILABLE", "Wi-Fi Aware غير متاح الآن. تحقق من تشغيل Wi-Fi ودعم الهاتف", null); return
        }
        if (wifiAwareStarted) {
            emitWifiAware("started", message = "بث بلوساب والبحث المباشر يعملان بالفعل")
            result.success(true)
            return
        }
        if (wifiAwareStarting) {
            result.success(true)
            return
        }
        wifiAwareStarting = true
        wifiAwareUserId = userId
        wifiAwareIdentity = "BLOUSAB|" + userId.take(48) + "|" + userName.replace("|", " ").take(48)
        manager.attach(object : AttachCallback() {
            override fun onAttached(session: WifiAwareSession) {
                wifiAwareSession = session
                try {
                    val payload = wifiAwareIdentity.toByteArray(Charsets.UTF_8).take(220).toByteArray()
                    session.publish(
                        PublishConfig.Builder().setServiceName("blousab-nearby").setServiceSpecificInfo(payload).build(),
                        object : DiscoverySessionCallback() {
                            override fun onPublishStarted(discoverySession: PublishDiscoverySession) {
                                wifiPublishSession = discoverySession
                                markWifiAwareStarted()
                            }
                            override fun onMessageReceived(peerHandle: PeerHandle, message: ByteArray) {
                                val parts = try { String(message, Charsets.UTF_8).split("|", limit = 3) } catch (_: Exception) { emptyList() }
                                if (parts.size >= 2 && parts[0] == "BLOUSAB_CONNECT" && parts[1].isNotBlank() && parts[1] != wifiAwareUserId) {
                                    val peerId = parts[1]
                                    val peerName = parts.getOrNull(2) ?: "مستخدم بلوساب"
                                    awarePublishHandles[peerId] = peerHandle
                                    if (Build.VERSION.SDK_INT >= 29) {
                                        startWifiAwareServerDataPath(peerHandle, peerId, peerName)
                                    } else {
                                        emitWifiAware("dataUnavailable", peerId, peerName, "هذا الجهاز لا يدعم مسار بيانات Wi-Fi Aware المطلوب؛ استخدم LAN إن توفرت")
                                    }
                                }
                            }
                            override fun onSessionConfigFailed() {
                                emitWifiAware("error", message = "فشل بدء بث هوية بلوساب عبر Wi-Fi Aware")
                                stopWifiAware()
                            }
                        }, mainHandler
                    )
                    session.subscribe(
                        SubscribeConfig.Builder().setServiceName("blousab-nearby").build(),
                        object : DiscoverySessionCallback() {
                            override fun onSubscribeStarted(discoverySession: SubscribeDiscoverySession) {
                                wifiSubscribeSession = discoverySession
                                markWifiAwareStarted()
                            }
                            override fun onServiceDiscovered(peerHandle: PeerHandle, serviceSpecificInfo: ByteArray?, matchFilter: List<ByteArray>?) {
                                val raw = try { serviceSpecificInfo?.toString(Charsets.UTF_8) ?: "" } catch (_: Exception) { "" }
                                if (!raw.startsWith("BLOUSAB|")) return
                                val parts = raw.split("|", limit = 3)
                                if (parts.size >= 3 && parts[1].isNotBlank()) {
                                    wifiAwarePeers[peerHandle] = Pair(parts[1], parts[2])
                                    emitWifiAware("userFound", parts[1], parts[2])
                                    if (Build.VERSION.SDK_INT >= 29 && wifiAwareUserId.compareTo(parts[1]) < 0) {
                                        awareSubscribeHandles[parts[1]] = peerHandle
                                        wifiSubscribeSession?.let { sendWifiAwareConnectRequest(peerHandle, parts[1], parts[2], it) }
                                    } else if (Build.VERSION.SDK_INT < 29) {
                                        emitWifiAware("dataUnavailable", parts[1], parts[2], "نقل Wi-Fi Aware المباشر يحتاج Android 10 أو أحدث؛ سيبقى الاكتشاف متاحًا")
                                    }
                                }
                            }
                            override fun onMessageReceived(peerHandle: PeerHandle, message: ByteArray) {
                                val parts = try { String(message, Charsets.UTF_8).split("|", limit = 2) } catch (_: Exception) { emptyList() }
                                if (parts.size == 2 && parts[0] == "BLOUSAB_READY" && parts[1].isNotBlank()) {
                                    val peerId = parts[1]
                                    val peerName = wifiAwarePeers.values.firstOrNull { it.first == peerId }?.second ?: "مستخدم بلوساب"
                                    wifiSubscribeSession?.let { startWifiAwareClientDataPath(peerHandle, peerId, peerName, it) }
                                }
                            }
                            override fun onServiceLost(peerHandle: PeerHandle, reason: Int) {
                                val peer = wifiAwarePeers.remove(peerHandle)
                                if (peer != null) {
                                    closeWifiAwarePeer(peer.first)
                                    awareRetryCounts.remove(peer.first)
                                    awareSubscribeHandles.remove(peer.first)
                                    awarePublishHandles.remove(peer.first)
                                    awareReconnectScheduled.remove(peer.first)
                                    emitWifiAware("userLost", peer.first, peer.second)
                                }
                            }
                            override fun onSessionConfigFailed() {
                                emitWifiAware("error", message = "فشل بدء البحث عن مستخدمي بلوساب عبر Wi-Fi Aware")
                                stopWifiAware()
                            }
                        }, mainHandler
                    )
                } catch (e: Exception) {
                    emitWifiAware("error", message = e.message ?: "تعذر بدء جلسات Wi-Fi Aware")
                    stopWifiAware()
                }
            }
            override fun onAttachFailed() {
                wifiAwareStarting = false
                emitWifiAware("error", message = "فشل تهيئة Wi-Fi Aware على هذا الهاتف")
                stopWifiAware()
            }
        }, mainHandler)
        result.success(true)
    }

    @Synchronized private fun markWifiAwareStarted() {
        if (wifiPublishSession != null && wifiSubscribeSession != null && !wifiAwareStarted) {
            wifiAwareStarted = true
            wifiAwareStarting = false
            emitWifiAware("started", message = "يتم بث إشارة بلوساب والبحث عن الأجهزة القريبة مباشرة")
        }
    }

    @android.annotation.TargetApi(29)
    private fun wifiAwarePassphrase(peerId: String): String {
        val ids = listOf(wifiAwareUserId, peerId).sorted()
        val digest = MessageDigest.getInstance("SHA-256").digest(ids.joinToString("|").toByteArray(Charsets.UTF_8))
        return digest.take(24).joinToString("") { "%02x".format(it) }
    }

    private fun sendWifiAwareConnectRequest(
        peerHandle: PeerHandle,
        peerId: String,
        peerName: String,
        subscribeSession: SubscribeDiscoverySession
    ) {
        if (awareNetworkCallbacks.containsKey(peerId) || awareSockets.containsKey(peerId) || !awareConnectRequests.add(peerId)) return
        try {
            val message = "BLOUSAB_CONNECT|$wifiAwareUserId|${wifiAwareIdentity.substringAfterLast('|').take(24)}".toByteArray(Charsets.UTF_8)
            subscribeSession.sendMessage(peerHandle, (System.currentTimeMillis() and 0x7fffffff).toInt(), message)
            scheduleWifiAwareReconnect(peerId) // L2 discovery messages are short and may need retry.
        } catch (e: Exception) {
            awareConnectRequests.remove(peerId)
            emitWifiAware("dataError", peerId, peerName, e.message ?: "تعذر طلب اتصال Wi-Fi Aware")
            scheduleWifiAwareReconnect(peerId)
        }
    }

    @android.annotation.TargetApi(29)
    private fun startWifiAwareServerDataPath(peerHandle: PeerHandle, peerId: String, peerName: String) {
        val publishSession = wifiPublishSession
        if (publishSession == null) return
        if (awareSockets.containsKey(peerId)) return
        if (awareNetworkCallbacks.containsKey(peerId)) {
            try { publishSession.sendMessage(peerHandle, (System.currentTimeMillis() and 0x7fffffff).toInt(),
                "BLOUSAB_READY|$wifiAwareUserId".toByteArray(Charsets.UTF_8)) } catch (_: Exception) {}
            return
        }
        if (!awareConnecting.add(peerId)) return
        val server = try { ServerSocket(0) } catch (e: Exception) {
            awareConnecting.remove(peerId)
            emitWifiAware("dataError", peerId, peerName, e.message ?: "تعذر فتح منفذ استقبال Wi-Fi Aware")
            return
        }
        awareServers[peerId] = server
        executor.execute {
            try {
                val socket = server.accept()
                attachWifiAwareSocket(peerId, peerName, socket)
            } catch (e: Exception) {
                if (!server.isClosed) {
                    emitWifiAware("dataError", peerId, peerName, e.message ?: "فشل استقبال اتصال Wi-Fi Aware")
                    closeWifiAwarePeer(peerId)
                    scheduleWifiAwareReconnect(peerId)
                }
            } finally {
                awareServers.remove(peerId)
                try { server.close() } catch (_: Exception) {}
            }
        }

        try {
            val specifier = WifiAwareNetworkSpecifier.Builder(publishSession, peerHandle)
                .setPskPassphrase(wifiAwarePassphrase(peerId))
                .setPort(server.localPort)
                .setTransportProtocol(6) // IANA IPPROTO_TCP; server-side only.
                .build()
            val request = NetworkRequest.Builder()
                .addTransportType(NetworkCapabilities.TRANSPORT_WIFI_AWARE)
                .setNetworkSpecifier(specifier)
                .build()
            val connectivity = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
            val callback = object : ConnectivityManager.NetworkCallback() {
                override fun onAvailable(network: Network) {
                    awareNetworks[peerId] = network
                    // The publisher owns the listening socket. The subscriber
                    // requests its side after receiving this short READY message.
                }
                override fun onUnavailable() {
                    closeWifiAwarePeer(peerId)
                    emitWifiAware("dataUnavailable", peerId, peerName, "تعذر إنشاء مسار بيانات Wi-Fi Aware")
                    scheduleWifiAwareReconnect(peerId)
                }
                override fun onLost(network: Network) {
                    closeWifiAwarePeer(peerId)
                    emitWifiAware("dataDisconnected", peerId, peerName, "انقطع اتصال Wi-Fi Aware")
                    scheduleWifiAwareReconnect(peerId)
                }
            }
            awareNetworkCallbacks[peerId] = callback
            connectivity.requestNetwork(request, callback, mainHandler)
            // Notify the subscriber to request its matching side of the NDP.
            publishSession.sendMessage(peerHandle, (System.currentTimeMillis() and 0x7fffffff).toInt(),
                "BLOUSAB_READY|$wifiAwareUserId".toByteArray(Charsets.UTF_8))
        } catch (e: Exception) {
            closeWifiAwarePeer(peerId)
            emitWifiAware("dataError", peerId, peerName, e.message ?: "تعذر طلب مسار بيانات Wi-Fi Aware")
            scheduleWifiAwareReconnect(peerId)
        }
    }

    @android.annotation.TargetApi(29)
    private fun startWifiAwareClientDataPath(
        peerHandle: PeerHandle,
        peerId: String,
        peerName: String,
        subscribeSession: SubscribeDiscoverySession
    ) {
        awareConnectRequests.remove(peerId)
        if (awareNetworkCallbacks.containsKey(peerId) || !awareConnecting.add(peerId)) return
        try {
            val specifier = WifiAwareNetworkSpecifier.Builder(subscribeSession, peerHandle)
                .setPskPassphrase(wifiAwarePassphrase(peerId))
                .build() // Client side: do not set the publisher's port.
            val request = NetworkRequest.Builder()
                .addTransportType(NetworkCapabilities.TRANSPORT_WIFI_AWARE)
                .setNetworkSpecifier(specifier)
                .build()
            val connectivity = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
            val callback = object : ConnectivityManager.NetworkCallback() {
                override fun onAvailable(network: Network) {
                    awareNetworks[peerId] = network
                }
                override fun onCapabilitiesChanged(network: Network, networkCapabilities: NetworkCapabilities) {
                    val info = networkCapabilities.transportInfo as? WifiAwareNetworkInfo ?: return
                    val address = info.peerIpv6Addr
                    val port = info.port
                    if (address == null || port !in 1..65535 || awareSockets.containsKey(peerId) || !awareSocketOpening.add(peerId)) return
                    executor.execute {
                        try {
                            val socket = network.socketFactory.createSocket(address, port)
                            attachWifiAwareSocket(peerId, peerName, socket)
                        } catch (e: Exception) {
                            awareSocketOpening.remove(peerId)
                            closeWifiAwarePeer(peerId)
                            emitWifiAware("dataError", peerId, peerName, e.message ?: "تعذر الاتصال بمنفذ Wi-Fi Aware")
                            scheduleWifiAwareReconnect(peerId)
                        }
                    }
                }
                override fun onUnavailable() {
                    closeWifiAwarePeer(peerId)
                    emitWifiAware("dataUnavailable", peerId, peerName, "تعذر إنشاء مسار بيانات Wi-Fi Aware")
                    scheduleWifiAwareReconnect(peerId)
                }
                override fun onLost(network: Network) {
                    closeWifiAwarePeer(peerId)
                    emitWifiAware("dataDisconnected", peerId, peerName, "انقطع اتصال Wi-Fi Aware")
                    scheduleWifiAwareReconnect(peerId)
                }
            }
            awareNetworkCallbacks[peerId] = callback
            connectivity.requestNetwork(request, callback, mainHandler)
        } catch (e: Exception) {
            closeWifiAwarePeer(peerId)
            emitWifiAware("dataError", peerId, peerName, e.message ?: "تعذر طلب مسار بيانات Wi-Fi Aware")
            scheduleWifiAwareReconnect(peerId)
        }
    }

    private fun scheduleWifiAwareReconnect(peerId: String) {
        if (!awareReconnectScheduled.add(peerId)) return
        val attempts = (awareRetryCounts[peerId] ?: 0) + 1
        awareRetryCounts[peerId] = attempts
        if (attempts > 3) {
            awareReconnectScheduled.remove(peerId)
            return
        }
        mainHandler.postDelayed({
            awareReconnectScheduled.remove(peerId)
            if (!wifiAwareStarted || awareSockets.containsKey(peerId) || awareNetworkCallbacks.containsKey(peerId)) return@postDelayed
            if (wifiAwareUserId.compareTo(peerId) < 0) {
                awareConnectRequests.remove(peerId)
                val handle = awareSubscribeHandles[peerId] ?: return@postDelayed
                val session = wifiSubscribeSession ?: return@postDelayed
                sendWifiAwareConnectRequest(handle, peerId, "مستخدم بلوساب", session)
            } else {
                val handle = awarePublishHandles[peerId] ?: return@postDelayed
                startWifiAwareServerDataPath(handle, peerId, "مستخدم بلوساب")
            }
        }, 2500L)
    }

    /**
     * Registers a connected Wi-Fi Aware TCP socket and continuously receives
     * length-prefixed UTF-8 packets from the remote Blousab client.
     */
    private fun attachWifiAwareSocket(peerId: String, peerName: String, socket: Socket) {
        try {
            socket.tcpNoDelay = true
            socket.keepAlive = true
            // Replace any stale connection for this peer before publishing the new one.
            closeWifiAwareSocketOnly(peerId)
            val input = DataInputStream(socket.getInputStream())
            val output = DataOutputStream(socket.getOutputStream())
            awareSockets[peerId] = socket
            awareWriters[peerId] = output
            awareConnecting.remove(peerId)
            awareSocketOpening.remove(peerId)
            awareRetryCounts.remove(peerId)
            emitWifiAware("dataConnected", peerId, peerName, "اتصل الجهاز عبر Wi-Fi Aware")

            executor.execute {
                try {
                    while (!socket.isClosed) {
                        val packetLength = input.readInt()
                        if (packetLength <= 0 || packetLength > awareMaxPacketBytes) {
                            throw java.io.IOException("حجم حزمة Wi-Fi Aware غير صالح")
                        }
                        val packet = ByteArray(packetLength)
                        input.readFully(packet)
                        emitWifiAware("dataPacket", peerId, peerName, String(packet, Charsets.UTF_8))
                    }
                } catch (e: Exception) {
                    if (!socket.isClosed) {
                        emitWifiAware("dataDisconnected", peerId, peerName,
                            e.message ?: "انقطع اتصال Wi-Fi Aware")
                    }
                } finally {
                    if (awareSockets[peerId] === socket) {
                        closeWifiAwareSocketOnly(peerId)
                        awareConnecting.remove(peerId)
                        awareSocketOpening.remove(peerId)
                        if (wifiAwareStarted) scheduleWifiAwareReconnect(peerId)
                    } else {
                        try { socket.close() } catch (_: Exception) {}
                    }
                }
            }
        } catch (e: Exception) {
            awareConnecting.remove(peerId)
            awareSocketOpening.remove(peerId)
            try { socket.close() } catch (_: Exception) {}
            emitWifiAware("dataError", peerId, peerName,
                e.message ?: "تعذر تهيئة قناة بيانات Wi-Fi Aware")
        }
    }

    private fun sendWifiAwarePacket(peerId: String, payload: String) {
        val bytes = payload.toByteArray(Charsets.UTF_8)
        if (bytes.isEmpty() || bytes.size > awareMaxPacketBytes) throw IllegalArgumentException("حجم الحزمة يتجاوز الحد المسموح")
        val output = awareWriters[peerId] ?: throw IllegalStateException("لا توجد قناة Wi-Fi Aware جاهزة لهذا الجهاز")
        synchronized(output) {
            output.writeInt(bytes.size)
            output.write(bytes)
            output.flush()
        }
    }

    private fun closeWifiAwareSocketOnly(peerId: String) {
        awareWriters.remove(peerId)
        try { awareSockets.remove(peerId)?.close() } catch (_: Exception) {}
    }

    private fun closeWifiAwarePeer(peerId: String) {
        closeWifiAwareSocketOnly(peerId)
        try { awareServers.remove(peerId)?.close() } catch (_: Exception) {}
        awareNetworks.remove(peerId)
        awareConnecting.remove(peerId)
        awareSocketOpening.remove(peerId)
        awareConnectRequests.remove(peerId)
        val callback = awareNetworkCallbacks.remove(peerId)
        if (callback != null) {
            try { (getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager).unregisterNetworkCallback(callback) } catch (_: Exception) {}
        }
    }

    private fun stopWifiAware() {
        wifiAwareStarted = false
        wifiAwareStarting = false
        try { wifiPublishSession?.close() } catch (_: Exception) {}
        try { wifiSubscribeSession?.close() } catch (_: Exception) {}
        wifiPublishSession = null
        wifiSubscribeSession = null
        wifiAwarePeers.clear()
        awareRetryCounts.clear()
        awareSubscribeHandles.clear()
        awarePublishHandles.clear()
        awareSocketOpening.clear()
        awareConnectRequests.clear()
        awareReconnectScheduled.clear()
        awareNetworkCallbacks.keys.toList().forEach { closeWifiAwarePeer(it) }
        awareSockets.keys.toList().forEach { closeWifiAwarePeer(it) }
        try { wifiAwareSession?.close() } catch (_: Exception) {}
        wifiAwareSession = null
        emitWifiAware("stopped")
    }

    private fun hasConnectPermission(): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.S ||
            ContextCompat.checkSelfPermission(this, Manifest.permission.BLUETOOTH_CONNECT) ==
            PackageManager.PERMISSION_GRANTED

    private fun hasScanPermission(): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.S ||
            ContextCompat.checkSelfPermission(this, Manifest.permission.BLUETOOTH_SCAN) ==
            PackageManager.PERMISSION_GRANTED

    private fun hasAdvertisePermission(): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.S ||
            ContextCompat.checkSelfPermission(this, Manifest.permission.BLUETOOTH_ADVERTISE) ==
            PackageManager.PERMISSION_GRANTED

    private fun startDiscovery(result: MethodChannel.Result) {
        val bluetooth = adapter
        if (bluetooth == null || !bluetooth.isEnabled) {
            result.error("BLUETOOTH_OFF", "شغّل البلوتوث أولاً", null)
            return
        }
        try {
            try { bluetooth.cancelDiscovery() } catch (_: Exception) {}
            discoveryReceiver?.let {
                try { unregisterReceiver(it) } catch (_: Exception) {}
            }
            discovered.clear()
            val receiver = object : BroadcastReceiver() {
                override fun onReceive(context: Context?, intent: Intent?) {
                    if (intent?.action != BluetoothDevice.ACTION_FOUND) return
                    @Suppress("DEPRECATION")
                    val device = intent.getParcelableExtra(BluetoothDevice.EXTRA_DEVICE) as? BluetoothDevice ?: return
                    try {
                        val address = device.address ?: return
                        val name = try { device.name ?: "جهاز بلوتوث" } catch (_: SecurityException) { "جهاز بلوتوث" }
                        discovered[address] = device
                        emit("deviceFound", address, name)
                    } catch (_: SecurityException) { }
                }
            }
            discoveryReceiver = receiver
            val filter = IntentFilter(BluetoothDevice.ACTION_FOUND)
            if (Build.VERSION.SDK_INT >= 33) {
                registerReceiver(receiver, filter, Context.RECEIVER_EXPORTED)
            } else {
                @Suppress("DEPRECATION")
                registerReceiver(receiver, filter)
            }
            val started = bluetooth.startDiscovery()
            if (!started) {
                try { unregisterReceiver(receiver) } catch (_: Exception) {}
                discoveryReceiver = null
                result.error("DISCOVERY_FAILED", "تعذر بدء البحث عن أجهزة قريبة", null)
            } else result.success(true)
        } catch (e: Exception) {
            result.error("DISCOVERY_FAILED", e.message ?: "تعذر البحث عن الأجهزة", null)
        }
    }

    private fun emit(type: String, address: String? = null, name: String? = null, message: String? = null) {
        val event = mutableMapOf<String, Any>("type" to type)
        address?.let { event["address"] = it }
        name?.let { event["name"] = it }
        message?.let { event["message"] = it }
        mainHandler.post { eventSink?.success(event) }
    }

    private fun startServer(result: MethodChannel.Result) {
        val bluetooth = adapter
        if (bluetooth == null) {
            result.error("UNSUPPORTED", "هذا الجهاز لا يدعم البلوتوث", null)
            return
        }
        if (!bluetooth.isEnabled) {
            result.error("BLUETOOTH_OFF", "شغّل البلوتوث أولاً", null)
            return
        }
        if (!serverRunning.compareAndSet(false, true)) {
            result.success(true)
            return
        }

        executor.execute {
            try {
                val listening = bluetooth.listenUsingRfcommWithServiceRecord(SERVICE_NAME, SERVICE_UUID)
                serverSocket = listening
                mainHandler.post { result.success(true) }
                emit("serverStarted")
                while (serverRunning.get()) {
                    val client = listening.accept()
                    executor.execute { registerPeer(client) }
                }
            } catch (e: Exception) {
                if (serverRunning.get()) emit("serverError", message = e.message ?: "تعذر تشغيل الاستقبال")
                mainHandler.post {
                    // result.error is only safe if the start request has not already completed;
                    // the event channel reports asynchronous listener errors.
                }
            } finally {
                serverRunning.set(false)
                try { serverSocket?.close() } catch (_: Exception) {}
                serverSocket = null
            }
        }
    }

    private fun connect(address: String, result: MethodChannel.Result) {
        executor.execute {
            var socket: BluetoothSocket? = null
            try {
                val device = adapter?.getRemoteDevice(address)
                    ?: throw IllegalStateException("البلوتوث غير متاح")
                try { adapter?.cancelDiscovery() } catch (_: SecurityException) {}
                socket = device.createRfcommSocketToServiceRecord(SERVICE_UUID)
                socket.connect()
                registerPeer(socket)
                mainHandler.post { result.success(true) }
            } catch (e: Exception) {
                try { socket?.close() } catch (_: Exception) {}
                emit("connectionError", address, message = e.message ?: "تعذر الاتصال بالجهاز")
                mainHandler.post { result.error("CONNECT_FAILED", e.message ?: "تعذر الاتصال بالجهاز", null) }
            }
        }
    }

    private fun registerPeer(socket: BluetoothSocket) {
        val address = socket.remoteDevice.address
        val name = try { socket.remoteDevice.name ?: "جهاز" } catch (_: Exception) { "جهاز" }
        // Keep one socket per physical address to avoid duplicate writers/connection conflicts.
        closePeer(address, notify = false)
        try {
            val writer = PrintWriter(OutputStreamWriter(socket.outputStream, Charsets.UTF_8), true)
            sockets[address] = socket
            writers[address] = writer
            emit("connected", address, name)
            executor.execute {
                try {
                    val reader = BufferedReader(InputStreamReader(socket.inputStream, Charsets.UTF_8))
                    while (true) {
                        val line = reader.readLine() ?: break
                        emit("message", address, name, line)
                    }
                } catch (e: Exception) {
                    emit("connectionError", address, message = e.message ?: "انقطع الاتصال")
                } finally {
                    if (sockets[address] === socket) closePeer(address)
                    else try { socket.close() } catch (_: Exception) {}
                }
            }
        } catch (e: Exception) {
            try { socket.close() } catch (_: Exception) {}
            emit("connectionError", address, message = e.message ?: "تعذر إعداد الاتصال")
        }
    }

    private fun closePeer(address: String, notify: Boolean = true) {
        writers.remove(address)
        try { sockets.remove(address)?.close() } catch (_: Exception) {}
        if (notify) emit("disconnected", address)
    }

    private fun closeAll() {
        sockets.keys.toList().forEach { closePeer(it) }
    }

    private fun stopServer() {
        serverRunning.set(false)
        try { serverSocket?.close() } catch (_: Exception) {}
        serverSocket = null
        closeAll()
        emit("serverStopped")
    }

    override fun onDestroy() {
        stopWifiAware()
        stopServer()
        try { adapter?.cancelDiscovery() } catch (_: Exception) {}
        discoveryReceiver?.let { try { unregisterReceiver(it) } catch (_: Exception) {} }
        discoveryReceiver = null
        executor.shutdownNow()
        super.onDestroy()
    }
}
