import Flutter
import UIKit
import Linklab

@available(iOS 14.3, *)
public class LinkLabFlutterPlugin: NSObject, FlutterPlugin {
  private var channel: FlutterMethodChannel?
  private var linkDestination: LinkDestination?
  private var pendingInitialLinkRequest = false
  private var initialLinkResult: FlutterResult?
  private var isInitialized = false
  private var pendingUniversalLink: URL? = nil

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

  // Add support for handling URL schemes
  public func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
    NSLog("LinkLabFlutterPlugin - application open URL: \(url.absoluteString)")
    return handleUniversalLink(url)
  }

  private func handleUniversalLink(_ url: URL) -> Bool {
    NSLog("LinkLabFlutterPlugin - handleUniversalLink: \(url.absoluteString)")
    // If we're not initialized yet, store the URL for later processing
    if !isInitialized {
      NSLog("LinkLabFlutterPlugin - Not initialized yet, storing URL for later processing")
      pendingUniversalLink = url
      return true
    }

    NSLog("LinkLabFlutterPlugin - Plugin initialized, passing URL to Linklab SDK")
    let result = Linklab.shared.handleUniversalLink(url)
    NSLog("LinkLabFlutterPlugin - handleUniversalLink result from SDK: \(result)")
    return result
  }

  private func convertLinkDestinationToMap(_ destination: LinkDestination?) -> [String: Any]? {
    NSLog("LinkLabFlutterPlugin - convertLinkDestinationToMap called")
    guard let destination = destination else {
      NSLog("LinkLabFlutterPlugin - destination is nil, returning nil")
      return nil
    }

    let parameters: [String: String] = destination.parameters ?? [:]

    let map: [String: Any] = [
      "id": destination.route,
      "fullLink": "https://potje.linklab.cc/\(destination.route)", // Reconstruct full link
      "createdAt": Int(Date().timeIntervalSince1970 * 1000),
      "updatedAt": Int(Date().timeIntervalSince1970 * 1000),
      "userId": "",
      "domainType": "custom",
      "domain": "potje.linklab.cc", // Set actual domain
      "parameters": parameters
    ]
    NSLog("LinkLabFlutterPlugin - convertLinkDestinationToMap: created map with route: \(destination.route)")
    return map
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    NSLog("LinkLabFlutterPlugin - handle method called: \(call.method)")
    switch call.method {
    case "init":
      NSLog("LinkLabFlutterPlugin - initializing with config")

      // Only initialize once
      if isInitialized {
        NSLog("LinkLabFlutterPlugin - already initialized, returning true")
        result(true)
        return
      }

      let config = Configuration(
        debugLoggingEnabled: true
      )

      NSLog("LinkLabFlutterPlugin - calling Linklab.shared.initialize")
      Linklab.shared.initialize(with: config) { [weak self] destination in
        NSLog("LinkLabFlutterPlugin - initialize callback received")
        guard let self = self else {
          NSLog("LinkLabFlutterPlugin - self is nil in callback, ignoring")
          return
        }

        NSLog("LinkLabFlutterPlugin - setting isInitialized = true")
        self.isInitialized = true
        self.linkDestination = destination
        if let destination = destination {
          NSLog("LinkLabFlutterPlugin - received destination in callback: \(destination.route)")
        } else {
          NSLog("LinkLabFlutterPlugin - no destination in callback")
        }

        // Process any pending universal link
        if let pendingUrl = self.pendingUniversalLink {
          NSLog("LinkLabFlutterPlugin - Processing stored universal link after initialization: \(pendingUrl.absoluteString)")
          self.pendingUniversalLink = nil
          _ = self.handleUniversalLink(pendingUrl)
        } else {
          NSLog("LinkLabFlutterPlugin - No pending universal link to process")
        }

        if let destination = destination, let channel = self.channel {
          let linkData = self.convertLinkDestinationToMap(destination)
          NSLog("LinkLabFlutterPlugin - invoking onDynamicLinkReceived")
          DispatchQueue.main.async {
            NSLog("LinkLabFlutterPlugin - sending link data to Flutter")
            channel.invokeMethod("onDynamicLinkReceived", arguments: linkData)
          }
        } else {
          NSLog("LinkLabFlutterPlugin - no destination or channel to send")
        }

        // Resolve pending initial link request if there is one
        if self.pendingInitialLinkRequest {
          NSLog("LinkLabFlutterPlugin - resolving pending initial link request")
          self.pendingInitialLinkRequest = false
          DispatchQueue.main.async {
            NSLog("LinkLabFlutterPlugin - sending initial link result")
            self.initialLinkResult?(self.convertLinkDestinationToMap(destination))
            self.initialLinkResult = nil
          }
        } else {
          NSLog("LinkLabFlutterPlugin - no pending initial link request")
        }
      }

      NSLog("LinkLabFlutterPlugin - init method returning true")
      result(true)

    case "getInitialLink":
      NSLog("LinkLabFlutterPlugin - getInitialLink called")
      if let linkDestination = self.linkDestination {
        NSLog("LinkLabFlutterPlugin - returning cached link destination: \(linkDestination.route)")
        result(convertLinkDestinationToMap(linkDestination))
      } else if isInitialized {
        NSLog("LinkLabFlutterPlugin - no link destination and already initialized, returning nil")
        result(nil)
      } else {
        NSLog("LinkLabFlutterPlugin - not initialized yet, setting pending request")
        pendingInitialLinkRequest = true
        initialLinkResult = result
        // Will return result when deep link is received or timeout after 5 seconds
        NSLog("LinkLabFlutterPlugin - setting 5 second timeout for getInitialLink")
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) { [weak self] in
          guard let self = self else { return }
          if self.pendingInitialLinkRequest {
            NSLog("LinkLabFlutterPlugin - getInitialLink timed out after 5 seconds")
            self.pendingInitialLinkRequest = false
            self.initialLinkResult?(nil)
            self.initialLinkResult = nil
          } else {
            NSLog("LinkLabFlutterPlugin - timeout fired but request already handled")
          }
        }
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