import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/services.dart';

// Helper function for consistent logging
void log(String message) {
  developer.log(message, name: 'LinkLab');
}

class LinkLabData {
  final String? id;
  final String rawLink;
  final int? createdAt;
  final int? updatedAt;
  final String? userId;
  final String? packageName;
  final String? bundleId;
  final String? appStoreId;
  final String domainType;
  final String? domain;
  final Map<String, String>? parameters;

  LinkLabData({
    required this.id,
    required this.rawLink,
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
    log('LinkLabData created: id=$id, fullLink=$rawLink');
  }

  factory LinkLabData.fromMap(Map<dynamic, dynamic> map) {
    log('LinkLabData.fromMap called with: ${map.toString()}');

    // Handle parameters coming from iOS SDK
    Map<String, String>? params;
    if (map['parameters'] != null) {
      if (map['parameters'] is Map) {
        params = Map<String, String>.from((map['parameters'] as Map).map((key, value) {
          return MapEntry(key.toString(), value.toString());
        }));
      } else {
        log('Warning: parameters is not a Map: ${map['parameters'].runtimeType}');
      }
    }

    // Handle both int and double types for timestamps
    final createdAt = map['createdAt'] == null
        ? null
        : map['createdAt'] is int
        ? map['createdAt'] as int
        : (map['createdAt'] as double).toInt();

    final updatedAt = map['updatedAt'] == null
        ? null
        : map['updatedAt'] is int
        ? map['updatedAt'] as int
        : (map['updatedAt'] as double).toInt();

    return LinkLabData(
      // CRITICAL FIX: Cast as String? because id can be null for unrecognized links
      id: map['id'] as String?,
      rawLink: map['rawLink'] as String? ?? "", // Safety fallback
      createdAt: createdAt,
      updatedAt: updatedAt,
      userId: map['userId'] as String?,
      packageName: map['packageName'] as String?,
      bundleId: map['bundleId'] as String?,
      appStoreId: map['appStoreId'] as String?,
      domainType: map['domainType'] as String? ?? "unrecognized", // Fallback
      domain: map['domain'] as String?,
      parameters: params,
    );
  }

  Map<String, dynamic> toMap() {
    final map = {
      'id': id,
      'rawLink': rawLink,
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
    return map;
  }
}

typedef LinkLabLinkCallback = void Function(LinkLabData data);
typedef LinkLabErrorCallback = void Function(String message, String? stackTrace);

class LinkLabConfig {
  final List<String> customDomains;
  final bool debugLoggingEnabled;
  final double networkTimeout;
  final int networkRetryCount;

  LinkLabConfig({
    this.customDomains = const [],
    this.debugLoggingEnabled = false,
    this.networkTimeout = 30.0,
    this.networkRetryCount = 3,
  });

  Map<String, dynamic> toMap() {
    return {
      'customDomains': customDomains,
      'debugLoggingEnabled': debugLoggingEnabled,
      'networkTimeout': networkTimeout,
      'networkRetryCount': networkRetryCount,
    };
  }
}

class LinkLab {
  static final LinkLab _instance = LinkLab._internal();

  factory LinkLab() {
    return _instance;
  }

  LinkLab._internal();

  final MethodChannel _channel = const MethodChannel('cc.linklab.flutter/linklab');
  final StreamController<LinkLabData> _dynamicLinkStream = StreamController<LinkLabData>.broadcast();

  Stream<LinkLabData> get onLink => _dynamicLinkStream.stream;

  LinkLabLinkCallback? _onLink;
  LinkLabErrorCallback? _onError;

  Future<void> initialize({LinkLabConfig? config}) async {
    _channel.setMethodCallHandler(_handleMethod);

    try {
      final Map<String, dynamic> configMap = config?.toMap() ?? {};
      await _channel.invokeMethod('init', configMap);
      log('LinkLab initialization successful');
    } catch (e, stackTrace) {
      log('Error during LinkLab initialization: $e');
      _onError?.call(e.toString(), stackTrace.toString());
      rethrow;
    }
  }

  Future<dynamic> _handleMethod(MethodCall call) async {
    switch (call.method) {
      case 'onDynamicLinkReceived':
        try {
          // Check if arguments are null
          if (call.arguments == null) return;

          final data = LinkLabData.fromMap(call.arguments);
          _dynamicLinkStream.add(data);

          if (_onLink != null) {
            _onLink?.call(data);
          }
        } catch (e, stackTrace) {
          log('Error processing dynamic link: $e');
          _onError?.call('Error processing dynamic link: $e', stackTrace.toString());
        }
        break;

      case 'onError':
        final Map<dynamic, dynamic> args = call.arguments;
        final message = args['message'] as String;
        final stackTrace = args['stackTrace'] as String?;
        _onError?.call(message, stackTrace);
        break;
    }
  }

  void setLinkListener(LinkLabLinkCallback onLink) {
    _onLink = onLink;
  }

  void setErrorListener(LinkLabErrorCallback onError) {
    _onError = onError;
  }

  Future<bool> isLinkLabLink(String link) async {
    try {
      final result = await _channel.invokeMethod('isLinkLabLink', {'link': link}) ?? false;
      return result;
    } catch (e, stackTrace) {
      _onError?.call('Error checking link: $e', stackTrace.toString());
      return false;
    }
  }

  Future<void> getDynamicLink(String shortLink) async {
    try {
      await _channel.invokeMethod('getDynamicLink', {'shortLink': shortLink});
    } catch (e, stackTrace) {
      _onError?.call('Error getting dynamic link: $e', stackTrace.toString());
      rethrow;
    }
  }

  Future<LinkLabData?> getInitialLink() async {
    try {
      final data = await _channel.invokeMethod('getInitialLink');
      if (data == null) return null;

      return LinkLabData.fromMap(data);
    } catch (e, stackTrace) {
      _onError?.call('Error getting initial link: $e', stackTrace.toString());
      return null;
    }
  }
}