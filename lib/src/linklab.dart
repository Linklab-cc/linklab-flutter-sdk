import 'dart:async';
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
          (map['parameters'] as Map).map((key, value) => 
            MapEntry(key.toString(), value.toString()))
        );
      }
    }
    
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
}

typedef LinkLabLinkCallback = void Function(LinkLabData data);
typedef LinkLabErrorCallback = void Function(String message, String? stackTrace);

class LinkLab {
  static final LinkLab _instance = LinkLab._internal();
  
  factory LinkLab() => _instance;
  
  LinkLab._internal();
  
  final MethodChannel _channel = const MethodChannel('cc.linklab.flutter/linklab');
  
  final StreamController<LinkLabData> _dynamicLinkStream = 
      StreamController<LinkLabData>.broadcast();
  
  Stream<LinkLabData> get onLink => _dynamicLinkStream.stream;
  
  LinkLabLinkCallback? _onLink;
  LinkLabErrorCallback? _onError;
  
  Future<void> initialize() async {
    _channel.setMethodCallHandler(_handleMethod);
  }
  
  Future<dynamic> _handleMethod(MethodCall call) async {
    switch (call.method) {
      case 'onDynamicLinkReceived':
        final data = LinkLabData.fromMap(call.arguments);
        _dynamicLinkStream.add(data);
        _onLink?.call(data);
        break;
      case 'onError':
        final Map<dynamic, dynamic> args = call.arguments;
        final message = args['message'] as String;
        final stackTrace = args['stackTrace'] as String?;
        _onError?.call(message, stackTrace);
        break;
    }
  }
  
  Future<void> configure(String apiKey) async {
    await _channel.invokeMethod('configure', {'apiKey': apiKey});
  }
  
  void setLinkListener(LinkLabLinkCallback onLink) {
    _onLink = onLink;
  }
  
  void setErrorListener(LinkLabErrorCallback onError) {
    _onError = onError;
  }
  
  Future<bool> isLinkLabLink(String link) async {
    return await _channel.invokeMethod('isLinkLabLink', {'link': link}) ?? false;
  }
  
  Future<void> getDynamicLink(String shortLink) async {
    await _channel.invokeMethod('getDynamicLink', {'shortLink': shortLink});
  }
  
  Future<LinkLabData?> getInitialLink() async {
    final data = await _channel.invokeMethod('getInitialLink');
    if (data == null) return null;
    return LinkLabData.fromMap(data);
  }
}