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
import android.bluetooth.le.ScanResult
import android.content.Context
import android.content.pm.PackageManager
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
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
import kotlin.concurrent.thread
import kotlin.math.abs
import kotlin.math.log10
import kotlin.math.max
import kotlin.math.sqrt

private const val SAR_CONTROL_CHANNEL = "dispatch_mobile/sar_control"
private const val SAR_EVENTS_CHANNEL = "dispatch_mobile/sar_events"
private const val SOS_SERVICE_UUID = "6f53a7fb-3258-4d8f-bf1d-6cf36442f0e0"

class SarPlatformBridge(
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
    private var bleScanCallback: ScanCallback? = null
    private var advertiseCallback: AdvertiseCallback? = null
    private var audioRecord: AudioRecord? = null
    private var acousticThread: Thread? = null
    @Volatile private var acousticSampling = false

    fun register(flutterEngine: FlutterEngine) {
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            SAR_CONTROL_CHANNEL,
        ).setMethodCallHandler(this)
        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            SAR_EVENTS_CHANNEL,
        ).setStreamHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "getCapabilities" -> result.success(capabilityMap())
            "startBlePassiveScan" -> result.success(startBlePassiveScan())
            "stopBlePassiveScan" -> {
                stopBlePassiveScan()
                result.success(null)
            }
            "startAcousticSampling" -> result.success(startAcousticSampling())
            "stopAcousticSampling" -> {
                stopAcousticSampling()
                result.success(null)
            }
            "startSosBeaconBroadcast" -> startSosBeaconBroadcast(
                call.argument<String>("deviceId") ?: "local-device",
                result,
            )
            "stopSosBeaconBroadcast" -> {
                stopSosBeaconBroadcast()
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
        stopBlePassiveScan()
        stopAcousticSampling()
        stopSosBeaconBroadcast()
    }

    private fun capabilityMap(): Map<String, Any?> {
        val bleAvailable = bluetoothAdapter != null && bluetoothScanner != null
        val advertiseAvailable = bluetoothAdapter != null && bluetoothAdvertiser != null
        val hasBlePermissions = hasNearbyDevicesPermission()
        val hasAudioPermission = hasRecordAudioPermission()

        return mapOf(
            "wifiProbeSupported" to false,
            "wifiProbeNote" to "Standard Android app sandboxes cannot passively sniff Wi-Fi probe requests without privileged device access.",
            "blePassiveSupported" to bleAvailable,
            "blePassiveNote" to when {
                !bleAvailable -> "BLE scanning hardware is unavailable on this device."
                !hasBlePermissions -> "Grant Nearby Devices permission to scan for nearby BLE beacons."
                else -> "BLE passive scan is ready for nearby advertising devices."
            },
            "acousticSupported" to true,
            "acousticNote" to if (hasAudioPermission) {
                "On-device 5-second microphone summaries are ready. Raw audio never leaves the phone."
            } else {
                "Grant Microphone permission to classify 5-second local audio windows on-device."
            },
            "sosBeaconSupported" to advertiseAvailable,
            "sosBeaconNote" to when {
                !advertiseAvailable -> "BLE advertising is unavailable on this device."
                !hasBlePermissions -> "Grant Nearby Devices permission to advertise this phone as an SOS beacon."
                else -> "SOS beacon advertising is ready on this device."
            },
        )
    }

    private fun startBlePassiveScan(): Boolean {
        if (bleScanCallback != null) {
            return true
        }
        val scanner = bluetoothScanner ?: return false
        if (!hasNearbyDevicesPermission()) {
            return false
        }

        bleScanCallback = object : ScanCallback() {
            override fun onScanResult(callbackType: Int, result: ScanResult) {
                emitBleResult(result)
            }

            override fun onBatchScanResults(results: MutableList<ScanResult>) {
                results.forEach(::emitBleResult)
            }
        }

        return try {
            scanner.startScan(bleScanCallback)
            true
        } catch (_: SecurityException) {
            bleScanCallback = null
            false
        } catch (_: IllegalStateException) {
            bleScanCallback = null
            false
        }
    }

    private fun stopBlePassiveScan() {
        val callback = bleScanCallback ?: return
        try {
            bluetoothScanner?.stopScan(callback)
        } catch (_: SecurityException) {
            // Best effort stop.
        }
        bleScanCallback = null
    }

    private fun startSosBeaconBroadcast(deviceId: String, result: MethodChannel.Result) {
        if (advertiseCallback != null) {
            result.success(true)
            return
        }
        val advertiser = bluetoothAdvertiser
        if (advertiser == null || !hasNearbyDevicesPermission()) {
            result.success(false)
            return
        }

        val callback = object : AdvertiseCallback() {
            override fun onStartSuccess(settingsInEffect: AdvertiseSettings) {
                advertiseCallback = this
                result.success(true)
            }

            override fun onStartFailure(errorCode: Int) {
                advertiseCallback = null
                result.success(false)
            }
        }

        val serviceUuid = ParcelUuid(UUID.fromString(SOS_SERVICE_UUID))
        val advertiseData = AdvertiseData.Builder()
            .addServiceUuid(serviceUuid)
            .addServiceData(serviceUuid, hashedDeviceIdentifier(deviceId))
            .setIncludeDeviceName(false)
            .setIncludeTxPowerLevel(false)
            .build()
        val settings = AdvertiseSettings.Builder()
            .setAdvertiseMode(AdvertiseSettings.ADVERTISE_MODE_LOW_LATENCY)
            .setConnectable(false)
            .setTxPowerLevel(AdvertiseSettings.ADVERTISE_TX_POWER_HIGH)
            .build()

        try {
            advertiser.startAdvertising(settings, advertiseData, callback)
        } catch (_: SecurityException) {
            advertiseCallback = null
            result.success(false)
        } catch (_: IllegalStateException) {
            advertiseCallback = null
            result.success(false)
        }
    }

    private fun stopSosBeaconBroadcast() {
        val callback = advertiseCallback ?: return
        try {
            bluetoothAdvertiser?.stopAdvertising(callback)
        } catch (_: SecurityException) {
            // Best effort stop.
        }
        advertiseCallback = null
    }

    private fun startAcousticSampling(): Boolean {
        if (acousticSampling) {
            return true
        }
        if (!hasRecordAudioPermission()) {
            return false
        }

        val sampleRate = 16000
        val minBuffer = AudioRecord.getMinBufferSize(
            sampleRate,
            AudioFormat.CHANNEL_IN_MONO,
            AudioFormat.ENCODING_PCM_16BIT,
        )
        if (minBuffer <= 0) {
            return false
        }

        val recorder = AudioRecord(
            MediaRecorder.AudioSource.MIC,
            sampleRate,
            AudioFormat.CHANNEL_IN_MONO,
            AudioFormat.ENCODING_PCM_16BIT,
            max(minBuffer * 2, sampleRate),
        )
        if (recorder.state != AudioRecord.STATE_INITIALIZED) {
            recorder.release()
            return false
        }

        return try {
            recorder.startRecording()
            audioRecord = recorder
            acousticSampling = true
            acousticThread = thread(start = true, name = "dispatch-sar-audio") {
                runAcousticLoop(recorder, sampleRate)
            }
            true
        } catch (_: SecurityException) {
            recorder.release()
            false
        } catch (_: IllegalStateException) {
            recorder.release()
            false
        }
    }

    private fun stopAcousticSampling() {
        acousticSampling = false
        acousticThread?.interrupt()
        acousticThread = null
        val recorder = audioRecord
        audioRecord = null
        if (recorder != null) {
            try {
                recorder.stop()
            } catch (_: IllegalStateException) {
                // Recorder may already be stopped.
            }
            recorder.release()
        }
    }

    private fun emitBleResult(result: ScanResult) {
        val scanRecord = result.scanRecord
        val serviceUuid = ParcelUuid(UUID.fromString(SOS_SERVICE_UUID))
        val beaconData = scanRecord?.getServiceData(serviceUuid)
        val hasSosService = beaconData != null ||
            (scanRecord?.serviceUuids?.any { it.uuid.toString().equals(SOS_SERVICE_UUID, ignoreCase = true) } == true)
        val identifier = if (beaconData != null && beaconData.isNotEmpty()) {
            beaconData.joinToString(separator = "") { byte -> "%02X".format(byte) }
        } else {
            result.device.address ?: "UNKNOWN"
        }

        emit(
            mapOf(
                "type" to "ble_scan",
                "address" to (result.device.address ?: "UNKNOWN"),
                "rssi" to result.rssi,
                "isSosBeacon" to hasSosService,
                "beaconIdentifier" to identifier,
                "timestamp" to System.currentTimeMillis(),
            ),
        )
    }

    // Summarize each 5-second microphone window so Flutter only receives
    // classifier-friendly features, never the raw PCM samples themselves.
    private fun runAcousticLoop(recorder: AudioRecord, sampleRate: Int) {
        val windowSamples = sampleRate * 5
        val buffer = ShortArray(1024)

        while (acousticSampling && !Thread.currentThread().isInterrupted) {
            var totalSamples = 0
            var peakAbs = 0
            var sumSquares = 0.0
            var zeroCrossings = 0
            var transientFrames = 0
            var highEnergyFrames = 0
            var frameSamples = 0
            var frameSquares = 0.0
            var lastFrameDb = -120.0
            var previousSample = 0

            while (acousticSampling && totalSamples < windowSamples) {
                val requested = minOf(buffer.size, windowSamples - totalSamples)
                val read = recorder.read(buffer, 0, requested)
                if (read <= 0) {
                    break
                }
                for (index in 0 until read) {
                    val sample = buffer[index].toInt()
                    val absSample = abs(sample)
                    peakAbs = max(peakAbs, absSample)
                    sumSquares += sample * sample.toDouble()
                    frameSquares += sample * sample.toDouble()
                    if ((sample >= 0 && previousSample < 0) || (sample < 0 && previousSample >= 0)) {
                        zeroCrossings += 1
                    }
                    previousSample = sample
                    frameSamples += 1
                    totalSamples += 1

                    if (frameSamples >= 320) {
                        val frameRms = sqrt(frameSquares / frameSamples) / Short.MAX_VALUE.toDouble()
                        val frameDb = if (frameRms > 0) 20 * log10(frameRms) else -120.0
                        if (frameDb >= -28.0) {
                            highEnergyFrames += 1
                        }
                        if (frameDb - lastFrameDb >= 12.0) {
                            transientFrames += 1
                        }
                        lastFrameDb = frameDb
                        frameSamples = 0
                        frameSquares = 0.0
                    }
                }
            }

            if (totalSamples == 0) {
                continue
            }

            val normalizedPeak = peakAbs / Short.MAX_VALUE.toDouble()
            val peakDb = if (normalizedPeak > 0) 20 * log10(normalizedPeak) else 0.0
            val rms = sqrt(sumSquares / totalSamples) / Short.MAX_VALUE.toDouble()
            val rmsDb = if (rms > 0) 20 * log10(rms) else -120.0
            val zcr = zeroCrossings / totalSamples.toDouble()
            val voiceBandPresent = rmsDb >= -34.0 && zcr in 0.03..0.20 && highEnergyFrames >= 8
            val repeatedImpacts = transientFrames >= 3 && peakDb >= -22.0
            val anomalyDetected = peakDb >= -18.0 && (highEnergyFrames >= 10 || rmsDb >= -26.0)

            emit(
                mapOf(
                    "type" to "acoustic_window",
                    "peakDb" to (peakDb + 90.0),
                    "repeatedImpacts" to repeatedImpacts,
                    "voiceBandPresent" to voiceBandPresent,
                    "anomalyDetected" to anomalyDetected,
                    "timestamp" to System.currentTimeMillis(),
                ),
            )
        }
    }

    private fun emit(payload: Map<String, Any>) {
        mainHandler.post {
            eventSink?.success(payload)
        }
    }

    private fun hashedDeviceIdentifier(deviceId: String): ByteArray {
        return MessageDigest.getInstance("SHA-256")
            .digest(deviceId.toByteArray())
            .copyOfRange(0, 6)
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

    private fun hasRecordAudioPermission(): Boolean {
        return hasPermission(Manifest.permission.RECORD_AUDIO)
    }

    private fun hasPermission(permission: String): Boolean {
        return ContextCompat.checkSelfPermission(activity, permission) == PackageManager.PERMISSION_GRANTED
    }
}
