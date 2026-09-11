// ignore_for_file: hardcoded_ui_string
import '../models/conversation_style.dart';

/// 样式系统集中文案
///
/// P2 阶段先把散落在各渲染器/组件里的中文文案集中到此处，
/// 预留未来接入 ARB/l10n 的统一替换点（一处改，处处生效）。
/// 字符串标识符英文，值为默认中文。
class StyleL10n {
  const StyleL10n._();

  // 通用
  static const String switchStyleTooltip = '切换对话样式';
  static const String expandedFullText = '展开全文';
  static const String collapse = '收起';

  // 长按菜单
  static const String menuCopy = '复制内容';
  static const String menuQuote = '引用回复';
  static const String menuRetry = '重新生成';
  static const String menuShare = '分享';
  static const String menuDelete = '删除';
  static const String copied = '已复制';
  static const String deleted = '已删除';

  // 切换提示
  static String switchedTo(String displayName) => '已切换为 $displayName';

  // 错误恢复
  static const String sendFailed = '发送失败';
  static const String retrySend = '重试';
  static const String continueGenerating = '继续生成';
  static const String toolFailed = '工具调用失败';
  static const String waitingApproval = '等待审批';
  static const String approved = '已批准';
  static const String rejected = '已拒绝';

  // 设置页
  static const String styleSettingsTitle = '对话样式';
  static const String autoMode = '自动选择样式';
  static const String autoModeDesc = '根据对话内容特征自动推荐最合适的样式';
  static const String chooseDefaultStyle = '选择默认样式';
  static const String current = '当前';
  static const String tipBottomBar = '也可以在对话页右上角随时切换，切换仅对当前会话生效。';
  static const String resetLearning = '重置学习数据';
  static const String noUsageData = '暂无使用数据，切换行为将用于优化推荐';
  static String mostUsed(String displayName, int pct) =>
      '你最常使用：$displayName（$pct%）';

  // 无障碍
  static String userMessageSemantic(String time) => '用户消息，时间：$time';
  static String assistantMessageSemantic(String time) => '助手消息，时间：$time';
  static const String userAvatarSemantic = '用户头像';
  static const String assistantAvatarSemantic = '助手头像';
  static const String copyActionSemantic = '复制消息内容';
  static const String quoteActionSemantic = '引用回复此消息';
  static const String retryActionSemantic = '重新生成此消息';
  static const String shareActionSemantic = '分享此消息';
  static const String deleteActionSemantic = '删除此消息';

  /// 样式名（占位：实际由 StyleMetaRegistry.displayName 提供，此处仅兜底）
  static String styleName(ConversationStyle s) => s.name;
}
