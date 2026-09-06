import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../l10n/app_localizations.dart';
import '../../../core/models/chat_message.dart';
import '../../../core/models/conversation.dart';
import '../../../core/providers/assistant_provider.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../core/providers/user_provider.dart';
import '../../../core/services/chat/chat_service.dart';
import '../../../core/services/api/chat_api_service.dart';
import '../../../shared/widgets/snackbar.dart';
import '../../chat/widgets/chat_message_widget.dart';
import '../../home/widgets/chat_input_bar.dart';
import '../../home/widgets/side_drawer.dart';
import '../../../core/models/chat_input_data.dart';

/// 聊天页 —— 完整迁移自 HomePage（消息渲染 + 流式 + 持久化 + 侧边栏）。
///
/// Push 到根 Navigator（parentNavigatorKey = root），覆盖底栏骨架。
/// 带右侧 EndDrawer（对话历史/助手选择），顶栏右侧有新建对话按钮。
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

  Future<void> _newChat() async {
    final chatService = context.read<ChatService>();
    final convo = await chatService.createConversation();
    if (mounted) {
      // 用 go 替换当前 ChatPage（保持在根 Navigator）
      context.go('/chat/${convo.id}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final assistant = context.watch<AssistantProvider>().currentAssistant;
    final settings = context.watch<SettingsProvider>();
    final chatService = context.watch<ChatService>();
    final userName = context.watch<UserProvider>().name;

    final title = (_conversation?.title ?? '').trim().isNotEmpty
        ? _conversation!.title
        : l10n.chatPageTitle;

    final providerKey = assistant?.chatModelProvider ?? settings.currentModelProvider;
    final modelId = assistant?.chatModelId ?? settings.currentModelId;
    final assistantName = assistant?.name.trim() ?? l10n.mobileDrawerGuest;

    return Scaffold(
      endDrawer: SideDrawer(
        userName: userName.isEmpty ? l10n.mobileDrawerGuest : userName,
        assistantName: assistantName,
        loadingConversationIds: _loadingIds,
        onSelectConversation: (id) {
          Scaffold.of(context).closeEndDrawer();
          if (id != widget.conversationId) {
            context.go('/chat/$id');
          }
        },
        onNewConversation: () async {
          Scaffold.of(context).closeEndDrawer();
          final convo = await chatService.createConversation();
          if (mounted) context.go('/chat/${convo.id}');
        },
      ),
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
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
        actions: [
          // 新建对话
          IconButton(
            icon: const Icon(Icons.add_rounded),
            tooltip: l10n.chatServiceDefaultConversationTitle,
            onPressed: _newChat,
          ),
          // 右侧边栏按钮（对话历史/助手列表）
          IconButton(
            icon: const Icon(Icons.menu_open_rounded),
            onPressed: () => Scaffold.of(context).openEndDrawer(),
          ),
        ],
      ),
      body: Column(
        children: [
          // 消息列表
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
          // 输入栏
          ChatInputBar(
            onSend: _sendMessage,
            onStop: _cancelStreaming,
            loading: _isLoading,
          ),
        ],
      ),
    );
  }

  // ── 发送消息 ──

  Future<void> _sendMessage(ChatInputData input) async {
    final content = input.text.trim();
    if (content.isEmpty && input.imagePaths.isEmpty && input.documents.isEmpty) return;
    if (_conversation == null) return;

    final chatService = context.read<ChatService>();
    final settings = context.read<SettingsProvider>();
    final assistant = context.read<AssistantProvider>().currentAssistant;
    final l10n = AppLocalizations.of(context)!;

    final providerKey = assistant?.chatModelProvider ?? settings.currentModelProvider;
    final modelId = assistant?.chatModelId ?? settings.currentModelId;

    if (providerKey == null || modelId == null) {
      showAppSnackBar(
        context,
        message: l10n.chatPleaseSelectModel,
        type: NotificationType.warning,
      );
      return;
    }

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

    final apiMessages = _messages
        .where((m) => m.id != assistantMessage.id && m.content.isNotEmpty)
        .map((m) => {
              'role': m.role == 'assistant' ? 'assistant' : 'user',
              'content': m.content,
            })
        .toList();

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
        final l10n = AppLocalizations.of(context)!;
        setState(() {
          _loadingIds.remove(_conversation!.id);
          final idx = _messages.indexWhere((m) => m.id == assistantMessage.id);
          if (idx != -1) {
            _messages[idx] = _messages[idx].copyWith(
              isStreaming: false,
              content: fullContent.isNotEmpty
                  ? '$fullContent\n\n${l10n.chatGenerationFailed(e.toString())}'
                  : l10n.chatGenerationFailed(e.toString()),
            );
          }
        });
        showAppSnackBar(
          context,
          message: l10n.chatGenerationFailed(e.toString()),
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
    final l10n = AppLocalizations.of(context)!;
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
            l10n.chatEmptyTitle,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          Text(
            l10n.chatEmptySubtitle,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: cs.onSurface.withOpacity(0.5),
                ),
          ),
        ],
      ),
    );
  }
}
