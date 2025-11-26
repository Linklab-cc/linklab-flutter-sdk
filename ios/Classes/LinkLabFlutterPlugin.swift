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
    return false
  }

  private func handleUniversalLink(_ url: URL) -> Bool {
    NSLog("LinkLabFlutterPlugin - handleUniversalLink: \(url.absoluteString)")
    // Dispatch to MainActor as handleIncomingURL is isolated to MainActor
    Task { @MainActor in
      _ = Linklab.shared.handleIncomingURL(url)
    }
    return true
  }

  // Convert LinkData to a map format that Flutter can understand
  // UPDATED: Safer dictionary construction logic
  private func convertLinkDataToMap(_ linkData: LinkData?) -> [String: Any]? {
    guard let linkData = linkData else {
      NSLog("LinkLabFlutterPlugin - convertLinkDataToMap: linkData is nil")
      return nil
    }

    // Start with non-optional values
    var map: [String: Any] = [
        "rawLink": linkData.rawLink,
        "domainType": linkData.domainType,
        "parameters": [:] // Always return empty parameters map as per SDK structure
    ]
    
    // Safely add optional values only if they exist
    if let id = linkData.id {
        map["id"] = id
    }
    
    if let domain = linkData.domain {
        map["domain"] = domain
    }
    
    if let userId = linkData.userId {
        map["userId"] = userId
    }
    
    if let packageName = linkData.packageName {
        map["packageName"] = packageName
    }
    
    if let bundleId = linkData.bundleId {
        map["bundleId"] = bundleId
    }
    
    if let appStoreId = linkData.appStoreId {
        map["appStoreId"] = appStoreId
    }

    // Convert Dates to Milliseconds (if present)
    if let createdAt = linkData.createdAt {
        map["createdAt"] = Int64(createdAt.timeIntervalSince1970 * 1000)
    }

    if let updatedAt = linkData.updatedAt {
        map["updatedAt"] = Int64(updatedAt.timeIntervalSince1970 * 1000)
    }

    NSLog("LinkLabFlutterPlugin - convertLinkDataToMap: map created successfully")
    return map
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "init":
      NSLog("LinkLabFlutterPlugin - initializing")

      var customDomains: [String] = []
      var debugLoggingEnabled = true
      var networkTimeout: TimeInterval = 30.0
      var networkRetryCount = 3

      if let args = call.arguments as? [String: Any] {
          if let domains = args["customDomains"] as? [String] { customDomains = domains }
          if let debug = args["debugLoggingEnabled"] as? Bool { debugLoggingEnabled = debug }
          if let timeout = args["networkTimeout"] as? Double { networkTimeout = timeout }
          if let retryCount = args["networkRetryCount"] as? Int { networkRetryCount = retryCount }
      }

      let config = Configuration(
        networkTimeout: networkTimeout,
        networkRetryCount: networkRetryCount,
        debugLoggingEnabled: debugLoggingEnabled,
        customDomains: customDomains
      )

      Task { @MainActor in
        Linklab.shared.initialize(with: config) { [weak self] linkData in
          guard let self = self else { return }
          
          if let linkData = linkData, let channel = self.channel {
            NSLog("LinkLabFlutterPlugin - linkData received: \(linkData.id ?? "unrecognized")")
            let linkDataMap = self.convertLinkDataToMap(linkData)
            channel.invokeMethod("onDynamicLinkReceived", arguments: linkDataMap)
          }
        }
      }
      result(true)

    case "getInitialLink":
      Task { @MainActor in
        let linkData = Linklab.shared.getLinkData()
        result(convertLinkDataToMap(linkData))
        Linklab.shared.processDeferredDeepLink()
      }

    case "getDynamicLink":
      guard let args = call.arguments as? [String: Any],
            let shortLink = args["shortLink"] as? String,
            let url = URL(string: shortLink) else {
        result(FlutterError(code: "INVALID_ARGS", message: "Invalid URL", details: nil))
        return
      }
      if handleUniversalLink(url) {
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
