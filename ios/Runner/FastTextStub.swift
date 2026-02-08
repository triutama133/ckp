import Foundation
import Flutter

// NOTE: This is a stub. Implement native fastText loading/inference here using a C++ bridge or port.
public class FastTextStub: NSObject {
  private let channel: FlutterMethodChannel
  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: "ckp/fasttext", binaryMessenger: messenger)
    super.init()
    channel.setMethodCallHandler(handle)
  }

  private func handle(call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "loadModel":
      // let args = call.arguments as? [String:Any]
      // let path = args?["path"] as? String
      result(nil)
    case "predict":
      // let args = call.arguments as? [String:Any]
      // let text = args?["text"] as? String ?? ""
      // return sample
      result([["label": "create", "score": 0.75]])
    default:
      result(FlutterMethodNotImplemented)
    }
  }
}
