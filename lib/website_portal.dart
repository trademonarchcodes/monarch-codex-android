import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

const _portalGold = Color(0xFFF3CF3C);
const _portalInk = Color(0xFF09090B);
const _portalSite = 'https://monarchcodex.online';

/// In-app gateway to the complete responsive Monarch Codex website.
class WebsitePortalPage extends StatefulWidget {
  const WebsitePortalPage({super.key, required this.dark});

  final bool dark;

  @override
  State<WebsitePortalPage> createState() => _WebsitePortalPageState();
}

class _WebsitePortalPageState extends State<WebsitePortalPage> {
  late final WebViewController _controller;
  int _progress = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(widget.dark ? _portalInk : Colors.white)
      ..setNavigationDelegate(NavigationDelegate(
        onProgress: (progress) {
          if (mounted) setState(() => _progress = progress);
        },
        onPageStarted: (_) {
          if (mounted) setState(() {
            _error = null;
            _progress = 0;
          });
        },
        onPageFinished: (_) {
          if (mounted) setState(() => _progress = 100);
        },
        onWebResourceError: (error) {
          if (error.isForMainFrame == true && mounted) {
            setState(() => _error = 'This page could not be loaded. Check your connection and try again.');
          }
        },
      ))
      ..loadRequest(Uri.parse(_portalSite));
  }

  Future<bool> _handleBack() async {
    if (await _controller.canGoBack()) {
      await _controller.goBack();
      return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final foreground = widget.dark ? Colors.white : _portalInk;
    return WillPopScope(
      onWillPop: _handleBack,
      child: Scaffold(
        backgroundColor: widget.dark ? _portalInk : const Color(0xFFF8F7F2),
        appBar: AppBar(
          title: const Text('ALL WEBSITE SECTIONS', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, letterSpacing: .5)),
          actions: [
            IconButton(
              tooltip: 'Go back',
              onPressed: () async {
                if (await _controller.canGoBack()) {
                  await _controller.goBack();
                } else {
                  await _controller.loadRequest(Uri.parse(_portalSite));
                }
              },
              icon: const Icon(Icons.arrow_back_rounded, color: _portalGold),
            ),
            IconButton(
              tooltip: 'Refresh',
              onPressed: () => _controller.reload(),
              icon: const Icon(Icons.refresh_rounded, color: _portalGold),
            ),
          ],
        ),
        body: Column(
          children: [
            if (_progress < 100)
              LinearProgressIndicator(
                value: _progress == 0 ? null : _progress / 100,
                minHeight: 2,
                color: _portalGold,
                backgroundColor: widget.dark ? const Color(0xFF292929) : const Color(0xFFE6E1D2),
              ),
            if (_error != null)
              Material(
                color: widget.dark ? const Color(0xFF201B0C) : const Color(0xFFFFF5D2),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(children: [
                    Expanded(child: Text(_error!, style: TextStyle(color: foreground))),
                    TextButton(onPressed: () {
                      setState(() => _error = null);
                      _controller.reload();
                    }, child: const Text('RETRY', style: TextStyle(color: _portalGold, fontWeight: FontWeight.w900))),
                  ]),
                ),
              ),
            Expanded(child: WebViewWidget(controller: _controller)),
          ],
        ),
      ),
    );
  }
}
