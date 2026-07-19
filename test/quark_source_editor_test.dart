import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/modules/cloud/cloud_source.dart';
import 'package:kanyingyin/pages/cloud/quark/quark_source_editor.dart';
import 'package:kanyingyin/providers/cloud_library_controller.dart';
import 'package:kanyingyin/repositories/cloud_source_repository.dart';
import 'package:kanyingyin/services/cloud/cloud_credential_store.dart';

void main() {
  testWidgets('夸克编辑器包含必要字段且不回显已有 Cookie', (tester) async {
    const source = CloudSource(
      id: 'quark-fixture',
      type: CloudSourceType.quark,
      name: '夸克媒体库',
      baseUrl: 'https://pan.quark.cn',
      rootPaths: <String>['/影视'],
    );
    final credentials = MemoryCloudCredentialStore();
    await credentials.write(
      source.id,
      const CloudCredential(cookie: 'existing-cookie-must-not-render'),
    );
    final controller = CloudLibraryController(
      repository: CloudSourceRepository(
        storage: MemoryCloudSourceStorage(),
        credentialStore: credentials,
      ),
      credentialStore: credentials,
    );

    await tester.pumpWidget(MaterialApp(
      home: QuarkSourceEditorPage(source: source, controller: controller),
    ));
    await tester.pumpAndSettle();

    expect(find.text('夸克网盘数据源'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, '来源名称'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'Cookie'), findsOneWidget);
    expect(find.text('测试登录'), findsOneWidget);
    expect(find.text('媒体根目录'), findsOneWidget);
    expect(find.text('默认转存目录'), findsOneWidget);
    expect(find.text('启用此来源'), findsOneWidget);
    final cookieFinder = find.widgetWithText(TextFormField, 'Cookie');
    final cookieField = tester.widget<TextFormField>(cookieFinder);
    final editable = tester.widget<EditableText>(
      find.descendant(of: cookieFinder, matching: find.byType(EditableText)),
    );
    expect(editable.obscureText, isTrue);
    expect(cookieField.controller?.text, isEmpty);
    expect(
        find.textContaining('existing-cookie-must-not-render'), findsNothing);
    controller.dispose();
  });
}
