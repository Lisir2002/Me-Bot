// App 启动冒烟测试。
//
// 历史说明：Flutter 模板自带的「Counter increments smoke test」从一开始就是红的
// （本应用不是计数器 Demo，`find.text('0')` 必然失败），意味着 main 分支的
// `flutter test` 长期处于失败状态、无人运行。这里替换为真实冒烟：
// 只要 MyApp 能完成首帧渲染、挂出 MaterialApp，就证明启动路径没有硬崩。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:minime_core/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // SettingsProvider 等在构造期异步读取 prefs；测试环境必须给 mock，
  // 否则 MissingPluginException 会以未捕获异步错误的形式炸掉测试。
  SharedPreferences.setMockInitialValues(<String, Object>{});

  testWidgets('App 启动冒烟：MyApp 可渲染出 MaterialApp 骨架', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MyApp());
    // 只泵固定时长：应用里有未完成的异步初始化与计时器，pumpAndSettle 会一直等不到静止。
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
