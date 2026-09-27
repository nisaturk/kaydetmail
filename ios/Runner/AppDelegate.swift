import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    excludeLocalMailDataFromBackup()
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  /// The encrypted mail cache/outbox lives in Application Support, which iOS
  /// otherwise includes in iCloud and computer backups. Caches is never
  /// backed up; the flag is set there too so a future OS policy change
  /// cannot silently start copying downloaded attachments off-device.
  private func excludeLocalMailDataFromBackup() {
    let manager = FileManager.default
    for directory in [FileManager.SearchPathDirectory.applicationSupportDirectory, .cachesDirectory] {
      guard var url = manager.urls(for: directory, in: .userDomainMask).first else { continue }
      try? manager.createDirectory(at: url, withIntermediateDirectories: true)
      var values = URLResourceValues()
      values.isExcludedFromBackup = true
      try? url.setResourceValues(values)
    }
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}
