import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:linklab_flutter_sdk/linklab_flutter_sdk.dart';

const MethodChannel channel = MethodChannel(LinkLab.channelName);

final Map<String, dynamic> linkMap = <String, dynamic>{
  'id': 'abc',
  'fullLink': 'https://potje.tech/?promo=1',
  'shortLink': 'https://linklab.cc/abc',
  'domain': 'linklab.cc',
  'domainType': 'linklab',
  'parameters': <String, String>{'promo': '1'},
  'resolutionStatus': 'resolved',
  'isDeferred': false,
  'matchType': 'direct',
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late List<MethodCall> calls;
  Future<Object?> Function(MethodCall call)? responder;

  /// Simulates a native → Dart call on the channel.
  Future<void> nativeCall(String method, [Object? arguments]) async {
    final completer = Completer<void>();
    await messenger.handlePlatformMessage(
      LinkLab.channelName,
      const StandardMethodCodec().encodeMethodCall(MethodCall(method, arguments)),
      (_) => completer.complete(),
    );
    await completer.future;
  }

  setUp(() {
    calls = <MethodCall>[];
    responder = null;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (responder != null) return responder!(call);
      switch (call.method) {
        case 'init':
          return true;
        case 'ready':
          return null;
        default:
          return null;
      }
    });
  });

  tearDown(() {
    LinkLab().dispose();
    messenger.setMockMethodCallHandler(channel, null);
  });

  group('initialize', () {
    test('sends init with the config map, then ready', () async {
      final linkLab = LinkLab();
      expect(linkLab.isInitialized, isFalse);

      await linkLab.initialize(
        config: const LinkLabConfig(
          customDomains: ['go.potje.tech'],
          pasteboardMode: LinkLabPasteboardMode.manual,
        ),
      );

      expect(linkLab.isInitialized, isTrue);
      expect(calls.map((c) => c.method), ['init', 'ready']);
      final config = calls.first.arguments as Map;
      expect(config['customDomains'], ['go.potje.tech']);
      expect(config['pasteboardMode'], 'manual');
      expect(config['networkTimeout'], 10.0);
      expect(config['forwardNonLinklabLinks'], isFalse);
    });

    test('sends forwardNonLinklabLinks when enabled', () async {
      await LinkLab().initialize(
        config: const LinkLabConfig(forwardNonLinklabLinks: true),
      );
      final config = calls.first.arguments as Map;
      expect(config['forwardNonLinklabLinks'], isTrue);
    });

    test('is idempotent: same future while pending, no-op after', () async {
      final linkLab = LinkLab();
      final first = linkLab.initialize();
      final second = linkLab.initialize();
      expect(identical(first, second), isTrue);
      await first;
      await linkLab.initialize();
      expect(calls.where((c) => c.method == 'init').length, 1);
      expect(calls.where((c) => c.method == 'ready').length, 1);
    });

    test('reports and rethrows errors once, then allows a retry', () async {
      final linkLab = LinkLab();
      final errors = <String>[];
      linkLab.setErrorListener((message, details) => errors.add(message));
      responder = (call) async {
        if (call.method == 'init') {
          throw PlatformException(code: 'BOOM', message: 'native failure');
        }
        return null;
      };

      final future = linkLab.initialize();
      final again = linkLab.initialize();
      expect(identical(future, again), isTrue);
      await expectLater(future, throwsA(isA<PlatformException>()));
      await expectLater(again, throwsA(isA<PlatformException>()));

      expect(errors, hasLength(1));
      expect(errors.single, contains('native failure'));
      expect(linkLab.isInitialized, isFalse);

      responder = null;
      await linkLab.initialize();
      expect(linkLab.isInitialized, isTrue);
    });
  });

  group('onLink', () {
    test('delivers a forwarded non-Linklab link as passthrough', () async {
      final linkLab = LinkLab();
      await linkLab.initialize(
        config: const LinkLabConfig(forwardNonLinklabLinks: true),
      );
      final received = <LinkLabData>[];
      final sub = linkLab.onLink.listen(received.add);

      await nativeCall('onLink', <String, dynamic>{
        'fullLink': 'https://auth.example.com/?mode=signIn&oobCode=abc',
        'shortLink': 'https://auth.example.com/?mode=signIn&oobCode=abc',
        'domain': 'auth.example.com',
        'domainType': 'unrecognized',
        'parameters': <String, String>{},
        'resolutionStatus': 'passthrough',
        'isDeferred': false,
        'matchType': 'direct',
      });
      await Future<void>.delayed(Duration.zero);

      expect(received, hasLength(1));
      final link = received.single;
      expect(link.isPassthrough, isTrue);
      expect(link.isResolved, isFalse);
      expect(link.id, isNull);
      expect(link.uri.host, 'auth.example.com');
      expect(link.parameters, {'mode': 'signIn', 'oobCode': 'abc'});
      await sub.cancel();
    });

    test('buffers links until the first listener and flushes in order',
        () async {
      final linkLab = LinkLab();
      await linkLab.initialize();

      await nativeCall('onLink', {...linkMap, 'id': 'first'});
      await nativeCall('onLink', {...linkMap, 'id': 'second'});

      final received = <String?>[];
      final sub = linkLab.onLink.listen((l) => received.add(l.id));
      await Future<void>.delayed(Duration.zero);
      expect(received, ['first', 'second']);

      await nativeCall('onLink', {...linkMap, 'id': 'third'});
      await Future<void>.delayed(Duration.zero);
      expect(received, ['first', 'second', 'third']);
      await sub.cancel();
    });

    test('delivers each link once to the stream and once to the listener',
        () async {
      final linkLab = LinkLab();
      await linkLab.initialize();

      final fromStream = <LinkLabData>[];
      final fromListener = <LinkLabData>[];
      final sub = linkLab.onLink.listen(fromStream.add);
      linkLab.setLinkListener(fromListener.add);

      await nativeCall('onLink', linkMap);
      await Future<void>.delayed(Duration.zero);

      expect(fromStream, hasLength(1));
      expect(fromListener, hasLength(1));
      expect(fromStream.single, fromListener.single);
      expect(fromStream.single.parameters, {'promo': '1'});
      await sub.cancel();
    });

    test('a second stream listener does not replay past links', () async {
      final linkLab = LinkLab();
      await linkLab.initialize();
      final a = <LinkLabData>[];
      final b = <LinkLabData>[];
      final subA = linkLab.onLink.listen(a.add);
      await nativeCall('onLink', linkMap);
      await Future<void>.delayed(Duration.zero);
      final subB = linkLab.onLink.listen(b.add);
      await Future<void>.delayed(Duration.zero);
      expect(a, hasLength(1));
      expect(b, isEmpty);
      await subA.cancel();
      await subB.cancel();
    });
  });

  group('native onError', () {
    test('is forwarded to the error listener with code as details', () async {
      final linkLab = LinkLab();
      await linkLab.initialize();
      String? message;
      String? details;
      linkLab.setErrorListener((m, d) {
        message = m;
        details = d;
      });

      await nativeCall('onError', {'message': 'Network down', 'code': 'NETWORK'});
      expect(message, 'Network down');
      expect(details, 'NETWORK');
    });
  });

  group('method passthrough', () {
    test('getInitialLink returns the mapped link or null', () async {
      final linkLab = LinkLab();
      await linkLab.initialize();

      responder = (call) async => call.method == 'getInitialLink' ? linkMap : null;
      final link = await linkLab.getInitialLink();
      expect(link, isNotNull);
      expect(link!.id, 'abc');
      expect(link.fullLink, 'https://potje.tech/?promo=1');
      expect(link.matchType, LinkLabMatchType.direct);

      responder = (call) async => null;
      expect(await linkLab.getInitialLink(), isNull);
      expect(calls.where((c) => c.method == 'getInitialLink').length, 2);
    });

    test('getInitialLink waits for a pending initialize', () async {
      final linkLab = LinkLab();
      final order = <String>[];
      responder = (call) async {
        order.add(call.method);
        return call.method == 'getInitialLink' ? linkMap : null;
      };
      // Not awaited on purpose: getInitialLink must queue behind it.
      final init = linkLab.initialize();
      final link = await linkLab.getInitialLink();
      await init;
      expect(order, ['init', 'ready', 'getInitialLink']);
      expect(link?.id, 'abc');
    });

    test('resolve returns the value directly and sends shortLink', () async {
      final linkLab = LinkLab();
      await linkLab.initialize();
      responder = (call) async {
        if (call.method == 'resolve') {
          expect(call.arguments, {'shortLink': 'https://linklab.cc/abc'});
          return linkMap;
        }
        return null;
      };
      final link = await linkLab.resolve('https://linklab.cc/abc');
      expect(link?.id, 'abc');

      // ignore: deprecated_member_use_from_same_package
      final legacy = await linkLab.getDynamicLink('https://linklab.cc/abc');
      expect(legacy, link);
    });

    test('resolve returns null for a non-Linklab link', () async {
      final linkLab = LinkLab();
      await linkLab.initialize();
      responder = (call) async => null;
      expect(await linkLab.resolve('https://example.com'), isNull);
    });

    test('isLinkLabLink and checkPasteboard pass through', () async {
      final linkLab = LinkLab();
      await linkLab.initialize();
      responder = (call) async {
        switch (call.method) {
          case 'isLinkLabLink':
            return (call.arguments as Map)['link'] == 'https://linklab.cc/x';
          case 'checkPasteboard':
            return {...linkMap, 'matchType': 'clipboard', 'isDeferred': true};
        }
        return null;
      };
      expect(await linkLab.isLinkLabLink('https://linklab.cc/x'), isTrue);
      expect(await linkLab.isLinkLabLink('https://example.com'), isFalse);
      final pasted = await linkLab.checkPasteboard();
      expect(pasted?.matchType, LinkLabMatchType.clipboard);
      expect(pasted?.isDeferred, isTrue);
    });

    test('platform errors propagate to the caller', () async {
      final linkLab = LinkLab();
      await linkLab.initialize();
      responder = (call) async {
        if (call.method == 'resolve') {
          throw PlatformException(code: 'TIMEOUT', message: 'timed out');
        }
        return null;
      };
      await expectLater(
        linkLab.resolve('https://linklab.cc/slow'),
        throwsA(isA<PlatformException>()),
      );
    });
  });

  group('dispose', () {
    test('closes the stream, clears state and allows re-initialization',
        () async {
      final linkLab = LinkLab();
      await linkLab.initialize();
      final stream = linkLab.onLink;
      final done = Completer<void>();
      stream.listen(null, onDone: done.complete);

      linkLab.dispose();
      await done.future;
      expect(linkLab.isInitialized, isFalse);

      // No handler is attached any more: the native call is not delivered.
      calls.clear();
      await nativeCall('onLink', linkMap);

      final received = <LinkLabData>[];
      linkLab.onLink.listen(received.add);
      await Future<void>.delayed(Duration.zero);
      expect(received, isEmpty);

      await linkLab.initialize();
      expect(linkLab.isInitialized, isTrue);
      expect(calls.map((c) => c.method), ['init', 'ready']);
    });
  });
}
