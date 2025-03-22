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
  final TextEditingController _linkController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _setupDynamicLinks();
  }

  @override
  void dispose() {
    _linkController.dispose();
    super.dispose();
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

    // Setup error listener
    _linkLab.setErrorListener((message, stackTrace) {
      setState(() {
        _linkData = 'Error: $message';
      });
    });
  }

  Future<void> _processLink() async {
    final link = _linkController.text.trim();
    if (link.isEmpty) {
      setState(() {
        _linkData = 'Please enter a link';
      });
      return;
    }

    final isValid = await _linkLab.isLinkLabLink(link);
    if (!isValid) {
      setState(() {
        _linkData = 'Not a valid LinkLab link';
      });
      return;
    }

    setState(() {
      _linkData = 'Processing link...';
    });
    
    await _linkLab.getDynamicLink(link);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          title: const Text('LinkLab Demo'),
        ),
        body: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TextField(
                controller: _linkController,
                decoration: const InputDecoration(
                  labelText: 'Enter LinkLab short link',
                  hintText: 'https://linklab.cc/abcd1234',
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _processLink,
                child: const Text('Process Link'),
              ),
              const SizedBox(height: 32),
              Text(
                'Link Data:',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              Text(_linkData),
            ],
          ),
        ),
      ),
    );
  }
}