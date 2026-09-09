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
import '../../../l10n/app_localizations.dart';
import '../checkup_strings_l10n.dart';
import '../../../l10n/build_context_l10n.dart';
import '../../../utils/app_directories.dart';
import '../../provider/pages/provider_detail_page.dart';

/// 安全中心（PR-5 ~ PR-8 的统一入口）。
///
/// 五段：① 安全体检（进页自动扫 + 一键修复带确认）② 密钥健康（轮换提醒 +
/// 标记已轮换 / 跳转换 Key）③ 隐私门禁（开关双向验证 + 解锁宽限期）
/// ④ 白名单策略（命令/例外站点可增删、MCP 服务器逐个开关）
/// ⑤ 最近安全事件（审计可见化）。
/// 移动与桌面共用同一页，避免两套 UI 逻辑漂移。
class SecurityPage extends StatefulWidget {
  const SecurityPage({super.key});

  @override
  State<SecurityPage> createState() => _SecurityPageState();
}

class _SecurityPageState extends State<SecurityPage> {
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
    _snack(l10n.checkupFixSuccess);
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
    _snack(ok ? l10n.rotateMarked : l10n.keyHealthEmpty);
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

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.securitySection)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _checkupSection(l10n, cs),
          const Divider(height: 32),
          _healthSection(l10n, cs),
          const Divider(height: 32),
          _lockSection(l10n, cs),
          const Divider(height: 32),
          _policySection(l10n, cs),
          const Divider(height: 32),
          _auditSection(l10n, cs),
        ],
      ),
    );
  }

  // ------------------------------------------------------------ ① 安全体检
  Widget _checkupSection(AppLocalizations l10n, ColorScheme cs) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.securityCheckup, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(l10n.securityCheckupDesc,
            style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 12),
        Row(
          children: [
            FilledButton.icon(
              onPressed: _running ? null : _runCheckup,
              icon: _running
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.refresh),
              label: Text(_running ? l10n.checkupRunning : l10n.runCheckup),
            ),
            const SizedBox(width: 12),
            if (_report != null && _report!.fixable.isNotEmpty)
              OutlinedButton.icon(
                onPressed: _autoFix,
                icon: const Icon(Icons.auto_fix_high),
                label: Text(l10n.checkupFix),
              ),
          ],
        ),
        const SizedBox(height: 12),
        if (_report == null && !_running)
          const SizedBox.shrink()
        else if (_report != null && _report!.findings.isEmpty)
          _banner(cs, Icons.check_circle, l10n.checkupNoIssue, Colors.green)
        else if (_report != null)
          ..._report!.findings.map((f) => _findingCard(f, l10n, cs)),
      ],
    );
  }

  Widget _findingCard(CheckupFinding f, AppLocalizations l10n, ColorScheme cs) {
    final color = switch (f.severity) {
      CheckupSeverity.danger => Colors.red,
      CheckupSeverity.warn => Colors.amber.shade700,
      CheckupSeverity.safe => Colors.green,
    };
    IconData icon = Icons.info_outline;
    if (f.severity == CheckupSeverity.danger) {
      icon = Icons.error_outline;
    } else if (f.severity == CheckupSeverity.warn) {
      icon = Icons.warning_amber_rounded;
    }
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 8),
              Expanded(child: Text(f.title, style: const TextStyle(fontWeight: FontWeight.w600))),
            ]),
            const SizedBox(height: 4),
            Text(f.detail, style: Theme.of(context).textTheme.bodySmall),
            if (f.fixHint != null && f.fixHint!.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text('${l10n.fixHintLabel}${f.fixHint}',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: cs.primary)),
            ],
            if (f.autoFixable) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: _autoFix,
                  icon: const Icon(Icons.auto_fix_high, size: 16),
                  label: Text(l10n.checkupFix),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------- ② 密钥健康
  Widget _healthSection(AppLocalizations l10n, ColorScheme cs) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.keyHealth, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(l10n.keyHealthDesc, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 12),
        if (_loadingHealth)
          const Center(child: CircularProgressIndicator())
        else if (_health.isEmpty)
          _banner(cs, Icons.key_off, l10n.keyHealthEmpty, cs.onSurfaceVariant)
        else
          ..._health.map((h) => Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  onTap: () => _gotoProvider(h),
                  leading: Icon(
                    h.needsRotation ? Icons.warning_amber_rounded : Icons.verified_user,
                    color: h.needsRotation ? Colors.amber.shade700 : Colors.green,
                  ),
                  title: Text(h.providerId),
                  subtitle: Text(
                      '${l10n.keyCountLabel}: ${h.keyCount} · ${l10n.lastRotated}: ${_fmt(l10n, h.lastRotatedAt)}'),
                  trailing: h.needsRotation
                      ? Row(mainAxisSize: MainAxisSize.min, children: [
                          Chip(
                            label: Text(l10n.suggestRotation),
                            backgroundColor: Colors.amber.shade100,
                          ),
                          IconButton(
                            tooltip: l10n.rotateAction,
                            icon: const Icon(Icons.task_alt, size: 20),
                            onPressed: () => _markRotated(h),
                          ),
                        ])
                      : Chip(label: Text(l10n.rotationOk)),
                ),
              )),
        if (_health.any((h) => h.needsRotation)) ...[
          const SizedBox(height: 4),
          Text(l10n.goRotate,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: cs.onSurfaceVariant)),
        ],
      ],
    );
  }

  String _fmt(AppLocalizations l10n, DateTime? d) {
    if (d == null) return l10n.never;
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  // ------------------------------------------------------------ ③ 隐私门禁
  Widget _lockSection(AppLocalizations l10n, ColorScheme cs) {
    return FutureBuilder<AppLockService>(
      future: AppLockService.instance != null
          ? Future.value(AppLockService.instance)
          : AppLockService.load(),
      builder: (context, snap) {
        final lock = snap.data;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.appLock, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(l10n.appLockDesc, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 8),
            FutureBuilder<bool>(
              future: lock?.canEnable() ?? Future<bool>.value(false),
              builder: (context, snap2) {
                final supported = snap2.data ?? false;
                if (!supported) {
                  return _banner(cs, Icons.no_encryption, l10n.appLockUnsupported,
                      cs.onSurfaceVariant);
                }
                return Column(children: [
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(l10n.appLockEnable),
                    value: lock?.enabled ?? false,
                    onChanged: (v) => _toggleLock(lock!, v),
                  ),
                  if (lock?.enabled == true) ...[
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      title: Text(l10n.appLockGrace),
                      subtitle: Text(l10n.appLockGraceDesc),
                      trailing: Text(_graceLabel(l10n, lock!.graceMinutes)),
                      onTap: () => _pickGrace(lock),
                    ),
                    if (lock.graceMinutes > 0)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: () async {
                            await lock.lockNow();
                            _snack(l10n.appLockLockNow);
                          },
                          icon: const Icon(Icons.lock_outline, size: 18),
                          label: Text(l10n.appLockLockNow),
                        ),
                      ),
                  ],
                ]);
              },
            ),
          ],
        );
      },
    );
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
      _snack(l10n.appLockAuthFailed);
      return;
    }
    setState(() {});
  }

  Future<void> _pickGrace(AppLockService lock) async {
    final l10n = context.l10n;
    final picked = await showModalBottomSheet<int>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(l10n.appLockGrace, style: Theme.of(ctx).textTheme.titleMedium),
          ),
          for (final m in AppLockService.graceChoices)
            ListTile(
              title: Text(_graceLabel(l10n, m)),
              trailing: m == lock.graceMinutes ? const Icon(Icons.check) : null,
              onTap: () => Navigator.pop(ctx, m),
            ),
          const SizedBox(height: 8),
        ]),
      ),
    );
    if (picked != null) {
      await lock.setGraceMinutes(picked);
      if (mounted) setState(() {});
    }
  }

  // ---------------------------------------------------------- ④ 白名单策略
  Widget _policySection(AppLocalizations l10n, ColorScheme cs) {
    return FutureBuilder<LocalPolicyProvider>(
      future: LocalPolicyProvider.instance != null
          ? Future.value(LocalPolicyProvider.instance)
          : LocalPolicyProvider.load(),
      builder: (context, snap) {
        final policy = snap.data;
        if (policy == null) return const SizedBox.shrink();
        final servers = context.watch<McpProvider>().servers;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.allowlist, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(l10n.allowlistDesc, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(l10n.allowlistEnable),
              value: policy.enabled,
              onChanged: (v) async {
                await policy.setEnabled(v);
                if (mounted) setState(() {});
              },
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: Text(l10n.allowHttp),
              value: policy.allowWebViewHttp,
              onChanged: (v) async {
                await policy.setAllowWebViewHttp(v);
                if (mounted) setState(() {});
              },
            ),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                  child: Text(l10n.mcpCommandAllowlist,
                      style: Theme.of(context).textTheme.bodyMedium)),
              TextButton.icon(
                onPressed: () => _restoreDefaultCmds(policy),
                icon: const Icon(Icons.restart_alt, size: 16),
                label: Text(l10n.restoreDefaultCmds),
              ),
            ]),
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              runSpacing: -6,
              children: [
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
                  avatar: const Icon(Icons.add, size: 18),
                  label: Text(l10n.addCommand),
                  onPressed: () => _addCommand(policy),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                  child: Text(l10n.webviewHosts,
                      style: Theme.of(context).textTheme.bodyMedium)),
              TextButton.icon(
                onPressed: () => _addHost(policy),
                icon: const Icon(Icons.add, size: 16),
                label: Text(l10n.addHost),
              ),
            ]),
            if (policy.allowedWebViewHosts.isEmpty)
              Text(l10n.webviewHostsEmpty,
                  style: Theme.of(context).textTheme.bodySmall)
            else
              Wrap(
                spacing: 6,
                runSpacing: -6,
                children: [
                  for (final h in policy.allowedWebViewHosts)
                    InputChip(
                      label: Text(h),
                      onDeleted: () async {
                        final next = Set.of(policy.allowedWebViewHosts)..remove(h);
                        await policy.setWebViewHosts(next);
                        if (mounted) setState(() {});
                      },
                    ),
                ],
              ),
            const SizedBox(height: 12),
            Text(l10n.mcpServersPolicy,
                style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 4),
            if (servers.isEmpty)
              Text(l10n.mcpServersEmpty,
                  style: Theme.of(context).textTheme.bodySmall)
            else
              ...servers.map((s) => SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: Text(s.name.isNotEmpty ? s.name : s.id),
                    subtitle: s.command != null && s.command!.isNotEmpty
                        ? Text('stdio: ${s.command}', style: const TextStyle(fontSize: 12))
                        : Text(s.transport.name, style: const TextStyle(fontSize: 12)),
                    value: policy.isMcpServerAllowed(s.id),
                    onChanged: (v) async {
                      await policy.setMcpServerEnabled(s.id, v);
                      if (mounted) setState(() {});
                    },
                  )),
          ],
        );
      },
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
      _snack(l10n.invalidCommand);
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
      _snack(l10n.invalidHost);
      return;
    }
    final next = Set.of(policy.allowedWebViewHosts)..add(host);
    await policy.setWebViewHosts(next);
    if (mounted) setState(() {});
  }

  // ---------------------------------------------------------- ⑤ 最近安全事件
  Widget _auditSection(AppLocalizations l10n, ColorScheme cs) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Expanded(
              child: Text(l10n.auditTrail,
                  style: Theme.of(context).textTheme.titleMedium)),
          if (_audit.isNotEmpty)
            TextButton(
              onPressed: _clearAudit,
              child: Text(l10n.auditClear),
            ),
        ]),
        const SizedBox(height: 4),
        Text(l10n.auditTrailDesc, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 12),
        if (_auditLoading)
          const Center(child: CircularProgressIndicator())
        else if (_audit.isEmpty)
          _banner(cs, Icons.receipt_long, l10n.auditEmpty, cs.onSurfaceVariant)
        else
          ..._audit.map((e) => ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                leading: Icon(
                  e.ok ? Icons.receipt_long : Icons.warning_amber_rounded,
                  size: 20,
                  color: e.ok ? cs.onSurfaceVariant : Colors.amber.shade700,
                ),
                title: Text(_auditText(l10n, e)),
                subtitle: Text(_fmtTime(e.time),
                    style: Theme.of(context).textTheme.bodySmall),
              )),
      ],
    );
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

  Widget _banner(ColorScheme cs, IconData icon, String text, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 8),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}
