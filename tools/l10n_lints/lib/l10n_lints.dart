import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/error/error.dart';
import 'package:analyzer/error/listener.dart';
import 'package:custom_lint_builder/custom_lint_builder.dart';

/// Me-Bot l10n 自定义 lint。
///
/// 规则 1 `hardcoded_ui_string`：UI widget 参数位出现含中文的字符串字面量
///   → 语言遗漏的实时红线（IDE 波浪线 + CI）。项目 UI 主语言为中文，
///   硬编码中文几乎必然意味着「英文环境漏译」，因此只查 CJK，噪音低。
///   服务层日志/异常按约定不进 arb，也不在 widget 参数位，天然不受影响。
///
/// 规则 2 `l10n_no_field_cache`：把 AppLocalizations 存进字段/缓存
///   → 语言切换后旧文案不刷新的头号坑，直接禁止。
PluginBase createPlugin() => _MeBotL10nLints();

class _MeBotL10nLints extends PluginBase {
  @override
  List<LintRule> getLintRules(CustomLintConfigs configs) => [
        HardcodedUiString(),
        L10nNoFieldCache(),
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
