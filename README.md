# Linklab Flutter SDK

Flutter plugin for the [Linklab](https://linklab.cc) deep linking service. It wraps the
Linklab Android and iOS SDKs and delivers resolved links to Dart as a stream of
`LinkLabData`:

- **Direct links** — Android App Links / iOS universal links on `linklab.cc`,
  `*.linklab.cc` and your custom domains.
- **Deferred deep links** — Google Play Install Referrer (Android), pasteboard and
  IP attribution (iOS) on first launch.
- **Short-link resolution** — resolve any Linklab link on demand.

## Installation

```yaml
dependencies:
  linklab_flutter_sdk: ^0.3.0
```

Requirements: Flutter 3.19+, Android `minSdk` 21+, iOS 14.3+.

## Android setup

1. Add an App Links intent filter for every domain you use with Linklab to the
   `MainActivity` in `android/app/src/main/AndroidManifest.xml`:

   ```xml
   <intent-filter android:autoVerify="true">
       <action android:name="android.intent.action.VIEW" />
       <category android:name="android.intent.category.DEFAULT" />
       <category android:name="android.intent.category.BROWSABLE" />
       <data android:scheme="https" android:host="linklab.cc" />
       <!-- one <data> element per custom domain -->
       <data android:scheme="https" android:host="go.example.com" />
   </intent-filter>
   ```

2. Host `https://<domain>/.well-known/assetlinks.json` for each domain (Linklab serves
   it for `linklab.cc` and for custom domains configured in the dashboard). It must list
   your package name and the SHA-256 fingerprints of your signing certificates.

3. The plugin declares `android.permission.INTERNET`; nothing else is required. Deferred
   links use the Play Install Referrer library, which is bundled with the SDK.

## iOS setup

1. In Xcode, add the **Associated Domains** capability to the Runner target with one entry
   per domain:

   ```
   applinks:linklab.cc
   applinks:go.example.com
   ```

2. Linklab hosts `https://<domain>/.well-known/apple-app-site-association` for your
   domains; make sure the Team ID / bundle id in the dashboard match your app.

3. No `AppDelegate` or `SceneDelegate` changes are needed. The plugin registers for both
   lifecycles: `UIApplicationDelegate` (`application(_:continue:)`,
   `application(_:open:options:)`) and `UISceneDelegate` (`scene(_:willConnectTo:options:)`,
   `scene(_:openURLContexts:)`, `scene(_:continue:)`). Apps built with **Xcode 27** must adopt
   `UIScene` (see Flutter's [UIScene migration guide][uiscene]); the plugin works with either.

4. If you also use another deep-link plugin, both can coexist: this plugin only claims URLs
   whose host is a Linklab host and returns `false` for everything else, including links it
   forwards with `forwardNonLinklabLinks`.

[uiscene]: https://docs.flutter.dev/release/breaking-changes/uiscenedelegate

## Usage

### Initialize and listen

```dart
import 'package:linklab_flutter_sdk/linklab_flutter_sdk.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await LinkLab().initialize(
    config: const LinkLabConfig(
      customDomains: ['go.example.com'],
      debugLoggingEnabled: false,
      // iOS only; see "Pasteboard" below.
      pasteboardMode: LinkLabPasteboardMode.automatic,
    ),
  );

  runApp(const MyApp());
}

// Anywhere in the app (e.g. in a State.initState):
final subscription = LinkLab().onLink.listen((LinkLabData link) {
  if (link.isResolved) {
    router.go(link.uri.path, extra: link.parameters);
  } else {
    // unrecognized / failed: link.fullLink is the URL as received
  }
});
```

`initialize` is idempotent: repeated calls return the same `Future`, and once it has
completed further calls are no-ops. `onLink` is a broadcast stream that **buffers** every
link received before the first listener subscribes and replays them, in order, to that
listener — so it is safe to subscribe from a widget that is built after startup.

### `getInitialLink` vs the stream

Every link is delivered through `onLink`, including the one the app was launched with.
`getInitialLink()` additionally returns the **first** link delivered in this process
(or `null`), without consuming it. The platform side waits up to 5 s for a link that is
still being resolved, which makes it convenient for a splash screen:

```dart
final initial = await LinkLab().getInitialLink();
if (initial != null) { /* route immediately */ }
```

Use the stream for everything that happens while the app is running (a link opened from
another app, a deferred link resolved after launch). Do not rely on `getInitialLink`
alone: a deferred link may arrive after it returned `null`.

### `LinkLabData`

| Field | Type | Notes |
|---|---|---|
| `id` | `String?` | Server link id; `null` for unrecognized / failed |
| `fullLink` | `String` | Destination URL; for unrecognized / failed the URL as received |
| `shortLink` | `String?` | URL as received; `null` for install-referrer / IP attribution |
| `createdAt`, `updatedAt` | `int?` | Epoch millis |
| `packageName`, `bundleId`, `appStoreId` | `String?` | |
| `domain` | `String?` | Host of the short link |
| `domainType` | `LinkLabDomainType` | `linklab`, `custom`, `unrecognized` |
| `parameters` | `Map<String, String>` | Never null: query params of `fullLink`, overridden by server-side parameters |
| `resolutionStatus` | `LinkLabResolutionStatus` | `resolved`, `unrecognized`, `failed`, `passthrough` |
| `errorMessage` | `String?` | Set when `failed` |
| `isDeferred` | `bool` | Install referrer / pasteboard / IP attribution |
| `matchType` | `LinkLabMatchType` | `direct`, `installReferrer`, `clipboard`, `ipAddress`, `none` |
| `uri` | `Uri` | `fullLink` parsed |

Equality is defined on `(id, fullLink, shortLink, matchType)`.

Links on a Linklab domain that the backend does not know (404) or that have no id (e.g.
`https://go.example.com/?utm_source=x`) are delivered as `unrecognized` with the original
URL and its query parameters, so custom-domain landing pages still reach the app. Network
failures after retries are delivered as `failed` with `errorMessage`. Non-Linklab URLs are
not delivered unless `forwardNonLinklabLinks` is on (see below).

### Forward non-Linklab links

By default only Linklab links are delivered. Set `forwardNonLinklabLinks: true` to also
receive every other URL the OS hands to the app (universal links / App Links on your own
hosts, custom URL schemes) through the same stream, unchanged:

```dart
await LinkLab().initialize(
  config: const LinkLabConfig(
    customDomains: ['go.example.com'],
    forwardNonLinklabLinks: true,
  ),
);

LinkLab().onLink.listen((link) {
  if (link.isPassthrough) {
    // e.g. https://auth.example.com/?mode=signIn&oobCode=... or myapp://...
    handleRawUrl(link.uri, link.parameters);
  } else if (link.isResolved) {
    router.go(link.uri.path, extra: link.parameters);
  }
});
```

Forwarded links have `resolutionStatus == passthrough`, `id == null`, `fullLink` and
`shortLink` equal to the URL as received and `parameters` equal to its query. They are never
sent to the Linklab backend, and the plugin does not claim them on the platform side, so
sign-in / payment SDKs that listen for their own callback URLs keep working. This makes a
second deep-link plugin such as `app_links` unnecessary.

### Resolve a link on demand

```dart
final LinkLabData? link = await LinkLab().resolve('https://linklab.cc/abcd1234');
// null  -> not a Linklab link
// else  -> resolved / unrecognized / failed LinkLabData (NOT delivered to onLink)
```

`isLinkLabLink(String)` tells you whether a URL is on `linklab.cc`, `*.linklab.cc` or one
of your custom domains.

### Pasteboard (iOS)

`LinkLabConfig.pasteboardMode` controls deferred deep linking via the pasteboard:

- `automatic` (default) — read at most once per install, during the first-launch deferred
  check. iOS may show the "pasted from …" banner once. The pasteboard is only read when
  it contains a string that looks like a URL or a Linklab token.
- `manual` — the SDK never reads automatically. Call `checkPasteboard()` after a user
  action; the result is returned directly and not delivered to `onLink`:

  ```dart
  final link = await LinkLab().checkPasteboard(); // null on Android
  ```

- `disabled` — never read the pasteboard.

If no pasteboard link is found on first launch, the SDK asks the backend for an IP-based
match (`matchType == ipAddress`). On Android, deferred links come from the Play Install
Referrer (`matchType == installReferrer`); disable with `installReferrerEnabled: false`.

### Errors and cleanup

```dart
LinkLab().setErrorListener((message, details) => log('Linklab: $message ($details)'));
LinkLab().setLinkListener((link) => ...); // callback alternative to the stream
LinkLab().dispose();                       // closes the stream, clears listeners
```

Asynchronous native errors (deferred check failures, `checkPasteboard` failures) go to the
error listener. Failures of `initialize`, `resolve`, `getInitialLink` etc. are thrown to
the caller (`PlatformException`).

## Migration from 0.2.x

- `LinkLabData.rawLink` is deprecated; use `fullLink`. `userId` was removed.
- `parameters` is now non-null (`Map<String, String>`); drop the `?? {}`.
- `domainType` is an enum (`LinkLabDomainType`); new fields `shortLink`,
  `resolutionStatus`, `errorMessage`, `isDeferred`, `matchType`.
- `getDynamicLink(String)` is deprecated; use `resolve(String)`, which returns the
  `LinkLabData` directly instead of pushing it to the stream.
- **Universal links / App Links on domains that are not Linklab domains are no longer
  delivered** (previously the iOS plugin forwarded every universal link). If your app
  relied on that, handle your own domains with a package such as
  [`app_links`](https://pub.dev/packages/app_links); both plugins coexist.
- The public top-level `log` function was removed.
- `LinkLabConfig.networkTimeout` default changed from 30 s to 10 s; new options
  `baseUrl`, `installReferrerEnabled`, `pasteboardMode`.
- `initialize` now also completes the `ready` handshake; links are buffered on the
  native side until then, so nothing is lost if you subscribe late.

## Example

See [`example/lib/main.dart`](example/lib/main.dart) for a complete app that initializes
the SDK, shows the initial link, listens to the stream, resolves a typed link and checks
the pasteboard.

## License

Apache 2.0 — see [LICENSE](LICENSE).
