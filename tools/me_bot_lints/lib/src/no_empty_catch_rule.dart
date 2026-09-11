import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/error/error.dart';
import 'package:analyzer/error/listener.dart';
import 'package:custom_lint_builder/custom_lint_builder.dart';

/// 禁止空 catch 块
///
/// 检测 `catch` 块体为空（没有任何 statement）的情况。
/// 如果 catch 块内包含 `// ignore:` 或 `// intentionally` 注释，则不报告。
class NoEmptyCatchRule extends DartLintRule {
  static const LintCode _code = LintCode(
    name: 'no_empty_catch',
    problemMessage:
        '空 catch 块会静默吞掉异常，请至少添加 Logger.d/w 或注释说明忽略原因',
    // INFO 级：历史存量空 catch 较多，先作为建议性提示，不阻塞 analyze 门禁；
    // 后续逐处补 Logger.d/w 后再逐步升级为 WARNING。
    errorSeverity: ErrorSeverity.INFO,
  );

  const NoEmptyCatchRule() : super(code: _code);

  @override
  void run(
    CustomLintResolver resolver,
    ErrorReporter reporter,
    CustomLintContext context,
  ) {
    context.registry.addCatchClause((CatchClause node) {
      final body = node.body;

      // 只关心空 block（没有任何 statement）
      if (body.statements.isNotEmpty) return;

      // 检查 catch 块内是否有豁免注释
      if (_hasAllowComment(body)) return;

      reporter.reportErrorForNode(_code, body);
    });
  }

  /// 检查空 block 内部是否包含 `// ignore:` 或 `// intentionally` 注释。
  bool _hasAllowComment(Block block) {
    Token? token = block.leftBracket;
    while (token != null && token != block.rightBracket) {
      if (_containsAllowComment(token.precedingComments)) return true;
      token = token.next;
    }
    // 检查 rightBracket 前方的注释（闭合大括号前的注释）
    if (_containsAllowComment(block.rightBracket.precedingComments)) {
      return true;
    }
    return false;
  }

  /// 沿注释链查找是否包含豁免关键词
  bool _containsAllowComment(Token? comment) {
    Token? current = comment;
    while (current != null) {
      final lexeme = current.lexeme.toLowerCase();
      if (lexeme.contains('ignore:') || lexeme.contains('intentionally')) {
        return true;
      }
      current = current.next;
    }
    return false;
  }
}
