import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/models/chat_message.dart';
import '../../../core/models/conversation.dart';
import '../../../core/providers/assistant_provider.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../core/services/chat/chat_service.dart';
import '../../../core/services/api/chat_api_service.dart';
import '../../../shared/widgets/snackbar.dart';
import '../../chat/widgets/chat_message_widget.dart';
import '../../home/widgets/chat_input_bar.dart';
import '../../../core/models/chat_input_data.dart';

/// 聊天页 —— 从 HomePage 搬核心聊天逻辑。
///
/// 真实功能（完整可用）：消息列表渲染、发送消息、流式输出、消息持久化。
/// 高级功能（reasoning / tool events / translation / MCP / 消息版本管理）
/// 在 HomePage 有完整实现，逐步迁移到此页面。
class ChatPage extends StatefulWidget {
  final String conversationId;
  const ChatPage({super.key, required this.conversationId});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  Conversation? _conversation;
  List<ChatMessage> _messages = [];
  final Set<String> _loadingIds = {};
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _loadConversation();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ChatService>().addListener(_onChatChanged);
    });
  }

  @override
  void dispose() {
    context.read<ChatService>().removeListener(_onChatChanged);
    _scrollController.dispose();
    super.dispose();
  }

  void _onChatChanged() {
    if (!mounted) return;
    _loadConversation();
  }

  void _loadConversation() {
    final chatService = context.read<ChatService>();
    final convo = chatService.getConversation(widget.conversationId);
    if (convo != null) {
      final msgs = chatService.getMessages(widget.conversationId);
      setState(() {
        _conversation = convo;
        _messages = List.of(msgs);
      });
      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
      );
    });
  }

  bool get _isLoading => _loadingIds.contains(widget.conversationId);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final assistant = context.watch<AssistantProvider>().currentAssistant;
    final settings = context.watch<SettingsProvider>();

    final title = (_conversation?.title ?? '').trim().isNotEmpty
        ? _conversation!.title
        : 'Chat';

    final providerKey = assistant?.chatModelProvider ?? settings.currentModelProvider;
    final modelId = assistant?.chatModelId ?? settings.currentModelId;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title, overflow: TextOverflow.ellipsis, maxLines: 1),
            if (providerKey != null && modelId != null)
              Text(
                modelId,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: cs.onSurface.withOpacity(0.5),
                    ),
                overflow: TextOverflow.ellipsis,
              ),
          ],
        ),
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
      ),
      body: Column(
        children: [
          // 消息列表（复用 ChatMessageWidget）
          Expanded(
            child: _messages.isEmpty
                ? const _EmptyChat()
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      final msg = _messages[index];
                      return ChatMessageWidget(
                        message: msg,
                        assistantName: assistant?.name,
                        showModelIcon: false,
                        showUserAvatar: false,
                        onRegenerate: msg.role == 'assistant' && !msg.isStreaming
                            ? () => _regenerate(index)
                            : null,
                        onResend: msg.role == 'user'
                            ? () => _resend(index)
                            : null,
                      );
                    },
                  ),
          ),
          // 输入栏（复用 ChatInputBar）
          ChatInputBar(
            onSend: _sendMessage,
            onStop: _cancelStreaming,
            loading: _isLoading,
          ),
        ],
      ),
    );
  }

  // ── 发送消息（从 HomePage 搬核心逻辑，用真实 API）──

  Future<void> _sendMessage(ChatInputData input) async {
    final content = input.text.trim();
    if (content.isEmpty && input.imagePaths.isEmpty && input.documents.isEmpty) return;
    if (_conversation == null) return;

    final chatService = context.read<ChatService>();
    final settings = context.read<SettingsProvider>();
    final assistant = context.read<AssistantProvider>().currentAssistant;

    final providerKey = assistant?.chatModelProvider ?? settings.currentModelProvider;
    final modelId = assistant?.chatModelId ?? settings.currentModelId;

    if (providerKey == null || modelId == null) {
      showAppSnackBar(
        context,
        message: 'Please select a model first',
        type: NotificationType.warning,
      );
      return;
    }

    // 用户消息
    final imageMarkers = input.imagePaths.map((p) => '\n[image:$p]').join();
    final docMarkers = input.documents.map((d) => '\n[file:${d.path}|${d.fileName}|${d.mime}]').join();
    final userMessage = await chatService.addMessage(
      conversationId: _conversation!.id,
      role: 'user',
      content: content + imageMarkers + docMarkers,
    );

    setState(() {
      _messages.add(userMessage);
      _loadingIds.add(_conversation!.id);
    });
    _scrollToBottom();

    // 助手占位消息
    final assistantMessage = await chatService.addMessage(
      conversationId: _conversation!.id,
      role: 'assistant',
      content: '',
      modelId: modelId,
      providerId: providerKey,
      isStreaming: true,
    );

    setState(() => _messages.add(assistantMessage));
    _scrollToBottom();

    // 构建 API messages（HomePage 真实逻辑：ChatMessage → Map）
    final apiMessages = _messages
        .where((m) => m.id != assistantMessage.id && m.content.isNotEmpty)
        .map((m) => {
              'role': m.role == 'assistant' ? 'assistant' : 'user',
              'content': m.content,
            })
        .toList();

    // 发送流式请求（用 HomePage 真实的调用方式）
    final config = settings.getProviderConfig(providerKey);
    final stream = ChatApiService.sendMessageStream(
      config: config,
      modelId: modelId,
      messages: apiMessages,
      userImagePaths: input.imagePaths.isEmpty ? null : input.imagePaths,
      thinkingBudget: assistant?.thinkingBudget ?? settings.thinkingBudget,
      temperature: assistant?.temperature,
      topP: assistant?.topP,
      maxTokens: assistant?.maxTokens,
    );

    String fullContent = '';
    try {
      await for (final chunk in stream) {
        fullContent += chunk.content;
        await chatService.updateMessage(assistantMessage.id, content: fullContent);
        if (mounted) {
          setState(() {
            final idx = _messages.indexWhere((m) => m.id == assistantMessage.id);
            if (idx != -1) {
              _messages[idx] = _messages[idx].copyWith(content: fullContent);
            }
          });
          _scrollToBottom();
        }
      }
      // 完成
      await chatService.updateMessage(assistantMessage.id, isStreaming: false);
      if (mounted) {
        setState(() {
          _loadingIds.remove(_conversation!.id);
          final idx = _messages.indexWhere((m) => m.id == assistantMessage.id);
          if (idx != -1) {
            _messages[idx] = _messages[idx].copyWith(isStreaming: false);
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadingIds.remove(_conversation!.id);
          final idx = _messages.indexWhere((m) => m.id == assistantMessage.id);
          if (idx != -1) {
            _messages[idx] = _messages[idx].copyWith(
              isStreaming: false,
              content: fullContent.isNotEmpty
                  ? '$fullContent\n\n[Error: $e]'
                  : '[Error: $e]',
            );
          }
        });
        showAppSnackBar(
          context,
          message: 'Generation failed: $e',
          type: NotificationType.error,
        );
      }
    }
  }

  Future<void> _cancelStreaming() async {
    final chatService = context.read<ChatService>();
    if (_conversation != null) {
      setState(() => _loadingIds.remove(_conversation!.id));
      final msgs = chatService.getMessages(_conversation!.id);
      for (final m in msgs) {
        if (m.isStreaming) {
          await chatService.updateMessage(m.id, isStreaming: false);
        }
      }
      if (mounted) setState(() {});
    }
  }

  Future<void> _regenerate(int msgIndex) async {
    if (msgIndex <= 0) return;
    int? lastUserIdx;
    for (var i = msgIndex - 1; i >= 0; i--) {
      if (_messages[i].role == 'user') {
        lastUserIdx = i;
        break;
      }
    }
    if (lastUserIdx == null) return;
    final userMsg = _messages[lastUserIdx];
    await _sendMessage(ChatInputData(text: userMsg.content));
  }

  Future<void> _resend(int msgIndex) async {
    final msg = _messages[msgIndex];
    await _sendMessage(ChatInputData(text: msg.content));
  }
}

class _EmptyChat extends StatelessWidget {
  const _EmptyChat();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: cs.primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Icon(Icons.chat, size: 36, color: cs.primary),
          ),
          const SizedBox(height: 16),
          Text(
            'Start a conversation',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          Text(
            'Type a message below',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: cs.onSurface.withOpacity(0.5),
                ),
          ),
        ],
      ),
    );
  }
}
