import 'dart:async';
import 'dart:developer';

import 'package:flutter/services.dart';

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
  });

  factory LinkLabData.fromMap(Map<dynamic, dynamic> map) {
    // Handle parameters coming from iOS SDK
    Map<String, String>? params;
    if (map['parameters'] != null) {
      if (map['parameters'] is Map) {
        params = Map<String, String>.from(
            (map['parameters'] as Map).map((key, value) => MapEntry(key.toString(), value.toString())));
      }
    }

    _log('LinkLabData.fromMap: ${map}'); // Add debug log

    return LinkLabData(
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
  }

  Map<String, dynamic> toMap() {
    return {
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
  }

  @override
  String toString() {
    return 'LinkLabData{id: $id, fullLink: $fullLink, domain: $domain, parameters: $parameters}';
  }
}

typedef LinkLabLinkCallback = void Function(LinkLabData data);
typedef LinkLabErrorCallback = void Function(String message, String? stackTrace);

class LinkLab {
  static final LinkLab _instance = LinkLab._internal();

  factory LinkLab() => _instance;

  LinkLab._internal() {
    // Set up method call handler immediately in constructor
    _channel.setMethodCallHandler(_handleMethod);
  }

  final MethodChannel _channel = const MethodChannel('cc.linklab.flutter/linklab');

  final StreamController<LinkLabData> _dynamicLinkStream = StreamController<LinkLabData>.broadcast();

  Stream<LinkLabData> get onLink => _dynamicLinkStream.stream;

  LinkLabLinkCallback? _onLink;
  LinkLabErrorCallback? _onError;

  bool _isInitialized = false;
  Completer<bool>? _initCompleter;

  Future<bool> initialize() async {
    if (_isInitialized) {
      return true;
    }

    if (_initCompleter != null) {
      return _initCompleter!.future;
    }

    _initCompleter = Completer<bool>();

    _log('LinkLab - Initializing plugin');
    try {
      final result = await _channel.invokeMethod<bool>('init') ?? false;
      _log('LinkLab - Init result: $result');
      _isInitialized = result;
      _initCompleter!.complete(result);
      return result;
    } catch (e) {
      _log('LinkLab - Init error: $e');
      _initCompleter!.complete(false);
      return false;
    }
  }

  Future<dynamic> _handleMethod(MethodCall call) async {
    _log('LinkLab - Received method call: ${call.method}');
    switch (call.method) {
      case 'onDynamicLinkReceived':
        _log('LinkLab - onDynamicLinkReceived with args: ${call.arguments}');
        if (call.arguments != null) {
          try {
            final data = LinkLabData.fromMap(call.arguments);
            _log('LinkLab - Parsed link data: $data');
            _dynamicLinkStream.add(data);
            _onLink?.call(data);
          } catch (e) {
            _log('LinkLab - Error parsing link data: $e');
          }
        } else {
          _log('LinkLab - Received null arguments for dynamic link');
        }
        break;
      case 'onError':
        final Map<dynamic, dynamic> args = call.arguments;
        final message = args['message'] as String;
        final stackTrace = args['stackTrace'] as String?;
        _log('LinkLab - Error: $message');
        _onError?.call(message, stackTrace);
        break;
    }
  }

  void setLinkListener(LinkLabLinkCallback onLink) {
    _log('LinkLab - Setting link listener');
    _onLink = onLink;
  }

  void setErrorListener(LinkLabErrorCallback onError) {
    _onError = onError;
  }

  Future<bool> isLinkLabLink(String link) async {
    await initialize();
    return await _channel.invokeMethod('isLinkLabLink', {'link': link}) ?? false;
  }

  Future<void> getDynamicLink(String shortLink) async {
    await initialize();
    await _channel.invokeMethod('getDynamicLink', {'shortLink': shortLink});
  }

  Future<LinkLabData?> getInitialLink() async {
    await initialize();
    _log('LinkLab - Getting initial link');
    try {
      final data = await _channel.invokeMethod('getInitialLink');
      _log('LinkLab - Initial link data: $data');
      if (data == null) return null;
      return LinkLabData.fromMap(data);
    } catch (e) {
      _log('LinkLab - Error getting initial link: $e');
      return null;
    }
  }
}

void _log(
  Object? message, {
  Object? error,
  StackTrace? stackTrace,
}) {
  return log(
    '$message',
    name: 'LinkLab',
    error: error,
    stackTrace: stackTrace,
  );
}
