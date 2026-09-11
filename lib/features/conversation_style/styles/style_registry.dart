import '../framework/style_renderer_registry.dart';
import '../models/conversation_style.dart';
import 'classic_bubble_renderer.dart';
import 'full_width_document_renderer.dart';
import 'minimal_stream_renderer.dart';
import 'card_stack_renderer.dart';
import 'agent_three_tier_renderer.dart';
import 'tool_card_flow_renderer.dart';
import 'think_act_observe_renderer.dart';
import 'terminal_renderer.dart';
import 'multi_assistant_renderer.dart';
import 'rich_content_renderer.dart';
import 'generative_ui_renderer.dart';
import 'thread_branching_renderer.dart';
import 'context_panel_renderer.dart';
import 'plan_surface_renderer.dart';
import 'canvas_artifact_renderer.dart';

/// 注册所有 15 种样式到 StyleRendererRegistry
///
/// 调用此函数后，registry 中包含所有样式的工厂函数，
/// 支持 lazy load（首次访问时才实例化）。
void registerAllStyles(StyleRendererRegistry registry) {
  registry.registerAll({
    ConversationStyle.classicBubble: () => ClassicBubbleRenderer(),
    ConversationStyle.fullWidthDocument: () => FullWidthDocumentRenderer(),
    ConversationStyle.minimalStream: () => MinimalStreamRenderer(),
    ConversationStyle.cardStack: () => CardStackRenderer(),
    ConversationStyle.agentThreeTier: () => AgentThreeTierRenderer(),
    ConversationStyle.toolCardFlow: () => ToolCardFlowRenderer(),
    ConversationStyle.thinkActObserve: () => ThinkActObserveRenderer(),
    ConversationStyle.terminal: () => TerminalRenderer(),
    ConversationStyle.multiAssistant: () => MultiAssistantRenderer(),
    ConversationStyle.richContent: () => RichContentRenderer(),
    ConversationStyle.generativeUi: () => GenerativeUiRenderer(),
    ConversationStyle.threadBranching: () => ThreadBranchingRenderer(),
    ConversationStyle.contextPanel: () => ContextPanelRenderer(),
    ConversationStyle.planSurface: () => PlanSurfaceRenderer(),
    ConversationStyle.canvasArtifact: () => CanvasArtifactRenderer(),
  });
}
