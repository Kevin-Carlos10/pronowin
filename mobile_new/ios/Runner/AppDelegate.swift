import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    for name in [UIApplication.willResignActiveNotification, UIScene.willDeactivateNotification] {
      NotificationCenter.default.addObserver(self, selector: #selector(coverPrivateContent), name: name, object: nil)
    }
    for name in [UIApplication.didBecomeActiveNotification, UIScene.didActivateNotification] {
      NotificationCenter.default.addObserver(self, selector: #selector(revealPrivateContent), name: name, object: nil)
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  private var privacyCovers: [UIView] = []

  @objc private func coverPrivateContent() {
    guard privacyCovers.isEmpty else { return }
    for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) {
      for window in scene.windows where window.isKeyWindow {
        let cover = UIView(frame: window.bounds)
        cover.backgroundColor = .systemBackground
        cover.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        cover.isUserInteractionEnabled = true
        window.addSubview(cover)
        privacyCovers.append(cover)
      }
    }
  }

  @objc private func revealPrivateContent() {
    // Flutter retains its own cover until the lock route is ready.
    privacyCovers.forEach { $0.removeFromSuperview() }
    privacyCovers.removeAll()
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}
