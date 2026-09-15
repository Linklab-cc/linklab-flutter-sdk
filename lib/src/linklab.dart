import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/services.dart';

import 'config.dart';
import 'link_data.dart';

/// Callback for [LinkLab.setLinkListener].
typedef LinkLabLinkCallback = void Function(LinkLabData data);

/// Callback for [LinkLab.setErrorListener].
///
/// [details] carries the native error code or stack trace when available.
typedef LinkLabErrorCallback = void Function(String message, String? details);

/// Entry point of the Linklab Flutter SDK.
///
/// `LinkLab()` always returns the same instance. Call [initialize] once at
/// startup, then listen to [onLink]; links received before the first listener
/// subscribes are buffered and replayed in order.
class LinkLab {
  /// Returns the shared instance.
  factory LinkLab() => _instance;

  LinkLab._();

  static final LinkLab _instance = LinkLab._();

  /// Name of the method channel shared with the platform plugins.
  static const String channelName = 'cc.linklab.flutter/linklab';

  static const MethodChannel _channel = MethodChannel(channelName);

  Future<void>? _initFuture;
  bool _isInitialized = false;
  bool _debugLogging = false;

  StreamController<LinkLabData>? _controller;
  final List<LinkLabData> _buffer = <LinkLabData>[];

  LinkLabLinkCallback? _linkListener;
  LinkLabErrorCallback? _errorListener;

  /// `true` once [initialize] has completed successfully.
  bool get isInitialized => _isInitialized;

  /// Every link delivered to the app, exactly once each.
  ///
  /// Broadcast stream. Links that arrive before the first listener subscribes
  /// are buffered and flushed, in order, to that first listener.
  Stream<LinkLabData> get onLink => _streamController.stream;

  StreamController<LinkLabData> get _streamController {
    return _controller ??= StreamController<LinkLabData>.broadcast(
      onListen: _flushBuffer,
    );
  }

  /// Initialises the native SDK.
  ///
  /// Idempotent: concurrent and repeated calls return the same [Future]; once
  /// complete, further calls are a no-op. If initialization fails, the error
  /// listener (see [setErrorListener]) is invoked once and the error is
  /// rethrown; a later call starts a fresh attempt.
  Future<void> initialize({LinkLabConfig? config}) {
    final pending = _initFuture;
    if (pending != null) return pending;
    final future = _initialize(config ?? const LinkLabConfig());
    _initFuture = future;
    return future;
  }

  Future<void> _initialize(LinkLabConfig config) async {
    _debugLogging = config.debugLoggingEnabled;
    _channel.setMethodCallHandler(_handleMethodCall);
    try {
      await _channel.invokeMethod<void>('init', config.toMap());
      await _channel.invokeMethod<void>('ready');
      _isInitialized = true;
      _log('initialized');
    } catch (error, stackTrace) {
      _initFuture = null;
      _log('initialization failed: $error');
      _errorListener?.call(error.toString(), stackTrace.toString());
      rethrow;
    }
  }

  /// The first link delivered in this process, or `null`.
  ///
  /// Non-destructive: the same link is also delivered through [onLink]. The
  /// platform side waits (up to 5 s) for an in-flight resolution before
  /// answering. If [initialize] has been called, this waits for it first.
  Future<LinkLabData?> getInitialLink() async {
    await _awaitInitialization();
    final map = await _channel.invokeMapMethod<dynamic, dynamic>('getInitialLink');
    return map == null ? null : LinkLabData.fromMap(map);
  }

  /// Resolves [shortLink] and returns the result directly (not via [onLink]).
  ///
  /// Returns `null` when [shortLink] is not a Linklab link. Resolution
  /// failures are reported as a [LinkLabData] with
  /// [LinkLabResolutionStatus.failed] or [LinkLabResolutionStatus.unrecognized].
  Future<LinkLabData?> resolve(String shortLink) async {
    await _awaitInitialization();
    final map = await _channel.invokeMapMethod<dynamic, dynamic>(
      'resolve',
      <String, dynamic>{'shortLink': shortLink},
    );
    return map == null ? null : LinkLabData.fromMap(map);
  }

  /// Legacy alias of [resolve].
  @Deprecated('Use resolve')
  Future<LinkLabData?> getDynamicLink(String shortLink) => resolve(shortLink);

  /// Whether [link] is an http(s) URL on `linklab.cc`, a subdomain of it, or
  /// one of the configured custom domains.
  Future<bool> isLinkLabLink(String link) async {
    await _awaitInitialization();
    final result = await _channel.invokeMethod<bool>(
      'isLinkLabLink',
      <String, dynamic>{'link': link},
    );
    return result ?? false;
  }

  /// iOS: reads the pasteboard once and resolves a Linklab URL or token found
  /// there. Intended for [LinkLabPasteboardMode.manual] after a user action.
  /// The result is returned here only, not via [onLink].
  ///
  /// Always returns `null` on Android.
  Future<LinkLabData?> checkPasteboard() async {
    await _awaitInitialization();
    final map = await _channel.invokeMapMethod<dynamic, dynamic>('checkPasteboard');
    return map == null ? null : LinkLabData.fromMap(map);
  }

  /// Registers a callback invoked for every link, in addition to [onLink].
  ///
  /// Sugar over the stream: each link is delivered to the stream and to this
  /// callback exactly once each. Pass `null` to remove the callback. Links
  /// buffered before any stream listener are not replayed to this callback.
  void setLinkListener(LinkLabLinkCallback? onLink) {
    _linkListener = onLink;
  }

  /// Registers a callback for asynchronous native errors and
  /// [initialize] failures. Pass `null` to remove it.
  void setErrorListener(LinkLabErrorCallback? onError) {
    _errorListener = onError;
  }

  /// Releases the stream, clears buffered links and listeners, and detaches
  /// from the method channel. A later [initialize] starts from scratch.
  void dispose() {
    _channel.setMethodCallHandler(null);
    _controller?.close();
    _controller = null;
    _buffer.clear();
    _linkListener = null;
    _errorListener = null;
    _initFuture = null;
    _isInitialized = false;
  }

  Future<void> _awaitInitialization() async {
    final pending = _initFuture;
    if (pending == null) return;
    try {
      await pending;
    } catch (_) {
      // Already reported through the error listener and to the initialize()
      // caller; the platform call below decides how to respond.
    }
  }

  Future<dynamic> _handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'onLink':
        final args = call.arguments;
        if (args is Map) {
          _deliver(LinkLabData.fromMap(args));
        } else {
          _log('onLink without a map payload ignored');
        }
        return null;
      case 'onError':
        final args = call.arguments;
        final message = args is Map ? args['message']?.toString() : null;
        final details = args is Map
            ? (args['stackTrace'] ?? args['code'])?.toString()
            : null;
        _log('native error: $message');
        _errorListener?.call(message ?? 'Unknown error', details);
        return null;
      default:
        throw MissingPluginException('${call.method} is not implemented');
    }
  }

  void _deliver(LinkLabData data) {
    _log('link delivered: ${data.resolutionStatus.name}/${data.matchType.name}');
    final controller = _streamController;
    if (controller.hasListener) {
      controller.add(data);
    } else {
      _buffer.add(data);
    }
    final listener = _linkListener;
    if (listener != null) {
      try {
        listener(data);
      } catch (error, stackTrace) {
        _log('link listener threw: $error');
        _errorListener?.call(
          'Link listener threw: $error',
          stackTrace.toString(),
        );
      }
    }
  }

  void _flushBuffer() {
    if (_buffer.isEmpty) return;
    final controller = _streamController;
    final pending = List<LinkLabData>.of(_buffer);
    _buffer.clear();
    for (final data in pending) {
      controller.add(data);
    }
  }

  void _log(String message) {
    if (_debugLogging) {
      developer.log(message, name: 'LinkLab');
    }
  }
}
