import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "ScontriniStorage") {
      registerStorageChannel(messenger: registrar.messenger())
    }
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "ScontriniWindow") {
      registerWindowChannel(messenger: registrar.messenger())
    }
  }

  /// Schermo sicuro (facoltativo): quando l'app non è attiva la copre con
  /// una sfocatura, così il contenuto non compare tra le app recenti.
  private var secureScreen = false
  private var privacyCover: UIView?

  private func registerWindowChannel(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "scontrini/window", binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      guard call.method == "setSecure" else {
        result(FlutterMethodNotImplemented)
        return
      }
      self?.secureScreen = (call.arguments as? Bool) ?? false
      result(nil)
    }
    NotificationCenter.default.addObserver(
      self, selector: #selector(sceneWillDeactivate(_:)), name: UIScene.willDeactivateNotification, object: nil)
    NotificationCenter.default.addObserver(
      self, selector: #selector(sceneDidActivate(_:)), name: UIScene.didActivateNotification, object: nil)
  }

  @objc private func sceneWillDeactivate(_ note: Notification) {
    guard secureScreen, privacyCover == nil, let scene = note.object as? UIWindowScene,
      let window = scene.windows.first(where: { $0.isKeyWindow }) ?? scene.windows.first
    else { return }
    let cover = UIVisualEffectView(effect: UIBlurEffect(style: .systemMaterial))
    cover.frame = window.bounds
    cover.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    window.addSubview(cover)
    privacyCover = cover
  }

  @objc private func sceneDidActivate(_ note: Notification) {
    privacyCover?.removeFromSuperview()
    privacyCover = nil
  }

  /// Esclude la cartella del database dal backup iCloud/iTunes: i dati
  /// escono dal telefono solo con il backup manuale dell'app.
  private func registerStorageChannel(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "scontrini/storage", binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      guard call.method == "excludeFromBackup", let path = call.arguments as? String else {
        result(FlutterMethodNotImplemented)
        return
      }
      var url = URL(fileURLWithPath: path, isDirectory: true)
      var values = URLResourceValues()
      values.isExcludedFromBackup = true
      do {
        try url.setResourceValues(values)
        result(nil)
      } catch {
        result(FlutterError(code: "io", message: error.localizedDescription, details: nil))
      }
    }
  }
}
