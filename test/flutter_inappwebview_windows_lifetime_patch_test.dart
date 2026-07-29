import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _unsafeProcessInfoCallback = '''
                  if (auto environment13 = environment_.try_query<ICoreWebView2Environment13>()) {
                    auto hr = environment13->GetProcessExtendedInfos(Callback<ICoreWebView2GetProcessExtendedInfosCompletedHandler>(
                      [this](HRESULT error, wil::com_ptr<ICoreWebView2ProcessExtendedInfoCollection> processCollection) -> HRESULT
                      {
                        if (succeededOrLog(error) && processCollection) {
                          auto browserProcessInfosChangedDetail = BrowserProcessInfosChangedDetail::fromICoreWebView2ProcessExtendedInfoCollection(processCollection);
                          channelDelegate->onProcessInfosChanged(std::move(browserProcessInfosChangedDetail));
                        }
                        return S_OK;
                      }).Get());

                    if (succeededOrLog(hr)) {
                      return S_OK;
                    }
                  }
''';

const _synchronousFallback = '''
                  wil::com_ptr<ICoreWebView2ProcessInfoCollection> processCollection;
                  if (channelDelegate && succeededOrLog(environment8->GetProcessInfos(&processCollection))) {
''';

const _activeProcessInfoQuery = '''
  void WebViewEnvironment::getProcessInfos() const
  {
    auto hr = environment13->GetProcessExtendedInfos(Callback<ICoreWebView2GetProcessExtendedInfosCompletedHandler>(
      [completionHandler](HRESULT error, wil::com_ptr<ICoreWebView2ProcessExtendedInfoCollection> processCollection) -> HRESULT
      {
        completionHandler({});
        return S_OK;
      }).Get());
  }
''';

void main() {
  test('Windows WebView 补丁脚本显式启用项目所需的 CMake 策略', () async {
    final script = await File(
      'windows/cmake/patch_flutter_inappwebview_windows.cmake',
    ).readAsString(encoding: utf8);

    expect(
      script.trimLeft(),
      startsWith('cmake_minimum_required(VERSION 3.14)'),
    );
  });

  test('Windows WebView 补丁仅移除事件异步回调并保留主动查询', () async {
    final workspace = await _createWorkspace();
    final source = File('${workspace.path}/webview_environment.cpp');
    final output = File('${workspace.path}/webview_environment_patched.cpp');
    await source.writeAsString(
      '$_unsafeProcessInfoCallback$_synchronousFallback'
      '$_activeProcessInfoQuery',
      encoding: utf8,
    );

    final result = await _runPatch(source: source, output: output);

    expect(result.exitCode, 0, reason: _processOutput(result));
    final patched = await output.readAsString(encoding: utf8);
    expect(
      'GetProcessExtendedInfosCompletedHandler'.allMatches(patched),
      hasLength(1),
    );
    expect(patched, isNot(contains('[this](HRESULT error')));
    expect(patched, contains('[completionHandler](HRESULT error'));
    expect(patched, contains('environment8->GetProcessInfos'));
  });

  test('Windows WebView 补丁拒绝不匹配的上游源码', () async {
    final workspace = await _createWorkspace();
    final source = File('${workspace.path}/webview_environment.cpp');
    final output = File('${workspace.path}/webview_environment_patched.cpp');
    await source.writeAsString(_activeProcessInfoQuery, encoding: utf8);

    final result = await _runPatch(source: source, output: output);

    expect(result.exitCode, isNot(0));
    expect(_processOutput(result), contains('WEBVIEW_PATCH_FRAGMENT_COUNT'));
    expect(await output.exists(), isFalse);
  });

  test('Windows WebView 补丁拒绝重复修改多个事件回调', () async {
    final workspace = await _createWorkspace();
    final source = File('${workspace.path}/webview_environment.cpp');
    final output = File('${workspace.path}/webview_environment_patched.cpp');
    await source.writeAsString(
      '$_unsafeProcessInfoCallback$_unsafeProcessInfoCallback',
      encoding: utf8,
    );

    final result = await _runPatch(source: source, output: output);

    expect(result.exitCode, isNot(0));
    expect(_processOutput(result), contains('WEBVIEW_PATCH_FRAGMENT_COUNT'));
    expect(await output.exists(), isFalse);
  });

  test('Windows 构建恰好替换一个插件环境源文件', () async {
    final fixture = await _configureTargetFixture(sourceOccurrences: 1);

    expect(fixture.result.exitCode, 0, reason: _processOutput(fixture.result));
    final sources = await fixture.resolvedSources.readAsString(encoding: utf8);
    expect(sources, isNot(contains(fixture.originalSource.path)));
    expect(
      RegExp(r'patched_plugins[/\\]flutter_inappwebview_windows'
              r'[/\\]webview_environment\.cpp')
          .allMatches(sources),
      hasLength(1),
    );
  });

  test('Windows 构建拒绝未注册原始插件环境源文件', () async {
    final fixture = await _configureTargetFixture(sourceOccurrences: 0);

    expect(fixture.result.exitCode, isNot(0));
    expect(
        _processOutput(fixture.result), contains('WEBVIEW_PATCH_SOURCE_COUNT'));
  });

  test('Windows 构建拒绝重复注册原始插件环境源文件', () async {
    final fixture = await _configureTargetFixture(sourceOccurrences: 2);

    expect(fixture.result.exitCode, isNot(0));
    expect(
        _processOutput(fixture.result), contains('WEBVIEW_PATCH_SOURCE_COUNT'));
  });

  test('Windows 构建在插件注册后应用 WebView 生命周期补丁', () async {
    final cmake = await File('windows/CMakeLists.txt').readAsString(
      encoding: utf8,
    );
    final generatedPlugins = cmake.indexOf(
      'include(flutter/generated_plugins.cmake)',
    );
    final lifetimePatch = cmake.indexOf(
      'include(cmake/flutter_inappwebview_windows_lifetime_patch.cmake)',
    );

    expect(generatedPlugins, greaterThanOrEqualTo(0));
    expect(lifetimePatch, greaterThan(generatedPlugins));
  });
}

Future<Directory> _createWorkspace() async {
  final workspace = await Directory.systemTemp.createTemp(
    'kanyingyin-webview-lifetime-patch-',
  );
  addTearDown(() async {
    if (await workspace.exists()) {
      await workspace.delete(recursive: true);
    }
  });
  return workspace;
}

Future<ProcessResult> _runPatch({
  required File source,
  required File output,
}) =>
    Process.run(
      'cmake',
      <String>[
        '-DINPUT_FILE=${source.path}',
        '-DOUTPUT_FILE=${output.path}',
        '-P',
        'windows/cmake/patch_flutter_inappwebview_windows.cmake',
      ],
      workingDirectory: Directory.current.path,
    );

Future<_TargetFixtureResult> _configureTargetFixture({
  required int sourceOccurrences,
}) async {
  final workspace = await _createWorkspace();
  final originalSource = File(
    '${workspace.path}/flutter/ephemeral/.plugin_symlinks/'
    'flutter_inappwebview_windows/windows/webview_environment/'
    'webview_environment.cpp',
  );
  await originalSource.parent.create(recursive: true);
  await originalSource.writeAsString(
    '$_unsafeProcessInfoCallback$_synchronousFallback',
    encoding: utf8,
  );
  final dummySource = File('${workspace.path}/dummy.cpp');
  await dummySource.writeAsString('void fixture() {}\n', encoding: utf8);
  final buildDirectory = Directory('${workspace.path}/build');
  final resolvedSources = File('${buildDirectory.path}/resolved_sources.txt');
  final sourceList = <String>[
    _cmakePath(dummySource.path),
    ...List<String>.filled(
      sourceOccurrences,
      _cmakePath(originalSource.path),
    ),
  ].map((path) => '"$path"').join('\n    ');
  final modulePath = _cmakePath(
    File(
      'windows/cmake/flutter_inappwebview_windows_lifetime_patch.cmake',
    ).absolute.path,
  );
  final cmakeLists = File('${workspace.path}/CMakeLists.txt');
  await cmakeLists.writeAsString('''
cmake_minimum_required(VERSION 3.14)
project(webview_lifetime_patch_fixture LANGUAGES CXX)
add_library(flutter_inappwebview_windows_plugin SHARED
  "${_cmakePath(dummySource.path)}")
set_property(TARGET flutter_inappwebview_windows_plugin PROPERTY SOURCES
    $sourceList)
include("$modulePath")
get_target_property(RESOLVED_SOURCES flutter_inappwebview_windows_plugin SOURCES)
file(WRITE "\${CMAKE_BINARY_DIR}/resolved_sources.txt" "\${RESOLVED_SOURCES}")
''', encoding: utf8);

  final result = await Process.run(
    'cmake',
    <String>['-S', workspace.path, '-B', buildDirectory.path],
    workingDirectory: Directory.current.path,
  );
  return _TargetFixtureResult(
    result: result,
    originalSource: originalSource,
    resolvedSources: resolvedSources,
  );
}

String _cmakePath(String path) => path.replaceAll('\\', '/');

String _processOutput(ProcessResult result) =>
    '${result.stdout}\n${result.stderr}';

class _TargetFixtureResult {
  const _TargetFixtureResult({
    required this.result,
    required this.originalSource,
    required this.resolvedSources,
  });

  final ProcessResult result;
  final File originalSource;
  final File resolvedSources;
}
