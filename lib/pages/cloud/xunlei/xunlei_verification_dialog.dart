import 'dart:async';
import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:kanyingyin/bean/widget/glass_surface.dart';
import 'package:kanyingyin/services/cloud/xunlei/xunlei_models.dart';
import 'package:kanyingyin/services/cloud/xunlei/xunlei_verification_bridge.dart';
import 'package:kanyingyin/services/cloud/xunlei/xunlei_verification_profile.dart';

enum XunleiVerificationDialogOutcome { verified, cancelled, failed }

class XunleiVerificationDialogResult {
  const XunleiVerificationDialogResult._(
    this.outcome, {
    this.creditKey,
    this.errorMessage,
  });

  const XunleiVerificationDialogResult.verified(String creditKey)
      : this._(
          XunleiVerificationDialogOutcome.verified,
          creditKey: creditKey,
        );

  const XunleiVerificationDialogResult.cancelled()
      : this._(XunleiVerificationDialogOutcome.cancelled);

  const XunleiVerificationDialogResult.failed(String message)
      : this._(
          XunleiVerificationDialogOutcome.failed,
          errorMessage: message,
        );

  final XunleiVerificationDialogOutcome outcome;
  final String? creditKey;
  final String? errorMessage;

  @override
  String toString() =>
      'XunleiVerificationDialogResult(${outcome.name}, <redacted>)';
}

typedef XunleiVerificationDialogLauncher
    = Future<XunleiVerificationDialogResult> Function(
  BuildContext context,
  XunleiVerificationChallenge challenge,
);

class XunleiVerificationSurfaceCallbacks {
  const XunleiVerificationSurfaceCallbacks({
    required this.onLoading,
    required this.onReady,
    required this.onLoadFailed,
    required this.onSecurityViolation,
    required this.onResult,
    required this.onControllerCreated,
  });

  final VoidCallback onLoading;
  final VoidCallback onReady;
  final VoidCallback onLoadFailed;
  final VoidCallback onSecurityViolation;
  final ValueChanged<XunleiVerificationResult> onResult;
  final ValueChanged<InAppWebViewController> onControllerCreated;
}

typedef XunleiVerificationSurfaceBuilder = Widget Function(
  XunleiVerificationSurfaceCallbacks callbacks,
  int attempt,
);

Future<XunleiVerificationDialogResult> showXunleiVerificationDialog(
  BuildContext context,
  XunleiVerificationChallenge challenge, {
  XunleiVerificationProfileFactory? profileFactory,
}) async {
  final loggingGuard = _XunleiWebViewDebugLoggingGuard.acquire();
  XunleiVerificationProfile? profile;
  try {
    profile =
        await (profileFactory ?? XunleiVerificationProfileFactory()).create();
    if (!context.mounted) {
      return const XunleiVerificationDialogResult.cancelled();
    }
    return await showDialog<XunleiVerificationDialogResult>(
          context: context,
          barrierDismissible: false,
          builder: (_) => XunleiVerificationDialog(
            challenge: challenge,
            profile: profile,
          ),
        ) ??
        const XunleiVerificationDialogResult.cancelled();
  } on XunleiVerificationProfileException catch (error) {
    final message = switch (error.type) {
      XunleiVerificationProfileError.runtimeUnavailable =>
        '迅雷验证组件不可用，请安装或修复 Microsoft Edge WebView2 Runtime',
      XunleiVerificationProfileError.runtimeOutdated =>
        '迅雷验证组件版本过低，请更新 Microsoft Edge WebView2 Runtime',
      XunleiVerificationProfileError.initializationFailed => '迅雷验证组件初始化失败，请重试',
    };
    if (context.mounted) {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          title: const Text('迅雷设备验证'),
          content: Text(message),
          actions: <Widget>[
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('关闭'),
            ),
          ],
        ),
      );
    }
    return XunleiVerificationDialogResult.failed(message);
  } finally {
    try {
      await profile?.dispose();
    } finally {
      loggingGuard.release();
    }
  }
}

class _XunleiWebViewDebugLoggingGuard {
  _XunleiWebViewDebugLoggingGuard._();

  static DebugLoggingSettings? _previousSettings;
  static int _activeSessions = 0;

  bool _released = false;

  static _XunleiWebViewDebugLoggingGuard acquire() {
    if (_activeSessions == 0) {
      _previousSettings = PlatformInAppWebViewController.debugLoggingSettings;
      PlatformInAppWebViewController.debugLoggingSettings =
          DebugLoggingSettings(enabled: false);
    }
    _activeSessions++;
    return _XunleiWebViewDebugLoggingGuard._();
  }

  void release() {
    if (_released) return;
    _released = true;
    _activeSessions--;
    if (_activeSessions != 0) return;
    final previousSettings = _previousSettings;
    _previousSettings = null;
    if (previousSettings != null) {
      PlatformInAppWebViewController.debugLoggingSettings = previousSettings;
    }
  }
}

class XunleiVerificationDialog extends StatefulWidget {
  const XunleiVerificationDialog({
    super.key,
    required this.challenge,
    required this.profile,
    DateTime Function()? now,
  })  : _surfaceBuilder = null,
        _now = now;

  const XunleiVerificationDialog.test({
    super.key,
    required this.challenge,
    required XunleiVerificationSurfaceBuilder surfaceBuilder,
    DateTime Function()? now,
  })  : profile = null,
        _surfaceBuilder = surfaceBuilder,
        _now = now;

  final XunleiVerificationChallenge challenge;
  final XunleiVerificationProfile? profile;
  final XunleiVerificationSurfaceBuilder? _surfaceBuilder;
  final DateTime Function()? _now;

  @override
  State<XunleiVerificationDialog> createState() =>
      _XunleiVerificationDialogState();
}

enum _XunleiVerificationViewState { loading, ready, error }

class _XunleiVerificationDialogState extends State<XunleiVerificationDialog> {
  static const Duration _verificationLifetime = Duration(minutes: 10);

  _XunleiVerificationViewState _viewState =
      _XunleiVerificationViewState.loading;
  InAppWebViewController? _webViewController;
  Timer? _expirationTimer;
  String? _errorMessage;
  String? _failureMessage;
  bool _canRetry = false;
  bool _finishing = false;
  int _attempt = 1;

  @override
  void initState() {
    super.initState();
    final currentTime = widget._now?.call() ?? DateTime.now();
    final elapsed = currentTime.toUtc().difference(
          widget.challenge.startedAt.toUtc(),
        );
    final remaining = _verificationLifetime - elapsed;
    if (remaining <= Duration.zero) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_finish(
          const XunleiVerificationDialogResult.failed(
            '迅雷验证已过期，请重新登录',
          ),
        ));
      });
    } else {
      _expirationTimer = Timer(remaining, () {
        unawaited(_finish(
          const XunleiVerificationDialogResult.failed(
            '迅雷验证已过期，请重新登录',
          ),
        ));
      });
    }
  }

  void _setLoading() {
    if (!mounted ||
        _finishing ||
        _viewState == _XunleiVerificationViewState.error) {
      return;
    }
    setState(() => _viewState = _XunleiVerificationViewState.loading);
  }

  void _setReady() {
    if (!mounted ||
        _finishing ||
        _viewState == _XunleiVerificationViewState.error) {
      return;
    }
    setState(() => _viewState = _XunleiVerificationViewState.ready);
  }

  void _handleResult(XunleiVerificationResult result) {
    switch (result.outcome) {
      case XunleiVerificationOutcome.success:
        unawaited(_finish(
          XunleiVerificationDialogResult.verified(result.creditKey!),
        ));
      case XunleiVerificationOutcome.cancelled:
        unawaited(_finish(
          const XunleiVerificationDialogResult.cancelled(),
        ));
      case XunleiVerificationOutcome.failed:
        unawaited(_showError(
          '迅雷设备验证失败，请重新登录',
          canRetry: false,
        ));
      case XunleiVerificationOutcome.incompatible:
        unawaited(_showError(
          '迅雷设备验证结果不兼容，请重新登录',
          canRetry: false,
        ));
    }
  }

  Future<void> _showError(
    String message, {
    required bool canRetry,
  }) async {
    if (_finishing) return;
    await _detachController();
    if (!mounted || _finishing) return;
    setState(() {
      _viewState = _XunleiVerificationViewState.error;
      _errorMessage = message;
      _canRetry = canRetry;
      _failureMessage = canRetry ? null : message;
    });
  }

  Future<void> _retry() async {
    if (_finishing) return;
    await _detachController();
    if (!mounted || _finishing) return;
    setState(() {
      _attempt++;
      _viewState = _XunleiVerificationViewState.loading;
      _errorMessage = null;
      _failureMessage = null;
      _canRetry = false;
    });
  }

  Future<void> _detachController() async {
    final controller = _webViewController;
    _webViewController = null;
    if (controller == null) return;
    try {
      await controller.stopLoading();
    } on Object {
      // 关闭流程继续执行，异常正文不得写入日志。
    }
    try {
      controller.removeJavaScriptHandler(
        handlerName: xunleiVerificationHandlerName,
      );
    } on Object {
      // Handler 清理失败不保留挑战，也不阻止关闭。
    }
  }

  Future<void> _finish(XunleiVerificationDialogResult result) async {
    if (_finishing) return;
    _finishing = true;
    _expirationTimer?.cancel();
    await _detachController();
    if (mounted) Navigator.of(context).pop(result);
  }

  XunleiVerificationSurfaceCallbacks _callbacks() =>
      XunleiVerificationSurfaceCallbacks(
        onLoading: _setLoading,
        onReady: _setReady,
        onLoadFailed: () => unawaited(_showError(
          '迅雷验证页面加载失败',
          canRetry: true,
        )),
        onSecurityViolation: () => unawaited(_showError(
          '已阻止不安全的迅雷验证页面',
          canRetry: false,
        )),
        onResult: _handleResult,
        onControllerCreated: (controller) {
          _webViewController = controller;
        },
      );

  Widget _buildSurface() {
    final callbacks = _callbacks();
    final testBuilder = widget._surfaceBuilder;
    if (testBuilder != null) return testBuilder(callbacks, _attempt);
    return _XunleiVerificationWebView(
      key: ValueKey<int>(_attempt),
      challenge: widget.challenge,
      profile: widget.profile!,
      callbacks: callbacks,
    );
  }

  Widget _buildBody() {
    if (_viewState == _XunleiVerificationViewState.error) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(Icons.error_outline_rounded, size: 48),
              const SizedBox(height: 16),
              Text(
                _errorMessage ?? '迅雷设备验证失败，请重新登录',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        _buildSurface(),
        if (_viewState == _XunleiVerificationViewState.loading)
          const ColoredBox(
            color: Color(0xCC101114),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('正在加载迅雷验证页面'),
                ],
              ),
            ),
          ),
      ],
    );
  }

  List<Widget> _buildActions() {
    if (_viewState != _XunleiVerificationViewState.error) {
      return <Widget>[
        TextButton(
          onPressed: _finishing
              ? null
              : () => unawaited(_finish(
                    const XunleiVerificationDialogResult.cancelled(),
                  )),
          child: const Text('取消'),
        ),
      ];
    }
    if (_canRetry) {
      return <Widget>[
        TextButton(
          onPressed: _finishing
              ? null
              : () => unawaited(_finish(
                    const XunleiVerificationDialogResult.cancelled(),
                  )),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _finishing ? null : () => unawaited(_retry()),
          child: const Text('重试'),
        ),
      ];
    }
    return <Widget>[
      FilledButton(
        onPressed: _finishing
            ? null
            : () => unawaited(_finish(
                  XunleiVerificationDialogResult.failed(
                    _failureMessage ?? '迅雷设备验证失败，请重新登录',
                  ),
                )),
        child: const Text('关闭'),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return GlassDialog(
      insetPadding: const EdgeInsets.all(24),
      child: SizedBox(
        width: 760,
        height: 560,
        child: Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 18, 12, 12),
              child: Row(
                children: <Widget>[
                  const Expanded(
                    child: Text(
                      '迅雷设备验证',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: '取消验证',
                    onPressed: _finishing
                        ? null
                        : () => unawaited(_finish(
                              const XunleiVerificationDialogResult.cancelled(),
                            )),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(child: _buildBody()),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 12,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: _buildActions()
                    .expand((widget) => <Widget>[
                          const SizedBox(width: 12),
                          widget,
                        ])
                    .toList(growable: false),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _expirationTimer?.cancel();
    super.dispose();
  }
}

class _XunleiVerificationWebView extends StatelessWidget {
  const _XunleiVerificationWebView({
    super.key,
    required this.challenge,
    required this.profile,
    required this.callbacks,
  });

  final XunleiVerificationChallenge challenge;
  final XunleiVerificationProfile profile;
  final XunleiVerificationSurfaceCallbacks callbacks;

  @override
  Widget build(BuildContext context) {
    final bridge = XunleiVerificationBridge(challenge);
    return InAppWebView(
      webViewEnvironment: profile.environment,
      initialUrlRequest: URLRequest(
        url: WebUri(xunleiVerificationEntryUri),
      ),
      initialUserScripts: UnmodifiableListView<UserScript>(<UserScript>[
        UserScript(
          groupName: 'xunlei-verification-bridge',
          source: bridge.documentStartScript,
          injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
          forMainFrameOnly: false,
        ),
      ]),
      initialSettings: InAppWebViewSettings(
        javaScriptEnabled: true,
        javaScriptCanOpenWindowsAutomatically: false,
        useShouldOverrideUrlLoading: true,
        useOnDownloadStart: true,
        incognito: true,
        cacheEnabled: false,
        databaseEnabled: false,
        geolocationEnabled: false,
        disableContextMenu: true,
        supportZoom: false,
        supportMultipleWindows: false,
        isInspectable: false,
        allowFileAccessFromFileURLs: false,
        allowUniversalAccessFromFileURLs: false,
      ),
      onWebViewCreated: (controller) {
        callbacks.onControllerCreated(controller);
        controller.addJavaScriptHandler(
          handlerName: xunleiVerificationHandlerName,
          callback: (List<dynamic> arguments) {
            final raw = arguments.length == 1 ? arguments.first : null;
            callbacks.onResult(bridge.parseOperationResult(raw));
            return null;
          },
        );
      },
      shouldOverrideUrlLoading: (controller, action) async {
        final value = action.request.url?.toString();
        final uri = value == null ? null : Uri.tryParse(value);
        if (uri == null ||
            !XunleiVerificationNavigationPolicy.allowsNavigation(
              uri,
              isForMainFrame: action.isForMainFrame,
              method: action.request.method,
            )) {
          callbacks.onSecurityViolation();
          return NavigationActionPolicy.CANCEL;
        }
        return NavigationActionPolicy.ALLOW;
      },
      onCreateWindow: (controller, action) async => false,
      onDownloadStarting: (controller, request) {
        callbacks.onSecurityViolation();
        return DownloadStartResponse(
          handled: true,
          action: DownloadStartResponseAction.CANCEL,
        );
      },
      onPermissionRequest: (controller, request) async => PermissionResponse(
        resources: request.resources,
        action: PermissionResponseAction.DENY,
      ),
      onGeolocationPermissionsShowPrompt: (controller, origin) async =>
          GeolocationPermissionShowPromptResponse(
        origin: origin,
        allow: false,
        retain: false,
      ),
      onLoadStart: (controller, url) => callbacks.onLoading(),
      onLoadStop: (controller, url) {
        final uri = url == null ? null : Uri.tryParse(url.toString());
        if (uri == null || !XunleiVerificationNavigationPolicy.allows(uri)) {
          callbacks.onSecurityViolation();
          return;
        }
        callbacks.onReady();
      },
      onReceivedError: (controller, request, error) {
        if (request.isForMainFrame == true) callbacks.onLoadFailed();
      },
      onReceivedHttpError: (controller, request, response) {
        if (request.isForMainFrame == true) callbacks.onLoadFailed();
      },
    );
  }
}
