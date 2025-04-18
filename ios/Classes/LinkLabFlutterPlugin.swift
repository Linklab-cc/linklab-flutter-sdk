import Flutter
import UIKit
import Linklab

@available(iOS 14.3, *)
public class LinkLabFlutterPlugin: NSObject, FlutterPlugin {
  private var channel: FlutterMethodChannel?

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
    // Since handleIncomingURL is @MainActor-isolated, we need to dispatch to the main actor
    Task { @MainActor in
      _ = Linklab.shared.handleIncomingURL(url)
    }
    // We return true to indicate we're handling the URL, though the actual processing will happen asynchronously
    return true
  }

  // Convert LinkData to a map format that Flutter can understand
  private func convertLinkDataToMap(_ linkData: LinkData?) -> [String: Any]? {
    NSLog("LinkLabFlutterPlugin - convertLinkDataToMap called")
    guard let linkData = linkData else {
      NSLog("LinkLabFlutterPlugin - convertLinkDataToMap: linkData is nil")
      return nil
    }

    // Create a date formatter to convert Date objects to milliseconds since epoch
    let dateFormatter = ISO8601DateFormatter()

    var createdAtMs: Int64 = 0
    if let createdAt = linkData.createdAt {
        createdAtMs = Int64(createdAt.timeIntervalSince1970 * 1000)
    }

    var updatedAtMs: Int64 = 0
    if let updatedAt = linkData.updatedAt {
        updatedAtMs = Int64(updatedAt.timeIntervalSince1970 * 1000)
    }

    let map: [String: Any] = [
      "id": linkData.id,
      "fullLink": linkData.fullLink,
      "createdAt": createdAtMs,
      "updatedAt": updatedAtMs,
      "userId": linkData.userId,
      "packageName": linkData.packageName ?? "",
      "bundleId": linkData.bundleId ?? "",
      "appStoreId": linkData.appStoreId ?? "",
      "domainType": linkData.domainType,
      "domain": linkData.domain,
      // Add any additional parameters if needed
      "parameters": [:] // In the new implementation, you might need to extract parameters from somewhere else
    ]

    NSLog("LinkLabFlutterPlugin - convertLinkDataToMap: created map with id: \(linkData.id)")
    return map
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    NSLog("LinkLabFlutterPlugin - handle method called: \(call.method)")
    switch call.method {
    case "init":
      NSLog("LinkLabFlutterPlugin - initializing with config")

      // Parse configuration from Flutter arguments if needed
      var customDomains: [String] = []
      var debugLoggingEnabled = true
      var networkTimeout: TimeInterval = 30.0
      var networkRetryCount = 3

      if let args = call.arguments as? [String: Any] {
          if let domains = args["customDomains"] as? [String] {
              customDomains = domains
          }
          if let debug = args["debugLoggingEnabled"] as? Bool {
              debugLoggingEnabled = debug
          }
          if let timeout = args["networkTimeout"] as? Double {
              networkTimeout = timeout
          }
          if let retryCount = args["networkRetryCount"] as? Int {
              networkRetryCount = retryCount
          }
      }

      let config = Configuration(
        networkTimeout: networkTimeout,
        networkRetryCount: networkRetryCount,
        debugLoggingEnabled: debugLoggingEnabled,
        customDomains: customDomains
      )

      // Since initialize is @MainActor-isolated, we need to run it on the main actor
      Task { @MainActor in
        Linklab.shared.initialize(with: config) { [weak self] linkData in
          NSLog("LinkLabFlutterPlugin - initialize callback received")
          guard let self = self else {
            NSLog("LinkLabFlutterPlugin - self is nil in initialization callback")
            return
          }
          
          // Always notify via stream if we got a link destination
          if let linkData = linkData, let channel = self.channel {
            NSLog("LinkLabFlutterPlugin - linkData received in init callback: \(linkData.id)")
            let linkDataMap = self.convertLinkDataToMap(linkData)
            NSLog("LinkLabFlutterPlugin - invoking onDynamicLinkReceived")
            channel.invokeMethod("onDynamicLinkReceived", arguments: linkDataMap)
          } else {
            NSLog("LinkLabFlutterPlugin - no linkData or channel in init callback")
          }
        }
      }

      NSLog("LinkLabFlutterPlugin - init completed, returning true")
      result(true)

    case "getInitialLink":
      NSLog("LinkLabFlutterPlugin - getInitialLink called")
      Task { @MainActor in
        // Try to get current link data from the SDK
        let linkData = Linklab.shared.getLinkData()
        NSLog("LinkLabFlutterPlugin - getInitialLink: got linkData: \(String(describing: linkData))")
        
        // Convert the link data to a map and return it (or nil if no link)
        result(convertLinkDataToMap(linkData))
        
        // Also process any deferred links that might be pending
        Linklab.shared.processDeferredDeepLink()
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
      if handleUniversalLink(url) {
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