import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:kanyingyin/features/tv_pairing/domain/tv_pairing_models.dart';
import 'package:synchronized/synchronized.dart';

enum TvPairingSubmissionResult { accepted, rejected }

typedef TvPairingPayloadHandler = Future<TvPairingSubmissionResult> Function(
  TvPairingPayload payload,
);
typedef TvPairingCancelledHandler = Future<void> Function();
typedef TvPairingHostResolver = Future<String> Function();

class TvPairingServerEndpoint {
  const TvPairingServerEndpoint({
    required this.host,
    required this.port,
    required this.pairingToken,
  });

  final String host;
  final int port;
  final String pairingToken;

  Uri get pairUri => Uri(
        scheme: 'http',
        host: host,
        port: port,
        path: '/pair',
        queryParameters: <String, String>{
          'token': pairingToken,
          'v': TvPairingPayload.currentProtocolVersion.toString(),
        },
      );

  Uri get pairApiUri => Uri(
        scheme: 'http',
        host: host,
        port: port,
        path: '/api/pair',
      );

  Uri get cancelApiUri => Uri(
        scheme: 'http',
        host: host,
        port: port,
        path: '/api/cancel',
      );

  @override
  String toString() => 'TvPairingServerEndpoint(host: $host, port: $port)';
}

abstract interface class TvPairingServer {
  bool get isRunning;

  Future<TvPairingServerEndpoint> start({
    required TvPairingSession session,
    required TvPairingPayloadHandler onPayload,
    TvPairingCancelledHandler? onCancelled,
  });

  Future<void> stop();
}

class TvPairingHttpServer implements TvPairingServer {
  TvPairingHttpServer({
    InternetAddress? bindAddress,
    TvPairingHostResolver? advertisedHostResolver,
    DateTime Function()? now,
  })  : _bindAddress = bindAddress ?? InternetAddress.anyIPv4,
        _advertisedHostResolver =
            advertisedHostResolver ?? _resolveLanIpv4Address,
        _now = now ?? DateTime.now;

  final InternetAddress _bindAddress;
  final TvPairingHostResolver _advertisedHostResolver;
  final DateTime Function() _now;
  final Lock _requestLock = Lock();

  HttpServer? _server;
  TvPairingSession? _session;
  TvPairingPayloadHandler? _onPayload;
  TvPairingCancelledHandler? _onCancelled;

  @override
  bool get isRunning => _server != null;

  @override
  Future<TvPairingServerEndpoint> start({
    required TvPairingSession session,
    required TvPairingPayloadHandler onPayload,
    TvPairingCancelledHandler? onCancelled,
  }) async {
    if (_server != null) {
      throw StateError('TV 配对服务已启动');
    }
    if (!session.isActive(_now().toUtc())) {
      throw StateError('TV 配对会话已失效');
    }

    final advertisedHost = await _advertisedHostResolver();
    final server = await HttpServer.bind(_bindAddress, 0, shared: false);
    _server = server;
    _session = session;
    _onPayload = onPayload;
    _onCancelled = onCancelled;
    server.listen(
      (request) => unawaited(_handleRequest(request)),
      onError: (_) {},
      cancelOnError: false,
    );
    return TvPairingServerEndpoint(
      host: advertisedHost,
      port: server.port,
      pairingToken: session.token,
    );
  }

  @override
  Future<void> stop() async {
    final server = _server;
    _server = null;
    _session = null;
    _onPayload = null;
    _onCancelled = null;
    if (server != null) {
      await server.close(force: true);
    }
  }

  Future<void> _handleRequest(HttpRequest request) async {
    final session = _session;
    final onPayload = _onPayload;
    final onCancelled = _onCancelled;
    if (session == null || onPayload == null) {
      await _respondJson(request.response, HttpStatus.serviceUnavailable,
          <String, Object>{'status': 'stopped'});
      return;
    }

    try {
      if (request.method == 'GET' && request.uri.path == '/pair') {
        await _handlePairPage(request, session);
        return;
      }
      if (request.method == 'POST' && request.uri.path == '/api/pair') {
        await _requestLock.synchronized(
          () => _handlePairSubmission(request, session, onPayload),
        );
        return;
      }
      if (request.method == 'POST' && request.uri.path == '/api/cancel') {
        await _requestLock.synchronized(
          () => _handleCancellation(request, session, onCancelled),
        );
        return;
      }
      await _respondJson(request.response, HttpStatus.notFound,
          <String, Object>{'status': 'not_found'});
    } on Object {
      try {
        await _respondJson(request.response, HttpStatus.internalServerError,
            <String, Object>{'status': 'request_failed'});
      } on Object {
        await request.response.close();
      }
    }
  }

  Future<void> _handlePairPage(
    HttpRequest request,
    TvPairingSession session,
  ) async {
    final tokenStatus = _tokenStatus(
      session,
      request.uri.queryParameters['token'],
    );
    if (tokenStatus != _TokenStatus.valid) {
      await _respondTokenError(request.response, tokenStatus);
      return;
    }
    if (request.uri.queryParameters['v'] !=
        TvPairingPayload.currentProtocolVersion.toString()) {
      await _respondJson(request.response, HttpStatus.badRequest,
          <String, Object>{'status': 'unsupported_version'});
      return;
    }

    final response = request.response;
    _setNoStoreHeaders(response);
    response.statusCode = HttpStatus.ok;
    response.headers.contentType = ContentType.html;
    response.headers.set(
      'Content-Security-Policy',
      "default-src 'none'; style-src 'unsafe-inline'; script-src 'unsafe-inline'; connect-src 'self'; form-action 'self'; base-uri 'none'",
    );
    response.headers.set('Referrer-Policy', 'no-referrer');
    response.write(_phoneConfigurationPage(session.token));
    await response.close();
  }

  Future<void> _handlePairSubmission(
    HttpRequest request,
    TvPairingSession session,
    TvPairingPayloadHandler onPayload,
  ) async {
    final tokenStatus = _tokenStatus(
      session,
      request.headers.value('X-Pairing-Token'),
    );
    if (tokenStatus != _TokenStatus.valid) {
      await request.drain<void>();
      await _respondTokenError(request.response, tokenStatus);
      return;
    }
    if (!_isJsonRequest(request)) {
      await request.drain<void>();
      await _respondJson(
        request.response,
        HttpStatus.unsupportedMediaType,
        <String, Object>{'status': 'json_required'},
      );
      return;
    }

    try {
      final bytes = await _readLimitedBody(request);
      final payload = TvPairingPayload.decode(bytes);
      final decision = await onPayload(payload);
      if (decision != TvPairingSubmissionResult.accepted) {
        await _respondJson(request.response, HttpStatus.conflict,
            <String, Object>{'status': 'rejected_on_tv'});
        return;
      }
      if (!session.consume(session.token, now: _now().toUtc())) {
        await _respondJson(request.response, HttpStatus.gone,
            <String, Object>{'status': 'session_expired'});
        return;
      }
      await _respondJson(request.response, HttpStatus.ok,
          <String, Object>{'status': 'paired'});
      unawaited(_stopAcceptingNewRequests(session));
    } on TvPairingPayloadTooLargeException {
      await _respondJson(
        request.response,
        HttpStatus.requestEntityTooLarge,
        <String, Object>{'status': 'payload_too_large'},
      );
    } on TvPairingInvalidPayloadException {
      await _respondJson(request.response, HttpStatus.badRequest,
          <String, Object>{'status': 'invalid_payload'});
    }
  }

  Future<void> _handleCancellation(
    HttpRequest request,
    TvPairingSession session,
    TvPairingCancelledHandler? onCancelled,
  ) async {
    final tokenStatus = _tokenStatus(
      session,
      request.headers.value('X-Pairing-Token'),
    );
    if (tokenStatus != _TokenStatus.valid) {
      await request.drain<void>();
      await _respondTokenError(request.response, tokenStatus);
      return;
    }
    if (!_isJsonRequest(request)) {
      await request.drain<void>();
      await _respondJson(
        request.response,
        HttpStatus.unsupportedMediaType,
        <String, Object>{'status': 'json_required'},
      );
      return;
    }
    try {
      await _readLimitedBody(request);
    } on TvPairingPayloadTooLargeException {
      await _respondJson(
        request.response,
        HttpStatus.requestEntityTooLarge,
        <String, Object>{'status': 'payload_too_large'},
      );
      return;
    }

    session.cancel();
    await onCancelled?.call();
    await _respondJson(request.response, HttpStatus.ok,
        <String, Object>{'status': 'cancelled'});
    unawaited(_stopAcceptingNewRequests(session));
  }

  _TokenStatus _tokenStatus(TvPairingSession session, String? token) {
    final now = _now().toUtc();
    if (!session.isActive(now)) return _TokenStatus.inactive;
    if (token == null || !session.matches(token, now: now)) {
      return _TokenStatus.invalid;
    }
    return _TokenStatus.valid;
  }

  bool _isJsonRequest(HttpRequest request) =>
      request.headers.contentType?.mimeType == ContentType.json.mimeType;

  Future<List<int>> _readLimitedBody(HttpRequest request) async {
    if (request.contentLength > TvPairingPayload.maxPayloadBytes) {
      await request.drain<void>();
      throw TvPairingPayloadTooLargeException(request.contentLength);
    }
    final bytes = <int>[];
    var actualBytes = 0;
    await for (final chunk in request) {
      actualBytes += chunk.length;
      if (actualBytes <= TvPairingPayload.maxPayloadBytes) {
        bytes.addAll(chunk);
      }
    }
    if (actualBytes > TvPairingPayload.maxPayloadBytes) {
      throw TvPairingPayloadTooLargeException(actualBytes);
    }
    return bytes;
  }

  Future<void> _stopAcceptingNewRequests(
    TvPairingSession completedSession,
  ) async {
    if (!identical(_session, completedSession)) return;
    final server = _server;
    _server = null;
    _session = null;
    _onPayload = null;
    _onCancelled = null;
    if (server != null) {
      await server.close(force: false);
    }
  }

  static Future<void> _respondTokenError(
    HttpResponse response,
    _TokenStatus status,
  ) =>
      _respondJson(
        response,
        status == _TokenStatus.inactive
            ? HttpStatus.gone
            : HttpStatus.unauthorized,
        <String, Object>{
          'status': status == _TokenStatus.inactive
              ? 'session_expired'
              : 'invalid_token',
        },
      );

  static Future<void> _respondJson(
    HttpResponse response,
    int statusCode,
    Map<String, Object> body,
  ) async {
    _setNoStoreHeaders(response);
    response.statusCode = statusCode;
    response.headers.contentType = ContentType.json;
    response.write(jsonEncode(body));
    await response.close();
  }

  static void _setNoStoreHeaders(HttpResponse response) {
    response.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
    response.headers.set('X-Content-Type-Options', 'nosniff');
  }

  static Future<String> _resolveLanIpv4Address() async {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLinkLocal: false,
      includeLoopback: false,
    );
    final addresses = interfaces
        .expand((interface) => interface.addresses)
        .where((address) => address.type == InternetAddressType.IPv4)
        .toList(growable: false);
    for (final address in addresses) {
      if (_isPrivateIpv4(address.address)) return address.address;
    }
    if (addresses.isNotEmpty) return addresses.first.address;
    throw const TvPairingNetworkUnavailableException();
  }

  static bool _isPrivateIpv4(String value) {
    final parts = value.split('.').map(int.tryParse).toList(growable: false);
    if (parts.length != 4 || parts.any((part) => part == null)) return false;
    final first = parts[0]!;
    final second = parts[1]!;
    return first == 10 ||
        (first == 172 && second >= 16 && second <= 31) ||
        (first == 192 && second == 168);
  }

  static String _phoneConfigurationPage(String token) {
    final tokenLiteral = jsonEncode(token);
    return '''<!doctype html>
<html lang="zh-CN">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width,initial-scale=1">
  <title>看影音 TV 配置</title>
  <style>
    :root{color-scheme:light;--ink:#17202a;--muted:#667085;--line:#d7dde5;--brand:#176b5b;--accent:#c94b32;--surface:#fff;--page:#f4f6f8}
    *{box-sizing:border-box}body{margin:0;background:var(--page);color:var(--ink);font:16px/1.5 system-ui,sans-serif}
    main{max-width:720px;margin:auto;padding:24px 16px 48px}h1{font-size:24px;margin:0 0 20px}h2{font-size:18px;margin:0}
    section{background:var(--surface);border:1px solid var(--line);border-radius:8px;padding:18px;margin:0 0 16px}
    label{display:block;font-weight:600;margin:12px 0 6px}input,select{width:100%;min-height:44px;border:1px solid #aeb7c2;border-radius:6px;padding:9px 11px;font:inherit;background:#fff}
    .row{display:grid;grid-template-columns:1fr 1fr;gap:12px}.source{border-top:1px solid var(--line);padding-top:14px;margin-top:14px}
    .actions{display:flex;gap:10px;flex-wrap:wrap;margin-top:16px}button{min-height:44px;border:0;border-radius:6px;padding:10px 16px;font:600 15px system-ui,sans-serif;background:var(--brand);color:#fff}
    button.secondary{background:#e8ecef;color:var(--ink)}button.danger{background:var(--accent)}button:disabled{opacity:.55}
    #status{min-height:24px;color:var(--muted);margin-top:12px}.summary{white-space:pre-wrap;background:#eef2f4;border-radius:6px;padding:12px}
    @media(max-width:540px){.row{grid-template-columns:1fr}}
  </style>
</head>
<body><main>
  <h1>看影音 TV 配置</h1>
  <form id="config-form">
    <section>
      <h2>基础配置</h2>
      <label for="device-name">配置名称</label><input id="device-name" value="手机配置" maxlength="80" required>
      <label for="tmdb-key">TMDB API Key</label><input id="tmdb-key" type="password" autocomplete="off">
    </section>
    <section>
      <div class="row"><h2>网盘来源</h2><button class="secondary" type="button" id="add-source">添加来源</button></div>
      <div id="sources"></div>
    </section>
    <section id="review" hidden><h2>提交摘要</h2><p class="summary" id="summary"></p></section>
    <div class="actions"><button type="submit" id="submit">发送到电视</button><button type="button" class="danger" id="cancel">取消配对</button></div>
    <p id="status" role="status"></p>
  </form>
</main>
<template id="source-template"><div class="source">
  <div class="row"><div><label>类型</label><select data-field="type"><option value="openList">OpenList</option><option value="quark">夸克</option><option value="baidu">百度</option><option value="xunlei">迅雷</option></select></div><div><label>名称</label><input data-field="name" required></div></div>
  <label>服务地址</label><input data-field="baseUrl" type="url" required>
  <label>根目录（多个目录用换行分隔）</label><input data-field="rootPaths" value="/">
  <div class="row"><div><label>用户名</label><input data-field="username" autocomplete="username"></div><div><label>密码</label><input data-field="password" type="password" autocomplete="current-password"></div></div>
  <label>Cookie</label><input data-field="cookie" type="password" autocomplete="off">
  <div class="row"><div><label>访问令牌</label><input data-field="accessToken" type="password" autocomplete="off"></div><div><label>刷新令牌</label><input data-field="refreshToken" type="password" autocomplete="off"></div></div>
  <div class="actions"><button type="button" class="secondary remove-source">移除此来源</button></div>
</div></template>
<script>
const token=$tokenLiteral;const form=document.getElementById('config-form');const sources=document.getElementById('sources');const status=document.getElementById('status');
function addSource(){const node=document.getElementById('source-template').content.cloneNode(true);node.querySelector('.remove-source').onclick=function(e){e.target.closest('.source').remove()};sources.appendChild(node)}
function value(node,name){return node.querySelector('[data-field="'+name+'"]').value.trim()}
function makeId(index){return 'tv-pair-'+Date.now().toString(36)+'-'+index.toString(36)}
function buildPayload(){const records=Array.from(sources.querySelectorAll('.source')).map(function(node,index){const credential={};['username','password','cookie','accessToken','refreshToken'].forEach(function(key){const item=value(node,key);if(item)credential[key]=item});return {source:{id:makeId(index),type:value(node,'type'),name:value(node,'name'),baseUrl:value(node,'baseUrl'),rootPaths:value(node,'rootPaths').split(/\r?\n/).map(function(v){return v.trim()}).filter(Boolean),enabled:true,allowSelfSignedCertificate:false,scanStatus:'never',indexedVideoCount:0,matchedSubtitleCount:0,lastScanFailureCount:0},credential:Object.keys(credential).length?credential:null}});return {protocolVersion:1,deviceName:document.getElementById('device-name').value.trim(),tmdbApiKey:document.getElementById('tmdb-key').value.trim(),cloudSources:records}}
document.getElementById('add-source').onclick=addSource;
form.onsubmit=async function(event){event.preventDefault();const payload=buildPayload();document.getElementById('summary').textContent='配置名称：'+payload.deviceName+'\nTMDB：'+(payload.tmdbApiKey?'将更新':'不更新')+'\n网盘来源：'+payload.cloudSources.length+' 个';document.getElementById('review').hidden=false;status.textContent='等待电视端确认…';document.getElementById('submit').disabled=true;try{const response=await fetch('/api/pair',{method:'POST',headers:{'Content-Type':'application/json','X-Pairing-Token':token},body:JSON.stringify(payload)});const result=await response.json();status.textContent=response.ok?'配置已写入电视':(result.status==='rejected_on_tv'?'电视端已拒绝':'提交失败，请返回电视重试')}catch(_){status.textContent='无法连接电视，请确认手机与电视在同一网络'}finally{document.getElementById('submit').disabled=false}}
document.getElementById('cancel').onclick=async function(){try{await fetch('/api/cancel',{method:'POST',headers:{'Content-Type':'application/json','X-Pairing-Token':token},body:'{}'})}finally{status.textContent='配对已取消';form.querySelectorAll('input,select,button').forEach(function(node){node.disabled=true})}};
</script></body></html>''';
  }
}

enum _TokenStatus { valid, invalid, inactive }

class TvPairingNetworkUnavailableException implements Exception {
  const TvPairingNetworkUnavailableException();

  @override
  String toString() => 'TvPairingNetworkUnavailableException';
}
