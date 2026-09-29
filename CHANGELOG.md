# Changelog

## 0.4.0 - 2026-09-29

### Added
- iOS: `UIScene` lifecycle support. The plugin now registers as a Flutter scene delegate and
  receives universal links and custom-scheme URLs through `scene(_:willConnectTo:options:)`,
  `scene(_:openURLContexts:)` and `scene(_:continue:)`, next to the existing
  `UIApplicationDelegate` callbacks (Flutter forwards only one of the two, depending on whether
  the app adopted `UIScene`). Required for apps built with Xcode 27 / the iOS 27 SDK, where
  Apple mandates `UIScene` and apps without it fail to launch.
- `LinkLabConfig.forwardNonLinklabLinks` (default `false`): deliver URLs that are not Linklab
  links (other https hosts, custom URL schemes) through `onLink` unchanged, as
  `LinkLabResolutionStatus.passthrough`, so the plugin can be the app's only deep-link
  receiver. Such links are never sent to the backend and never claimed on the platform side.
- `LinkLabResolutionStatus.passthrough` and `LinkLabData.isPassthrough`.

### Changed
- iOS: URLs received before Dart calls `initialize` are queued in the plugin and routed once
  the configuration (custom domains, forwarding) is known. Previously a custom-domain link
  that arrived before `init` (cold start) was dropped because the domains were not known yet.
- Minimum Flutter version is 3.38.0 (Dart 3.10), for the scene-delegate registration API.

## 0.3.0 - 2026-09-15

Major rewrite on top of Linklab Android SDK 0.1.0 and Linklab iOS SDK 0.3.0.

### Added
- `LinkLabData.shortLink`, `resolutionStatus`, `errorMessage`, `isDeferred`, `matchType`,
  `uri`, `isResolved`; enums `LinkLabDomainType`, `LinkLabResolutionStatus`,
  `LinkLabMatchType`; `==`/`hashCode` on `(id, fullLink, shortLink, matchType)`.
- `LinkLabConfig.baseUrl`, `installReferrerEnabled` (Android) and `pasteboardMode`
  (iOS, `LinkLabPasteboardMode.automatic | manual | disabled`).
- `LinkLab.resolve(String)` returns the resolved `LinkLabData` directly.
- `LinkLab.checkPasteboard()` for manual pasteboard mode (iOS; `null` on Android).
- `LinkLab.isInitialized`, `LinkLab.dispose()`.
- Deferred deep links on iOS via pasteboard and IP attribution, on Android via the Play
  Install Referrer (state machine with retries, handled by the native SDKs).
- Links on a Linklab domain that are unknown to the backend or have no id are delivered
  as `unrecognized` with the original URL and query parameters; network failures as
  `failed` with `errorMessage`.
- `onLink` buffers links until the first listener subscribes, then replays them in order.
- Native side queues links until Dart signals `ready`, so nothing is lost during startup.
- Unit tests for the model and the method channel; `analysis_options.yaml`.

### Changed
- `initialize` is idempotent (same `Future` on repeated calls; no-op after completion) and
  reports failures to the error listener before rethrowing.
- `getInitialLink` is non-destructive and returns the first link delivered in this
  process; native waits up to 5 s for an in-flight resolution.
- `parameters` is non-null; `domainType` is an enum; `userId` removed.
- Only http(s) URLs on `linklab.cc`, `*.linklab.cc` or configured custom domains are
  handled. Other universal links / App Links are no longer delivered (use e.g.
  `app_links` for your own domains).
- Default `networkTimeout` is 10 s (was 30 s).
- Android: `minSdk` 21 (was 27), `compileSdk` 36, Kotlin Gradle DSL, no manifest
  `package` attribute; depends on `cc.linklab:android:0.1.0`; launch intent processed once
  per Activity instance; SDK listener registered/unregistered with the engine.
- iOS: depends on `Linklab ~> 0.3.0`, Swift 5.9, iOS 14.3; `application(_:continue:)`
  returns `false` for non-Linklab URLs; `application(_:open:options:)` returns `false`.
- Package metadata: repository, issue tracker, topics.

### Deprecated
- `LinkLabData.rawLink` (use `fullLink`), `LinkLab.getDynamicLink` (use `resolve`).

### Removed
- Public top-level `log` function.
- Unused `SwiftLinkLabFlutterPlugin` class and the i386 simulator exclusion.

## 0.2.5 - 2025-12-09
- Android: updated `cc.linklab:android` dependency to 0.0.4.
- iOS: updated `Linklab` pod dependency to `~> 0.2.3`.

## 0.2.4 - 2025-12-05
- Android: updated `cc.linklab:android` dependency to 0.0.3; `compileSdk`/`targetSdk`
  36, `minSdk` 27.
- iOS: podspec version aligned with the package version.

## 0.2.3 - 2025-11-26
- Updated Android SDK dependency to 0.0.2

## 0.0.1 - Initial Release (2025-03-27)

### Added
- Core functionality for LinkLab deep links
- Basic documentation and examples in README
