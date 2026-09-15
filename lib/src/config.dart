/// How the iOS SDK may read the system pasteboard for deferred deep linking.
///
/// Ignored on Android.
enum LinkLabPasteboardMode {
  /// Read at most once per install during the first-launch deferred check.
  /// iOS may show the "pasted from" banner once.
  automatic,

  /// Never read automatically. Call [LinkLab.checkPasteboard] after an
  /// explicit user action instead.
  manual,

  /// Never read the pasteboard.
  disabled,
}

/// Configuration passed to [LinkLab.initialize].
class LinkLabConfig {
  /// Creates a configuration. All fields have production defaults.
  const LinkLabConfig({
    this.customDomains = const [],
    this.debugLoggingEnabled = false,
    this.networkTimeout = 10.0,
    this.networkRetryCount = 3,
    this.baseUrl = 'https://linklab.cc',
    this.installReferrerEnabled = true,
    this.pasteboardMode = LinkLabPasteboardMode.automatic,
  });

  /// Additional hosts (exact, case-insensitive match) that are treated as
  /// Linklab links, e.g. `['go.example.com']`. `linklab.cc` and
  /// `*.linklab.cc` are always recognised.
  final List<String> customDomains;

  /// Enables native SDK logging (Logcat tag `LinkLab`, os_log subsystem
  /// `cc.linklab.sdk`) and Dart-side `developer.log` output. Query strings
  /// are never logged.
  final bool debugLoggingEnabled;

  /// Per-request timeout in seconds.
  final double networkTimeout;

  /// Number of retries after the first attempt for network errors and 5xx
  /// responses (exponential backoff). 4xx responses are never retried.
  final int networkRetryCount;

  /// Linklab API base URL.
  final String baseUrl;

  /// Android only: resolve deferred links from the Play Install Referrer on
  /// first launch.
  final bool installReferrerEnabled;

  /// iOS only: pasteboard policy for deferred deep linking.
  final LinkLabPasteboardMode pasteboardMode;

  /// Serialises the configuration for the platform side.
  Map<String, dynamic> toMap() => <String, dynamic>{
        'customDomains': List<String>.of(customDomains),
        'debugLoggingEnabled': debugLoggingEnabled,
        'networkTimeout': networkTimeout,
        'networkRetryCount': networkRetryCount,
        'baseUrl': baseUrl,
        'installReferrerEnabled': installReferrerEnabled,
        'pasteboardMode': pasteboardMode.name,
      };

  @override
  String toString() => 'LinkLabConfig(${toMap()})';
}
