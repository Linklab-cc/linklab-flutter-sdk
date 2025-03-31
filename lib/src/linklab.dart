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

    _log('LinkLabData.fromMap: $map');

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
    _log('LinkLab._internal() - Setting up method call handler');
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
    _log('LinkLab.initialize() called');
    if (_isInitialized) {
      _log('LinkLab already initialized, returning true');
      return true;
    }

    if (_initCompleter != null) {
      _log('LinkLab initialization already in progress, waiting for result');
      return _initCompleter!.future;
    }

    _log('LinkLab starting initialization');
    _initCompleter = Completer<bool>();

    try {
      _log('LinkLab calling init method on native plugin');
      final result = await _channel.invokeMethod<bool>('init') ?? false;
      _log('LinkLab.initialize() - Native init result: $result');
      _isInitialized = result;
      _initCompleter!.complete(result);
      return result;
    } catch (e, stackTrace) {
      _log('LinkLab.initialize() - Error initializing plugin', error: e, stackTrace: stackTrace);
      _initCompleter!.complete(false);
      return false;
    }
  }

  Future<dynamic> _handleMethod(MethodCall call) async {
    _log('LinkLab._handleMethod() - Received method call: ${call.method}');
    switch (call.method) {
      case 'onDynamicLinkReceived':
        _log('LinkLab received onDynamicLinkReceived with args: ${call.arguments}');
        if (call.arguments != null) {
          try {
            final data = LinkLabData.fromMap(call.arguments);
            _log('LinkLab parsed link data: $data');
            _dynamicLinkStream.add(data);
            _log('LinkLab added link data to stream');

            if (_onLink != null) {
              _log('LinkLab calling onLink callback');
              _onLink?.call(data);
            } else {
              _log('LinkLab no onLink callback registered');
            }
          } catch (e, stackTrace) {
            _log('LinkLab error parsing link data', error: e, stackTrace: stackTrace);
          }
        } else {
          _log('LinkLab received null arguments for dynamic link');
        }
        break;
      case 'onError':
        _log('LinkLab received onError');
        final Map<dynamic, dynamic> args = call.arguments;
        final message = args['message'] as String;
        final stackTrace = args['stackTrace'] as String?;
        _log('LinkLab error: $message');
        _onError?.call(message, stackTrace);
        break;
      default:
        _log('LinkLab received unknown method: ${call.method}');
    }
  }

  void setLinkListener(LinkLabLinkCallback onLink) {
    _log('LinkLab.setLinkListener() called');
    _onLink = onLink;
  }

  void setErrorListener(LinkLabErrorCallback onError) {
    _log('LinkLab.setErrorListener() called');
    _onError = onError;
  }

  Future<bool> isLinkLabLink(String link) async {
    _log('LinkLab.isLinkLabLink() called with: $link');
    await initialize();
    _log('LinkLab.isLinkLabLink() - initialization complete, checking link');
    final result = await _channel.invokeMethod('isLinkLabLink', {'link': link}) ?? false;
    _log('LinkLab.isLinkLabLink() result: $result');
    return result;
  }

  Future<void> getDynamicLink(String shortLink) async {
    _log('LinkLab.getDynamicLink() called with: $shortLink');
    await initialize();
    _log('LinkLab.getDynamicLink() - initialization complete, getting link');
    await _channel.invokeMethod('getDynamicLink', {'shortLink': shortLink});
    _log('LinkLab.getDynamicLink() complete');
  }

  Future<LinkLabData?> getInitialLink() async {
    _log('LinkLab.getInitialLink() called');
    await initialize();
    _log('LinkLab.getInitialLink() - initialization complete, getting initial link');
    try {
      final data = await _channel.invokeMethod('getInitialLink');
      _log('LinkLab.getInitialLink() result: $data');
      if (data == null) {
        _log('LinkLab.getInitialLink() returning null, no initial link');
        return null;
      }
      final linkData = LinkLabData.fromMap(data);
      _log('LinkLab.getInitialLink() returning link data: $linkData');
      return linkData;
    } catch (e, stackTrace) {
      _log('LinkLab.getInitialLink() - Error getting initial link', error: e, stackTrace: stackTrace);
      return null;
    }
  }
}

void _log(
    String message, {
      Object? error,
      StackTrace? stackTrace,
    }) {
  log(
    message,
    name: 'LinkLab',
    error: error,
    stackTrace: stackTrace,
  );
}