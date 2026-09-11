import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/error/error.dart';
import 'package:analyzer/error/listener.dart';
import 'package:custom_lint_builder/custom_lint_builder.dart';

/// 禁止 print 调用
///
/// 检测对顶层 `print()` 函数的直接调用。
/// 不包括 `debugPrint`、`Logger`、或其他对象的 print 方法调用。
class NoPrintRule extends DartLintRule {
  static const LintCode _code = LintCode(
    name: 'no_print_call',
    problemMessage: '禁止使用 print()，请使用 Logger.d/i/w/e',
    errorSeverity: ErrorSeverity.WARNING,
  );

  const NoPrintRule() : super(code: _code);

  @override
  void run(
    CustomLintResolver resolver,
    ErrorReporter reporter,
    CustomLintContext context,
  ) {
    context.registry.addMethodInvocation((MethodInvocation node) {
      // 只检测顶层调用：target 为 null 表示无对象前缀
      if (node.target != null) return;

      // 方法名必须是 print
      if (node.methodName.name != 'print') return;

      reporter.reportErrorForNode(_code, node);
    });
  }
}
