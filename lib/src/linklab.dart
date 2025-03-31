import 'dart:async';
import 'package:flutter/services.dart';
import 'dart:developer' as developer;

// Helper function for consistent logging
void log(String message) {
  developer.log(message, name: 'LinkLab');
}

class LinkLabData {
  final String id;
  final String fullLink;
  final int createdAt;
  final int updatedAt;
  final String userId;
  final String? packageName;
  final String? bundleId;
  final String? appStoreId;
  final String domainType;
  final String domain;
  final Map<String, String>? parameters;

  LinkLabData({
    required this.id,
    required this.fullLink,
    required this.createdAt,
    required this.updatedAt,
    required this.userId,
    this.packageName,
    this.bundleId,
    this.appStoreId,
    required this.domainType,
    required this.domain,
    this.parameters,
  }) {
    log('LinkLabData created: id=$id, fullLink=$fullLink');
  }

  factory LinkLabData.fromMap(Map<dynamic, dynamic> map) {
    log('LinkLabData.fromMap called with: ${map.toString()}');

    // Handle parameters coming from iOS SDK
    Map<String, String>? params;
    if (map['parameters'] != null) {
      log('Processing parameters: ${map['parameters']}');
      if (map['parameters'] is Map) {
        params = Map<String, String>.from(
            (map['parameters'] as Map).map((key, value) {
              log('Parameter: $key = $value');
              return MapEntry(key.toString(), value.toString());
            })
        );
      } else {
        log('Warning: parameters is not a Map: ${map['parameters'].runtimeType}');
      }
    } else {
      log('No parameters provided');
    }

    final data = LinkLabData(
      id: map['id'] as String,
      fullLink: map['fullLink'] as String,
      createdAt: map['createdAt'] as int,
      updatedAt: map['updatedAt'] as int,
      userId: map['userId'] as String,
      packageName: map['packageName'] as String?,
      bundleId: map['bundleId'] as String?,
      appStoreId: map['appStoreId'] as String?,
      domainType: map['domainType'] as String,
      domain: map['domain'] as String,
      parameters: params,
    );

    log('LinkLabData.fromMap created object: id=${data.id}');
    return data;
  }

  Map<String, dynamic> toMap() {
    log('Converting LinkLabData to Map: id=$id');
    final map = {
      'id': id,
      'fullLink': fullLink,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
      'userId': userId,
      'packageName': packageName,
      'bundleId': bundleId,
      'appStoreId': appStoreId,
      'domainType': domainType,
      'domain': domain,
      'parameters': parameters,
    };
    log('Converted to map: ${map.toString()}');
    return map;
  }
}

typedef LinkLabLinkCallback = void Function(LinkLabData data);
typedef LinkLabErrorCallback = void Function(String message, String? stackTrace);

class LinkLab {
  static final LinkLab _instance = LinkLab._internal();

  factory LinkLab() {
    log('LinkLab factory called');
    return _instance;
  }

  LinkLab._internal() {
    log('LinkLab._internal constructor called');
  }

  final MethodChannel _channel = const MethodChannel('cc.linklab.flutter/linklab');

  final StreamController<LinkLabData> _dynamicLinkStream =
  StreamController<LinkLabData>.broadcast();

  Stream<LinkLabData> get onLink => _dynamicLinkStream.stream;

  LinkLabLinkCallback? _onLink;
  LinkLabErrorCallback? _onError;

  Future<void> initialize() async {
    log('LinkLab.initialize called');
    _channel.setMethodCallHandler(_handleMethod);
    log('Method call handler set');

    try {
      await _channel.invokeMethod('init');
      log('LinkLab initialization successful');
    } catch (e, stackTrace) {
      log('Error during LinkLab initialization: $e');
      log('Stack trace: $stackTrace');
      rethrow;
    }
  }

  Future<dynamic> _handleMethod(MethodCall call) async {
    log('Received method call: ${call.method}');
    log('Arguments: ${call.arguments}');

    switch (call.method) {
      case 'onDynamicLinkReceived':
        log('Processing dynamic link');
        try {
          final data = LinkLabData.fromMap(call.arguments);
          log('Successfully parsed LinkLabData: id=${data.id}');
          _dynamicLinkStream.add(data);
          log('Added to dynamic link stream');

          if (_onLink != null) {
            log('Calling onLink callback');
            _onLink?.call(data);
          } else {
            log('No onLink callback registered');
          }
        } catch (e, stackTrace) {
          log('Error processing dynamic link: $e');
          log('Stack trace: $stackTrace');
          _onError?.call('Error processing dynamic link: $e', stackTrace.toString());
        }
        break;

      case 'onError':
        log('Processing error from native side');
        final Map<dynamic, dynamic> args = call.arguments;
        final message = args['message'] as String;
        final stackTrace = args['stackTrace'] as String?;
        log('Error from native: $message');
        if (stackTrace != null) {
          log('Native stack trace: $stackTrace');
        }
        _onError?.call(message, stackTrace);
        break;

      default:
        log('Unknown method call: ${call.method}');
    }
  }

  void setLinkListener(LinkLabLinkCallback onLink) {
    log('Setting link listener');
    _onLink = onLink;
  }

  void setErrorListener(LinkLabErrorCallback onError) {
    log('Setting error listener');
    _onError = onError;
  }

  Future<bool> isLinkLabLink(String link) async {
    log('isLinkLabLink called with: $link');
    try {
      final result = await _channel.invokeMethod('isLinkLabLink', {'link': link}) ?? false;
      log('isLinkLabLink result: $result');
      return result;
    } catch (e, stackTrace) {
      log('Error in isLinkLabLink: $e');
      log('Stack trace: $stackTrace');
      _onError?.call('Error checking if link is LinkLab link: $e', stackTrace.toString());
      return false;
    }
  }

  Future<void> getDynamicLink(String shortLink) async {
    log('getDynamicLink called with: $shortLink');
    try {
      await _channel.invokeMethod('getDynamicLink', {'shortLink': shortLink});
      log('getDynamicLink method invoked successfully');
    } catch (e, stackTrace) {
      log('Error in getDynamicLink: $e');
      log('Stack trace: $stackTrace');
      _onError?.call('Error getting dynamic link: $e', stackTrace.toString());
      rethrow;
    }
  }

  Future<LinkLabData?> getInitialLink() async {
    log('getInitialLink called');
    try {
      final data = await _channel.invokeMethod('getInitialLink');
      if (data == null) {
        log('No initial link data available');
        return null;
      }

      log('Initial link data received: $data');
      final linkData = LinkLabData.fromMap(data);
      log('Initial link parsed successfully: id=${linkData.id}');
      return linkData;
    } catch (e, stackTrace) {
      log('Error in getInitialLink: $e');
      log('Stack trace: $stackTrace');
      _onError?.call('Error getting initial link: $e', stackTrace.toString());
      return null;
    }
  }
}