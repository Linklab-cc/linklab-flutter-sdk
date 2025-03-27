import Flutter
import UIKit
import Linklab

@available(iOS 14.3, *)
public class LinkLabFlutterPlugin: NSObject, FlutterPlugin {
  private var channel: FlutterMethodChannel?
  private var linkDestination: LinkDestination?
  private var pendingInitialLinkRequest = false
  
  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "cc.linklab.flutter/linklab", binaryMessenger: registrar.messenger())
    let instance = LinkLabFlutterPlugin()
    instance.channel = channel
    registrar.addMethodCallDelegate(instance, channel: channel)
    registrar.addApplicationDelegate(instance)
  }
  
  public func application(_ application: UIApplication, continue userActivity: NSUserActivity, restorationHandler: @escaping ([Any]) -> Void) -> Bool {
    if userActivity.activityType == NSUserActivityTypeBrowsingWeb, let url = userActivity.webpageURL {
      return handleUniversalLink(url)
    }
    return false
  }
  
  private func handleUniversalLink(_ url: URL) -> Bool {
    return Linklab.shared.handleUniversalLink(url)
  }
  
  private func convertLinkDestinationToMap(_ destination: LinkDestination?) -> [String: Any]? {
    guard let destination = destination else { return nil }
    
    return [
      "id": destination.route,
      "fullLink": destination.route,
      "createdAt": Int(Date().timeIntervalSince1970 * 1000),
      "updatedAt": Int(Date().timeIntervalSince1970 * 1000),
      "userId": "",
      "domainType": "custom",
      "domain": destination.route,
      "parameters": destination.parameters
    ]
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "init":
      let config = Configuration(
        debugLoggingEnabled: true
      )
      
      Linklab.shared.initialize(with: config) { [weak self] destination in
        self?.linkDestination = destination

        if let destination = destination, let channel = self?.channel {
          let linkData = self?.convertLinkDestinationToMap(destination)
          channel.invokeMethod("onDynamicLinkReceived", arguments: linkData)
        }

        if self?.pendingInitialLinkRequest == true {
          self?.pendingInitialLinkRequest = false
          result(self?.convertLinkDestinationToMap(destination))
        }
      }
      result(true)

    case "getInitialLink":
      if let linkDestination = self.linkDestination {
        result(convertLinkDestinationToMap(linkDestination))
      } else {
        pendingInitialLinkRequest = true
        // Will return result when deep link is received
      }

    case "getDynamicLink":
      guard let args = call.arguments as? [String: Any],
            let shortLink = args["shortLink"] as? String,
            let url = URL(string: shortLink) else {
        result(FlutterError(code: "INVALID_ARGS", message: "Invalid URL", details: nil))
        return
      }

      if handleUniversalLink(url) { //TODO check how do we send full link details to external app?
        result(true)
      } else {
        result(false)
      }

    case "isLinkLabLink":
      guard let args = call.arguments as? [String: Any],
            let link = args["link"] as? String,
            let url = URL(string: link) else {
        result(false)
        return
      }

      // Simple check if domain is linklab domain
      if url.host?.contains("linklab.cc") == true {
        result(true)
      } else {
        result(false)
      }

    default:
      result(FlutterMethodNotImplemented)
    }
  }
}

// Forwarding for iOS versions below 14.3
public class SwiftLinkLabFlutterPlugin: NSObject {
  public static func register(with registrar: FlutterPluginRegistrar) {
    if #available(iOS 14.3, *) {
      LinkLabFlutterPlugin.register(with: registrar)
    } else {
      let channel = FlutterMethodChannel(name: "cc.linklab.flutter/linklab", binaryMessenger: registrar.messenger())
      channel.setMethodCallHandler { (call, result) in
        result(FlutterMethodNotImplemented)
      }
    }
  }
}