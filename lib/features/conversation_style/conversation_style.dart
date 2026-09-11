/// 对话流样式系统 —— 统一导出
///
/// 提供 15 种对话流样式的完整实现，支持样式切换、自动推荐、
/// 错误降级等功能。
library;

// 数据模型
export 'models/message_part.dart';
export 'models/conversation_style.dart';
export 'models/conversation_state.dart';
export 'models/style_settings.dart';

// 数据层
export 'data/conversation_data_source.dart';
export 'data/hive_conversation_data_source.dart';

// 框架
export 'framework/style_renderer.dart';
export 'framework/style_renderer_registry.dart';
export 'framework/style_resolver.dart';
export 'framework/style_switcher.dart';
export 'framework/style_error_boundary.dart';
export 'framework/conversation_view.dart';

// 共享组件
export 'widgets/shared_message_part_renderers.dart';

// 样式实现
export 'styles/classic_bubble_renderer.dart';
export 'styles/full_width_document_renderer.dart';
export 'styles/minimal_stream_renderer.dart';
export 'styles/card_stack_renderer.dart';
export 'styles/agent_three_tier_renderer.dart';
export 'styles/tool_card_flow_renderer.dart';
export 'styles/think_act_observe_renderer.dart';
export 'styles/terminal_renderer.dart';
export 'styles/multi_assistant_renderer.dart';
export 'styles/rich_content_renderer.dart';
export 'styles/generative_ui_renderer.dart';
export 'styles/thread_branching_renderer.dart';
export 'styles/context_panel_renderer.dart';
export 'styles/plan_surface_renderer.dart';
export 'styles/canvas_artifact_renderer.dart';

// 样式注册
export 'styles/style_registry.dart';
