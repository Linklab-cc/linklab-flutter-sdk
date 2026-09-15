/// Flutter plugin for the Linklab deep linking service.
///
/// ```dart
/// await LinkLab().initialize(config: const LinkLabConfig(customDomains: ['go.example.com']));
/// LinkLab().onLink.listen((link) => print(link.fullLink));
/// ```
library;

export 'src/config.dart';
export 'src/link_data.dart';
export 'src/linklab.dart';
