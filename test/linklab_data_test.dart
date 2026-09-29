import 'package:flutter_test/flutter_test.dart';
import 'package:linklab_flutter_sdk/linklab_flutter_sdk.dart';

void main() {
  const destination =
      'https://potje.tech/en/?promoId=75iOS8HDjnRcPNS00qor&type=getPromoCode';

  group('LinkLabData.fromMap', () {
    test('parses a passthrough link (custom scheme, no parameters entry)', () {
      final data = LinkLabData.fromMap({
        'fullLink': 'myapp://open?screen=home',
        'shortLink': 'myapp://open?screen=home',
        'domainType': 'unrecognized',
        'resolutionStatus': 'passthrough',
        'isDeferred': false,
        'matchType': 'direct',
      });

      expect(data.resolutionStatus, LinkLabResolutionStatus.passthrough);
      expect(data.isPassthrough, isTrue);
      expect(data.isResolved, isFalse);
      expect(data.domainType, LinkLabDomainType.unrecognized);
      expect(data.parameters, {'screen': 'home'});
      expect(data.uri.scheme, 'myapp');
    });

    test('maps every contract field', () {
      final data = LinkLabData.fromMap({
        'id': 'abc123',
        'fullLink': destination,
        'shortLink': 'https://linklab.cc/abc123',
        'createdAt': 1700000000000,
        'updatedAt': 1700000001000.0,
        'packageName': 'tech.potje.app',
        'bundleId': 'tech.potje.ios',
        'appStoreId': '123456',
        'domain': 'linklab.cc',
        'domainType': 'linklab',
        'parameters': {'promoId': '75iOS8HDjnRcPNS00qor', 'type': 'getPromoCode'},
        'resolutionStatus': 'resolved',
        'errorMessage': null,
        'isDeferred': false,
        'matchType': 'direct',
      });

      expect(data.id, 'abc123');
      expect(data.fullLink, destination);
      expect(data.shortLink, 'https://linklab.cc/abc123');
      expect(data.createdAt, 1700000000000);
      expect(data.updatedAt, 1700000001000);
      expect(data.packageName, 'tech.potje.app');
      expect(data.bundleId, 'tech.potje.ios');
      expect(data.appStoreId, '123456');
      expect(data.domain, 'linklab.cc');
      expect(data.domainType, LinkLabDomainType.linklab);
      expect(data.parameters, {
        'promoId': '75iOS8HDjnRcPNS00qor',
        'type': 'getPromoCode',
      });
      expect(data.resolutionStatus, LinkLabResolutionStatus.resolved);
      expect(data.errorMessage, isNull);
      expect(data.isDeferred, isFalse);
      expect(data.matchType, LinkLabMatchType.direct);
      expect(data.isResolved, isTrue);
      expect(data.uri, Uri.parse(destination));
      // ignore: deprecated_member_use_from_same_package
      expect(data.rawLink, destination);
    });

    test('derives parameters from fullLink when the map has none', () {
      for (final key in ['fullLink', 'rawLink']) {
        final data = LinkLabData.fromMap({
          key: destination,
          'domainType': 'custom',
          'domain': 'app.potje.tech',
        });
        expect(data.fullLink, destination);
        expect(data.parameters, {
          'promoId': '75iOS8HDjnRcPNS00qor',
          'type': 'getPromoCode',
        });
      }
    });

    test('server parameters override query parameters and decode once', () {
      final data = LinkLabData.fromMap({
        'fullLink':
            'https://potje.tech/en/?campaign=spring%26summer&code=a%252Fb',
        'parameters': {'campaign': 'override', 'source': 'newsletter', 'n': 1},
      });
      expect(data.parameters, {
        'campaign': 'override',
        'code': 'a%2Fb',
        'source': 'newsletter',
        'n': '1',
      });
    });

    test('parameters is never null and is unmodifiable', () {
      final data = LinkLabData.fromMap({'fullLink': 'https://potje.tech/en/'});
      expect(data.parameters, isEmpty);
      expect(() => data.parameters['x'] = 'y', throwsUnsupportedError);
    });

    test('tolerates empty, invalid and query-less URLs', () {
      for (final url in ['https://potje.tech/en/', '', 'https://[invalid']) {
        final data = LinkLabData.fromMap({'fullLink': url});
        expect(data.fullLink, url);
        expect(data.parameters, isEmpty);
      }
    });

    test('unknown enum strings fall back to unrecognized / failed / none', () {
      final data = LinkLabData.fromMap({
        'fullLink': 'https://linklab.cc/x',
        'domainType': 'default',
        'resolutionStatus': 'weird',
        'matchType': 'telepathy',
      });
      expect(data.domainType, LinkLabDomainType.unrecognized);
      expect(data.resolutionStatus, LinkLabResolutionStatus.failed);
      expect(data.matchType, LinkLabMatchType.none);
    });

    test('missing enum keys use the same fallbacks', () {
      final data = LinkLabData.fromMap({'fullLink': 'https://linklab.cc/x'});
      expect(data.domainType, LinkLabDomainType.unrecognized);
      expect(data.resolutionStatus, LinkLabResolutionStatus.failed);
      expect(data.matchType, LinkLabMatchType.none);
    });

    test('accepts num and string timestamps', () {
      expect(LinkLabData.fromMap({'fullLink': 'x', 'createdAt': 12.9}).createdAt,
          12);
      expect(LinkLabData.fromMap({'fullLink': 'x', 'createdAt': '42'}).createdAt,
          42);
      expect(LinkLabData.fromMap({'fullLink': 'x', 'createdAt': 'nope'}).createdAt,
          isNull);
    });

    test('failed link carries errorMessage and original URL', () {
      final data = LinkLabData.fromMap({
        'id': null,
        'fullLink': 'https://linklab.cc/abc?x=1',
        'shortLink': 'https://linklab.cc/abc?x=1',
        'domainType': 'unrecognized',
        'parameters': {'x': '1'},
        'resolutionStatus': 'failed',
        'errorMessage': 'Network error',
        'isDeferred': false,
        'matchType': 'direct',
      });
      expect(data.id, isNull);
      expect(data.resolutionStatus, LinkLabResolutionStatus.failed);
      expect(data.errorMessage, 'Network error');
      expect(data.isResolved, isFalse);
    });
  });

  group('LinkLabData.toMap', () {
    test('round-trips through fromMap', () {
      const original = LinkLabData(
        id: 'id1',
        fullLink: 'https://potje.tech/?a=1',
        shortLink: 'https://go.potje.tech/id1',
        createdAt: 1,
        updatedAt: 2,
        packageName: 'p',
        bundleId: 'b',
        appStoreId: 's',
        domain: 'go.potje.tech',
        domainType: LinkLabDomainType.custom,
        parameters: {'a': '1', 'b': '2'},
        resolutionStatus: LinkLabResolutionStatus.resolved,
        isDeferred: true,
        matchType: LinkLabMatchType.installReferrer,
      );
      final map = original.toMap();
      expect(map['domainType'], 'custom');
      expect(map['resolutionStatus'], 'resolved');
      expect(map['matchType'], 'installReferrer');
      expect(map['isDeferred'], isTrue);
      expect(map.containsKey('userId'), isFalse);

      final copy = LinkLabData.fromMap(map);
      expect(copy, original);
      expect(copy.parameters, original.parameters);
      expect(copy.domainType, original.domainType);
      expect(copy.resolutionStatus, original.resolutionStatus);
      expect(copy.isDeferred, original.isDeferred);
      expect(copy.createdAt, 1);
    });
  });

  group('LinkLabData equality', () {
    const a = LinkLabData(
      id: '1',
      fullLink: 'https://a',
      shortLink: 'https://s',
      matchType: LinkLabMatchType.direct,
      createdAt: 1,
    );

    test('equal on (id, fullLink, shortLink, matchType) only', () {
      const same = LinkLabData(
        id: '1',
        fullLink: 'https://a',
        shortLink: 'https://s',
        matchType: LinkLabMatchType.direct,
        createdAt: 999,
        domain: 'other',
      );
      expect(a, same);
      expect(a.hashCode, same.hashCode);
    });

    test('differs when any key field differs', () {
      expect(a, isNot(const LinkLabData(id: '2', fullLink: 'https://a', shortLink: 'https://s')));
      expect(a, isNot(const LinkLabData(id: '1', fullLink: 'https://b', shortLink: 'https://s')));
      expect(a, isNot(const LinkLabData(id: '1', fullLink: 'https://a', shortLink: 'https://t')));
      expect(
        a,
        isNot(const LinkLabData(
          id: '1',
          fullLink: 'https://a',
          shortLink: 'https://s',
          matchType: LinkLabMatchType.clipboard,
        )),
      );
    });
  });

  group('LinkLabConfig', () {
    test('defaults match the contract', () {
      const config = LinkLabConfig();
      expect(config.toMap(), {
        'customDomains': <String>[],
        'debugLoggingEnabled': false,
        'networkTimeout': 10.0,
        'networkRetryCount': 3,
        'baseUrl': 'https://linklab.cc',
        'installReferrerEnabled': true,
        'pasteboardMode': 'automatic',
        'forwardNonLinklabLinks': false,
      });
    });

    test('serialises pasteboardMode as a string', () {
      const config = LinkLabConfig(
        customDomains: ['go.potje.tech'],
        pasteboardMode: LinkLabPasteboardMode.manual,
      );
      expect(config.toMap()['pasteboardMode'], 'manual');
      expect(config.toMap()['customDomains'], ['go.potje.tech']);
    });
  });
}
