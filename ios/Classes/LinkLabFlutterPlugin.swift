import Flutter
import Linklab
import OSLog
import UIKit

/// Flutter bridge for the Linklab iOS SDK.
///
/// Method channel `cc.linklab.flutter/linklab`:
/// - Dart -> native: `init`, `ready`, `getInitialLink`, `resolve`, `isLinkLabLink`, `checkPasteboard`
/// - native -> Dart: `onLink(map)` (only after `ready`), `onError({message, code})`
///
/// Incoming URLs are received through both lifecycles, `UIApplicationDelegate` and
/// `UISceneDelegate` (required by Xcode 27 / the iOS 27 SDK). Flutter forwards only one of them,
/// depending on whether the app adopted UIScene, so each URL is seen once. The scene callbacks
/// mirror the ones in `app_links`.
///
/// Routing: Linklab-host URLs go to the SDK (resolved server-side). Any other URL is dropped,
/// unless `forwardNonLinklabLinks` is on, in which case it is delivered to Dart unchanged with
/// `resolutionStatus == "passthrough"`. Forwarded URLs are never *claimed* (the callbacks return
/// `false`), so other plugins and the app keep receiving them. URLs received before Dart sends
/// `init` are queued and routed once the configuration (custom domains, forwarding) is known.
///
/// All plugin state is touched on the main thread only: Flutter invokes method-call,
/// app-delegate and scene-delegate callbacks there and `Linklab` is `@MainActor`.
public class LinkLabFlutterPlugin: NSObject, FlutterPlugin, FlutterSceneLifeCycleDelegate {
  private static let channelName = "cc.linklab.flutter/linklab"
  private static let initialLinkTimeout: TimeInterval = 5

  private let channel: FlutterMethodChannel

  /// Set as soon as Dart sends `init` (before the SDK finishes initializing).
  private var initReceived = false
  /// Custom domains from the `init` config, lower-cased; used for host checks before the SDK is ready.
  private var customDomains: [String] = []
  private var forwardNonLinklabLinks = false
  private var debugLoggingEnabled = false
  private var networkTimeout: TimeInterval = 10

  /// os_log output (subsystem `cc.linklab.flutter`), only when `debugLoggingEnabled`. Query strings
  /// are never logged.
  private static let log = Logger(subsystem: "cc.linklab.flutter", category: "LinkLabFlutterPlugin")
  private func debug(_ message: String) {
    guard debugLoggingEnabled else { return }
    Self.log.debug("\(message, privacy: .public)")
  }
  private static func describe(_ url: URL) -> String {
    "\(url.scheme ?? "?")://\(url.host ?? "")\(url.path)"
  }
  private var networkRetryCount = 3

  /// URLs received before `init`; routed by `flushPendingURLs()` once the config is known.
  private var pendingURLs: [URL] = []

  private var dartReady = false
  private var queuedLinks: [[String: Any]] = []
  /// First (non-resolve) link delivered in this process.
  private var firstLink: [String: Any]?

  private final class ResolveWaiter {
    let key: String
    let result: FlutterResult
    var done = false
    init(key: String, result: @escaping FlutterResult) {
      self.key = key
      self.result = result
    }
    func finish(_ value: Any?) {
      guard !done else { return }
      done = true
      result(value)
    }
  }

  private var resolveWaiters: [ResolveWaiter] = []
  /// URLs requested through `resolve`; their results bypass the stream.
  private var requestedURLs: Set<String> = []

  private init(channel: FlutterMethodChannel) {
    self.channel = channel
    super.init()
  }

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: channelName, binaryMessenger: registrar.messenger())
    let instance = LinkLabFlutterPlugin(channel: channel)
    registrar.addMethodCallDelegate(instance, channel: channel)
    // Both lifecycles: Flutter calls the application-delegate methods for apps that have not
    // adopted UIScene and the scene-delegate methods for apps that have (never both).
    registrar.addApplicationDelegate(instance)
    registrar.addSceneDelegate(instance)
  }

  // MARK: - FlutterApplicationLifeCycleDelegate (apps without UIScene)

  public func application(
    _ application: UIApplication,
    continue userActivity: NSUserActivity,
    restorationHandler: @escaping ([Any]) -> Void
  ) -> Bool {
    guard let url = userActivity.webpageURL else { return false }
    return handleIncomingURL(url)
  }

  public func application(
    _ application: UIApplication,
    open url: URL,
    options: [UIApplication.OpenURLOptionsKey: Any] = [:]
  ) -> Bool {
    // Custom URL schemes are never Linklab links; forwarded to Dart only when configured.
    return handleIncomingURL(url)
  }

  // MARK: - FlutterSceneLifeCycleDelegate (apps with UIScene)

  /// Cold start: the launch URL / universal link arrives in the connection options.
  public func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions?
  ) -> Bool {
    guard let options = connectionOptions else { return false }
    var claimed = false
    for context in options.urlContexts {
      claimed = handleIncomingURL(context.url) || claimed
    }
    for userActivity in options.userActivities {
      if let url = userActivity.webpageURL {
        claimed = handleIncomingURL(url) || claimed
      }
    }
    return claimed
  }

  /// Custom URL schemes while running.
  public func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) -> Bool {
    var claimed = false
    for context in URLContexts {
      claimed = handleIncomingURL(context.url) || claimed
    }
    return claimed
  }

  /// Universal links while running.
  public func scene(_ scene: UIScene, continue userActivity: NSUserActivity) -> Bool {
    guard let url = userActivity.webpageURL else { return false }
    return handleIncomingURL(url)
  }

  // MARK: - URL routing

  /// Routes a URL the app received.
  ///
  /// Returns `true` only when the URL is claimed by this plugin (a Linklab host, handed to the
  /// SDK). Non-Linklab URLs return `false` whether or not they are forwarded to Dart, so that
  /// Flutter still offers them to other plugins. Before `init` the URL is queued and the return
  /// value reflects only the built-in hosts, because custom domains are not known yet.
  @discardableResult
  private func handleIncomingURL(_ url: URL) -> Bool {
    guard initReceived else {
      pendingURLs.append(url)
      return isLinklabHost(url)
    }
    if isLinklabHost(url) {
      debug("Handing Linklab URL to the SDK: \(Self.describe(url))")
      runOnMain {
        Linklab.shared.handleIncomingURL(url)
      }
      return true
    }
    if forwardNonLinklabLinks {
      debug("Forwarding non-Linklab URL to Dart as passthrough: \(Self.describe(url))")
      deliver(passthroughMap(for: url))
    } else {
      debug("Dropping non-Linklab URL (forwardNonLinklabLinks is off): \(Self.describe(url))")
    }
    return false
  }

  private func flushPendingURLs() {
    let pending = pendingURLs
    pendingURLs = []
    if !pending.isEmpty { debug("Routing \(pending.count) URL(s) received before init") }
    pending.forEach { handleIncomingURL($0) }
  }

  /// Contract rule 1 with the custom domains known to the plugin (from `init`), so links on
  /// custom domains are accepted even before `Linklab.shared.initialize` has completed.
  private func isLinklabHost(_ url: URL) -> Bool {
    guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
          let host = url.host?.lowercased(), !host.isEmpty else {
      return false
    }
    return host == "linklab.cc" || host.hasSuffix(".linklab.cc") || customDomains.contains(host)
  }

  // MARK: - Method channel

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "init":
      handleInit(call.arguments as? [String: Any] ?? [:], result: result)

    case "ready":
      dartReady = true
      let queued = queuedLinks
      queuedLinks = []
      queued.forEach { channel.invokeMethod("onLink", arguments: $0) }
      result(nil)

    case "getInitialLink":
      Task { @MainActor [weak self] in
        // Waits for initialization, in-flight direct fetches and the deferred check (5 s cap).
        _ = await Linklab.shared.getInitialLink()
        result(self?.firstLink)
      }

    case "resolve":
      handleResolve(call.arguments as? [String: Any] ?? [:], result: result)

    case "isLinkLabLink":
      guard let link = (call.arguments as? [String: Any])?["link"] as? String,
            let url = URL(string: link) else {
        result(false)
        return
      }
      Task { @MainActor [weak self] in
        if Linklab.shared.isInitialized {
          result(Linklab.shared.isLinklabLink(url))
        } else {
          result(self?.isLinklabHost(url) ?? false)
        }
      }

    case "checkPasteboard":
      Task { @MainActor [weak self] in
        let link = await Linklab.shared.checkPasteboard(deliver: false)
        result(link.flatMap { self?.toMap($0) })
      }

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func handleInit(_ args: [String: Any], result: @escaping FlutterResult) {
    let domains = (args["customDomains"] as? [Any])?.compactMap { ($0 as? String)?.lowercased() } ?? []
    let timeout = (args["networkTimeout"] as? NSNumber)?.doubleValue ?? 10
    let retries = (args["networkRetryCount"] as? NSNumber)?.intValue ?? 3
    let debug = (args["debugLoggingEnabled"] as? Bool) ?? false
    let baseURL = (args["baseUrl"] as? String).flatMap { URL(string: $0) } ?? URL(string: "https://linklab.cc")!
    let pasteboardMode: PasteboardMode
    switch (args["pasteboardMode"] as? String)?.lowercased() {
    case "manual": pasteboardMode = .manual
    case "disabled": pasteboardMode = .disabled
    default: pasteboardMode = .automatic
    }

    customDomains = domains
    forwardNonLinklabLinks = (args["forwardNonLinklabLinks"] as? Bool) ?? false
    debugLoggingEnabled = debug
    networkTimeout = timeout
    networkRetryCount = max(0, retries)
    initReceived = true

    let configuration = LinklabConfiguration(
      networkTimeout: timeout,
      networkRetryCount: retries,
      debugLoggingEnabled: debug,
      customDomains: domains,
      baseURL: baseURL,
      pasteboardMode: pasteboardMode
    )

    Task { @MainActor [weak self] in
      guard let self else { return }
      Linklab.shared.onLink = { [weak self] link in
        self?.onLinkDelivered(link)
      }
      Linklab.shared.onError = { [weak self] error in
        self?.channel.invokeMethod(
          "onError",
          arguments: ["message": error.localizedDescription, "code": error.code]
        )
      }
      Linklab.shared.initialize(with: configuration)
      // URLs that arrived before `init` (cold start): route them now that the config is known.
      self.flushPendingURLs()
      result(true)
    }
  }

  private func handleResolve(_ args: [String: Any], result: @escaping FlutterResult) {
    guard let shortLink = (args["shortLink"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
          !shortLink.isEmpty else {
      result(FlutterError(code: "INVALID_ARGUMENT", message: "shortLink must not be empty", details: nil))
      return
    }
    guard let url = URL(string: shortLink), isLinklabHost(url) else {
      result(nil)
      return
    }
    let key = url.absoluteString
    let waiter = ResolveWaiter(key: key, result: result)
    resolveWaiters.append(waiter)
    requestedURLs.insert(key)

    let timeout = networkTimeout * Double(networkRetryCount + 1) + 2
    Task { @MainActor [weak self] in
      guard let self else { return }
      let accepted = Linklab.shared.handleIncomingURL(url)
      if !accepted {
        self.removeWaiter(waiter)
        waiter.finish(nil)
        return
      }
      DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { [weak self] in
        guard let self, self.resolveWaiters.contains(where: { $0 === waiter }) else { return }
        self.removeWaiter(waiter)
        waiter.finish(FlutterError(code: "TIMEOUT", message: "Timed out resolving \(key)", details: nil))
      }
    }
  }

  private func removeWaiter(_ waiter: ResolveWaiter) {
    resolveWaiters.removeAll { $0 === waiter }
    requestedURLs.remove(waiter.key)
  }

  // MARK: - Delivery

  private func onLinkDelivered(_ link: LinkData) {
    let map = toMap(link)

    if let waiter = resolveWaiters.first(where: { $0.key == link.shortLink || $0.key == link.fullLink }) {
      removeWaiter(waiter)
      waiter.finish(map)
      return
    }
    if let shortLink = link.shortLink, requestedURLs.remove(shortLink) != nil {
      // Requested via resolve() but the caller already timed out: keep it off the stream.
      return
    }
    deliver(map)
  }

  /// Sends a link to Dart (or queues it until `ready`) and records it as the initial link.
  private func deliver(_ map: [String: Any]) {
    if firstLink == nil { firstLink = map }
    if dartReady {
      channel.invokeMethod("onLink", arguments: map)
    } else {
      queuedLinks.append(map)
    }
  }

  /// A non-Linklab URL, delivered as received. Dart derives `parameters` from `fullLink`.
  private func passthroughMap(for url: URL) -> [String: Any] {
    var map: [String: Any] = [
      "fullLink": url.absoluteString,
      "shortLink": url.absoluteString,
      "domainType": "unrecognized",
      "parameters": [String: String](),
      "resolutionStatus": "passthrough",
      "isDeferred": false,
      "matchType": "direct",
    ]
    if let host = url.host?.lowercased(), !host.isEmpty { map["domain"] = host }
    return map
  }

  private func toMap(_ link: LinkData) -> [String: Any] {
    var map: [String: Any] = [
      "fullLink": link.fullLink,
      "domainType": link.domainType,
      "parameters": link.parameters,
      "resolutionStatus": link.resolutionStatus,
      "isDeferred": link.isDeferred,
      "matchType": link.matchType,
    ]
    if let id = link.id { map["id"] = id }
    if let shortLink = link.shortLink { map["shortLink"] = shortLink }
    if let createdAt = link.createdAt { map["createdAt"] = Self.millis(createdAt) }
    if let updatedAt = link.updatedAt { map["updatedAt"] = Self.millis(updatedAt) }
    if let packageName = link.packageName { map["packageName"] = packageName }
    if let bundleId = link.bundleId { map["bundleId"] = bundleId }
    if let appStoreId = link.appStoreId { map["appStoreId"] = appStoreId }
    if let domain = link.domain { map["domain"] = domain }
    if let errorMessage = link.errorMessage { map["errorMessage"] = errorMessage }
    return map
  }

  private static func millis(_ date: Date) -> Int64 {
    Int64((date.timeIntervalSince1970 * 1000).rounded())
  }

  /// Runs `body` on the main actor, synchronously when already on the main thread.
  private func runOnMain(_ body: @escaping @MainActor () -> Void) {
    if Thread.isMainThread {
      MainActor.assumeIsolated { body() }
    } else {
      Task { @MainActor in body() }
    }
  }
}
