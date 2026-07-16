import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

class InAppBrowserPage extends StatefulWidget {
  final String url;
  final String title;

  const InAppBrowserPage({super.key, required this.url, required this.title});

  @override
  State<InAppBrowserPage> createState() => _InAppBrowserPageState();
}

class _InAppBrowserPageState extends State<InAppBrowserPage> {
  late final WebViewController _controller;
  int  _loadingProgress = 0;
  bool _canGoBack       = false;
  bool _hasError        = false;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onProgress: (p) => setState(() => _loadingProgress = p),
        onPageFinished: (_) async {
          final canGoBack = await _controller.canGoBack();
          setState(() { _canGoBack = canGoBack; _hasError = false; });
        },
        onWebResourceError: (error) {
          if (error.isForMainFrame ?? true) {
            setState(() => _hasError = true);
          }
        },
      ))
      ..loadRequest(Uri.parse(widget.url));
  }

  Future<void> _openExternal() async {
    final uri = Uri.parse(widget.url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const accent = Color(0xFFFF6B35);

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        backgroundColor: theme.colorScheme.surface,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          widget.title,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          if (_canGoBack && !_hasError)
            IconButton(
              icon: const Icon(Icons.arrow_back_ios, size: 18),
              onPressed: () => _controller.goBack(),
            ),
          if (!_hasError)
            IconButton(
              icon: const Icon(Icons.refresh, size: 20),
              onPressed: () {
                setState(() => _hasError = false);
                _controller.reload();
              },
            ),
        ],
        bottom: !_hasError && _loadingProgress < 100
            ? PreferredSize(
                preferredSize: const Size.fromHeight(2),
                child: LinearProgressIndicator(
                  value: _loadingProgress / 100,
                  backgroundColor: Colors.transparent,
                  color: accent,
                ),
              )
            : null,
      ),
      body: _hasError
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.wifi_off_rounded, size: 56, color: Colors.white38),
                    const SizedBox(height: 16),
                    const Text(
                      'Impossible de charger la page',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Vérifie ta connexion ou ouvrez dans le navigateur.',
                      style: TextStyle(fontSize: 13, color: Colors.white54),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 28),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: accent,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        icon: const Icon(Icons.open_in_browser),
                        label: const Text('Ouvrir dans le navigateur',
                            style: TextStyle(fontWeight: FontWeight.w600)),
                        onPressed: _openExternal,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: () {
                        setState(() => _hasError = false);
                        _controller.reload();
                      },
                      child: const Text('Réessayer',
                          style: TextStyle(color: Colors.white54)),
                    ),
                  ],
                ),
              ),
            )
          : WebViewWidget(controller: _controller),
    );
  }
}
