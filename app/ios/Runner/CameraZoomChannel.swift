import AVFoundation
import Flutter

final class CameraZoomChannel: NSObject, FlutterPlugin {
  private lazy var device = AVCaptureDevice.DiscoverySession(
    deviceTypes: [.builtInTripleCamera, .builtInDualCamera, .builtInWideAngleCamera],
    mediaType: .video,
    position: .back
  ).devices.first
  private weak var captureSession: AVCaptureSession?
  private var sessionObserver: NSObjectProtocol?

  static func register(with registrar: FlutterPluginRegistrar) {
    let instance = CameraZoomChannel()
    let channel = FlutterMethodChannel(
      name: "dev.herdr.herdr_mobile/camera_zoom",
      binaryMessenger: registrar.messenger()
    )
    registrar.addMethodCallDelegate(instance, channel: channel)
    instance.sessionObserver = NotificationCenter.default.addObserver(
      forName: AVCaptureSession.didStartRunningNotification,
      object: nil,
      queue: .main
    ) { [weak instance] notification in
      guard let instance = instance,
        let session = notification.object as? AVCaptureSession,
        let device = instance.device,
        let input = session.inputs.first(where: {
          ($0 as? AVCaptureDeviceInput)?.device.uniqueID == device.uniqueID
        }) as? AVCaptureDeviceInput
      else { return }
      instance.device = input.device
      instance.captureSession = session
    }
  }

  deinit {
    if let observer = sessionObserver {
      NotificationCenter.default.removeObserver(observer)
    }
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard call.method == "getRange" || call.method == "setZoom" else {
      result(FlutterMethodNotImplemented)
      return
    }
    guard let device = device else {
      result(FlutterError(code: "camera_unavailable", message: "No back camera is available.", details: nil))
      return
    }
    guard captureSession?.isRunning == true else {
      result(FlutterError(code: "camera_not_running", message: "The camera is not running.", details: nil))
      return
    }

    if call.method == "getRange" {
      let factors = device.virtualDeviceSwitchOverVideoZoomFactors
      var wideZoom: CGFloat = 1
      for (index, constituent) in device.constituentDevices.enumerated() {
        if constituent.deviceType != .builtInUltraWideCamera {
          if index > 0 && index <= factors.count {
            wideZoom = CGFloat(truncating: factors[index - 1])
          }
          break
        }
      }
      result([
        "minZoom": Double(device.minAvailableVideoZoomFactor),
        "maxZoom": Double(device.maxAvailableVideoZoomFactor),
        "wideZoom": Double(wideZoom),
        "switchOverFactors": factors.map { $0.doubleValue },
      ])
      return
    }

    guard let arguments = call.arguments as? [String: Any],
      let zoom = arguments["zoom"] as? Double, zoom.isFinite,
      let animated = arguments["animated"] as? Bool
    else {
      result(FlutterError(code: "invalid_arguments", message: "Provide a finite zoom and an animated flag.", details: nil))
      return
    }
    do {
      try device.lockForConfiguration()
      defer { device.unlockForConfiguration() }
      let factor = CGFloat(zoom)
      guard factor >= device.minAvailableVideoZoomFactor,
        factor <= device.maxAvailableVideoZoomFactor
      else {
        result(FlutterError(code: "invalid_zoom", message: "The zoom is outside the camera range.", details: nil))
        return
      }
      if animated {
        device.ramp(toVideoZoomFactor: factor, withRate: 8)
      } else {
        device.cancelVideoZoomRamp()
        device.videoZoomFactor = factor
      }
      result(nil)
    } catch {
      result(FlutterError(code: "camera_error", message: error.localizedDescription, details: nil))
    }
  }
}
