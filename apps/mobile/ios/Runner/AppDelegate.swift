import CoreLocation
import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private let compassStreamHandler = CompassHeadingStreamHandler()

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "CompassHeadingStreamHandler")
    let channel = FlutterEventChannel(
      name: "dispatch_mobile/compass_heading",
      binaryMessenger: registrar.messenger()
    )
    channel.setStreamHandler(compassStreamHandler)
  }
}

final class CompassHeadingStreamHandler: NSObject, FlutterStreamHandler, CLLocationManagerDelegate {
  private let locationManager = CLLocationManager()
  private var eventSink: FlutterEventSink?

  override init() {
    super.init()
    locationManager.delegate = self
    locationManager.headingFilter = 1
  }

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    guard CLLocationManager.headingAvailable() else {
      return FlutterError(
        code: "unavailable",
        message: "Heading sensors unavailable on this device.",
        details: nil
      )
    }

    self.eventSink = events
    let status = locationManager.authorizationStatus
    if status == .notDetermined {
      locationManager.requestWhenInUseAuthorization()
    }
    locationManager.startUpdatingHeading()
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    locationManager.stopUpdatingHeading()
    eventSink = nil
    return nil
  }

  func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
    if eventSink != nil {
      manager.startUpdatingHeading()
    }
  }

  func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
    let heading = newHeading.trueHeading >= 0 ? newHeading.trueHeading : newHeading.magneticHeading
    eventSink?([
      "heading": normalize(heading),
      "accuracy": newHeading.headingAccuracy,
      "timestamp": Int(Date().timeIntervalSince1970 * 1000),
      "source": "ios-heading"
    ])
  }

  func locationManagerShouldDisplayHeadingCalibration(_ manager: CLLocationManager) -> Bool {
    return true
  }

  private func normalize(_ degrees: CLLocationDirection) -> CLLocationDirection {
    let value = degrees.truncatingRemainder(dividingBy: 360)
    return value >= 0 ? value : value + 360
  }
}