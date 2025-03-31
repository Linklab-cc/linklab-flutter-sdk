import Flutter
import UIKit
import Linklab

@available(iOS 14.3, *)
public class LinkLabFlutterPlugin: NSObject, FlutterPlugin {
  private var channel: FlutterMethodChannel?
  private var linkDestination: LinkDestination?
  private var pendingInitialLinkRequest = false
  
  public static func register(with registrar: FlutterPluginRegistrar) {
    NSLog("LinkLabFlutterPlugin - register called")
    let channel = FlutterMethodChannel(name: "cc.linklab.flutter/linklab", binaryMessenger: registrar.messenger())
    let instance = LinkLabFlutterPlugin()
    instance.channel = channel
    registrar.addMethodCallDelegate(instance, channel: channel)
    registrar.addApplicationDelegate(instance)
    NSLog("LinkLabFlutterPlugin - registration complete")
  }

  public func application(_ application: UIApplication, continue userActivity: NSUserActivity, restorationHandler: @escaping ([Any]) -> Void) -> Bool {
    NSLog("LinkLabFlutterPlugin - application continue userActivity: \(userActivity.activityType)")
    if userActivity.activityType == NSUserActivityTypeBrowsingWeb, let url = userActivity.webpageURL {
      NSLog("LinkLabFlutterPlugin - handling universal link: \(url.absoluteString)")
      return handleUniversalLink(url)
    }
    NSLog("LinkLabFlutterPlugin - not a web browsing activity or no URL")
    return false
  }

  private func handleUniversalLink(_ url: URL) -> Bool {
    NSLog("LinkLabFlutterPlugin - handleUniversalLink: \(url.absoluteString)")
    let result = Linklab.shared.handleUniversalLink(url)
    NSLog("LinkLabFlutterPlugin - handleUniversalLink result: \(result)")
    return result
  }

  private func convertLinkDestinationToMap(_ destination: LinkDestination?) -> [String: Any]? {
    NSLog("LinkLabFlutterPlugin - convertLinkDestinationToMap called")
    guard let destination = destination else {
      NSLog("LinkLabFlutterPlugin - convertLinkDestinationToMap: destination is nil")
      return nil
    }

    let map = [
      "id": destination.route,
      "fullLink": destination.route,
      "createdAt": Int(Date().timeIntervalSince1970 * 1000),
      "updatedAt": Int(Date().timeIntervalSince1970 * 1000),
      "userId": "",
      "domainType": "custom",
      "domain": destination.route,
      "parameters": destination.parameters
    ]
    NSLog("LinkLabFlutterPlugin - convertLinkDestinationToMap: created map with route: \(destination.route)")
    return map
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    NSLog("LinkLabFlutterPlugin - handle method called: \(call.method)")
    switch call.method {
    case "init":
      NSLog("LinkLabFlutterPlugin - initializing with config")
      let config = Configuration(
        debugLoggingEnabled: true
      )

      Linklab.shared.initialize(with: config) { [weak self] destination in
        NSLog("LinkLabFlutterPlugin - initialize callback received")
        self?.linkDestination = destination

        if let destination = destination, let channel = self?.channel {
          NSLog("LinkLabFlutterPlugin - destination received in init callback: \(destination.route)")
          let linkData = self?.convertLinkDestinationToMap(destination)
          NSLog("LinkLabFlutterPlugin - invoking onDynamicLinkReceived")
          channel.invokeMethod("onDynamicLinkReceived", arguments: linkData)
        } else {
          NSLog("LinkLabFlutterPlugin - no destination or channel in init callback")
        }

        if self?.pendingInitialLinkRequest == true {
          NSLog("LinkLabFlutterPlugin - resolving pending initial link request")
          self?.pendingInitialLinkRequest = false
          result(self?.convertLinkDestinationToMap(destination))
        }
      }
      NSLog("LinkLabFlutterPlugin - init completed, returning true")
      result(true)

    case "getInitialLink":
      NSLog("LinkLabFlutterPlugin - getInitialLink called")
      if let linkDestination = self.linkDestination {
        NSLog("LinkLabFlutterPlugin - getInitialLink: returning cached destination: \(linkDestination.route)")
        result(convertLinkDestinationToMap(linkDestination))
      } else {
        NSLog("LinkLabFlutterPlugin - getInitialLink: no cached destination, setting pendingInitialLinkRequest")
        pendingInitialLinkRequest = true
        // Will return result when deep link is received
      }

    case "getDynamicLink":
      NSLog("LinkLabFlutterPlugin - getDynamicLink called")
      guard let args = call.arguments as? [String: Any],
            let shortLink = args["shortLink"] as? String,
            let url = URL(string: shortLink) else {
        NSLog("LinkLabFlutterPlugin - getDynamicLink: invalid arguments")
        result(FlutterError(code: "INVALID_ARGS", message: "Invalid URL", details: nil))
        return
      }

      NSLog("LinkLabFlutterPlugin - getDynamicLink: processing URL: \(url.absoluteString)")
      if handleUniversalLink(url) { //TODO check how do we send full link details to external app?
        NSLog("LinkLabFlutterPlugin - getDynamicLink: handleUniversalLink returned true")
        result(true)
      } else {
        NSLog("LinkLabFlutterPlugin - getDynamicLink: handleUniversalLink returned false")
        result(false)
      }

    case "isLinkLabLink":
      NSLog("LinkLabFlutterPlugin - isLinkLabLink called")
      guard let args = call.arguments as? [String: Any],
            let link = args["link"] as? String,
            let url = URL(string: link) else {
        NSLog("LinkLabFlutterPlugin - isLinkLabLink: invalid arguments")
        result(false)
        return
      }

      NSLog("LinkLabFlutterPlugin - isLinkLabLink: checking URL: \(url.absoluteString)")
      // Simple check if domain is linklab domain
      if url.host?.contains("linklab.cc") == true {
        NSLog("LinkLabFlutterPlugin - isLinkLabLink: URL is a LinkLab link")
        result(true)
      } else {
        NSLog("LinkLabFlutterPlugin - isLinkLabLink: URL is not a LinkLab link")
        result(false)
      }

    default:
      NSLog("LinkLabFlutterPlugin - unhandled method called: \(call.method)")
      result(FlutterMethodNotImplemented)
    }
  }
}

// Forwarding for iOS versions below 14.3
public class SwiftLinkLabFlutterPlugin: NSObject {
  public static func register(with registrar: FlutterPluginRegistrar) {
    NSLog("SwiftLinkLabFlutterPlugin - register called")
    if #available(iOS 14.3, *) {
      NSLog("SwiftLinkLabFlutterPlugin - iOS 14.3+ detected, registering LinkLabFlutterPlugin")
      LinkLabFlutterPlugin.register(with: registrar)
    } else {
      NSLog("SwiftLinkLabFlutterPlugin - iOS below 14.3 detected, setting up stub implementation")
      let channel = FlutterMethodChannel(name: "cc.linklab.flutter/linklab", binaryMessenger: registrar.messenger())
      channel.setMethodCallHandler { (call, result) in
        NSLog("SwiftLinkLabFlutterPlugin - method called but not supported on this iOS version: \(call.method)")
        result(FlutterMethodNotImplemented)
      }
    }
    NSLog("SwiftLinkLabFlutterPlugin - registration complete")
  }
}