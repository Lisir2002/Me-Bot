// ──────────────────────────────────────────────────────────────
// 迁移到 AppPage 骨架（批次 4 第 2 页，1405 → 见下方行数）
//
//   Scaffold + AppBar + ListView        → AppPage(title / leading / actions / body)
//   _iosSectionCard / _iosDivider       → AppSectionCard / AppSectionDivider（shared）
//   _iosNavRow                          → AppNavRow（shared）
//   _iosSwitchRow                       → AppSwitchRow（shared，原「待办 E」落地）
//   _TactileRow / _AnimatedPressColor   → IosTactileRow / IosPressColor
//   _TactileIconButton                  → IosIconButton(haptics: true, minSize: 44)
//   _TactileTextButton                  → IosIconButton(builder:) 渲染文字
//   showModalBottomSheet ×3             → showAppSheet / AppSheet
//
// ⚠️ body 是 Column + crossAxisAlignment.stretch —— scrollable 模式下子部件拿到
//    「无界高度 + 紧凑宽度」，不 stretch 卡片会缩到内容宽度（清单 3d）。
// ⚠️ 三处弹层都**没有**用 AppSheet 的 title 槽位：它们的标题是居中/三段式的，
//    而 AppSheet.title 是 Align(centerLeft)。故 title 留空、把居中标题作为
//    第一个 child，其余（把手 / 滚动 / 键盘避让 / 最大高度）交给模板（经验 #38）。
// ⚠️ _RemoteListSheet 是 DraggableScrollableSheet —— 超出 AppSheet 模板能力，
//    只把外层换成 showAppSheet（safeArea + 键盘避让），内部保持自建。
//
// 保留私有的：`_SmallTactileIcon`（0.7 按压透明度 + soft 触觉，无共享对应件，
// 见经验 #16）、`_IosOutlineButton` / `_IosFilledButton` / `_InputRow` /
// `_PasswordToggleButton` / `_ActionCard` / `_SnapshotNavRow`。
// ──────────────────────────────────────────────────────────────
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/snackbar.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../icons/lucide_adapter.dart';
import '../../../shared/animations/widgets.dart';
import '../../../core/services/haptics.dart';
import '../../../core/models/backup.dart';
import '../../../core/providers/backup_provider.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../core/services/chat/chat_service.dart';
import '../../../core/services/backup/cherry_importer.dart';
import '../../../core/services/backup/backup_encryptor.dart';
import '../../../core/services/backup/credential_bridge.dart';
import '../../../utils/app_directories.dart';
import '../../../shared/widgets/app_page.dart';
import '../../../shared/widgets/app_sheet.dart';
import '../../../shared/widgets/app_section.dart';
import '../../../shared/widgets/ios_tactile.dart';
import '../../../theme/design_tokens.dart';
import '../../storage/pages/local_snapshot_page.dart';
import '../widgets/backup_progress_card.dart';

// File size formatter (B, KB, MB, GB)
String _fmtBytes(int bytes) {
  const kb = 1024;
  const mb = kb * 1024;
  const gb = mb * 1024;
  if (bytes >= gb) return '${(bytes / gb).toStringAsFixed(2)} GB';
  if (bytes >= mb) return '${(bytes / mb).toStringAsFixed(2)} MB';
  if (bytes >= kb) return '${(bytes / kb).toStringAsFixed(2)} KB';
  return '$bytes B';
}

class BackupPage extends StatefulWidget {
  const BackupPage({super.key});

  @override
  State<BackupPage> createState() => _BackupPageState();
}

class _BackupPageState extends State<BackupPage> {
  List<BackupFileItem> _remote = const <BackupFileItem>[];
  bool _loadingRemote = false;
  bool _remindBackup = false;

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _remindBackup = prefs.getBool('backup_remind_me') ?? false;
    });
  }

  Future<bool?> _confirmCherryImport(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final locale = Localizations.localeOf(context);
    final isZh = locale.languageCode.startsWith('zh');
    final String body = isZh
        ? '此功能目前仍处于实验阶段。\n目前仅能导入助手，对话内容，供应商和文件，\n一些供应商需要在baseurl后面添加/v1 or /v1beta。 \n为确保数据安全，建议在导入前先执行备份。\n是否已知晓并继续选择文件？'
        : 'This feature is experimental.\nTo keep your data safe, it is recommended to back up before importing.\nProceed to choose a file?';

    return showAppSheet<bool>(
      context: context,
      builder: AppSheet(
        // ignore: sort_child_properties_last —— AppSheet 语义顺序是 title → children → footer，与 lint 的「children 放最后」冲突
        contentPadding: const EdgeInsets.fromLTRB(AppGap.md, AppGap.sm, AppGap.md, AppGap.md),
        children: [
          Center(
            child: Text(
              l10n.backupPageImportFromCherryStudio,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(height: AppGap.sm),
          Text(
            body,
            style: TextStyle(fontSize: 14, height: 1.35, color: cs.onSurface.withOpacity(0.72)),
          ),
        ],
        footer: Row(
          children: [
            Expanded(
              child: _IosOutlineButton(
                label: l10n.backupPageCancel,
                onTap: () => Navigator.of(context).pop(false),
              ),
            ),
            const SizedBox(width: AppGap.sm),
            Expanded(
              child: _IosFilledButton(
                label: l10n.backupPageOK,
                onTap: () => Navigator.of(context).pop(true),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<RestoreMode?> _chooseImportModeDialog(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? Colors.white10 : const Color(0xFFF7F7F9);

    return showDialog<RestoreMode>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.backupPageSelectImportMode),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _ActionCard(
              color: cardColor,
              icon: Lucide.RotateCw,
              title: l10n.backupPageOverwriteMode,
              subtitle: l10n.backupPageOverwriteModeDescription,
              onTap: () => Navigator.of(ctx).pop(RestoreMode.overwrite),
            ),
            const SizedBox(height: 10),
            _ActionCard(
              color: cardColor,
              icon: Lucide.GitFork,
              title: l10n.backupPageMergeMode,
              subtitle: l10n.backupPageMergeModeDescription,
              onTap: () => Navigator.of(ctx).pop(RestoreMode.merge),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(l10n.backupPageCancel),
          ),
        ],
      ),
    );
  }

  // ===== PR-4 加密备份相关 UI =====

  /// 选择导出策略：脱敏（不含密钥）/ 加密（含密钥，需口令）。
  Future<BackupCredentialPolicy?> _chooseExportPolicyDialog(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? Colors.white10 : const Color(0xFFF7F7F9);
    return showDialog<BackupCredentialPolicy>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.backupEncryptPolicy),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _ActionCard(
              color: cardColor,
              icon: Lucide.EyeOff,
              title: l10n.backupExportRedacted,
              subtitle: l10n.backupExportRedactedDesc,
              onTap: () => Navigator.of(ctx).pop(BackupCredentialPolicy.redacted),
            ),
            const SizedBox(height: 10),
            _ActionCard(
              color: cardColor,
              icon: Icons.lock,
              title: l10n.backupExportEncrypted,
              subtitle: l10n.backupExportEncryptedDesc,
              onTap: () => Navigator.of(ctx).pop(BackupCredentialPolicy.encrypted),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(l10n.backupPageCancel),
          ),
        ],
      ),
    );
  }

  /// 输入备份口令。
  /// [confirm]=true 要求输入两次并校验一致与最短长度（导出加密用）；
  /// [confirm]=false 仅单次输入（导入解密用）。取消返回 null。
  Future<String?> _promptPassphrase(BuildContext context, {bool confirm = false}) {
    final l10n = AppLocalizations.of(context)!;
    final controller = TextEditingController();
    final confirmController = TextEditingController();
    var obscured = true;
    final formKey = GlobalKey<FormState>();
    return showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx2, setState) => AlertDialog(
          title: Text(confirm ? l10n.backupPassphrase : l10n.backupEnterPassphrase),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: controller,
                  obscureText: obscured,
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText: l10n.backupPassphrase,
                    helperText: l10n.backupPassphraseHint,
                    helperMaxLines: 2,
                    suffixIcon: IconButton(
                      icon: Icon(obscured ? Lucide.Eye : Lucide.EyeOff),
                      onPressed: () => setState(() => obscured = !obscured),
                    ),
                  ),
                  validator: (v) => (v == null || v.length < BackupEncryptor.minPassphraseLength)
                      ? l10n.backupPassphraseHint
                      : null,
                ),
                if (confirm) ...[
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: confirmController,
                    obscureText: obscured,
                    decoration: InputDecoration(labelText: l10n.backupPassphraseConfirm),
                    validator: (v) =>
                        v != controller.text ? l10n.backupPassphraseMismatch : null,
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(l10n.backupPageCancel),
            ),
            TextButton(
              onPressed: () {
                if (formKey.currentState?.validate() != true) return;
                Navigator.of(ctx).pop(controller.text);
              },
              child: Text(l10n.backupPageSave),
            ),
          ],
        ),
      ),
    );
  }

  void _showError(BuildContext context, String msg) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  /// 运行一次导入任务，遇到加密备份缺口令时弹窗索要并重试；口令错误提示后放弃。
  /// [task] 内部应已包裹导入遮罩（_runWithImportingOverlay）。返回是否成功导入。
  Future<bool> _restoreEncryptedAware(
    BuildContext context,
    Future<void> Function(String? passphrase) task,
  ) async {
    try {
      await task(null);
      return true;
    } on BackupCryptoError catch (e) {
      if (!context.mounted) return false;
      final l10n = AppLocalizations.of(context)!;
      if (e.kind == BackupCryptoErrorKind.needPassphrase) {
        final pass = await _promptPassphrase(context, confirm: false);
        if (pass == null) return false;
        try {
          await task(pass);
          return true;
        } on BackupCryptoError catch (e2) {
          if (!context.mounted) return false;
          if (e2.kind == BackupCryptoErrorKind.wrongPassphrase) {
            _showError(context, l10n.backupPassphraseWrong);
            return false;
          }
          rethrow;
        }
      } else if (e.kind == BackupCryptoErrorKind.wrongPassphrase) {
        _showError(context, l10n.backupPassphraseWrong);
        return false;
      }
      rethrow;
    }
  }

  Future<T> _runWithExportingOverlay<T>(BuildContext context, Future<T> Function() task) async {
    final l10n = AppLocalizations.of(context)!;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Center(
        child: Material(
          color: Colors.transparent,
          child: BackupProgressCard(
            title: l10n.backupPageExportToFile,
            progress: -1, // 不确定进度，动画条
            phase: l10n.backupPhasePacking,
          ),
        ),
      ),
    );
    try {
      final res = await task();
      return res;
    } finally {
      if (context.mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }
    }
  }

  Future<T> _runWithImportingOverlay<T>(BuildContext context, Future<T> Function() task) async {
    final cs = Theme.of(context).colorScheme;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Center(
        child: Material(
          color: Colors.transparent,
          child: Container(
            decoration: BoxDecoration(
              color: cs.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: cs.outlineVariant.withOpacity(0.2)),
            ),
            child: const Padding(
              padding: EdgeInsets.all(16),
              child: CupertinoActivityIndicator(radius: 14),
            ),
          ),
        ),
      ),
    );
    try {
      final res = await task();
      return res;
    } finally {
      if (context.mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final settings = context.watch<SettingsProvider>();

    return ChangeNotifierProvider(
      create: (_) => BackupProvider(
        chatService: context.read<ChatService>(),
        initialConfig: settings.webDavConfig,
      ),
      child: Builder(builder: (context) {
        final vm = context.watch<BackupProvider>();
        final cfg = vm.config;

        // iOS-style section header
        Widget header(String text, {bool first = false}) => Padding(
          // 18 / 6 无精确 token（md=16 / lg=20、xs=8），保留字面量
          padding: EdgeInsets.fromLTRB(AppGap.sm, first ? AppGap.xxxs : 18, AppGap.sm, 6),
          child: Text(
            text,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: cs.onSurface.withOpacity(0.8),
            ),
          ),
        );

        return AppPage(
          title: l10n.backupPageTitle,
          leading: Tooltip(
            message: l10n.settingsPageBackButton,
            child: IosIconButton(
              haptics: true,
              icon: Lucide.ArrowLeft,
              color: cs.onSurface,
              size: 22,
              minSize: 44,
              onTap: () => Navigator.of(context).maybePop(),
            ),
          ),
          actions: const [SizedBox(width: AppGap.sm)],
          bodyPadding: const EdgeInsets.fromLTRB(AppGap.md, AppGap.sm, AppGap.md, AppGap.xl),
          // ⚠️ scrollable 模式下子部件拿到「无界高度 + 紧凑宽度」，
          // Column 必须 stretch，否则卡片缩到内容宽度。
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Section 1: 备份管理
              header(l10n.backupPageBackupManagement, first: true),
              AppSectionCard(children: [
                AppSwitchRow(
                  icon: Lucide.MessageSquare,
                  label: l10n.backupPageChatsLabel,
                  value: cfg.includeChats,
                  onChanged: (v) async {
                    final newCfg = cfg.copyWith(includeChats: v);
                    await settings.setWebDavConfig(newCfg);
                    vm.updateConfig(newCfg);
                  },
                ),
                const AppSectionDivider(),
                AppSwitchRow(
                  icon: Lucide.FileText,
                  label: l10n.backupPageFilesLabel,
                  value: cfg.includeFiles,
                  onChanged: (v) async {
                    final newCfg = cfg.copyWith(includeFiles: v);
                    await settings.setWebDavConfig(newCfg);
                    vm.updateConfig(newCfg);
                  },
                ),
              ]),

              // Section 1.5: 备份提醒
              header(l10n.backupPageReminderHeader),
              AppSectionCard(children: [
                AppSwitchRow(
                  icon: Lucide.Bell,
                  label: l10n.backupPageRemindMe,
                  value: _remindBackup,
                  onChanged: (v) async {
                    setState(() => _remindBackup = v);
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.setBool('backup_remind_me', v);
                  },
                ),
              ]),

              // Section 1.6: 本地副本
              header(l10n.backupPageLocalCopiesHeader),
              AppSectionCard(children: [
                AppSwitchRow(
                  icon: Lucide.Save,
                  label: l10n.backupPageKeepLocalCopy,
                  value: cfg.keepLocalCopy,
                  onChanged: (v) async {
                    final newCfg = cfg.copyWith(keepLocalCopy: v);
                    await settings.setWebDavConfig(newCfg);
                    vm.updateConfig(newCfg);
                  },
                ),
                const AppSectionDivider(),
                _SnapshotNavRow(
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const LocalSnapshotPage()),
                    );
                  },
                ),
              ]),

              // Section 2: WebDAV备份
              header(l10n.backupPageWebDavBackup),
              AppSectionCard(children: [
                AppNavRow(
                  icon: Lucide.Settings,
                  label: l10n.backupPageWebDavServerSettings,
                  onTap: () => _showWebDavSettingsSheet(context, settings, vm, cfg),
                ),
                const AppSectionDivider(),
                AppNavRow(
                  icon: Lucide.Cable,
                  label: l10n.backupPageTestConnection,
                  onTap: vm.busy ? null : () async {
                    await vm.test();
                    if (!mounted) return;
                    final rawMessage = vm.message;
                    final message = rawMessage ?? l10n.backupPageTestDone;
                    showAppSnackBar(
                      context,
                      message: message,
                      type: rawMessage != null && rawMessage != 'OK'
                          ? NotificationType.error
                          : NotificationType.success,
                    );
                  },
                ),
                const AppSectionDivider(),
                AppNavRow(
                  icon: Lucide.Import,
                  label: l10n.backupPageRestore,
                  onTap: vm.busy ? null : () async {
                    // 加载远程备份列表
                    setState(() => _loadingRemote = true);
                    try {
                      final list = await vm.listRemote();
                      // 按时间倒序排列（最新的在前）
                      list.sort((a, b) {
                        // 优先使用 lastModified
                        if (a.lastModified != null && b.lastModified != null) {
                          return b.lastModified!.compareTo(a.lastModified!);
                        }
                        // 如果都没有 lastModified，按文件名倒序（文件名通常包含时间戳）
                        if (a.lastModified == null && b.lastModified == null) {
                          return b.displayName.compareTo(a.displayName);
                        }
                        // 有 lastModified 的排在前面
                        if (a.lastModified == null) return 1;
                        return -1;
                      });
                      setState(() => _remote = list);
                    } finally {
                      setState(() => _loadingRemote = false);
                    }

                    if (!mounted) return;
                    await showAppSheet(
                      context: context,
                      builder: _RemoteListSheet(
                        items: _remote,
                        loading: _loadingRemote,
                        onDelete: (item) async {
                          final list = await vm.deleteAndReload(item);
                          // 按时间倒序排列（最新的在前）
                          list.sort((a, b) {
                            // 优先使用 lastModified
                            if (a.lastModified != null && b.lastModified != null) {
                              return b.lastModified!.compareTo(a.lastModified!);
                            }
                            // 如果都没有 lastModified，按文件名倒序（文件名通常包含时间戳）
                            if (a.lastModified == null && b.lastModified == null) {
                              return b.displayName.compareTo(a.displayName);
                            }
                            // 有 lastModified 的排在前面
                            if (a.lastModified == null) return 1;
                            return -1;
                          });
                          setState(() => _remote = list);
                        },
                        onRestore: (item) async {
                          Navigator.of(context).pop();

                          if (!mounted) return;
                          final mode = await _chooseImportModeDialog(context);

                          if (mode == null) return;

                          final ok = await _restoreEncryptedAware(
                            context,
                            (p) => _runWithImportingOverlay(
                              context,
                              () => vm.restoreFromItem(item, mode: mode, passphrase: p),
                            ),
                          );
                          if (!mounted || !ok) return;
                          await showDialog(
                            context: context,
                            builder: (dctx) => AlertDialog(
                              title: Text(l10n.backupPageRestartRequired),
                              content: Text(l10n.backupPageRestartContent),
                              actions: [
                                TextButton(onPressed: () => Navigator.of(dctx).pop(), child: Text(l10n.backupPageOK)),
                              ],
                            ),
                          );
                        },
                      ),
                    );
                  },
                ),
                const AppSectionDivider(),
                AppNavRow(
                  icon: Lucide.Upload,
                  label: l10n.backupPageBackupNow,
                  onTap: vm.busy ? null : () async {
                    await _runWithExportingOverlay(context, () => vm.backup());
                    if (!mounted) return;
                    final rawMessage = vm.message;
                    final message = rawMessage ?? l10n.backupPageBackupUploaded;
                    showAppSnackBar(
                      context,
                      message: message,
                      type: NotificationType.info,
                    );
                  },
                ),
              ]),

              // Section 3: 本地备份
              header(l10n.backupPageLocalBackup),
              AppSectionCard(children: [
                AppNavRow(
                  icon: Lucide.Export,
                  label: l10n.backupPageExportToFile,
                  onTap: () => _doExport(context, vm),
                ),
                const AppSectionDivider(),
                AppNavRow(
                  icon: Lucide.Import2,
                  label: l10n.backupPageImportBackupFile,
                  onTap: () => _doImportLocal(context, vm),
                ),
                const AppSectionDivider(),
                AppNavRow(
                  icon: Lucide.Box,
                  label: l10n.backupPageImportFromCherryStudio,
                  onTap: () async {
                    // 1) Warn user that Cherry import is experimental
                    final acknowledged = await _confirmCherryImport(context);
                    if (acknowledged != true) return;

                    if (!mounted) return;
                    // Pick Cherry Studio backup (.zip or .bak)
                    final result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['zip', 'bak']);
                    final path = result?.files.single.path;
                    if (path == null) return;

                    final mode = await _chooseImportModeDialog(context);
                    if (mode == null) return;

                    await _runWithImportingOverlay(context, () async {
                      try {
                        final settings = context.read<SettingsProvider>();
                        final cs = context.read<ChatService>();
                        final file = File(path);
                        // Defer import to service
                        final res = await CherryImporter.importFromCherryStudio(
                          file: file,
                          mode: mode,
                          settings: settings,
                          chatService: cs,
                        );
                        if (!mounted) return;
                        await showDialog(
                          context: context,
                          builder: (dctx) => AlertDialog(
                            title: Text(l10n.backupPageRestartRequired),
                            content: Text(
                              '${l10n.backupPageImportFromCherryStudio}:\n'
                              ' • Providers: ${res.providers}\n'
                              ' • Assistants: ${res.assistants}\n'
                              ' • Conversations: ${res.conversations}\n'
                              ' • Messages: ${res.messages}\n'
                              ' • Files: ${res.files}\n\n'
                              '${l10n.backupPageRestartContent}',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.of(dctx).pop(),
                                child: Text(l10n.backupPageOK),
                              ),
                            ],
                          ),
                        );
                      } catch (e) {
                        if (!mounted) return;
                        showAppSnackBar(
                          context,
                          message: e.toString(),
                          type: NotificationType.error,
                        );
                      }
                    });
                  },
                ),
              ]),
            ],
          ),
        );
      }),
    );
  }

  Future<void> _doExport(BuildContext context, BackupProvider vm) async {
    final policy = await _chooseExportPolicyDialog(context);
    if (policy == null) return;
    String? passphrase;
    if (policy == BackupCredentialPolicy.encrypted) {
      passphrase = await _promptPassphrase(context, confirm: true);
      if (passphrase == null) return;
    }
    final file = await _runWithExportingOverlay(
      context,
      () => vm.exportToFile(policy: policy, passphrase: passphrase),
    );
    if (!mounted) return;

    // iPad: anchor popover to the overlay's center
    Rect rect;
    final overlay = Overlay.of(context);
    final ro = overlay.context.findRenderObject();
    if (ro is RenderBox && ro.hasSize) {
      final center = ro.size.center(Offset.zero);
      final global = ro.localToGlobal(center);
      rect = Rect.fromCenter(center: global, width: 1, height: 1);
    } else {
      final size = MediaQuery.of(context).size;
      rect = Rect.fromCenter(center: Offset(size.width / 2, size.height / 2), width: 1, height: 1);
    }

    await Future.delayed(const Duration(milliseconds: 50));
    await Share.shareXFiles(
      [XFile(file.path)],
      sharePositionOrigin: rect,
    );
  }

  Future<void> _doImportLocal(BuildContext context, BackupProvider vm) async {
    final l10n = AppLocalizations.of(context)!;
    final result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['zip']);
    final path = result?.files.single.path;
    if (path == null) return;

    if (!mounted) return;
    final mode = await _chooseImportModeDialog(context);

    if (mode == null) return;

    final ok = await _restoreEncryptedAware(
      context,
      (p) => _runWithImportingOverlay(
        context,
        () => vm.restoreFromLocalFile(File(path), mode: mode, passphrase: p),
      ),
    );
    if (!mounted || !ok) return;
    await showDialog(
      context: context,
      builder: (dctx) => AlertDialog(
        title: Text(l10n.backupPageRestartRequired),
        content: Text(l10n.backupPageRestartContent),
        actions: [TextButton(onPressed: () => Navigator.of(dctx).pop(), child: Text(l10n.backupPageOK))],
      ),
    );
  }

  Future<void> _showWebDavSettingsSheet(BuildContext context, SettingsProvider settings, BackupProvider vm, WebDavConfig cfg) async {
    await showAppSheet(
      context: context,
      builder: _WebDavSettingsSheet(
        settings: settings,
        vm: vm,
        cfg: cfg,
      ),
    );
  }
}

// --- iOS-style widgets ---

class _InputRow extends StatelessWidget {
  const _InputRow({
    required this.label,
    required this.controller,
    this.hint,
    this.obscure = false,
    this.suffix,
  });
  final String label;
  final TextEditingController controller;
  final String? hint;
  final bool obscure;
  final Widget? suffix;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 13, color: cs.onSurface.withOpacity(0.8))),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          obscureText: obscure,
          decoration: InputDecoration(
            hintText: hint,
            filled: true,
            fillColor: isDark ? Colors.white10 : const Color(0xFFF2F3F5),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.transparent)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.transparent)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: cs.primary.withOpacity(0.4))),
            suffixIcon: suffix,
          ),
        ),
      ],
    );
  }
}

class _SmallTactileIcon extends StatefulWidget {
  const _SmallTactileIcon({required this.icon, required this.onTap, this.baseColor});
  final IconData icon;
  final VoidCallback onTap;
  final Color? baseColor;
  @override
  State<_SmallTactileIcon> createState() => _SmallTactileIconState();
}

class _SmallTactileIconState extends State<_SmallTactileIcon> {
  bool _pressed = false;
  @override
  Widget build(BuildContext context) {
    final base = widget.baseColor ?? Theme.of(context).colorScheme.onSurface;
    final c = _pressed ? base.withOpacity(0.7) : base;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: () {
        Haptics.soft();
        widget.onTap();
      },
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Icon(widget.icon, size: 18, color: c),
      ),
    );
  }
}

// 本地副本导航行：展示 份数 + 大小，点击进入管理页。
class _SnapshotNavRow extends StatefulWidget {
  const _SnapshotNavRow({required this.onTap});
  final VoidCallback onTap;
  @override
  State<_SnapshotNavRow> createState() => _SnapshotNavRowState();
}

class _SnapshotNavRowState extends State<_SnapshotNavRow> {
  int _count = 0;
  int _bytes = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final root = await AppDirectories.getAppDataDirectory();
    final dir = Directory('${root.path}/snapshots');
    int count = 0;
    int bytes = 0;
    if (await dir.exists()) {
      await for (final ent in dir.list(followLinks: false)) {
        if (ent is File && ent.path.toLowerCase().endsWith('.zip')) {
          count += 1;
          try {
            bytes += ent.statSync().size;
          } catch (_) {}
        }
      }
    }
    if (!mounted) return;
    if (count != _count || bytes != _bytes) {
      setState(() {
        _count = count;
        _bytes = bytes;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return AppNavRow(
      icon: Lucide.Box,
      label: l10n.storageManageSnapshots,
      detailText: l10n.backupPageManageCopiesDetail(_count, _fmtBytes(_bytes)),
      onTap: widget.onTap,
    );
  }
}

// --- Local iOS-style buttons for sheets ---
class _IosOutlineButton extends StatefulWidget {
  const _IosOutlineButton({required this.label, required this.onTap});
  final String label; final VoidCallback onTap;
  @override State<_IosOutlineButton> createState() => _IosOutlineButtonState();
}

class _IosOutlineButtonState extends State<_IosOutlineButton> {
  bool _pressed = false;
  void _set(bool v){ if(_pressed!=v) setState(()=>_pressed=v);}
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _set(true),
      onTapUp: (_) => Future.delayed(const Duration(milliseconds: 80), ()=>_set(false)),
      onTapCancel: () => _set(false),
      onTap: () { Haptics.soft(); widget.onTap(); },
      child: AnimatedScale(
        scale: _pressed ? 0.97 : 1.0,
        duration: const Duration(milliseconds: 110), curve: Curves.easeOutCubic,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: cs.primary.withOpacity(0.5)),
          ),
          child: Text(widget.label, style: TextStyle(color: cs.primary, fontWeight: FontWeight.w600)),
        ),
      ),
    );
  }
}

class _IosFilledButton extends StatefulWidget {
  const _IosFilledButton({required this.label, required this.onTap});
  final String label; final VoidCallback onTap;
  @override State<_IosFilledButton> createState() => _IosFilledButtonState();
}

class _IosFilledButtonState extends State<_IosFilledButton> {
  bool _pressed = false;
  void _set(bool v){ if(_pressed!=v) setState(()=>_pressed=v);}
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _set(true),
      onTapUp: (_) => Future.delayed(const Duration(milliseconds: 80), ()=>_set(false)),
      onTapCancel: () => _set(false),
      onTap: () { Haptics.soft(); widget.onTap(); },
      child: AnimatedScale(
        scale: _pressed ? 0.97 : 1.0,
        duration: const Duration(milliseconds: 110), curve: Curves.easeOutCubic,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          alignment: Alignment.center,
          decoration: BoxDecoration(color: cs.primary, borderRadius: BorderRadius.circular(12)),
          child: Text(widget.label, style: TextStyle(color: cs.onPrimary, fontWeight: FontWeight.w600)),
        ),
      ),
    );
  }
}

class _RemoteListSheet extends StatelessWidget {
  const _RemoteListSheet({required this.items, required this.loading, required this.onDelete, required this.onRestore});
  final List<BackupFileItem> items;
  final bool loading;
  final Future<void> Function(BackupFileItem) onDelete;
  final Future<void> Function(BackupFileItem) onRestore;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    // ⚠️ 这里的 safeArea 由外层 showAppSheet 提供，不要再套一层（否则底部重复留白）。
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      builder: (ctx, controller) => Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 16),
        child: Column(
          children: [
            Container(width: 42, height: 4, decoration: BoxDecoration(color: cs.onSurface.withOpacity(0.2), borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 10),
            Stack(
              alignment: Alignment.center,
              children: [
                Center(
                  child: Text(l10n.backupPageRemoteBackups, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                ),
                if (loading)
                  Positioned(
                    right: 0,
                    child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Expanded(
              child: (items.isEmpty)
                  ? Padding(
                      padding: const EdgeInsets.all(20),
                      child: Text(l10n.backupPageNoBackups, style: TextStyle(color: cs.onSurface.withOpacity(0.6))),
                    )
                  : ListView.builder(
                      controller: controller,
                      itemCount: items.length,
                      itemBuilder: (ctx, i) {
                        final it = items[i];
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Container(
                            decoration: BoxDecoration(
                              color: Theme.of(context).brightness == Brightness.dark ? Colors.white10 : const Color(0xFFF7F7F9),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: cs.outlineVariant.withOpacity(0.18)),
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(it.displayName, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                                      const SizedBox(height: 4),
                                      Text(_fmtBytes(it.size), style: TextStyle(fontSize: 12, color: cs.onSurface.withOpacity(0.7))),
                                    ],
                                  ),
                                ),
                                _SmallTactileIcon(icon: Lucide.Import, onTap: () => onRestore(it)),
                                const SizedBox(width: 6),
                                _SmallTactileIcon(icon: Lucide.Trash2, onTap: () => onDelete(it), baseColor: cs.error),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({required this.color, required this.icon, required this.title, required this.subtitle, required this.onTap});
  final Color color;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return IosTactileRow(
      pressedScale: 0.98,
      onTap: onTap,
      builder: (context, pressed) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final overlay = pressed ? (isDark ? Colors.black.withOpacity(0.06) : Colors.white.withOpacity(0.05)) : Colors.transparent;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(
            color: Color.alphaBlend(overlay, color),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: cs.outlineVariant.withOpacity(0.18)),
          ),
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: cs.primary.withOpacity(0.10), borderRadius: BorderRadius.circular(10)),
                alignment: Alignment.center,
                child: Icon(icon, color: cs.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(subtitle, style: TextStyle(fontSize: 12, color: cs.onSurface.withOpacity(0.7))),
                  ],
                ),
              ),
              const Icon(Lucide.ChevronRight, size: 18),
            ],
          ),
        );
      },
    );
  }
}

class _WebDavSettingsSheet extends StatefulWidget {
  const _WebDavSettingsSheet({
    required this.settings,
    required this.vm,
    required this.cfg,
  });

  final SettingsProvider settings;
  final BackupProvider vm;
  final WebDavConfig cfg;

  @override
  State<_WebDavSettingsSheet> createState() => _WebDavSettingsSheetState();
}

class _WebDavSettingsSheetState extends State<_WebDavSettingsSheet> {
  late final TextEditingController _urlCtrl;
  late final TextEditingController _userCtrl;
  late final TextEditingController _passCtrl;
  late final TextEditingController _pathCtrl;
  bool _showPassword = false;

  @override
  void initState() {
    super.initState();
    _urlCtrl = TextEditingController(text: widget.cfg.url);
    _userCtrl = TextEditingController(text: widget.cfg.username);
    _passCtrl = TextEditingController(text: widget.cfg.password);
    _pathCtrl = TextEditingController(text: widget.cfg.path.isEmpty ? 'minime-core_backups' : widget.cfg.path);
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    _userCtrl.dispose();
    _passCtrl.dispose();
    _pathCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;

    return AppSheet(
      // 三段式 header（关闭 / 居中标题 / 保存）：AppSheet.title 是左对齐的，
      // 故整行自绘并作为第一个 child（见文件头说明）。
      contentPadding: const EdgeInsets.fromLTRB(AppGap.md, AppGap.sm, AppGap.md, AppGap.md),
      children: [
        Row(
          children: [
            IosIconButton(
              haptics: true,
              icon: Lucide.X,
              color: cs.onSurface,
              size: 20,
              minSize: 44,
              onTap: () => Navigator.of(context).pop(),
            ),
            Expanded(
              child: Center(
                child: Text(
                  l10n.backupPageWebDavServerSettings,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
            ),
            IosIconButton(
              haptics: true,
              color: cs.primary,
              minSize: 44,
              builder: (c) => Text(
                l10n.backupPageSave,
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: c),
              ),
              onTap: () async {
                final newCfg = widget.cfg.copyWith(
                  url: _urlCtrl.text.trim(),
                  username: _userCtrl.text.trim(),
                  password: _passCtrl.text,
                  path: _pathCtrl.text.trim().isEmpty ? 'minime-core_backups' : _pathCtrl.text.trim(),
                );
                await widget.settings.setWebDavConfig(newCfg);
                widget.vm.updateConfig(newCfg);
                if (context.mounted) {
                  Navigator.of(context).pop();
                }
              },
            ),
          ],
        ),
        const SizedBox(height: AppGap.md),

        // Input fields
        _InputRow(
          label: l10n.backupPageWebDavServerUrl,
          controller: _urlCtrl,
          hint: 'https://example.com/dav',
        ),
        const SizedBox(height: AppGap.sm),
        _InputRow(
          label: l10n.backupPageUsername,
          controller: _userCtrl,
        ),
        const SizedBox(height: AppGap.sm),
        _InputRow(
          label: l10n.backupPagePassword,
          controller: _passCtrl,
          obscure: !_showPassword,
          suffix: _PasswordToggleButton(
            showPassword: _showPassword,
            onPressed: () => setState(() => _showPassword = !_showPassword),
          ),
        ),
        const SizedBox(height: AppGap.sm),
        _InputRow(
          label: l10n.backupPagePath,
          controller: _pathCtrl,
          hint: 'minime-core_backups',
        ),
        const SizedBox(height: AppGap.md),
      ],
    );
  }
}

// iOS-style password toggle button (no ripple)
class _PasswordToggleButton extends StatefulWidget {
  const _PasswordToggleButton({
    required this.showPassword,
    required this.onPressed,
  });

  final bool showPassword;
  final VoidCallback onPressed;

  @override
  State<_PasswordToggleButton> createState() => _PasswordToggleButtonState();
}

class _PasswordToggleButtonState extends State<_PasswordToggleButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = _pressed ? cs.onSurface.withOpacity(0.5) : cs.onSurface.withOpacity(0.7);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: () {
        Haptics.light();
        widget.onPressed();
      },
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: AnimatedIconSwap(
          child: Icon(
            widget.showPassword ? Lucide.EyeOff : Lucide.Eye,
            key: ValueKey(widget.showPassword ? 'hide' : 'show'),
            size: 20,
            color: color,
          ),
        ),
      ),
    );
  }
}
