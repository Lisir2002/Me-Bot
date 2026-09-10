import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/providers/mcp_provider.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../core/services/logging/logger.dart';
import '../../../core/services/secure_storage/secure_storage_bootstrap.dart';
import '../../../core/services/security/checkup_scanner.dart';
import '../../../core/services/security/security_checkup_service.dart';
import '../../../core/services/security/scanners/legacy_prefs_scanner.dart';
import '../../../core/services/security/scanners/orphan_credential_scanner.dart';
import '../../../core/services/security/scanners/backup_file_scanner.dart';
import '../../../core/services/security/scanners/log_file_scanner.dart';
import '../../../core/services/security/key_health_service.dart';
import '../../../core/services/security/app_lock_service.dart';
import '../../../core/services/security/credential_audit_logger.dart';
import '../../../core/services/security/policy_provider.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../l10n/app_localizations.dart';
import '../../../l10n/build_context_l10n.dart';
import '../../../shared/widgets/app_list_view.dart';
import '../../../shared/widgets/app_page.dart';
import '../../../shared/widgets/app_section.dart';
import '../../../shared/widgets/app_sheet.dart';
import '../../../shared/widgets/ios_switch.dart';
import '../../../shared/widgets/ios_tactile.dart';
import '../../../shared/widgets/snackbar.dart';
import '../../../theme/design_tokens.dart';
import '../../../utils/app_directories.dart';
import '../checkup_strings_l10n.dart';
import '../../provider/pages/provider_detail_page.dart';

/// 安全中心（PR-5 ~ PR-8 的统一入口）。
///
/// 五段：① 安全体检（进页自动扫 + 一键修复带确认）② 密钥健康（轮换提醒 +
/// 标记已轮换 / 跳转换 Key）③ 隐私门禁（开关双向验证 + 解锁宽限期）
/// ④ 白名单策略（命令/例外站点可增删、MCP 服务器逐个开关）
/// ⑤ 最近安全事件（审计可见化）。
///
/// 双端结构（对齐设计系统的关键约束）：
/// - [SecurityPage] 移动端薄壳，只负责 [AppPage] 骨架（标题/返回键/滚动）；
/// - [SecurityBody] 纯 body（**无 Scaffold**），桌面端设置 pane 直接嵌入，
///   避免整页嵌套造成「双层标题栏」；业务逻辑只在 [SecurityBody] 一处。
class SecurityPage extends StatelessWidget {
  const SecurityPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AppPage.selfScrolling(
      title: l10n.securitySection,
      body: const SecurityBody(),
    );
  }
}

/// 安全中心正文（移动 / 桌面共用）。
///
/// ⚠️ 必须走设计系统，禁止回退：
/// - 容器用 [AppSectionCard]（裸 `Card` / `Scaffold` 不允许）；
/// - 行用 [AppNavRow] / [AppSwitchRow]（裸 `ListTile` / `SwitchListTile` 不允许）；
/// - 通知用 [showAppSnackBar]（裸 `ScaffoldMessenger` / `SnackBar` 不允许）；
/// - 语义色用 [AppStatusColor]（`Colors.red/green/amber` 不允许）；
/// - 弹层用 [showAppSheet] + [AppSheet]（裸 `showModalBottomSheet` 不允许）。
class SecurityBody extends StatefulWidget {
  const SecurityBody({super.key});

  @override
  State<SecurityBody> createState() => _SecurityBodyState();
}

class _SecurityBodyState extends State<SecurityBody> {
  CheckupReport? _report;
  bool _running = false;
  List<KeyHealthInfo> _health = const [];
  bool _loadingHealth = false;

  List<AuditEvent> _audit = const [];
  bool _auditLoading = true;

  @override
  void initState() {
    super.initState();
    // 进页自动体检：安全检查应该是「来了就能看到结果」，而不是等用户找按钮。
    _runCheckup();
    _loadHealth();
    _loadAudit();
  }

  SettingsProvider get _settings =>
      context.read<SettingsProvider>();

  /// 组装体检引擎：4 个扫描器（预留接口③ 的真实实现）。
  Future<SecurityCheckupService> _buildService() async {
    final prefs = await SharedPreferences.getInstance();
    // 未初始化（理论上启动期已完成）时降级为 null，避免直接抛异常打断体检。
    final secure =
        SecureStorage.isInitialized ? SecureStorage.instance : null;

    final knownProviders = _settings.providerConfigs.keys.toSet();
    final knownServices = <String>{
      ..._settings.searchServices.map((s) => s.id),
      ..._settings.ttsServices.map((s) => s.id),
    };

    // 日志文件：取既有 Logger 的日志目录
    final logDir = Logger.logDir;
    Future<List<File>> logs() async {
      if (logDir == null || !await logDir.exists()) return const [];
      return logDir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.log'))
          .toList();
    }

    // 本机备份文件：应用数据目录下的 *.json / *.bak（导出与自动备份的常见落点）。
    Future<List<File>> backups() async {
      try {
        final dir = await AppDirectories.getAppDataDirectory();
        if (!await dir.exists()) return const [];
        return dir
            .listSync()
            .whereType<File>()
            .where((f) {
              final n = f.path.toLowerCase();
              return n.endsWith('.json') || n.endsWith('.bak');
            })
            .toList();
      } catch (_) {
        return const [];
      }
    }

    return SecurityCheckupService([
      LegacyPrefsScanner(prefs),
      if (secure != null)
        OrphanCredentialScanner(
          secure,
          knownProviderIds: knownProviders,
          knownServiceIds: knownServices,
        ),
      BackupFileScanner(backups()),
      LogFileScanner(logs()),
    ]);
  }

  Future<void> _runCheckup() async {
    setState(() => _running = true);
    try {
      final svc = await _buildService();
      final report = await svc.run(L10nCheckupStrings(context.l10n));
      if (!mounted) return;
      setState(() => _report = report);
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  Future<void> _autoFix() async {
    final l10n = context.l10n;
    final report = _report;
    if (report == null) return;
    final fixable = report.fixable;
    if (fixable.isEmpty) {
      _snack(l10n.checkupFixNone);
      return;
    }
    // 自动修复会删除数据（旧明文残留 / 无主凭证）：先确认再动手。
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.checkupAutoFixConfirmTitle),
        content: Text(l10n.checkupAutoFixConfirmBody(fixable.length)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(MaterialLocalizations.of(ctx).cancelButtonLabel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.checkupFix),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final svc = await _buildService();
    await svc.fix(fixable);
    CredentialAuditLogger.record('fix', 'checkup:${fixable.length}');
    if (!mounted) return;
    _snack(l10n.checkupFixSuccess, type: NotificationType.success);
    await _runCheckup();
    await _loadHealth();
  }

  Future<void> _loadHealth() async {
    if (!SecureStorage.isInitialized) return;
    final secure = SecureStorage.instance;
    setState(() => _loadingHealth = true);
    try {
      final infos = await KeyHealthService(secure).scan();
      if (!mounted) return;
      setState(() => _health = infos);
    } finally {
      if (mounted) setState(() => _loadingHealth = false);
    }
  }

  Future<void> _loadAudit() async {
    setState(() => _auditLoading = true);
    try {
      final events = await CredentialAuditLogger.recent(limit: 12);
      if (!mounted) return;
      setState(() => _audit = events);
    } finally {
      if (mounted) setState(() => _auditLoading = false);
    }
  }

  Future<void> _clearAudit() async {
    final l10n = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.auditClear),
        content: Text(l10n.auditClearConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(MaterialLocalizations.of(ctx).cancelButtonLabel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.auditClear),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await CredentialAuditLogger.clear();
    await _loadAudit();
  }

  Future<void> _markRotated(KeyHealthInfo info) async {
    final l10n = context.l10n;
    if (!SecureStorage.isInitialized) return;
    final svc = KeyHealthService(SecureStorage.instance);
    final ok = await svc.markRotated(info.providerId);
    if (!mounted) return;
    _snack(
      ok ? l10n.rotateMarked : l10n.keyHealthEmpty,
      type: ok ? NotificationType.success : NotificationType.info,
    );
    if (ok) {
      CredentialAuditLogger.record('markRotated', 'provider:${info.providerId}');
      await _loadHealth();
    }
  }

  Future<void> _gotoProvider(KeyHealthInfo info) async {
    final cfg = _settings.providerConfigs[info.providerId] ??
        _settings.getProviderConfig(info.providerId);
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ProviderDetailPage(
          keyName: info.providerId,
          displayName: cfg.name.isNotEmpty ? cfg.name : info.providerId,
        ),
      ),
    );
    await _loadHealth();
  }

  void _snack(String msg, {NotificationType type = NotificationType.info}) {
    if (!mounted) return;
    showAppSnackBar(context, message: msg, type: type);
  }

  // ─────────────────────────────────────────── 页面骨架（黄金范式：backup_page）

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AppListView(
      bottomPadding: AppGap.xl,
      children: [
        _checkupSection(l10n),
        _healthSection(l10n),
        _lockSection(l10n),
        _policySection(l10n),
        _auditSection(l10n),
      ],
    );
  }

  /// 分组小节标题（13px w600，与 backup_page 的 `header` 范式一致）。
  Widget header(String text, {bool first = false}) => Padding(
        padding: EdgeInsets.fromLTRB(AppGap.sm, first ? 0 : AppGap.lg, AppGap.sm, AppGap.xxs),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.8),
          ),
        ),
      );

  /// 分组小节描述（12px 弱化）。
  Widget desc(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(AppGap.sm, 0, AppGap.sm, AppGap.sm),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.55),
          ),
        ),
      );

  /// 卡内统一状态行（原 `_banner` 的设计系统版）。
  Widget statusRow(String text, {IconData? icon, Color? color}) {
    final cs = Theme.of(context).colorScheme;
    final tint = color ?? cs.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppGap.sm, vertical: AppGap.xxs),
      child: Container(
        padding: const EdgeInsets.all(AppGap.sm),
        decoration: BoxDecoration(
          color: tint.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        child: Row(
          children: [
            if (icon != null) ...[
              Icon(icon, color: tint, size: 18),
              const SizedBox(width: AppGap.sm),
            ],
            Expanded(
              child: Text(
                text,
                style: TextStyle(
                  fontSize: 13,
                  color: cs.onSurface.withOpacity(0.7),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------------ ① 安全体检
  Widget _checkupSection(AppLocalizations l10n) {
    final report = _report;
    final fixable = report?.fixable ?? const [];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        header(l10n.securityCheckup, first: true),
        desc(l10n.securityCheckupDesc),
        AppSectionCard(children: [
          AppNavRow(
            icon: Lucide.RefreshCw,
            label: _running ? l10n.checkupRunning : l10n.runCheckup,
            onTap: _running ? null : _runCheckup,
            detailBuilder: _running
                ? (_) => const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                : null,
          ),
          if (!_running && fixable.isNotEmpty) ...[
            const AppSectionDivider(),
            AppNavRow(
              icon: Lucide.Wand2,
              label: l10n.checkupFix,
              detailText: '${fixable.length}',
              onTap: _autoFix,
            ),
          ],
          if (!_running && report != null) ...[
            if (report.findings.isEmpty) ...[
              const AppSectionDivider(),
              statusRow(
                l10n.checkupNoIssue,
                icon: Lucide.circleCheckBig,
                color: AppStatusColor.success,
              ),
            ] else
              for (final f in report.findings) ...[
                const AppSectionDivider(),
                _findingRow(f, l10n),
              ],
          ],
        ]),
      ],
    );
  }

  /// 体检发现行：severity → (图标, 语义色)，富文本行 + 可选修复按钮。
  Widget _findingRow(CheckupFinding f, AppLocalizations l10n) {
    final cs = Theme.of(context).colorScheme;
    final (IconData icon, Color color) = switch (f.severity) {
      CheckupSeverity.danger => (Lucide.CircleX, AppStatusColor.danger),
      CheckupSeverity.warn => (Lucide.circleDot, AppStatusColor.warning),
      CheckupSeverity.safe => (Lucide.circleCheckBig, AppStatusColor.success),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppGap.sm, vertical: AppGap.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 36, child: Icon(icon, size: 18, color: color)),
          const SizedBox(width: AppGap.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(f.title,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                if (f.detail.isNotEmpty) ...[
                  const SizedBox(height: AppGap.xxxs),
                  Text(f.detail,
                      style: TextStyle(
                          fontSize: 12, color: cs.onSurface.withOpacity(0.6))),
                ],
                if (f.fixHint != null && f.fixHint!.isNotEmpty) ...[
                  const SizedBox(height: AppGap.xxs),
                  Text('${l10n.fixHintLabel}${f.fixHint}',
                      style: TextStyle(fontSize: 12, color: cs.primary)),
                ],
              ],
            ),
          ),
          if (f.autoFixable) ...[
            const SizedBox(width: AppGap.xxs),
            Tooltip(
              message: l10n.checkupFix,
              child: IosIconButton(
                haptics: true,
                icon: Lucide.Wand2,
                size: 16,
                minSize: 32,
                onTap: _autoFix,
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ---------------------------------------------------------- ② 密钥健康
  Widget _healthSection(AppLocalizations l10n) {
    final anyRotation = _health.any((h) => h.needsRotation);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        header(l10n.keyHealth),
        desc(l10n.keyHealthDesc),
        AppSectionCard(children: _healthRows(l10n)),
        if (anyRotation)
          Padding(
            padding: const EdgeInsets.fromLTRB(AppGap.sm, AppGap.xxs, AppGap.sm, 0),
            child: Text(
              l10n.goRotate,
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.55),
              ),
            ),
          ),
      ],
    );
  }

  List<Widget> _healthRows(AppLocalizations l10n) {
    if (_loadingHealth) {
      return const [
        Padding(
          padding: EdgeInsets.all(AppGap.lg),
          child: Center(child: CircularProgressIndicator()),
        ),
      ];
    }
    if (_health.isEmpty) {
      return [statusRow(l10n.keyHealthEmpty, icon: Lucide.KeyRound)];
    }
    return [
      for (final h in _health) ...[
        if (h != _health.first) const AppSectionDivider(),
        AppNavRow(
          icon: Lucide.KeyRound,
          label: h.providerId,
          onTap: () => _gotoProvider(h),
          detailBuilder: (ctx) => Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('${h.keyCount} · ${_fmt(l10n, h.lastRotatedAt)}'),
              Text(
                h.needsRotation ? l10n.suggestRotation : l10n.rotationOk,
                style: h.needsRotation
                    ? const TextStyle(color: AppStatusColor.warning)
                    : null,
              ),
              if (h.needsRotation)
                Tooltip(
                  message: l10n.rotateAction,
                  child: IosIconButton(
                    haptics: true,
                    icon: Lucide.RotateCw,
                    size: 14,
                    minSize: 28,
                    onTap: () => _markRotated(h),
                  ),
                ),
            ],
          ),
        ),
      ],
    ];
  }

  String _fmt(AppLocalizations l10n, DateTime? d) {
    if (d == null) return l10n.never;
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  // ------------------------------------------------------------ ③ 隐私门禁
  Widget _lockSection(AppLocalizations l10n) {
    return FutureBuilder<AppLockService>(
      future: AppLockService.instance != null
          ? Future.value(AppLockService.instance)
          : AppLockService.load(),
      builder: (context, snap) {
        final lock = snap.data;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            header(l10n.appLock),
            desc(l10n.appLockDesc),
            AppSectionCard(children: _lockRows(l10n, lock)),
          ],
        );
      },
    );
  }

  List<Widget> _lockRows(AppLocalizations l10n, AppLockService? lock) {
    if (lock == null) return const [];
    return [
      FutureBuilder<bool>(
        future: lock.canEnable(),
        builder: (context, snap) {
          final supported = snap.data ?? false;
          if (!supported) {
            return statusRow(l10n.appLockUnsupported, icon: Lucide.Shield);
          }
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppSwitchRow(
                icon: Lucide.Shield,
                label: l10n.appLockEnable,
                value: lock.enabled,
                onChanged: (v) => _toggleLock(lock, v),
              ),
              if (lock.enabled) ...[
                const AppSectionDivider(),
                AppNavRow(
                  icon: Lucide.History,
                  label: l10n.appLockGrace,
                  detailText: _graceLabel(l10n, lock.graceMinutes),
                  onTap: () => _pickGrace(lock),
                ),
                if (lock.graceMinutes > 0) ...[
                  const AppSectionDivider(),
                  AppNavRow(
                    icon: Lucide.EyeOff,
                    label: l10n.appLockLockNow,
                    onTap: () async {
                      await lock.lockNow();
                      _snack(l10n.appLockLockNow);
                    },
                  ),
                ],
              ],
            ],
          );
        },
      ),
    ];
  }

  String _graceLabel(AppLocalizations l10n, int minutes) =>
      minutes == 0 ? l10n.appLockGraceOff : l10n.appLockGraceMinutes(minutes);

  /// 开/关门禁都要求**现场验证身份**：
  /// 开启确认是本人在开；关闭防止他人随手关掉门禁让保护形同虚设。
  Future<void> _toggleLock(AppLockService lock, bool v) async {
    final l10n = context.l10n;
    final ok = await lock.setEnabled(v,
        verify: () => lock.verifyWith(l10n.appLockVerifyToEnable));
    if (!mounted) return;
    if (!ok) {
      _snack(l10n.appLockAuthFailed, type: NotificationType.error);
      return;
    }
    setState(() {});
  }

  Future<void> _pickGrace(AppLockService lock) async {
    final l10n = context.l10n;
    final picked = await showAppSheet<int>(
      context: context,
      builder: AppSheet(
        title: l10n.appLockGrace,
        children: [
          // Builder 拿到 sheet 路由内的 context，pop 才能把选中值带回去
          // （与 display_settings_page 的 _OptionSheet 同一原理）。
          for (final m in AppLockService.graceChoices)
            Builder(
              builder: (sheetCtx) => AppNavRow(
                icon: m == lock.graceMinutes ? Lucide.Check : Lucide.circleDot,
                label: _graceLabel(l10n, m),
                onTap: () => Navigator.pop(sheetCtx, m),
              ),
            ),
        ],
      ),
    );
    if (picked != null) {
      await lock.setGraceMinutes(picked);
      if (mounted) setState(() {});
    }
  }

  // ---------------------------------------------------------- ④ 白名单策略
  Widget _policySection(AppLocalizations l10n) {
    return FutureBuilder<LocalPolicyProvider>(
      future: LocalPolicyProvider.instance != null
          ? Future.value(LocalPolicyProvider.instance)
          : LocalPolicyProvider.load(),
      builder: (context, snap) {
        final policy = snap.data;
        if (policy == null) return const SizedBox.shrink();
        final servers = context.watch<McpProvider>().servers;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            header(l10n.allowlist),
            desc(l10n.allowlistDesc),
            AppSectionCard(children: _policyRows(l10n, policy, servers)),
          ],
        );
      },
    );
  }

  List<Widget> _policyRows(
    AppLocalizations l10n,
    LocalPolicyProvider policy,
    List<McpServerConfig> servers,
  ) {
    final cs = Theme.of(context).colorScheme;
    return [
      AppSwitchRow(
        icon: Lucide.Shield,
        label: l10n.allowlistEnable,
        value: policy.enabled,
        onChanged: (v) async {
          await policy.setEnabled(v);
          if (mounted) setState(() {});
        },
      ),
      const AppSectionDivider(),
      AppSwitchRow(
        icon: Lucide.Globe,
        label: l10n.allowHttp,
        value: policy.allowWebViewHttp,
        onChanged: (v) async {
          await policy.setAllowWebViewHttp(v);
          if (mounted) setState(() {});
        },
      ),
      const AppSectionDivider(),
      _rowHeader(l10n.mcpCommandAllowlist, trailing: TextButton.icon(
        onPressed: () => _restoreDefaultCmds(policy),
        icon: const Icon(Lucide.RefreshCw, size: 16),
        label: Text(l10n.restoreDefaultCmds),
      )),
      _chipWrap([
        for (final c in policy.allowedMcpCommands)
          InputChip(
            label: Text(c),
            onDeleted: () async {
              final next = Set.of(policy.allowedMcpCommands)..remove(c);
              await policy.setAllowedMcpCommands(next);
              if (mounted) setState(() {});
            },
          ),
        ActionChip(
          avatar: const Icon(Lucide.Plus, size: 18),
          label: Text(l10n.addCommand),
          onPressed: () => _addCommand(policy),
        ),
      ]),
      const AppSectionDivider(),
      _rowHeader(l10n.webviewHosts, trailing: TextButton.icon(
        onPressed: () => _addHost(policy),
        icon: const Icon(Lucide.Plus, size: 16),
        label: Text(l10n.addHost),
      )),
      if (policy.allowedWebViewHosts.isEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(AppGap.sm, 0, AppGap.sm, AppGap.xxs),
          child: Text(l10n.webviewHostsEmpty,
              style: TextStyle(
                  fontSize: 12, color: cs.onSurface.withOpacity(0.55))),
        )
      else
        _chipWrap([
          for (final h in policy.allowedWebViewHosts)
            InputChip(
              label: Text(h),
              onDeleted: () async {
                final next = Set.of(policy.allowedWebViewHosts)..remove(h);
                await policy.setWebViewHosts(next);
                if (mounted) setState(() {});
              },
            ),
        ]),
      const AppSectionDivider(),
      Padding(
        padding: const EdgeInsets.fromLTRB(AppGap.sm, AppGap.xxs, AppGap.sm, AppGap.xxxs),
        child: Text(l10n.mcpServersPolicy,
            style: TextStyle(
                fontSize: 15, color: cs.onSurface.withOpacity(0.9))),
      ),
      if (servers.isEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(AppGap.sm, 0, AppGap.sm, AppGap.xxs),
          child: Text(l10n.mcpServersEmpty,
              style: TextStyle(
                  fontSize: 12, color: cs.onSurface.withOpacity(0.55))),
        )
      else
        for (final s in servers)
          _serverRow(l10n, cs, policy, s),
    ];
  }

  /// 卡内「标题 + 右侧操作」行头（与 AppNavRow 的横向留白对齐）。
  Widget _rowHeader(String text, {required Widget trailing}) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppGap.sm, vertical: AppGap.xxs),
        child: Row(
          children: [
            Expanded(
              child: Text(
                text,
                style: TextStyle(
                  fontSize: 15,
                  color: Theme.of(context).colorScheme.onSurface.withOpacity(0.9),
                ),
              ),
            ),
            trailing,
          ],
        ),
      );

  Widget _chipWrap(List<Widget> chips) => Padding(
        padding: const EdgeInsets.fromLTRB(AppGap.sm, AppGap.xxs, AppGap.sm, AppGap.xxs),
        child: Wrap(spacing: 6, runSpacing: -6, children: chips),
      );

  /// MCP 服务器开关行（AppSwitchRow 无副标题槽位，富副标题自定义行）。
  Widget _serverRow(
    AppLocalizations l10n,
    ColorScheme cs,
    LocalPolicyProvider policy,
    McpServerConfig s,
  ) {
    final sub = s.command != null && s.command!.isNotEmpty
        ? 'stdio: ${s.command}'
        : s.transport.name;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppGap.sm, vertical: AppGap.xxs),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(s.name.isNotEmpty ? s.name : s.id,
                    style: TextStyle(
                        fontSize: 15, color: cs.onSurface.withOpacity(0.9))),
                const SizedBox(height: AppGap.xxxs),
                Text(sub,
                    style: TextStyle(
                        fontSize: 12, color: cs.onSurface.withOpacity(0.55))),
              ],
            ),
          ),
          IosSwitch(
            value: policy.isMcpServerAllowed(s.id),
            onChanged: (v) async {
              await policy.setMcpServerEnabled(s.id, v);
              if (mounted) setState(() {});
            },
          ),
        ],
      ),
    );
  }

  Future<void> _restoreDefaultCmds(LocalPolicyProvider policy) async {
    await policy.setAllowedMcpCommands(policy.defaultMcpCommands);
    if (mounted) setState(() {});
  }

  static final RegExp _cmdRe = RegExp(r'^[a-zA-Z0-9][a-zA-Z0-9._-]*$');
  static final RegExp _hostRe = RegExp(r'^[a-zA-Z0-9]([a-zA-Z0-9.-]*[a-zA-Z0-9])?$');

  Future<void> _addCommand(LocalPolicyProvider policy) async {
    final l10n = context.l10n;
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.addCommand),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: InputDecoration(hintText: l10n.commandHint),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(MaterialLocalizations.of(ctx).cancelButtonLabel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(MaterialLocalizations.of(ctx).okButtonLabel),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final cmd = ctrl.text.trim();
    if (cmd.isEmpty || !_cmdRe.hasMatch(cmd)) {
      _snack(l10n.invalidCommand, type: NotificationType.error);
      return;
    }
    final next = Set.of(policy.allowedMcpCommands)..add(cmd);
    await policy.setAllowedMcpCommands(next);
    if (mounted) setState(() {});
  }

  Future<void> _addHost(LocalPolicyProvider policy) async {
    final l10n = context.l10n;
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.addHost),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: InputDecoration(hintText: l10n.hostHint),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(MaterialLocalizations.of(ctx).cancelButtonLabel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(MaterialLocalizations.of(ctx).okButtonLabel),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final host = ctrl.text.trim().toLowerCase();
    if (host.isEmpty || !_hostRe.hasMatch(host)) {
      _snack(l10n.invalidHost, type: NotificationType.error);
      return;
    }
    final next = Set.of(policy.allowedWebViewHosts)..add(host);
    await policy.setWebViewHosts(next);
    if (mounted) setState(() {});
  }

  // ---------------------------------------------------------- ⑤ 最近安全事件
  Widget _auditSection(AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        header(l10n.auditTrail),
        desc(l10n.auditTrailDesc),
        AppSectionCard(children: _auditRows(l10n)),
      ],
    );
  }

  List<Widget> _auditRows(AppLocalizations l10n) {
    if (_auditLoading) {
      return const [
        Padding(
          padding: EdgeInsets.all(AppGap.lg),
          child: Center(child: CircularProgressIndicator()),
        ),
      ];
    }
    if (_audit.isEmpty) {
      return [statusRow(l10n.auditEmpty, icon: Lucide.ScrollText)];
    }
    return [
      for (final e in _audit) ...[
        if (e != _audit.first) const AppSectionDivider(),
        AppNavRow(
          icon: e.ok ? Lucide.ScrollText : Lucide.CircleX,
          label: _auditText(l10n, e),
          detailText: _fmtTime(e.time),
        ),
      ],
      const AppSectionDivider(),
      AppNavRow(icon: Lucide.Eraser, label: l10n.auditClear, onTap: _clearAudit),
    ];
  }

  String _auditText(AppLocalizations l10n, AuditEvent e) {
    final action = switch (e.action) {
      'view' => l10n.auditActionView,
      'copy' => l10n.auditActionCopy,
      'export' => l10n.auditActionExport,
      'enterPassphrase' => l10n.auditActionEnterPassphrase,
      'migrate' => l10n.auditActionMigrate,
      'clearAudit' => l10n.auditActionClearAudit,
      'fix' => l10n.auditActionFix,
      'markRotated' => l10n.auditActionMarkRotated,
      _ => e.action,
    };
    final tail = e.ok ? '' : ' · ${l10n.auditFailed}';
    return '$action · ${e.target}$tail';
  }

  String _fmtTime(DateTime t) =>
      '${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')} '
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
}
