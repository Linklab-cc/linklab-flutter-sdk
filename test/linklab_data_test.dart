import 'package:flutter_test/flutter_test.dart';
import 'package:linklab_flutter_sdk/linklab_flutter_sdk.dart';

void main() {
  const destination =
      'https://potje.tech/en/?promoId=75iOS8HDjnRcPNS00qor&type=getPromoCode';

  for (final key in ['rawLink', 'fullLink']) {
    test('preserves destination parameters from $key on first launch', () {
      final data = LinkLabData.fromMap({
        key: destination,
        'domainType': 'customDomain',
        'domain': 'app.potje.tech',
        'parameters': <String, String>{},
      });

      expect(data.rawLink, destination);
      expect(data.parameters, {
        'promoId': '75iOS8HDjnRcPNS00qor',
        'type': 'getPromoCode',
      });
      expect(LinkLabData.fromMap(data.toMap()).parameters, data.parameters);
    });
  }

  test('preserves explicit parameters and decodes query values once', () {
    final data = LinkLabData.fromMap({
      'rawLink': 'https://potje.tech/en/?campaign=spring%26summer&code=a%252Fb',
      'parameters': {'campaign': 'override', 'source': 'newsletter'},
    });

    expect(data.parameters, {
      'campaign': 'override',
      'code': 'a%2Fb',
      'source': 'newsletter',
    });
  });

  test('handles a destination with no query or invalid URL', () {
    for (final url in ['https://potje.tech/en/', '', 'https://[invalid']) {
      final data = LinkLabData.fromMap({'rawLink': url});
      expect(data.rawLink, url);
      expect(data.parameters, isEmpty);
    }
  });
}
