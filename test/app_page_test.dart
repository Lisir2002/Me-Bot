import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:minime_core/shared/widgets/app_page.dart';
import 'package:minime_core/l10n/app_localizations.dart';
import 'package:minime_core/shared/widgets/app_states.dart';

/// AppPage 槽位引擎的回归基线。
///
/// 目的：引擎（分段 / 三态 / 滚动 / 重载策略）任何改动都必须守住这里的行为。
/// 覆盖范围：
///   1. 基础骨架（标题 / body / 默认返回键 / 默认可滚动）
///   2. scrollable: false
///   3. leading 与 showBack
///   3b. titleWidget（富标题覆盖纯文本标题；未传回落 Text(title)）
///   3c. title 可空（String?：null 不渲染标题；空串等价）
///   4. segments top（TabBar + TabBarView）
///   5. segments bottom（NavigationBar）
///   6. bottom 槽位
///   7. states 三态：loading / data / error / empty
///   8. ⭐ 回归：reloadKey 不变的父级重建不重复拉取（历史 bug）
///   9. ⭐ 回归：reloadKey 变化才重新拉取
///  10. ⭐ 回归：reloadKey 为 null 时只加载一次
void main() {
  Widget wrap(Widget page) => MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('zh'),
      home: page,
    );

  // ────────────────────────────────────────────────────────────
  // 1. 基础骨架
  // ────────────────────────────────────────────────────────────
  testWidgets('基础：渲染标题、body 与默认返回键，且默认包一层可滚动 ListView',
      (tester) async {
    await tester.pumpWidget(wrap(
      const AppPage(title: '基础页', body: Text('BODY')),
    ));

    expect(find.text('基础页'), findsOneWidget);
    expect(find.text('BODY'), findsOneWidget);
    // 默认 showBack: true → 引擎提供 iOS 风格返回键
    expect(find.byIcon(Icons.arrow_back_ios_new_rounded), findsOneWidget);
    // 默认 scrollable: true → body 被包进 ListView
    expect(find.byType(ListView), findsOneWidget);
  });

  // ────────────────────────────────────────────────────────────
  // 2. scrollable
  // ────────────────────────────────────────────────────────────
  testWidgets('scrollable: false 时不包 ListView（避免与 body 自带滚动嵌套）',
      (tester) async {
    await tester.pumpWidget(wrap(
      const AppPage(title: 'T', scrollable: false, body: Text('BODY')),
    ));

    expect(find.text('BODY'), findsOneWidget);
    expect(find.byType(ListView), findsNothing,
        reason: 'scrollable:false 时引擎不应再包一层 ListView');
  });

  // ────────────────────────────────────────────────────────────
  // 3. leading / showBack
  // ────────────────────────────────────────────────────────────
  testWidgets('showBack: false 时不渲染返回键，且支持自定义 leading', (tester) async {
    await tester.pumpWidget(wrap(
      const AppPage(
        title: 'T',
        showBack: false,
        leading: Icon(Icons.menu),
        body: Text('BODY'),
      ),
    ));

    expect(find.byIcon(Icons.arrow_back_ios_new_rounded), findsNothing);
    expect(find.byIcon(Icons.menu), findsOneWidget);
  });

  // ────────────────────────────────────────────────────────────
  // 3b. titleWidget（富标题）
  // ────────────────────────────────────────────────────────────
  testWidgets('titleWidget: 传入时完全覆盖纯文本标题，未传时回落 Text(title)',
      (tester) async {
    await tester.pumpWidget(wrap(
      const AppPage(
        title: '纯文本',
        titleWidget: Row(children: [Icon(Icons.star), Text('富标题')]),
        body: Text('BODY'),
      ),
    ));

    // titleWidget 生效：自定义内容渲染，纯文本标题不出现
    expect(find.byIcon(Icons.star), findsOneWidget);
    expect(find.text('富标题'), findsOneWidget);
    expect(find.text('纯文本'), findsNothing,
        reason: 'titleWidget 传入时不应再渲染 Text(title)');

    // 回落：不传 titleWidget 时仍渲染纯文本标题
    await tester.pumpWidget(wrap(
      const AppPage(title: '纯文本', body: Text('BODY')),
    ));
    expect(find.text('纯文本'), findsOneWidget);
    expect(find.byIcon(Icons.star), findsNothing);
  });

  // ────────────────────────────────────────────────────────────
  // 3c. title 可空（String?）
  // ────────────────────────────────────────────────────────────
  testWidgets('title: 为 null 时 AppBar.title 为 null（不渲染标题）',
      (tester) async {
    await tester.pumpWidget(wrap(const AppPage(title: null, body: Text('BODY'))));
    expect(find.text('BODY'), findsOneWidget);
    final appBar = tester.widget<AppBar>(find.byType(AppBar).first);
    expect(appBar.title, isNull,
        reason: 'title 为 null 且未传 titleWidget 时，引擎应传 null 标题');
  });

  testWidgets('title: 空串时渲染空 Text 标题（与 null 视觉等价）',
      (tester) async {
    await tester.pumpWidget(wrap(const AppPage(title: '', body: Text('BODY'))));
    final appBar = tester.widget<AppBar>(find.byType(AppBar).first);
    expect(appBar.title, isA<Text>());
    expect((appBar.title as Text).data, '');
  });

  // ────────────────────────────────────────────────────────────
  // 4. segments top
  // ────────────────────────────────────────────────────────────
  testWidgets('segments(top)：渲染 TabBar，切换后显示对应内容', (tester) async {
    await tester.pumpWidget(wrap(
      AppPage(
        title: 'T',
        segments: [
          AppSegment(label: 'A', body: (_) => const Text('BODY-A')),
          AppSegment(label: 'B', body: (_) => const Text('BODY-B')),
        ],
      ),
    ));

    expect(find.byType(TabBar), findsOneWidget);
    expect(find.text('A'), findsOneWidget);
    expect(find.text('B'), findsOneWidget);

    await tester.tap(find.text('B'));
    await tester.pumpAndSettle();

    expect(find.text('BODY-B'), findsOneWidget);
  });

  // ────────────────────────────────────────────────────────────
  // 5. segments bottom
  // ────────────────────────────────────────────────────────────
  testWidgets('segments(bottom)：渲染 NavigationBar，切换后显示对应内容',
      (tester) async {
    await tester.pumpWidget(wrap(
      AppPage(
        title: 'T',
        segmentsMode: AppSegmentMode.bottom,
        segments: [
          AppSegment(
            label: 'A',
            icon: Icons.home_outlined,
            selectedIcon: Icons.home,
            body: (_) => const Text('BODY-A'),
          ),
          AppSegment(
            label: 'B',
            icon: Icons.settings_outlined,
            selectedIcon: Icons.settings,
            body: (_) => const Text('BODY-B'),
          ),
        ],
      ),
    ));

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('BODY-A'), findsOneWidget);

    await tester.tap(find.text('B'));
    await tester.pumpAndSettle();

    expect(find.text('BODY-B'), findsOneWidget);
  });

  // ────────────────────────────────────────────────────────────
  // 6. bottom 槽位
  // ────────────────────────────────────────────────────────────
  testWidgets('bottom 槽位：渲染自定义底栏', (tester) async {
    await tester.pumpWidget(wrap(
      const AppPage(title: 'T', body: Text('BODY'), bottom: Text('BOTTOM')),
    ));

    expect(find.text('BOTTOM'), findsOneWidget);
  });

  // ────────────────────────────────────────────────────────────
  // 7. states 三态
  // ────────────────────────────────────────────────────────────
  testWidgets('states：Future 未完成时渲染 AppLoading', (tester) async {
    final completer = Completer<String>();

    await tester.pumpWidget(wrap(
      AppPage(
        title: 'T',
        states: AppPageStates<String>(
          load: () => completer.future,
          buildData: (_, data) => Text('DATA:$data'),
          loadingMessage: '加载中…',
        ),
      ),
    ));
    // 只 pump 一帧：future 仍处于 waiting，不能用 pumpAndSettle（会超时）
    await tester.pump();

    expect(find.byType(AppLoading), findsOneWidget);
    expect(find.text('加载中…'), findsOneWidget);
  });

  testWidgets('states：Future 成功时渲染 buildData', (tester) async {
    await tester.pumpWidget(wrap(
      AppPage(
        title: 'T',
        states: AppPageStates<String>(
          load: () async => 'hello',
          buildData: (_, data) => Text('DATA:$data'),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('DATA:hello'), findsOneWidget);
  });

  testWidgets('states：Future 失败时渲染 AppError，点重试会重新拉取', (tester) async {
    var loadCount = 0;
    Future<String> load() async {
      loadCount++;
      throw Exception('boom');
    }

    await tester.pumpWidget(wrap(
      AppPage(
        title: 'T',
        states: AppPageStates<String>(
          load: load,
          buildData: (_, data) => Text('DATA:$data'),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.byType(AppError), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);
    expect(loadCount, 1);

    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();

    expect(loadCount, 2, reason: '点击重试应触发一次新的 load');
  });

  testWidgets('states：emptyWhen 命中时渲染 AppEmpty', (tester) async {
    await tester.pumpWidget(wrap(
      AppPage(
        title: 'T',
        states: AppPageStates<String>(
          load: () async => '',
          emptyWhen: (data) => data.isEmpty,
          emptyMessage: '空空如也',
          buildData: (_, data) => Text('DATA:$data'),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.byType(AppEmpty), findsOneWidget);
    expect(find.text('空空如也'), findsOneWidget);
  });

  // ────────────────────────────────────────────────────────────
  // 8~10. ⭐ 回归：reloadKey 重载策略（修复「父级重建即 refetch」的历史 bug）
  // ────────────────────────────────────────────────────────────
  testWidgets('回归：reloadKey 不变时，父级重建不会重复拉取 Future', (tester) async {
    var loadCount = 0;
    Future<String> load() async {
      loadCount++;
      return 'x';
    }

    final hostKey = GlobalKey<_StatesHostState>();
    await tester.pumpWidget(MaterialApp(
      home: _StatesHost(key: hostKey, load: load, reloadKey: 'k1'),
    ));
    await tester.pumpAndSettle();
    expect(loadCount, 1);

    // 模拟父级因 Provider 通知等原因重建（会 new 一个新的 AppPageStates）
    hostKey.currentState!.rebuild();
    await tester.pumpAndSettle();

    expect(loadCount, 1,
        reason: 'reloadKey 未变，父级重建不应重新拉取（旧实现按对象引用比较会误触发）');
  });

  testWidgets('回归：reloadKey 变化时才重新拉取 Future', (tester) async {
    var loadCount = 0;
    Future<String> load() async {
      loadCount++;
      return 'x';
    }

    final hostKey = GlobalKey<_StatesHostState>();
    await tester.pumpWidget(MaterialApp(
      home: _StatesHost(key: hostKey, load: load, reloadKey: 'k1'),
    ));
    await tester.pumpAndSettle();
    expect(loadCount, 1);

    hostKey.currentState!.changeKey('k2');
    await tester.pumpAndSettle();

    expect(loadCount, 2, reason: 'reloadKey 变化应触发一次新的 load');
  });

  testWidgets('回归：reloadKey 为 null 时只加载一次', (tester) async {
    var loadCount = 0;
    Future<String> load() async {
      loadCount++;
      return 'x';
    }

    final hostKey = GlobalKey<_StatesHostState>();
    await tester.pumpWidget(MaterialApp(
      home: _StatesHost(key: hostKey, load: load),
    ));
    await tester.pumpAndSettle();
    expect(loadCount, 1);

    hostKey.currentState!.rebuild();
    await tester.pumpAndSettle();
    hostKey.currentState!.rebuild();
    await tester.pumpAndSettle();

    expect(loadCount, 1, reason: 'reloadKey 为 null 表示只在首次挂载加载一次');
  });
}

/// 承载 states 的宿主：每次 build 都 new 一个 AppPageStates，
/// 精确复现「页面内联创建 config」的真实写法（旧 bug 的触发条件）。
class _StatesHost extends StatefulWidget {
  const _StatesHost({super.key, required this.load, this.reloadKey});

  final Future<String> Function() load;
  final Object? reloadKey;

  @override
  State<_StatesHost> createState() => _StatesHostState();
}

class _StatesHostState extends State<_StatesHost> {
  Object? _reloadKey;

  @override
  void initState() {
    super.initState();
    _reloadKey = widget.reloadKey;
  }

  /// 触发父级重建（不改变 reloadKey）
  void rebuild() => setState(() {});

  /// 改变 reloadKey 并重建
  void changeKey(Object? key) => setState(() => _reloadKey = key);

  @override
  Widget build(BuildContext context) {
    return AppPage(
      title: 'States',
      states: AppPageStates<String>(
        load: widget.load,
        buildData: (_, data) => Text('DATA:$data'),
        reloadKey: _reloadKey,
      ),
    );
  }
}
