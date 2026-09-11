import 'package:custom_lint_builder/custom_lint_builder.dart';

import 'src/no_empty_catch_rule.dart';
import 'src/no_print_rule.dart';

/// Me-Bot 自定义 lint 插件入口。
///
/// 由 analyzer 插件系统调用，注册项目中所有自定义 lint 规则。
/// 规则列表在此处集中管理，新增规则时只需在 getLintRules 中追加即可。
///
/// 规则清单：
/// - `no_empty_catch`（warning）：禁止空 catch 块
/// - `no_print_call`（warning）：禁止顶层 print() 调用
PluginBase createPlugin() => _MeBotLintPlugin();

class _MeBotLintPlugin extends PluginBase {
  @override
  List<LintRule> getLintRules(CustomLintConfigs configs) => const [
        NoEmptyCatchRule(),
        NoPrintRule(),
      ];
}
