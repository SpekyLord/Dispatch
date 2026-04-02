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
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.ParcelUuid
import androidx.core.content.ContextCompat
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.security.MessageDigest
import java.util.UUID

private const val MESH_CONTROL_CHANNEL = "dispatch_mobile/mesh_control"
private const val MESH_EVENTS_CHANNEL = "dispatch_mobile/mesh_events"
private const val MESH_SERVICE_UUID = "8f6e33cb-46d0-46dd-8f13-dc6c2ce4a001"

// BLE discovery runs natively here until Wi-Fi Direct relay sessions are wired end-to-end.
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

    private var eventSink: EventChannel.EventSink? = null
    private var meshScanCallback: ScanCallback? = null
    private var meshAdvertiseCallback: AdvertiseCallback? = null

    fun register(flutterEngine: FlutterEngine) {
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            MESH_CONTROL_CHANNEL,
        ).setMethodCallHandler(this)
        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            MESH_EVENTS_CHANNEL,
        ).setStreamHandler(this)
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
    }

    private fun capabilityMap(): Map<String, Any?> {
        val bleScannerReady = bluetoothAdapter != null && bluetoothScanner != null
        val bleAdvertiserReady = bluetoothAdapter != null && bluetoothAdvertiser != null
        val hasBlePermissions = hasNearbyDevicesPermission()

        return mapOf(
            "bleDiscoverySupported" to bleScannerReady,
            "bleAdvertisingSupported" to bleAdvertiserReady,
            "wifiDirectSupported" to false,
            "bleNote" to when {
                !bleScannerReady -> "BLE discovery hardware is unavailable on this device."
                !hasBlePermissions -> "Grant Nearby Devices permission so Dispatch can discover nearby mesh peers."
                else -> "BLE peer discovery is ready for nearby Dispatch nodes."
            },
            "wifiDirectNote" to "Wi-Fi Direct session handoff is not wired in this build yet, so native mesh discovery currently uses BLE.",
        )
    }

    private fun startDiscovery(localDeviceId: String, isGateway: Boolean): Boolean {
        if (!hasNearbyDevicesPermission()) {
            return false
        }

        val scannerStarted = startBleScan()
        val advertiserStarted = startAdvertising(localDeviceId, isGateway)
        return scannerStarted || advertiserStarted
    }

    private fun stopDiscovery() {
        stopBleScan()
        stopAdvertising()
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
                emitPeer(result)
            }

            override fun onBatchScanResults(results: MutableList<ScanResult>) {
                results.forEach(::emitPeer)
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

    private fun emitPeer(result: ScanResult) {
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
                "timestamp" to System.currentTimeMillis(),
            ),
        )
    }

    private fun emit(payload: Map<String, Any>) {
        mainHandler.post {
            eventSink?.success(payload)
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

    private fun hasNearbyDevicesPermission(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            hasPermission(Manifest.permission.BLUETOOTH_SCAN) &&
                hasPermission(Manifest.permission.BLUETOOTH_ADVERTISE) &&
                hasPermission(Manifest.permission.BLUETOOTH_CONNECT)
        } else {
            hasPermission(Manifest.permission.ACCESS_FINE_LOCATION)
        }
    }

    private fun hasPermission(permission: String): Boolean {
        return ContextCompat.checkSelfPermission(activity, permission) == PackageManager.PERMISSION_GRANTED
    }
}

