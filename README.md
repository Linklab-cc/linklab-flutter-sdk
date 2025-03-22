# LinkLab Flutter SDK

A Flutter plugin for the LinkLab deep linking service. This plugin allows Flutter applications to handle dynamic links provided by LinkLab.

## Features

- Process deep links automatically when the app is opened via a LinkLab link
- Retrieve dynamic link details
- Validate if a link is a LinkLab link
- Support for both Android and iOS (coming soon)

## Getting Started

### Installation

Add the package to your `pubspec.yaml` file:

```yaml
dependencies:
  linklab_flutter_sdk: ^0.1.0
```

### Android Setup

1. Ensure your `android/app/src/main/AndroidManifest.xml` file has the proper intent filter for your deep links:

```xml
<activity
    android:name=".MainActivity"
    ...>
    <intent-filter>
        <action android:name="android.intent.action.VIEW" />
        <category android:name="android.intent.category.DEFAULT" />
        <category android:name="android.intent.category.BROWSABLE" />
        <data
            android:scheme="https"
            android:host="linklab.cc" />
    </intent-filter>
</activity>
```

### iOS Setup (Coming Soon)

iOS support will be added in a future update.

## Usage

### Initialization

Initialize the LinkLab SDK in your app:

```dart
import 'package:linklab_flutter_sdk/linklab_flutter_sdk.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Get the LinkLab singleton instance
  final linkLab = LinkLab();
  
  // Initialize the plugin
  await linkLab.initialize();
  
  // Configure with your API key
  await linkLab.configure('your_api_key_here');
  
  runApp(MyApp());
}
```

### Handling Dynamic Links

There are two ways to handle dynamic links:

1. Using callbacks:

```dart
linkLab.setLinkListener((linkData) {
  print('Received link: ${linkData.fullLink}');
  // Navigate to the appropriate page based on the link
});

linkLab.setErrorListener((message, stackTrace) {
  print('Error processing link: $message');
});
```

2. Using the Stream API:

```dart
linkLab.onLink.listen((linkData) {
  print('Received link: ${linkData.fullLink}');
  // Navigate to the appropriate page based on the link
});
```

### Getting the Initial Link

If your app was opened from a dynamic link, you can retrieve it:

```dart
Future<void> checkInitialLink() async {
  final linkData = await linkLab.getInitialLink();
  if (linkData != null) {
    print('App opened from link: ${linkData.fullLink}');
    // Navigate to the appropriate page based on the link
  }
}
```

### Processing Links Manually

You can also manually process a LinkLab short link:

```dart
await linkLab.getDynamicLink('https://linklab.cc/abcd1234');
```

### Validating Links

Check if a link is a valid LinkLab link:

```dart
bool isValid = await linkLab.isLinkLabLink('https://linklab.cc/abcd1234');
```

## Example

```dart
import 'package:flutter/material.dart';
import 'package:linklab_flutter_sdk/linklab_flutter_sdk.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  final linkLab = LinkLab();
  await linkLab.initialize();
  await linkLab.configure('your_api_key_here');
  
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  String _linkData = 'No link received yet';
  final LinkLab _linkLab = LinkLab();

  @override
  void initState() {
    super.initState();
    _setupDynamicLinks();
  }

  Future<void> _setupDynamicLinks() async {
    // Check for initial link
    final initialLink = await _linkLab.getInitialLink();
    if (initialLink != null) {
      setState(() {
        _linkData = 'Initial link: ${initialLink.fullLink}';
      });
    }

    // Listen for future links
    _linkLab.onLink.listen((linkData) {
      setState(() {
        _linkData = 'Link received: ${linkData.fullLink}';
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          title: const Text('LinkLab Demo'),
        ),
        body: Center(
          child: Text(_linkData),
        ),
      ),
    );
  }
}
```