import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {
  override func sceneWillResignActive(_ scene: UIScene) {
    ScreenProtection.cover(scene)
    super.sceneWillResignActive(scene)
  }

  override func sceneDidBecomeActive(_ scene: UIScene) {
    super.sceneDidBecomeActive(scene)
    ScreenProtection.uncover(scene)
  }
}

/// App-switcher privacy screen. iOS cannot block screenshots, so while the
/// scene is inactive (app switcher, control centre, incoming call) the window
/// is covered by an opaque blurred view and the mail content never appears in
/// the system snapshot. Toggled from Dart through the
/// `kaydetmail/screen_protection` channel (see AppDelegate).
enum ScreenProtection {
  /// Kept in sync with `ScreenProtectionService.preferenceKey` on the Dart
  /// side; `shared_preferences` stores keys under a "flutter." prefix. Read
  /// straight from UserDefaults so the very first background snapshot after a
  /// cold start is already covered.
  private static let defaultsKey = "flutter.kaydet.security.screenProtectionEnabled"
  private static var override: Bool?

  static var isEnabled: Bool {
    get { override ?? UserDefaults.standard.bool(forKey: defaultsKey) }
    set { override = newValue }
  }

  private static let coverTag = 0x4B41_5944

  static func cover(_ scene: UIScene) {
    guard isEnabled, let window = window(for: scene) else { return }
    if window.viewWithTag(coverTag) != nil { return }
    let blur = UIVisualEffectView(effect: UIBlurEffect(style: .systemThickMaterial))
    blur.tag = coverTag
    blur.frame = window.bounds
    blur.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    window.addSubview(blur)
  }

  static func uncover(_ scene: UIScene) {
    window(for: scene)?.viewWithTag(coverTag)?.removeFromSuperview()
  }

  private static func window(for scene: UIScene) -> UIWindow? {
    guard let windowScene = scene as? UIWindowScene else { return nil }
    return windowScene.windows.first(where: { $0.isKeyWindow }) ?? windowScene.windows.first
  }
}
