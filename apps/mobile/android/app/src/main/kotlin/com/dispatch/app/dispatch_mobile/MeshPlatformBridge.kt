package com.dispatch.app.dispatch_mobile

import android.Manifest
import android.app.Activity
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothManager
import android.bluetooth.le.AdvertiseCallback
import android.bluetooth.le.AdvertiseData
import android.bluetooth.le.AdvertiseSettings
import android.bluetooth.le.BluetoothLeAdvertiser
import android.bluetooth.le.BluetoothLeScanner
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanFilter
import android.bluetooth.le.ScanResult
import android.bluetooth.le.ScanSettings
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.net.NetworkInfo
import android.net.wifi.WpsInfo
import android.net.wifi.p2p.WifiP2pConfig
import android.net.wifi.p2p.WifiP2pDevice
import android.net.wifi.p2p.WifiP2pDeviceList
import android.net.wifi.p2p.WifiP2pInfo
import android.net.wifi.p2p.WifiP2pManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.ParcelUuid
import androidx.core.content.ContextCompat
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject
import java.io.BufferedReader
import java.io.BufferedWriter
import java.io.InputStreamReader
import java.io.OutputStreamWriter
import java.net.InetSocketAddress
import java.net.ServerSocket
import java.net.Socket
import java.security.MessageDigest
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap

private const val MESH_CONTROL_CHANNEL = "dispatch_mobile/mesh_control"
private const val MESH_EVENTS_CHANNEL = "dispatch_mobile/mesh_events"
private const val MESH_SERVICE_UUID = "8f6e33cb-46d0-46dd-8f13-dc6c2ce4a001"
private const val MESH_SOCKET_PORT = 45454

// BLE handles nearby discovery while Wi-Fi Direct sockets move full packet payloads between peers.
class MeshPlatformBridge(
    private val activity: Activity,
    private val context: Context,
) : MethodChannel.MethodCallHandler, EventChannel.StreamHandler {
    private val mainHandler = Handler(Looper.getMainLooper())
    private val bluetoothManager = context.getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager
    private val bluetoothAdapter: BluetoothAdapter? = bluetoothManager.adapter
    private val bluetoothScanner: BluetoothLeScanner?
        get() = bluetoothAdapter?.bluetoothLeScanner
    private val bluetoothAdvertiser: BluetoothLeAdvertiser?
        get() = bluetoothAdapter?.bluetoothLeAdvertiser
    private val wifiP2pManager = context.getSystemService(Context.WIFI_P2P_SERVICE) as? WifiP2pManager
    private val wifiP2pChannel = wifiP2pManager?.initialize(context, Looper.getMainLooper(), null)
    private val knownPeers = mutableMapOf<String, WifiP2pDevice>()
    private val connectionAttempts = mutableSetOf<String>()
    private val peerConnections = ConcurrentHashMap<String, PeerConnection>()

    private var eventSink: EventChannel.EventSink? = null
    private var meshScanCallback: ScanCallback? = null
    private var meshAdvertiseCallback: AdvertiseCallback? = null
    private var discoveryActive = false
    private var receiverRegistered = false
    private var localDeviceId = "dispatch-node"
    private var gatewayNode = false
    private var localWifiEndpointId = ""
    private var localDisplayName = Build.MODEL ?: "Dispatch Device"
    private var serverSocket: ServerSocket? = null
    private var acceptThread: Thread? = null
    private var wifiReceiver: BroadcastReceiver? = null

    fun register(flutterEngine: FlutterEngine) {
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            MESH_CONTROL_CHANNEL,
        ).setMethodCallHandler(this)
        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            MESH_EVENTS_CHANNEL,
        ).setStreamHandler(this)
        ensureWifiReceiverRegistered()
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "getCapabilities" -> result.success(capabilityMap())
            "startDiscovery" -> result.success(
                startDiscovery(
                    localDeviceId = call.argument<String>("localDeviceId") ?: "dispatch-node",
                    isGateway = call.argument<Boolean>("isGateway") == true,
                ),
            )
            "sendPacket" -> result.success(
                sendPacket(
                    packet = normalizeMap(call.argument<Map<*, *>>("packet") ?: emptyMap<Any, Any>()),
                    preferredTransport = call.argument<String>("preferredTransport") ?: "wifi_direct",
                    excludeEndpointIds = (call.argument<List<*>>("excludeEndpointIds") ?: emptyList<Any>())
                        .mapNotNull { it as? String }
                        .toSet(),
                ),
            )
            "stopDiscovery" -> {
                stopDiscovery()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        eventSink = events
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    fun dispose() {
        stopDiscovery()
        unregisterWifiReceiver()
    }

    private fun capabilityMap(): Map<String, Any?> {
        val bleScannerReady = bluetoothAdapter != null && bluetoothScanner != null
        val bleAdvertiserReady = bluetoothAdapter != null && bluetoothAdvertiser != null
        val hasBlePermissions = hasBlePermissions()
        val wifiDirectReady = wifiP2pManager != null && wifiP2pChannel != null
        val hasWifiPermissions = hasWifiDirectPermissions()

        return mapOf(
            "bleDiscoverySupported" to bleScannerReady,
            "bleAdvertisingSupported" to bleAdvertiserReady,
            "wifiDirectSupported" to wifiDirectReady,
            "bleNote" to when {
                !bleScannerReady -> "BLE discovery hardware is unavailable on this device."
                !hasBlePermissions -> "Grant Nearby Devices permission so Dispatch can discover nearby mesh peers."
                else -> "BLE discovery is ready for nearby Dispatch nodes."
            },
            "wifiDirectNote" to when {
                !wifiDirectReady -> "Wi-Fi Direct is unavailable on this device build."
                !hasWifiPermissions -> "Grant Wi-Fi nearby-device permission so Dispatch can open offline relay sockets."
                else -> "Wi-Fi Direct discovery and packet relay are ready."
            },
        )
    }

    private fun startDiscovery(localDeviceId: String, isGateway: Boolean): Boolean {
        this.localDeviceId = localDeviceId
        this.gatewayNode = isGateway
        this.localWifiEndpointId = fingerprintFrom(hashedIdentifier(localDeviceId))
        this.discoveryActive = true
        ensureWifiReceiverRegistered()
        startServerSocketIfNeeded()

        val bleStarted = if (hasBlePermissions()) {
            startBleScan() || startAdvertising(localDeviceId, isGateway)
        } else {
            false
        }
        val wifiStarted = if (hasWifiDirectPermissions()) {
            startWifiDirectDiscovery()
        } else {
            false
        }
        emitTransportState(
            note = if (wifiStarted) {
                "Scanning for Wi-Fi Direct peers and keeping the relay socket ready."
            } else {
                "Discovery started with BLE only because Wi-Fi Direct permissions are missing or unsupported."
            },
        )
        return bleStarted || wifiStarted
    }

    private fun stopDiscovery() {
        discoveryActive = false
        stopBleScan()
        stopAdvertising()
        stopWifiDirectDiscovery()
        closePeerConnections()
        stopServerSocket()
        emitTransportState(note = "Mesh discovery stopped.")
    }

    private fun startBleScan(): Boolean {
        if (meshScanCallback != null) {
            return true
        }
        val scanner = bluetoothScanner ?: return false

        val serviceUuid = ParcelUuid(UUID.fromString(MESH_SERVICE_UUID))
        val filters = listOf(ScanFilter.Builder().setServiceUuid(serviceUuid).build())
        val settings = ScanSettings.Builder()
            .setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY)
            .build()

        meshScanCallback = object : ScanCallback() {
            override fun onScanResult(callbackType: Int, result: ScanResult) {
                emitBlePeer(result)
            }

            override fun onBatchScanResults(results: MutableList<ScanResult>) {
                results.forEach(::emitBlePeer)
            }
        }

        return try {
            scanner.startScan(filters, settings, meshScanCallback)
            true
        } catch (_: SecurityException) {
            meshScanCallback = null
            false
        } catch (_: IllegalStateException) {
            meshScanCallback = null
            false
        }
    }

    private fun stopBleScan() {
        val callback = meshScanCallback ?: return
        try {
            bluetoothScanner?.stopScan(callback)
        } catch (_: SecurityException) {
            // Best effort stop.
        }
        meshScanCallback = null
    }

    private fun startAdvertising(localDeviceId: String, isGateway: Boolean): Boolean {
        if (meshAdvertiseCallback != null) {
            return true
        }
        val advertiser = bluetoothAdvertiser ?: return false
        val serviceUuid = ParcelUuid(UUID.fromString(MESH_SERVICE_UUID))
        val settings = AdvertiseSettings.Builder()
            .setAdvertiseMode(AdvertiseSettings.ADVERTISE_MODE_LOW_LATENCY)
            .setConnectable(false)
            .setTxPowerLevel(AdvertiseSettings.ADVERTISE_TX_POWER_MEDIUM)
            .build()
        val advertiseData = AdvertiseData.Builder()
            .addServiceUuid(serviceUuid)
            .addServiceData(
                serviceUuid,
                byteArrayOf(if (isGateway) 1 else 0) + hashedIdentifier(localDeviceId),
            )
            .setIncludeDeviceName(false)
            .setIncludeTxPowerLevel(false)
            .build()

        val callback = object : AdvertiseCallback() {
            override fun onStartSuccess(settingsInEffect: AdvertiseSettings) {
                meshAdvertiseCallback = this
            }

            override fun onStartFailure(errorCode: Int) {
                meshAdvertiseCallback = null
            }
        }

        return try {
            advertiser.startAdvertising(settings, advertiseData, callback)
            meshAdvertiseCallback = callback
            true
        } catch (_: SecurityException) {
            meshAdvertiseCallback = null
            false
        } catch (_: IllegalStateException) {
            meshAdvertiseCallback = null
            false
        }
    }

    private fun stopAdvertising() {
        val callback = meshAdvertiseCallback ?: return
        try {
            bluetoothAdvertiser?.stopAdvertising(callback)
        } catch (_: SecurityException) {
            // Best effort stop.
        }
        meshAdvertiseCallback = null
    }

    private fun emitBlePeer(result: ScanResult) {
        val record = result.scanRecord ?: return
        val serviceUuid = ParcelUuid(UUID.fromString(MESH_SERVICE_UUID))
        val serviceData = record.getServiceData(serviceUuid) ?: return
        val isGateway = serviceData.isNotEmpty() && serviceData[0].toInt() == 1
        val endpointId = result.device.address ?: fingerprintFrom(serviceData)
        val shortId = fingerprintFrom(serviceData)
        val deviceName = result.device.name ?: "Dispatch ${if (isGateway) "Gateway" else "Node"} $shortId"

        emit(
            mapOf(
                "type" to "peer_seen",
                "endpointId" to endpointId,
                "deviceName" to deviceName,
                "isGateway" to isGateway,
                "supportsWifiDirect" to false,
                "isConnected" to false,
                "transport" to "ble_discovery",
                "timestamp" to System.currentTimeMillis(),
            ),
        )
    }

    private fun startWifiDirectDiscovery(): Boolean {
        val manager = wifiP2pManager ?: return false
        val channel = wifiP2pChannel ?: return false
        return try {
            manager.discoverPeers(
                channel,
                object : WifiP2pManager.ActionListener {
                    override fun onSuccess() {
                        requestWifiPeers()
                    }

                    override fun onFailure(reason: Int) {
                        emitTransportState(note = "Wi-Fi Direct discovery failed with code $reason.")
                    }
                },
            )
            true
        } catch (_: SecurityException) {
            false
        } catch (_: IllegalStateException) {
            false
        }
    }

    private fun stopWifiDirectDiscovery() {
        val manager = wifiP2pManager ?: return
        val channel = wifiP2pChannel ?: return
        try {
            manager.stopPeerDiscovery(channel, object : WifiP2pManager.ActionListener {
                override fun onSuccess() = Unit
                override fun onFailure(reason: Int) = Unit
            })
        } catch (_: SecurityException) {
            // Best effort stop.
        }
    }

    private fun requestWifiPeers() {
        val manager = wifiP2pManager ?: return
        val channel = wifiP2pChannel ?: return
        try {
            manager.requestPeers(channel) { peers: WifiP2pDeviceList ->
                knownPeers.clear()
                peers.deviceList.forEach { device ->
                    knownPeers[device.deviceAddress] = device
                    val connected = peerConnections.containsKey(device.deviceAddress)
                    emit(
                        mapOf(
                            "type" to "peer_seen",
                            "endpointId" to device.deviceAddress,
                            "deviceName" to (device.deviceName ?: "Dispatch Node"),
                            "isGateway" to (gatewayNode && device.deviceAddress != localWifiEndpointId),
                            "supportsWifiDirect" to true,
                            "isConnected" to connected,
                            "transport" to if (connected) "wifi_direct" else "wifi_discovery",
                            "timestamp" to System.currentTimeMillis(),
                        ),
                    )
                    if (!connected) {
                        connectToPeer(device)
                    }
                }
                emitTransportState()
            }
        } catch (_: SecurityException) {
            emitTransportState(note = "Wi-Fi Direct peers require permission before relay sessions can start.")
        }
    }

    private fun connectToPeer(device: WifiP2pDevice) {
        val manager = wifiP2pManager ?: return
        val channel = wifiP2pChannel ?: return
        if (device.status == WifiP2pDevice.CONNECTED || connectionAttempts.contains(device.deviceAddress)) {
            return
        }

        val config = WifiP2pConfig().apply {
            deviceAddress = device.deviceAddress
            wps.setup = WpsInfo.PBC
            groupOwnerIntent = if (gatewayNode) 15 else 0
        }

        connectionAttempts.add(device.deviceAddress)
        try {
            manager.connect(
                channel,
                config,
                object : WifiP2pManager.ActionListener {
                    override fun onSuccess() {
                        emitTransportState(note = "Negotiating Wi-Fi Direct session with ${device.deviceName ?: device.deviceAddress}.")
                    }

                    override fun onFailure(reason: Int) {
                        connectionAttempts.remove(device.deviceAddress)
                        emitTransportState(note = "Wi-Fi Direct connect failed with code $reason.")
                    }
                },
            )
        } catch (_: SecurityException) {
            connectionAttempts.remove(device.deviceAddress)
        }
    }

    private fun handleConnectionChanged(networkInfo: NetworkInfo?) {
        val manager = wifiP2pManager ?: return
        val channel = wifiP2pChannel ?: return
        if (networkInfo?.isConnected != true) {
            emitTransportState(note = "Wi-Fi Direct session disconnected.")
            return
        }

        try {
            manager.requestConnectionInfo(channel) { info: WifiP2pInfo ->
                if (!info.groupFormed) {
                    emitTransportState(note = "Wi-Fi Direct group is still forming.")
                    return@requestConnectionInfo
                }
                startServerSocketIfNeeded()
                if (!info.isGroupOwner && info.groupOwnerAddress != null) {
                    connectSocketToHost(info.groupOwnerAddress.hostAddress ?: "192.168.49.1")
                }
                emitTransportState(
                    note = if (info.isGroupOwner) {
                        "Group owner relay ready on Wi-Fi Direct."
                    } else {
                        "Connected to Wi-Fi Direct relay owner."
                    },
                )
            }
        } catch (_: SecurityException) {
            emitTransportState(note = "Wi-Fi Direct connection info is blocked by missing permission.")
        }
    }

    private fun startServerSocketIfNeeded() {
        if (serverSocket != null) {
            return
        }
        try {
            val socket = ServerSocket(MESH_SOCKET_PORT)
            serverSocket = socket
            acceptThread = Thread {
                while (!socket.isClosed) {
                    try {
                        val client = socket.accept()
                        attachSocket(client)
                    } catch (_: Exception) {
                        break
                    }
                }
            }.also {
                it.name = "dispatch-mesh-accept"
                it.start()
            }
        } catch (_: Exception) {
            emitTransportState(note = "Unable to open the mesh relay socket on this device.")
        }
    }

    private fun stopServerSocket() {
        try {
            serverSocket?.close()
        } catch (_: Exception) {
            // Best effort close.
        }
        serverSocket = null
        acceptThread = null
    }

    private fun connectSocketToHost(hostAddress: String) {
        val attemptKey = "socket:$hostAddress"
        if (peerConnections.values.any { it.hostAddress == hostAddress } || connectionAttempts.contains(attemptKey)) {
            return
        }
        connectionAttempts.add(attemptKey)
        Thread {
            try {
                val socket = Socket()
                socket.connect(InetSocketAddress(hostAddress, MESH_SOCKET_PORT), 3500)
                attachSocket(socket)
            } catch (_: Exception) {
                emitTransportState(note = "Wi-Fi Direct relay socket is waiting for a peer to accept connections.")
            } finally {
                connectionAttempts.remove(attemptKey)
            }
        }.apply {
            name = "dispatch-mesh-connect"
            start()
        }
    }

    private fun attachSocket(socket: Socket) {
        try {
            socket.tcpNoDelay = true
            PeerConnection(socket).start()
        } catch (_: Exception) {
            try {
                socket.close()
            } catch (_: Exception) {
                // Ignore secondary close errors.
            }
        }
    }

    private fun closePeerConnections() {
        val connections = peerConnections.values.toList()
        peerConnections.clear()
        connections.forEach { it.close() }
        connectionAttempts.clear()
    }

    private fun sendPacket(
        packet: Map<String, Any?>,
        preferredTransport: String,
        excludeEndpointIds: Set<String>,
    ): Map<String, Any?> {
        val sentEndpointIds = mutableListOf<String>()
        val frame = mapOf(
            "type" to "packet",
            "packet" to packet,
            "timestamp" to System.currentTimeMillis(),
        )
        val snapshot = peerConnections.entries.toList()
        snapshot.forEach { (endpointId, connection) ->
            if (excludeEndpointIds.contains(endpointId)) {
                return@forEach
            }
            if (connection.sendFrame(frame)) {
                sentEndpointIds += endpointId
            }
        }
        emitTransportState()
        return mapOf(
            "transport" to if (sentEndpointIds.isNotEmpty()) "wifi_direct" else preferredTransport,
            "attemptedPeerCount" to snapshot.size,
            "sentEndpointIds" to sentEndpointIds,
        )
    }

    private fun ensureWifiReceiverRegistered() {
        if (receiverRegistered) {
            return
        }
        val manager = wifiP2pManager ?: return
        val channel = wifiP2pChannel ?: return
        wifiReceiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                when (intent?.action) {
                    WifiP2pManager.WIFI_P2P_STATE_CHANGED_ACTION -> {
                        val enabled = intent.getIntExtra(WifiP2pManager.EXTRA_WIFI_STATE, 0) == WifiP2pManager.WIFI_P2P_STATE_ENABLED
                        emitTransportState(
                            note = if (enabled) {
                                "Wi-Fi Direct radio is enabled."
                            } else {
                                "Wi-Fi Direct is disabled on this device."
                            },
                        )
                    }
                    WifiP2pManager.WIFI_P2P_PEERS_CHANGED_ACTION -> requestWifiPeers()
                    WifiP2pManager.WIFI_P2P_CONNECTION_CHANGED_ACTION -> {
                        @Suppress("DEPRECATION")
                        val networkInfo = intent.getParcelableExtra<NetworkInfo>(WifiP2pManager.EXTRA_NETWORK_INFO)
                        handleConnectionChanged(networkInfo)
                    }
                    WifiP2pManager.WIFI_P2P_THIS_DEVICE_CHANGED_ACTION -> {
                        val device = intent.getParcelableExtra<WifiP2pDevice>(WifiP2pManager.EXTRA_WIFI_P2P_DEVICE)
                        if (device != null) {
                            localDisplayName = device.deviceName ?: localDisplayName
                            localWifiEndpointId = device.deviceAddress ?: localWifiEndpointId
                        }
                    }
                }
            }
        }
        val filter = IntentFilter().apply {
            addAction(WifiP2pManager.WIFI_P2P_STATE_CHANGED_ACTION)
            addAction(WifiP2pManager.WIFI_P2P_PEERS_CHANGED_ACTION)
            addAction(WifiP2pManager.WIFI_P2P_CONNECTION_CHANGED_ACTION)
            addAction(WifiP2pManager.WIFI_P2P_THIS_DEVICE_CHANGED_ACTION)
        }
        context.registerReceiver(wifiReceiver, filter)
        receiverRegistered = true
        emitTransportState(note = if (manager != null && channel != null) "Wi-Fi Direct bridge ready." else "Wi-Fi Direct bridge unavailable.")
    }

    private fun unregisterWifiReceiver() {
        if (!receiverRegistered) {
            return
        }
        try {
            context.unregisterReceiver(wifiReceiver)
        } catch (_: Exception) {
            // Ignore duplicate unregisters.
        }
        receiverRegistered = false
        wifiReceiver = null
    }

    private fun emitTransportState(note: String? = null) {
        emit(
            mapOf(
                "type" to "transport_state",
                "discoveryActive" to discoveryActive,
                "connectedPeerCount" to peerConnections.size,
                "activeTransport" to when {
                    peerConnections.isNotEmpty() -> "wifi_direct"
                    meshScanCallback != null -> "ble_discovery"
                    else -> null
                },
                "note" to note,
                "timestamp" to System.currentTimeMillis(),
            ),
        )
    }

    private fun emit(payload: Map<String, Any?>) {
        mainHandler.post {
            eventSink?.success(payload)
        }
    }

    private fun normalizeMap(raw: Map<*, *>): Map<String, Any?> {
        return raw.entries.associate { (key, value) ->
            key.toString() to normalizeValue(value)
        }
    }

    private fun normalizeValue(value: Any?): Any? {
        return when (value) {
            is Map<*, *> -> normalizeMap(value)
            is List<*> -> value.map(::normalizeValue)
            is Number, is Boolean, is String -> value
            null -> null
            else -> value.toString()
        }
    }

    private fun jsonObjectFromMap(map: Map<String, Any?>): JSONObject {
        val json = JSONObject()
        map.forEach { (key, value) -> json.put(key, jsonValue(value)) }
        return json
    }

    private fun jsonValue(value: Any?): Any? {
        return when (value) {
            null -> JSONObject.NULL
            is Map<*, *> -> jsonObjectFromMap(normalizeMap(value))
            is List<*> -> JSONArray(value.map(::jsonValue))
            else -> value
        }
    }

    private fun mapFromJsonObject(json: JSONObject): Map<String, Any?> {
        val map = mutableMapOf<String, Any?>()
        val keys = json.keys()
        while (keys.hasNext()) {
            val key = keys.next()
            map[key] = fromJsonValue(json.get(key))
        }
        return map
    }

    private fun fromJsonValue(value: Any?): Any? {
        return when (value) {
            JSONObject.NULL -> null
            is JSONObject -> mapFromJsonObject(value)
            is JSONArray -> (0 until value.length()).map { index -> fromJsonValue(value.get(index)) }
            else -> value
        }
    }

    private fun hashedIdentifier(raw: String): ByteArray {
        return MessageDigest.getInstance("SHA-256")
            .digest(raw.toByteArray())
            .copyOfRange(0, 6)
    }

    private fun fingerprintFrom(bytes: ByteArray): String {
        val payload = if (bytes.size > 1) bytes.copyOfRange(1, bytes.size) else bytes
        return payload.joinToString(separator = "") { byte -> "%02X".format(byte) }
    }

    private fun hasBlePermissions(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            hasPermission(Manifest.permission.BLUETOOTH_SCAN) &&
                hasPermission(Manifest.permission.BLUETOOTH_ADVERTISE) &&
                hasPermission(Manifest.permission.BLUETOOTH_CONNECT)
        } else {
            hasPermission(Manifest.permission.ACCESS_FINE_LOCATION)
        }
    }

    private fun hasWifiDirectPermissions(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            hasPermission(Manifest.permission.NEARBY_WIFI_DEVICES)
        } else {
            hasPermission(Manifest.permission.ACCESS_FINE_LOCATION)
        }
    }

    private fun hasPermission(permission: String): Boolean {
        return ContextCompat.checkSelfPermission(activity, permission) == PackageManager.PERMISSION_GRANTED
    }

    private inner class PeerConnection(private val socket: Socket) {
        private val reader = BufferedReader(InputStreamReader(socket.getInputStream()))
        private val writer = BufferedWriter(OutputStreamWriter(socket.getOutputStream()))
        val hostAddress: String = socket.inetAddress?.hostAddress ?: "unknown-host"
        private var running = true
        private var endpointId: String = hostAddress
        private var deviceName: String = "Dispatch Node"
        private var remoteGateway = false

        fun start() {
            sendFrame(
                mapOf(
                    "type" to "hello",
                    "endpointId" to (localWifiEndpointId.ifEmpty { localDeviceId }),
                    "localDeviceId" to localDeviceId,
                    "deviceName" to localDisplayName,
                    "isGateway" to gatewayNode,
                ),
            )
            Thread {
                try {
                    while (running) {
                        val line = reader.readLine() ?: break
                        val json = JSONObject(line)
                        when (json.optString("type")) {
                            "hello" -> handleHello(json)
                            "packet" -> handlePacket(json)
                        }
                    }
                } catch (_: Exception) {
                    // Socket closed or malformed frame.
                } finally {
                    close()
                }
            }.apply {
                name = "dispatch-mesh-peer-$hostAddress"
                start()
            }
        }

        fun sendFrame(frame: Map<String, Any?>): Boolean {
            if (!running) {
                return false
            }
            return try {
                synchronized(writer) {
                    writer.write(jsonObjectFromMap(frame).toString())
                    writer.newLine()
                    writer.flush()
                }
                true
            } catch (_: Exception) {
                close()
                false
            }
        }

        private fun handleHello(json: JSONObject) {
            endpointId = json.optString("endpointId").ifBlank { hostAddress }
            deviceName = json.optString("deviceName").ifBlank { "Dispatch Node" }
            remoteGateway = json.optBoolean("isGateway", false)
            peerConnections[endpointId] = this
            connectionAttempts.remove(endpointId)
            emit(
                mapOf(
                    "type" to "peer_seen",
                    "endpointId" to endpointId,
                    "deviceName" to deviceName,
                    "isGateway" to remoteGateway,
                    "supportsWifiDirect" to true,
                    "isConnected" to true,
                    "transport" to "wifi_direct",
                    "timestamp" to System.currentTimeMillis(),
                ),
            )
            emitTransportState(note = "Relay link active with $deviceName.")
        }

        private fun handlePacket(json: JSONObject) {
            val packetJson = json.optJSONObject("packet") ?: return
            emit(
                mapOf(
                    "type" to "packet_received",
                    "sourceEndpointId" to endpointId,
                    "transport" to "wifi_direct",
                    "packet" to mapFromJsonObject(packetJson),
                    "timestamp" to System.currentTimeMillis(),
                ),
            )
        }

        fun close() {
            if (!running) {
                return
            }
            running = false
            peerConnections.remove(endpointId, this)
            try {
                socket.close()
            } catch (_: Exception) {
                // Ignore secondary close errors.
            }
            emitTransportState(note = "Relay link closed for $deviceName.")
        }
    }
}

