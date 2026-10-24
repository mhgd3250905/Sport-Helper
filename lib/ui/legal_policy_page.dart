import 'dart:async';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'theme.dart';

enum LegalPolicy {
  privacy('隐私政策', '/privacy/'),
  terms('使用条款', '/terms/');

  const LegalPolicy(this.title, this.path);

  final String title;
  final String path;

  Uri get uri => Uri.https('smartfit-store.pages.dev', path);
}

/// Policy links stay on the public policy site; this is not a general browser.
bool permitsLegalPolicyNavigation(String url) {
  final uri = Uri.tryParse(url);
  return uri != null &&
      uri.scheme == 'https' &&
      uri.host == 'smartfit-store.pages.dev' &&
      uri.userInfo.isEmpty &&
      uri.port == 443;
}

class LegalPolicyPage extends StatefulWidget {
  const LegalPolicyPage({super.key, required this.policy});

  final LegalPolicy policy;

  @override
  State<LegalPolicyPage> createState() => _LegalPolicyPageState();
}

class _LegalPolicyPageState extends State<LegalPolicyPage> {
  WebViewController? _controller;
  bool _loading = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    unawaited(_open());
  }

  Future<void> _open() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final controller =
          _controller ??
          WebViewController.fromPlatformCreationParams(
            const PlatformWebViewControllerCreationParams(),
            onPermissionRequest: (request) => unawaited(request.deny()),
          );
      if (_controller == null) {
        await controller.setJavaScriptMode(JavaScriptMode.disabled);
        await controller.setNavigationDelegate(
          NavigationDelegate(
            onNavigationRequest: (request) =>
                permitsLegalPolicyNavigation(request.url)
                ? NavigationDecision.navigate
                : NavigationDecision.prevent,
            onPageStarted: (_) {
              if (mounted) {
                setState(() {
                  _loading = true;
                  _failed = false;
                });
              }
            },
            onPageFinished: (_) {
              if (mounted) setState(() => _loading = false);
            },
            onWebResourceError: (error) {
              if (mounted && error.isForMainFrame != false) {
                setState(() {
                  _failed = true;
                  _loading = false;
                });
              }
            },
          ),
        );
        if (!mounted) return;
        setState(() => _controller = controller);
      }
      if (!mounted) return;
      await controller.loadRequest(widget.policy.uri);
    } catch (_) {
      if (mounted) {
        setState(() {
          _failed = true;
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: SfTopBar(title: widget.policy.title),
    body: _failed
        ? Center(
            child: Padding(
              padding: const EdgeInsets.all(SfSpace.gutter),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('页面暂时无法加载，请检查网络后重试。', style: SfType.body),
                  const SizedBox(height: SfSpace.x3),
                  SelectableText(
                    widget.policy.uri.toString(),
                    textAlign: TextAlign.center,
                    style: SfType.caption,
                  ),
                  const SizedBox(height: SfSpace.x3),
                  SfTextAction(
                    label: '重新加载',
                    color: SfColors.accentText,
                    onPressed: () => unawaited(_open()),
                  ),
                ],
              ),
            ),
          )
        : Stack(
            children: [
              if (_controller case final controller?)
                WebViewWidget(controller: controller),
              if (_loading)
                const Align(
                  alignment: Alignment.topCenter,
                  child: LinearProgressIndicator(),
                ),
            ],
          ),
  );
}
