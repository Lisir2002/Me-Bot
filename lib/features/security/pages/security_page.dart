import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
import '../../../core/services/security/policy_provider.dart';
import '../../../l10n/app_localizations.dart';

/// 安全中心（PR-5 ~ PR-8 的统一入口）。
///
/// 四段：① 安全体检（一键扫描 + 修复）② 密钥健康（轮换提醒）
/// ③ 隐私门禁（生物识别/PIN）④ 白名单策略（MCP 命令 / WebView URL）。
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

  @override
  void initState() {
    super.initState();
    _loadHealth();
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

    return SecurityCheckupService([
      LegacyPrefsScanner(prefs),
      if (secure != null)
        OrphanCredentialScanner(
          secure,
          knownProviderIds: knownProviders,
          knownServiceIds: knownServices,
        ),
      // 本机备份文件：暂无统一备份目录，接入后传实际文件列表即可（扫描器已单测）。
      BackupFileScanner(Future.value(const [])),
      LogFileScanner(logs()),
    ]);
  }

  Future<void> _runCheckup() async {
    setState(() => _running = true);
    try {
      final svc = await _buildService();
      final report = await svc.run();
      if (!mounted) return;
      setState(() => _report = report);
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  Future<void> _autoFix() async {
    final report = _report;
    if (report == null) return;
    final fixable = report.fixable;
    if (fixable.isEmpty) {
      _snack(AppLocalizations.of(context)!.checkupFixNone);
      return;
    }
    final svc = await _buildService();
    await svc.fix(fixable);
    if (!mounted) return;
    _snack(AppLocalizations.of(context)!.checkupFixSuccess);
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

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
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
                  : const Icon(Icons.play_arrow),
              label: Text(_running ? l10n.checkupRunning : l10n.runCheckup),
            ),
            const SizedBox(width: 12),
            if (_report != null && _report!.fixable.isNotEmpty)
              OutlinedButton.icon(
                onPressed: _autoFix,
                icon: const Icon(Icons.build),
                label: Text(l10n.checkupFix),
              ),
          ],
        ),
        const SizedBox(height: 12),
        if (_report == null)
          const SizedBox.shrink()
        else if (_report!.findings.isEmpty)
          _banner(cs, Icons.check_circle, l10n.checkupNoIssue, Colors.green)
        else
          ..._report!.findings.map((f) => _findingCard(f, l10n)),
      ],
    );
  }

  Widget _findingCard(CheckupFinding f, AppLocalizations l10n) {
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
      child: ListTile(
        leading: Icon(icon, color: color),
        title: Text(f.title),
        subtitle: Text(f.detail),
        isThreeLine: true,
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
                  leading: Icon(
                    h.needsRotation ? Icons.warning_amber_rounded : Icons.verified_user,
                    color: h.needsRotation ? Colors.amber.shade700 : Colors.green,
                  ),
                  title: Text(h.providerId),
                  subtitle: Text(
                      '${l10n.keyCountLabel}: ${h.keyCount} · ${l10n.lastRotated}: ${_fmt(l10n, h.lastRotatedAt)}'),
                  trailing: h.needsRotation
                      ? Chip(
                          label: Text(l10n.suggestRotation),
                          backgroundColor: Colors.amber.shade100,
                        )
                      : Chip(label: Text(l10n.rotationOk)),
                ),
              )),
      ],
    );
  }

  String _fmt(AppLocalizations l10n, DateTime? d) {
    if (d == null) return l10n.never;
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  // ------------------------------------------------------------ ③ 隐私门禁
  Widget _lockSection(AppLocalizations l10n, ColorScheme cs) {
    return FutureBuilder<bool>(
      future: AppLockService.instance?.canEnable() ?? AppLockService.load().then((s) => s.canEnable()),
      builder: (context, snap) {
        final supported = snap.data ?? false;
        final lock = AppLockService.instance;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.appLock, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(l10n.appLockDesc, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 8),
            if (!supported)
              _banner(cs, Icons.no_encryption, l10n.appLockUnsupported,
                  cs.onSurfaceVariant)
            else
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(l10n.appLockEnable),
                value: lock?.enabled ?? false,
                onChanged: (v) async {
                  final svc = AppLockService.instance ?? await AppLockService.load();
                  final ok = await svc.setEnabled(v);
                  if (!ok && mounted) {
                    _snack(l10n.appLockUnsupported);
                  }
                  if (mounted) setState(() {});
                },
              ),
          ],
        );
      },
    );
  }

  // ---------------------------------------------------------- ④ 白名单策略
  Widget _policySection(AppLocalizations l10n, ColorScheme cs) {
    return FutureBuilder<PolicyProvider>(
      future: LocalPolicyProvider.load(),
      builder: (context, snap) {
        final policy = snap.data;
        if (policy == null) return const SizedBox.shrink();
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
              title: Text(l10n.allowHttp),
              value: policy.allowWebViewHttp,
              onChanged: (v) async {
                await policy.setAllowWebViewHttp(v);
                if (mounted) setState(() {});
              },
            ),
            const SizedBox(height: 8),
            Text(l10n.mcpCommandAllowlist,
                style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              children: policy.allowedMcpCommands
                  .map((c) => Chip(label: Text(c)))
                  .toList(),
            ),
            if (policy.allowedWebViewHosts.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(l10n.webviewHosts,
                  style: Theme.of(context).textTheme.bodyMedium),
              const SizedBox(height: 4),
              Wrap(
                spacing: 6,
                children: policy.allowedWebViewHosts
                    .map((c) => Chip(label: Text(c)))
                    .toList(),
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _banner(ColorScheme cs, IconData icon, String text, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
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
