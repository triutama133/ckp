import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
  // Initialize FastText platform channel stub
  let messenger = self as! FlutterBinaryMessenger
  _ = FastTextStub(messenger: messenger)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
