import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/error/error.dart';
import 'package:analyzer/error/listener.dart';
import 'package:custom_lint_builder/custom_lint_builder.dart';

/// Me-Bot l10n + 设计系统自定义 lint。
///
/// 规则 1 `hardcoded_ui_string`：UI widget 参数位出现含中文的字符串字面量
///   → 语言遗漏的实时红线（IDE 波浪线 + CI）。项目 UI 主语言为中文，
///   硬编码中文几乎必然意味着「英文环境漏译」，因此只查 CJK，噪音低。
///   服务层日志/异常按约定不进 arb，也不在 widget 参数位，天然不受影响。
///
/// 规则 2 `l10n_no_field_cache`：把 AppLocalizations 存进字段/缓存
///   → 语言切换后旧文案不刷新的头号坑，直接禁止。
///
/// 规则 3 `no_material_snackbar`（error）：禁止裸 SnackBar / ScaffoldMessenger，
///   通知一律走 `showAppSnackBar`（AppSnackBarManager 统一渲染 + 语义色）。
///
/// 规则 4 `no_material_list_tile`（error）：禁止裸 ListTile 系组件，
///   列表行一律走 `AppNavRow` / `AppSwitchRow`（iOS 触觉 + 按压缩放 + 统一密度）。
///
/// 规则 5 `no_raw_scaffold`（error）：禁止页面自写裸 Scaffold，
///   页面骨架一律走 `AppPage`。全屏特例（浏览器/查看器/扫码/首页）在文件内
///   写明「no_raw_scaffold 白名单」注释后整文件豁免（见 image_viewer_page 等）。
///
/// 规则 6 `no_raw_alert_dialog`（error）：禁止裸 AlertDialog / Dialog，
///   中心化弹窗一律走 `AppDialog`（confirm/alert/progress/input/announcement）。
///   底部弹层走 `showAppSheet`，顶部通知走 `showAppSnackBar`。
///   现有复杂弹窗（tool_approval/emoji_picker/desktop 系列）加白名单注释豁免。
///
/// 规则 7 `no_manual_listview_padding`（error）：禁止页面级手写
///   `ListView(padding:)`，列表一律走 `AppListView` / `AppListViewBuilder`
///   （水平 padding 固定 16，防止双层 padding 导致卡片过窄）。
///   组件内部 ListView（非 *_page.dart）不受限。
///
/// 规则 8 `no_scrollable_false_without_selfscrolling`（error）：禁止
///   `AppPage(scrollable: false)` 而不用 `AppPage.selfScrolling`。
///   body 内部自带滚动容器时必须用 selfScrolling 命名构造（自动 bodyPadding:zero）。
///   特例（body 无滚动容器、靠 AppPage bodyPadding 提供边距）加白名单注释豁免。
PluginBase createPlugin() => _MeBotL10nLints();

class _MeBotL10nLints extends PluginBase {
  @override
  List<LintRule> getLintRules(CustomLintConfigs configs) => [
        HardcodedUiString(),
        L10nNoFieldCache(),
        NoMaterialSnackBar(),
        NoMaterialListTile(),
        NoRawScaffold(),
        NoRawAlertDialog(),
        NoManualListviewPadding(),
        NoScrollableFalseWithoutSelfscrolling(),
      ];
}

/// 判定是否包含 CJK（统一表意文字基本区）。
bool _containsCjk(String s) => RegExp(r'[\u4e00-\u9fff]').hasMatch(s);

/// 从字符串字面量取可读文本（拼接/插值各段合并）。
String _literalText(StringLiteral node) {
  if (node is SimpleStringLiteral) return node.stringValue ?? '';
  if (node is AdjacentStrings) return node.strings.map(_literalText).join();
  if (node is StringInterpolation) {
    return node.elements
        .whereType<InterpolationString>()
        .map((e) => e.value)
        .join();
  }
  return '';
}

class HardcodedUiString extends DartLintRule {
  HardcodedUiString() : super(code: _code);

  static const _code = LintCode(
    name: 'hardcoded_ui_string',
    problemMessage: 'UI 文案硬编码（含中文）——应加入 l10n 并改用 context.l10n.xxx，'
        '否则英文环境下漏译。特殊原因可 // ignore: hardcoded_ui_string',
    correctionMessage: '加入 lib/l10n/app_*.arb 三份文件后改用 context.l10n.xxx',
    errorSeverity: ErrorSeverity.WARNING,
  );

  /// 会被检查的具名参数（UI 展示位）。
  static const _paramNames = {
    'title', 'subtitle', 'label', 'tooltip', 'hintText', 'labelText',
    'helperText', 'semanticLabel', 'message', 'text', 'content',
    'confirmText', 'cancelText', 'dialogTitle', 'placeholder', 'hint',
    'emptyText', 'name', 'description', 'body',
  };

  @override
  void run(
    CustomLintResolver resolver,
    ErrorReporter reporter,
    CustomLintContext context,
  ) {
    // 测试与 l10n 自身不查。
    if (resolver.path.contains('/test/') ||
        resolver.path.contains('/l10n/') ||
        resolver.path.contains('l10n_lints/')) {
      return;
    }
    context.registry.addInstanceCreationExpression((node) {
      final typeName = node.constructorName.type.toString();
      for (final arg in node.argumentList.arguments) {
        final Expression literal;
        final String paramName;
        if (arg is NamedExpression) {
          paramName = arg.name.label.name;
          literal = arg.expression;
        } else {
          paramName = '';
          literal = arg;
        }
        final isNamed = paramName.isNotEmpty;
        final isTextPositional =
            typeName == 'Text' && !isNamed; // Text 的位置参数即文案
        if (isNamed && !_paramNames.contains(paramName)) continue;
        if (!isNamed && !isTextPositional) continue;
        if (literal is! StringLiteral) continue;
        if (_containsCjk(_literalText(literal))) {
          reporter.reportErrorForNode(code, arg);
        }
      }
    });
  }
}

class L10nNoFieldCache extends DartLintRule {
  L10nNoFieldCache() : super(code: _code);

  static const _code = LintCode(
    name: 'l10n_no_field_cache',
    problemMessage: '不要把 AppLocalizations 缓存到字段——语言切换后旧文案不会刷新；'
        '请在 build 内通过 context.l10n 现取',
    errorSeverity: ErrorSeverity.WARNING,
  );

  @override
  void run(
    CustomLintResolver resolver,
    ErrorReporter reporter,
    CustomLintContext context,
  ) {
    if (resolver.path.contains('/l10n/') || resolver.path.contains('l10n_lints/')) {
      return;
    }
    // 类字段：类型显式为 AppLocalizations，或初始化调用 AppLocalizations.of(...)
    context.registry.addFieldDeclaration((node) {
      final typeName = node.fields.type?.toString() ?? '';
      for (final v in node.fields.variables) {
        final init = v.initializer;
        final callsOf = init is MethodInvocation &&
            init.methodName.name == 'of' &&
            (init.target?.toString() ?? '').contains('AppLocalizations');
        if (typeName.contains('AppLocalizations') || callsOf) {
          reporter.reportErrorForNode(code, v);
        }
      }
    });
    // 顶层变量同理（极少见，兜底）
    context.registry.addTopLevelVariableDeclaration((node) {
      final typeName = node.variables.type?.toString() ?? '';
      for (final v in node.variables.variables) {
        final init = v.initializer;
        final callsOf = init is MethodInvocation &&
            init.methodName.name == 'of' &&
            (init.target?.toString() ?? '').contains('AppLocalizations');
        if (typeName.contains('AppLocalizations') || callsOf) {
          reporter.reportErrorForNode(code, v);
        }
      }
    });
  }
}

// ──────────────────────────────────────────────────────────────
// 设计系统守护规则（UI 对齐批次新增，error 级）
//
// 目的：把「新页面必须走设计系统」从口头约定变成机器红线——
// 写码时 IDE 直接标红，CI 里 custom_lint fatal，双端拦截。
// ──────────────────────────────────────────────────────────────

/// 共享的运行环境判定。
extension _GuardEnv on CustomLintResolver {
  /// 是否豁免目录（测试 / 设计系统实现自身 / lint 插件自身）。
  bool get inExemptDir =>
      path.contains('/test/') ||
      path.contains('l10n_lints/') ||
      path.contains('/tools/');

  /// 文件内是否带整文件豁免标记（全屏特例页在 Scaffold 处注明）。
  bool get hasWhitelistMark =>
      source.contents.data.contains('no_raw_scaffold 白名单');
}

/// 规则 3 `no_material_snackbar`：裸 SnackBar / SnackBarAction 一律 error。
class NoMaterialSnackBar extends DartLintRule {
  NoMaterialSnackBar() : super(code: _code);

  static const _code = LintCode(
    name: 'no_material_snackbar',
    problemMessage: '禁止裸 SnackBar——通知一律用 showAppSnackBar(context, '
        'message: ..., type: ...)（统一渲染、语义色、可点行为）',
    correctionMessage: "import '../../../shared/widgets/snackbar.dart' 后改用 "
        'showAppSnackBar；NotificationType.success/error/info/warning 表达语义',
    errorSeverity: ErrorSeverity.ERROR,
  );

  /// 被禁止的 Material 通知组件。
  static const _banned = {'SnackBar', 'SnackBarAction'};

  /// 设计系统实现自身（snackbar.dart）不在检查范围。
  static const _exemptPaths = ['/shared/widgets/snackbar.dart'];

  @override
  void run(
    CustomLintResolver resolver,
    ErrorReporter reporter,
    CustomLintContext context,
  ) {
    if (resolver.inExemptDir ||
        _exemptPaths.any(resolver.path.contains)) {
      return;
    }
    context.registry.addInstanceCreationExpression((node) {
      final type = node.constructorName.type.toString();
      if (_banned.contains(type)) {
        reporter.reportErrorForNode(code, node.constructorName.type);
      }
    });
  }
}

/// 规则 4 `no_material_list_tile`：裸 ListTile 系组件一律 error。
class NoMaterialListTile extends DartLintRule {
  NoMaterialListTile() : super(code: _code);

  static const _code = LintCode(
    name: 'no_material_list_tile',
    problemMessage: '禁止裸 ListTile / SwitchListTile 等列表行——'
        '一律用 AppNavRow / AppSwitchRow（iOS 触觉、按压缩放、统一密度与图标列）',
    correctionMessage: "import '../../../shared/widgets/app_section.dart' 后改用 "
        'AppNavRow（导航/选择行）或 AppSwitchRow（开关行）',
    errorSeverity: ErrorSeverity.ERROR,
  );

  /// 被禁止的 Material 列表行组件。
  static const _banned = {
    'ListTile',
    'SwitchListTile',
    'CheckboxListTile',
    'RadioListTile',
    'ExpansionTile',
    'AboutListTile',
  };

  @override
  void run(
    CustomLintResolver resolver,
    ErrorReporter reporter,
    CustomLintContext context,
  ) {
    if (resolver.inExemptDir) return;
    context.registry.addInstanceCreationExpression((node) {
      final type = node.constructorName.type.toString();
      if (_banned.contains(type)) {
        reporter.reportErrorForNode(code, node.constructorName.type);
      }
    });
  }
}

/// 规则 5 `no_raw_scaffold`：页面自写裸 Scaffold 一律 error。
///
/// 页面骨架必须走 `AppPage`（统一返回键/标题/滚动/SafeArea）。
/// 全屏特例（浏览器、查看器、扫码、首页）在文件任意处写
/// 「no_raw_scaffold 白名单」注释即可整文件豁免。
class NoRawScaffold extends DartLintRule {
  NoRawScaffold() : super(code: _code);

  static const _code = LintCode(
    name: 'no_raw_scaffold',
    problemMessage: '禁止页面自写裸 Scaffold——页面骨架一律用 AppPage '
        '（统一返回键、标题、滚动与 SafeArea，防止风格漂移）',
    correctionMessage: "import '../../../shared/widgets/app_page.dart' 后改用 "
        'AppPage(title: ..., body: ...)；全屏特例在文件内加 '
        '「no_raw_scaffold 白名单：…原因」注释豁免',
    errorSeverity: ErrorSeverity.ERROR,
  );

  /// 设计系统实现自身（AppPage 内部组装 Scaffold）。
  static const _exemptPaths = ['/shared/widgets/app_page.dart'];

  @override
  void run(
    CustomLintResolver resolver,
    ErrorReporter reporter,
    CustomLintContext context,
  ) {
    if (resolver.inExemptDir ||
        _exemptPaths.any(resolver.path.contains) ||
        resolver.hasWhitelistMark) {
      return;
    }
    context.registry.addInstanceCreationExpression((node) {
      if (node.constructorName.type.toString() != 'Scaffold') return;
      reporter.reportErrorForNode(code, node.constructorName.type);
    });
  }
}

// ──────────────────────────────────────────────────────────────
// 规则 6-8：弹窗 + 页面滚动容器强制执行（UI 统一化批次新增）
// ──────────────────────────────────────────────────────────────

/// 规则 6 `no_raw_alert_dialog`：禁止裸 AlertDialog / Dialog。
///
/// 中心化弹窗一律走 `AppDialog`（confirm/alert/progress/input/announcement）。
/// 现有复杂弹窗（tool_approval / emoji_picker / desktop 系列）在文件内写
/// 「no_raw_alert_dialog 白名单」注释豁免。
class NoRawAlertDialog extends DartLintRule {
  NoRawAlertDialog() : super(code: _code);

  static const _code = LintCode(
    name: 'no_raw_alert_dialog',
    problemMessage: '禁止裸 AlertDialog / Dialog——中心化弹窗一律用 AppDialog '
        '（confirm/alert/progress/input/announcement），底部弹层用 showAppSheet，'
        '顶部通知用 showAppSnackBar',
    correctionMessage: "import '../../../shared/widgets/app_dialog.dart' 后改用 "
        'AppDialog.confirm/alert/progress/input/announcement；复杂弹窗加 '
        '「no_raw_alert_dialog 白名单：…原因」注释豁免',
    errorSeverity: ErrorSeverity.ERROR,
  );

  /// 被禁止的 Material 弹窗组件。
  static const _banned = {'AlertDialog', 'Dialog', 'SimpleDialog'};

  /// 设计系统实现自身。
  static const _exemptPaths = [
    '/shared/widgets/app_dialog.dart',
    '/shared/widgets/app_sheet.dart',
  ];

  @override
  void run(
    CustomLintResolver resolver,
    ErrorReporter reporter,
    CustomLintContext context,
  ) {
    if (resolver.inExemptDir ||
        _exemptPaths.any(resolver.path.contains) ||
        resolver.source.contents.data.contains('no_raw_alert_dialog 白名单')) {
      return;
    }
    context.registry.addInstanceCreationExpression((node) {
      final type = node.constructorName.type.toString();
      if (_banned.contains(type)) {
        reporter.reportErrorForNode(code, node.constructorName.type);
      }
    });
  }
}

/// 规则 7 `no_manual_listview_padding`：禁止页面级手写 ListView(padding:)。
///
/// 只在 *_page.dart 文件中检测，组件内部 ListView 不受限。
/// 页面列表一律走 `AppListView` / `AppListViewBuilder`（水平 padding 固定 16）。
class NoManualListviewPadding extends DartLintRule {
  NoManualListviewPadding() : super(code: _code);

  static const _code = LintCode(
    name: 'no_manual_listview_padding',
    problemMessage: '禁止页面级手写 ListView(padding:)——列表一律用 AppListView / '
        'AppListViewBuilder（水平 padding 固定 16，防止双层 padding 导致卡片过窄）',
    correctionMessage: "import '../../../shared/widgets/app_list_view.dart' 后改用 "
        'AppListView(children: [...]) 或 AppListViewBuilder(itemCount: ..., itemBuilder: ...)',
    errorSeverity: ErrorSeverity.ERROR,
  );

  /// 设计系统实现自身。
  static const _exemptPaths = ['/shared/widgets/app_list_view.dart'];

  @override
  void run(
    CustomLintResolver resolver,
    ErrorReporter reporter,
    CustomLintContext context,
  ) {
    // 只查页面文件
    if (!resolver.path.endsWith('_page.dart')) return;
    if (resolver.inExemptDir ||
        _exemptPaths.any(resolver.path.contains) ||
        resolver.source.contents.data.contains('no_manual_listview_padding 白名单')) {
      return;
    }
    context.registry.addInstanceCreationExpression((node) {
      final type = node.constructorName.type.toString();
      if (type != 'ListView' && type != 'ListView.builder' && type != 'ListView.separated') return;
      // 检查是否有 padding 参数
      final hasPadding = node.argumentList.arguments.any(
        (arg) => arg is NamedExpression && arg.name.label.name == 'padding',
      );
      if (hasPadding) {
        reporter.reportErrorForNode(code, node.constructorName.type);
      }
    });
  }
}

/// 规则 8 `no_scrollable_false_without_selfscrolling`：禁止
/// `AppPage(scrollable: false)` 而不用 `AppPage.selfScrolling`。
///
/// body 内部自带滚动容器时必须用 selfScrolling 命名构造（自动 bodyPadding:zero）。
/// 特例（body 无滚动容器、靠 AppPage bodyPadding 提供边距）加白名单注释豁免。
class NoScrollableFalseWithoutSelfscrolling extends DartLintRule {
  NoScrollableFalseWithoutSelfscrolling() : super(code: _code);

  static const _code = LintCode(
    name: 'no_scrollable_false_without_selfscrolling',
    problemMessage: '禁止 AppPage(scrollable: false)——body 自带滚动容器时一律用 '
        'AppPage.selfScrolling(...)（自动 bodyPadding:zero，防止双层 padding）',
    correctionMessage: '改用 AppPage.selfScrolling(title: ..., body: ...)；'
        '若 body 无滚动容器需保留 bodyPadding，加 '
        '「no_scrollable_false_without_selfscrolling 白名单：…原因」注释豁免',
    errorSeverity: ErrorSeverity.ERROR,
  );

  @override
  void run(
    CustomLintResolver resolver,
    ErrorReporter reporter,
    CustomLintContext context,
  ) {
    if (resolver.inExemptDir ||
        resolver.source.contents.data
            .contains('no_scrollable_false_without_selfscrolling 白名单')) {
      return;
    }
    context.registry.addInstanceCreationExpression((node) {
      final type = node.constructorName.type.toString();
      // 只查 AppPage（非 selfScrolling 命名构造）
      if (type != 'AppPage') return;
      // 检查是否有 scrollable: false 参数
      final hasScrollableFalse = node.argumentList.arguments.any((arg) {
        if (arg is! NamedExpression) return false;
        if (arg.name.label.name != 'scrollable') return false;
        return arg.expression.toString() == 'false';
      });
      if (hasScrollableFalse) {
        reporter.reportErrorForNode(code, node.constructorName.type);
      }
    });
  }
}
