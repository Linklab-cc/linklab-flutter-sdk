import 'dart:async';

import 'package:flutter/material.dart';
import 'package:linklab_flutter_sdk/linklab_flutter_sdk.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize once, as early as possible. Links that arrive before anyone
  // listens to `onLink` are buffered and replayed to the first listener.
  await LinkLab().initialize(
    config: const LinkLabConfig(
      customDomains: <String>[], // e.g. ['go.example.com']
      debugLoggingEnabled: true,
      pasteboardMode: LinkLabPasteboardMode.manual,
    ),
  );

  runApp(const ExampleApp());
}

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      title: 'Linklab example',
      home: LinkPage(),
    );
  }
}

class LinkPage extends StatefulWidget {
  const LinkPage({super.key});

  @override
  State<LinkPage> createState() => _LinkPageState();
}

class _LinkPageState extends State<LinkPage> {
  final LinkLab _linkLab = LinkLab();
  final TextEditingController _controller =
      TextEditingController(text: 'https://linklab.cc/');
  StreamSubscription<LinkLabData>? _subscription;

  LinkLabData? _initialLink;
  final List<LinkLabData> _streamLinks = <LinkLabData>[];
  String _status = 'Waiting for links...';

  @override
  void initState() {
    super.initState();
    _subscription = _linkLab.onLink.listen((link) {
      setState(() => _streamLinks.insert(0, link));
    });
    _linkLab.setErrorListener((message, details) {
      setState(() => _status = 'Error: $message');
    });
    _loadInitialLink();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _loadInitialLink() async {
    final link = await _linkLab.getInitialLink();
    if (!mounted) return;
    setState(() {
      _initialLink = link;
      _status = link == null ? 'No initial link' : 'Initial link received';
    });
  }

  Future<void> _resolve() async {
    final input = _controller.text.trim();
    if (input.isEmpty) return;
    setState(() => _status = 'Resolving...');
    try {
      if (!await _linkLab.isLinkLabLink(input)) {
        setState(() => _status = 'Not a Linklab link: $input');
        return;
      }
      final link = await _linkLab.resolve(input);
      setState(() {
        _status = link == null
            ? 'Not a Linklab link'
            : 'Resolved: ${link.resolutionStatus.name} -> ${link.fullLink}';
      });
    } catch (error) {
      setState(() => _status = 'resolve failed: $error');
    }
  }

  Future<void> _checkPasteboard() async {
    setState(() => _status = 'Checking pasteboard...');
    try {
      final link = await _linkLab.checkPasteboard();
      setState(() {
        _status = link == null
            ? 'No Linklab link on the pasteboard'
            : 'Pasteboard link: ${link.fullLink} (${link.matchType.name})';
      });
    } catch (error) {
      setState(() => _status = 'checkPasteboard failed: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Linklab example')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _controller,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
              labelText: 'Linklab short link',
              hintText: 'https://linklab.cc/abcd1234',
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: _resolve,
                  child: const Text('Resolve'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton(
                  onPressed: _checkPasteboard,
                  child: const Text('Check pasteboard'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Text('Status', style: Theme.of(context).textTheme.titleSmall),
          Text(_status),
          const SizedBox(height: 24),
          Text('Initial link (getInitialLink)',
              style: Theme.of(context).textTheme.titleSmall),
          _LinkTile(link: _initialLink),
          const SizedBox(height: 24),
          Text('Stream (onLink), newest first',
              style: Theme.of(context).textTheme.titleSmall),
          if (_streamLinks.isEmpty) const Text('-'),
          for (final link in _streamLinks) _LinkTile(link: link),
        ],
      ),
    );
  }
}

class _LinkTile extends StatelessWidget {
  const _LinkTile({required this.link});

  final LinkLabData? link;

  @override
  Widget build(BuildContext context) {
    final link = this.link;
    if (link == null) return const Text('-');
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(link.fullLink,
                style: const TextStyle(fontWeight: FontWeight.bold)),
            Text('id: ${link.id ?? '-'}  short: ${link.shortLink ?? '-'}'),
            Text('status: ${link.resolutionStatus.name}  '
                'match: ${link.matchType.name}  '
                'deferred: ${link.isDeferred}  domain: ${link.domainType.name}'),
            if (link.errorMessage != null) Text('error: ${link.errorMessage}'),
            if (link.parameters.isNotEmpty) Text('params: ${link.parameters}'),
          ],
        ),
      ),
    );
  }
}
