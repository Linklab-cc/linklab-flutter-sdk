/// Which kind of host the received link was on.
enum LinkLabDomainType {
  /// `linklab.cc` or a subdomain of it.
  linklab,

  /// A custom domain registered with Linklab.
  custom,

  /// The link could not be attributed to a known domain type (also used for
  /// `unrecognized` / `failed` results).
  unrecognized,
}

/// Outcome of resolving a link against the Linklab backend.
enum LinkLabResolutionStatus {
  /// The backend knows the link; [LinkLabData.fullLink] is the destination.
  resolved,

  /// A Linklab-domain URL the backend does not know (404) or one without a
  /// link id (root path). [LinkLabData.fullLink] is the URL as received.
  unrecognized,

  /// Resolution failed after retries (network / server / decoding error).
  /// [LinkLabData.fullLink] is the URL as received and
  /// [LinkLabData.errorMessage] describes the failure.
  failed,

  /// Not a Linklab link: delivered unchanged because
  /// [LinkLabConfig.forwardNonLinklabLinks] is enabled. [LinkLabData.fullLink]
  /// is the URL as received; [LinkLabData.parameters] holds its query.
  /// The link was never sent to the Linklab backend.
  passthrough,
}

/// How the link reached the app.
enum LinkLabMatchType {
  /// Opened directly via an App Link / universal link / intent.
  direct,

  /// Deferred: Google Play Install Referrer (Android).
  installReferrer,

  /// Deferred: found on the pasteboard (iOS).
  clipboard,

  /// Deferred: IP-based attribution (iOS).
  ipAddress,

  /// No match information available.
  none,
}

T _enumFromWire<T extends Enum>(List<T> values, Object? raw, T fallback) {
  if (raw is! String) return fallback;
  for (final value in values) {
    if (value.name == raw) return value;
  }
  return fallback;
}

int? _intFromWire(Object? raw) {
  if (raw is int) return raw;
  if (raw is num) return raw.toInt();
  if (raw is String) return int.tryParse(raw);
  return null;
}

String? _stringFromWire(Object? raw) => raw?.toString();

/// A resolved (or unrecognized / failed) Linklab link.
///
/// Field names are identical across the Android, iOS and Flutter SDKs.
class LinkLabData {
  /// Creates a link. Only [fullLink] is required.
  const LinkLabData({
    this.id,
    required this.fullLink,
    this.shortLink,
    this.createdAt,
    this.updatedAt,
    this.packageName,
    this.bundleId,
    this.appStoreId,
    this.domain,
    this.domainType = LinkLabDomainType.unrecognized,
    this.parameters = const <String, String>{},
    this.resolutionStatus = LinkLabResolutionStatus.resolved,
    this.errorMessage,
    this.isDeferred = false,
    this.matchType = LinkLabMatchType.direct,
  });

  /// Builds a [LinkLabData] from a platform-channel map.
  ///
  /// Tolerant of `num` timestamps, missing keys, a legacy `rawLink` key and
  /// unknown enum strings (which fall back to
  /// [LinkLabDomainType.unrecognized], [LinkLabResolutionStatus.failed] and
  /// [LinkLabMatchType.none] respectively). [parameters] always contains the
  /// URL-decoded query parameters of [fullLink], overridden by any explicit
  /// `parameters` entry in the map.
  factory LinkLabData.fromMap(Map<dynamic, dynamic> map) {
    final fullLink = _stringFromWire(map['fullLink']) ??
        _stringFromWire(map['rawLink']) ??
        '';

    final parameters = <String, String>{};
    final parsed = Uri.tryParse(fullLink);
    if (parsed != null) {
      try {
        parameters.addAll(parsed.queryParameters);
      } on FormatException {
        // Malformed percent-encoding: ignore the query.
      }
    }
    final rawParameters = map['parameters'];
    if (rawParameters is Map) {
      rawParameters.forEach((key, value) {
        if (key != null && value != null) {
          parameters[key.toString()] = value.toString();
        }
      });
    }

    return LinkLabData(
      id: _stringFromWire(map['id']),
      fullLink: fullLink,
      shortLink: _stringFromWire(map['shortLink']),
      createdAt: _intFromWire(map['createdAt']),
      updatedAt: _intFromWire(map['updatedAt']),
      packageName: _stringFromWire(map['packageName']),
      bundleId: _stringFromWire(map['bundleId']),
      appStoreId: _stringFromWire(map['appStoreId']),
      domain: _stringFromWire(map['domain']),
      domainType: _enumFromWire(
        LinkLabDomainType.values,
        map['domainType'],
        LinkLabDomainType.unrecognized,
      ),
      parameters: Map.unmodifiable(parameters),
      resolutionStatus: _enumFromWire(
        LinkLabResolutionStatus.values,
        map['resolutionStatus'],
        LinkLabResolutionStatus.failed,
      ),
      errorMessage: _stringFromWire(map['errorMessage']),
      isDeferred: map['isDeferred'] == true,
      matchType: _enumFromWire(
        LinkLabMatchType.values,
        map['matchType'],
        LinkLabMatchType.none,
      ),
    );
  }

  /// Server link id; `null` for unrecognized / failed results.
  final String? id;

  /// Resolved destination URL. For unrecognized / failed results this is the
  /// original URL as received by the app.
  final String fullLink;

  /// The URL as received by the app (universal link, intent URI, clipboard
  /// URL); `null` for install-referrer and IP attribution.
  final String? shortLink;

  /// Creation time in epoch milliseconds.
  final int? createdAt;

  /// Last update time in epoch milliseconds.
  final int? updatedAt;

  /// Android package name configured for the link.
  final String? packageName;

  /// iOS bundle id configured for the link.
  final String? bundleId;

  /// App Store id configured for the link.
  final String? appStoreId;

  /// Host of the short link.
  final String? domain;

  /// Which kind of host the link was on.
  final LinkLabDomainType domainType;

  /// URL-decoded query parameters of [fullLink], overridden by server-side
  /// parameters. Never null; unmodifiable.
  final Map<String, String> parameters;

  /// Whether the backend resolved the link.
  final LinkLabResolutionStatus resolutionStatus;

  /// Failure description when [resolutionStatus] is
  /// [LinkLabResolutionStatus.failed].
  final String? errorMessage;

  /// `true` when obtained through deferred attribution (install referrer,
  /// pasteboard, IP address) rather than an incoming URL.
  final bool isDeferred;

  /// How the link reached the app.
  final LinkLabMatchType matchType;

  /// [fullLink] parsed as a [Uri].
  ///
  /// Throws a [FormatException] if [fullLink] is not a valid URI.
  Uri get uri => Uri.parse(fullLink);

  /// `true` when [resolutionStatus] is [LinkLabResolutionStatus.resolved].
  bool get isResolved => resolutionStatus == LinkLabResolutionStatus.resolved;

  /// `true` when this is a non-Linklab URL forwarded as received (see
  /// [LinkLabConfig.forwardNonLinklabLinks]).
  bool get isPassthrough =>
      resolutionStatus == LinkLabResolutionStatus.passthrough;

  /// Legacy alias of [fullLink].
  @Deprecated('Use fullLink')
  String get rawLink => fullLink;

  /// Serialises this link to a platform-channel style map.
  Map<String, dynamic> toMap() => <String, dynamic>{
        'id': id,
        'fullLink': fullLink,
        'shortLink': shortLink,
        'createdAt': createdAt,
        'updatedAt': updatedAt,
        'packageName': packageName,
        'bundleId': bundleId,
        'appStoreId': appStoreId,
        'domain': domain,
        'domainType': domainType.name,
        'parameters': Map<String, String>.of(parameters),
        'resolutionStatus': resolutionStatus.name,
        'errorMessage': errorMessage,
        'isDeferred': isDeferred,
        'matchType': matchType.name,
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LinkLabData &&
          other.id == id &&
          other.fullLink == fullLink &&
          other.shortLink == shortLink &&
          other.matchType == matchType;

  @override
  int get hashCode => Object.hash(id, fullLink, shortLink, matchType);

  @override
  String toString() => 'LinkLabData(id: $id, fullLink: $fullLink, '
      'shortLink: $shortLink, resolutionStatus: ${resolutionStatus.name}, '
      'matchType: ${matchType.name}, isDeferred: $isDeferred, '
      'parameters: $parameters)';
}
