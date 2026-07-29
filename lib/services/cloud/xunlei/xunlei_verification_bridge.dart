import 'dart:convert';

import 'package:kanyingyin/services/cloud/xunlei/xunlei_models.dart';

const String xunleiVerificationEntryUri =
    'https://i.xunlei.com/xlcaptcha/android.html';
const String xunleiVerificationHandlerName = 'xunleiVerificationResult';

enum XunleiVerificationOutcome { success, cancelled, failed, incompatible }

class XunleiVerificationResult {
  const XunleiVerificationResult._(this.outcome, {this.creditKey});

  const XunleiVerificationResult.success(String creditKey)
      : this._(XunleiVerificationOutcome.success, creditKey: creditKey);

  const XunleiVerificationResult.cancelled()
      : this._(XunleiVerificationOutcome.cancelled);

  const XunleiVerificationResult.failed()
      : this._(XunleiVerificationOutcome.failed);

  const XunleiVerificationResult.incompatible()
      : this._(XunleiVerificationOutcome.incompatible);

  final XunleiVerificationOutcome outcome;
  final String? creditKey;

  @override
  String toString() => 'XunleiVerificationResult(${outcome.name}, <redacted>)';
}

abstract final class XunleiVerificationNavigationPolicy {
  static const String _verificationApiHost = 'xluser-ssl.xunlei.com';
  static const String _verificationApiPath = '/xluser.core.login/v3/checksms';

  static bool allowsNavigation(
    Uri uri, {
    required bool? isForMainFrame,
    required String? method,
  }) {
    if (allows(uri)) return true;
    return isForMainFrame == false &&
        method?.toUpperCase() == 'POST' &&
        uri.scheme.toLowerCase() == 'https' &&
        uri.host.toLowerCase() == _verificationApiHost &&
        uri.userInfo.isEmpty &&
        (!uri.hasPort || uri.port == 443) &&
        uri.path == _verificationApiPath &&
        !uri.hasQuery &&
        !uri.hasFragment;
  }

  static bool allows(Uri uri) =>
      uri.scheme.toLowerCase() == 'https' &&
      uri.host.toLowerCase() == 'i.xunlei.com' &&
      uri.userInfo.isEmpty &&
      (!uri.hasPort || uri.port == 443);
}

class XunleiVerificationBridge {
  XunleiVerificationBridge(this._challenge);

  static const int _maxMessageLength = 16 * 1024;

  final XunleiVerificationChallenge _challenge;

  String get documentStartScript {
    final payload = jsonEncode(<String, String>{
      'creditkey': _challenge.creditKey,
      'reviewurl': _challenge.reviewUri.toString(),
      'deviceid': _challenge.deviceId,
      'devicesign': _challenge.deviceSign,
    });
    return '''
(() => {
  if (location.protocol !== 'https:' ||
      location.hostname !== 'i.xunlei.com' ||
      (location.port !== '' && location.port !== '443')) {
    return;
  }
  const challengeData = $payload;
  const bridge = Object.freeze({
    sendMessage: function(name, data, callbackName) {
      if (name === 'nativeGetUserDeviceInfo') {
        if (callbackName !== 'reviewCb' || typeof window.reviewCb !== 'function') {
          return false;
        }
        window.reviewCb(challengeData);
        return true;
      }
      if (name === 'nativeRecvOperationResult') {
        if (!window.flutter_inappwebview ||
            typeof window.flutter_inappwebview.callHandler !== 'function') {
          return false;
        }
        window.flutter_inappwebview.callHandler('xunleiVerificationResult', data);
        return true;
      }
      return false;
    }
  });
  Object.defineProperty(window, 'XLJSWebViewBridge', {
    value: bridge,
    configurable: false,
    enumerable: false,
    writable: false
  });
})();
''';
  }

  XunleiVerificationResult parseOperationResult(Object? raw) {
    Object? decoded = raw;
    if (raw is String) {
      if (raw.length > _maxMessageLength) {
        return const XunleiVerificationResult.incompatible();
      }
      try {
        decoded = jsonDecode(raw);
      } on Object {
        return const XunleiVerificationResult.incompatible();
      }
    } else if (raw is Map) {
      try {
        if (jsonEncode(raw).length > _maxMessageLength) {
          return const XunleiVerificationResult.incompatible();
        }
      } on Object {
        return const XunleiVerificationResult.incompatible();
      }
    }

    final message = _stringMap(decoded);
    if (message == null) {
      return const XunleiVerificationResult.incompatible();
    }
    final errorCode = _string(message['roErrorCode']);
    if (errorCode == '30001') {
      return const XunleiVerificationResult.cancelled();
    }
    if (errorCode != '0') {
      return const XunleiVerificationResult.failed();
    }
    final data = _stringMap(message['roData']);
    final creditKey = data == null ? null : _string(data['creditkey']);
    if (creditKey == null || creditKey == _challenge.creditKey) {
      return const XunleiVerificationResult.incompatible();
    }
    return XunleiVerificationResult.success(creditKey);
  }

  Map<String, Object?>? _stringMap(Object? value) {
    if (value is! Map) return null;
    final result = <String, Object?>{};
    for (final entry in value.entries) {
      final key = entry.key;
      if (key is! String) return null;
      result[key] = entry.value;
    }
    return result;
  }

  String? _string(Object? value) {
    if (value is! String) return null;
    final normalized = value.trim();
    return normalized.isEmpty ? null : normalized;
  }

  @override
  String toString() => 'XunleiVerificationBridge(<redacted>)';
}
