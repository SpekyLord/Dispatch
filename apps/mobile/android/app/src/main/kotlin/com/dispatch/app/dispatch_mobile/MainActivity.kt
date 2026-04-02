package com.dispatch.app.dispatch_mobile

import android.content.Context
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel

class MainActivity : FlutterActivity() {
    private var sarPlatformBridge: SarPlatformBridge? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        val sensorManager = getSystemService(Context.SENSOR_SERVICE) as SensorManager
        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "dispatch_mobile/compass_heading",
        ).setStreamHandler(CompassHeadingStreamHandler(sensorManager))

        sarPlatformBridge = SarPlatformBridge(this, applicationContext).also {
            it.register(flutterEngine)
        }
    }

    override fun onDestroy() {
        sarPlatformBridge?.dispose()
        sarPlatformBridge = null
        super.onDestroy()
    }
}

private class CompassHeadingStreamHandler(
    private val sensorManager: SensorManager,
) : EventChannel.StreamHandler, SensorEventListener {
    private val accelerometerReadings = FloatArray(3)
    private val magnetometerReadings = FloatArray(3)
    private val rotationMatrix = FloatArray(9)
    private val orientationAngles = FloatArray(3)
    private val accelerometer = sensorManager.getDefaultSensor(Sensor.TYPE_ACCELEROMETER)
    private val magnetometer = sensorManager.getDefaultSensor(Sensor.TYPE_MAGNETIC_FIELD)

    private var eventSink: EventChannel.EventSink? = null
    private var hasAccelerometer = false
    private var hasMagnetometer = false

    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        eventSink = events
        if (accelerometer == null || magnetometer == null) {
            events.error(
                "unavailable",
                "Heading sensors unavailable on this device.",
                null,
            )
            return
        }

        sensorManager.registerListener(this, accelerometer, SensorManager.SENSOR_DELAY_UI)
        sensorManager.registerListener(this, magnetometer, SensorManager.SENSOR_DELAY_UI)
    }

    override fun onCancel(arguments: Any?) {
        sensorManager.unregisterListener(this)
        eventSink = null
        hasAccelerometer = false
        hasMagnetometer = false
    }

    override fun onSensorChanged(event: SensorEvent) {
        when (event.sensor.type) {
            Sensor.TYPE_ACCELEROMETER -> {
                System.arraycopy(event.values, 0, accelerometerReadings, 0, accelerometerReadings.size)
                hasAccelerometer = true
            }
            Sensor.TYPE_MAGNETIC_FIELD -> {
                System.arraycopy(event.values, 0, magnetometerReadings, 0, magnetometerReadings.size)
                hasMagnetometer = true
            }
        }

        if (!hasAccelerometer || !hasMagnetometer) {
            return
        }

        // Fuse gravity + magnetic field so Flutter receives a north-referenced heading.
        if (!SensorManager.getRotationMatrix(rotationMatrix, null, accelerometerReadings, magnetometerReadings)) {
            return
        }

        SensorManager.getOrientation(rotationMatrix, orientationAngles)
        val heading = Math.toDegrees(orientationAngles[0].toDouble())
        val normalizedHeading = ((heading % 360) + 360) % 360

        eventSink?.success(
            mapOf(
                "heading" to normalizedHeading,
                "accuracy" to accuracyMeters(event.accuracy),
                "timestamp" to System.currentTimeMillis(),
                "source" to "android-sensor-fusion",
            ),
        )
    }

    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) = Unit

    private fun accuracyMeters(accuracy: Int): Double {
        return when (accuracy) {
            SensorManager.SENSOR_STATUS_ACCURACY_HIGH -> 5.0
            SensorManager.SENSOR_STATUS_ACCURACY_MEDIUM -> 12.0
            SensorManager.SENSOR_STATUS_ACCURACY_LOW -> 24.0
            else -> 48.0
        }
    }
}

