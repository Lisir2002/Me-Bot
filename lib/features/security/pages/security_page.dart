// ignore_for_file: hardcoded_ui_string
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
import '../../../core/services/security/credential_audit_logger.dart';
import '../../../core/services/security/policy_provider.dart';
import '../../../l10n/build_context_l10n.dart';
import '../../../shared/widgets/app_dialog.dart';
import '../../../shared/widgets/app_list_view.dart';
import '../../../shared/widgets/app_page.dart';
import '../../../shared/widgets/snackbar.dart';
import '../../../theme/design_tokens.dart';
import '../../../utils/app_directories.dart';
import '../checkup_strings_l10n.dart';
import '../../provider/pages/provider_detail_page.dart';
import '../widgets/security_score_card.dart';
import '../widgets/security_checkup_section.dart';
import '../widgets/security_key_health_section.dart';
import '../widgets/security_app_lock_section.dart';
import '../widgets/security_policy_section.dart';
import '../widgets/security_audit_section.dart';

/// 安全中心（PR-5 ~ PR-8 的统一入口）。
///
/// 五段：① 安全体检 ② 密钥健康 ③ 隐私门禁 ④ 白名单策略 ⑤ 最近安全事件。
/// 顶部新增安全评分仪表盘。
///
/// 双端结构：
/// - [SecurityPage] 移动端薄壳，只负责 [AppPage] 骨架；
/// - [SecurityBody] 纯 body（无 Scaffold），桌面端设置 pane 直接嵌入。
///
/// 业务逻辑已拆分到 widgets/ 下各 section 文件，本文件只保留状态管理与组装。
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
/// 持有全部状态（体检报告、密钥健康、审计日志、门禁/策略 Future 缓存），
/// 将数据与回调下发给各 section widget。
class SecurityBody extends StatefulWidget {
  const SecurityBody({super.key});

  @override
  State<SecurityBody> createState() => _SecurityBodyState();
}

class _SecurityBodyState extends State<SecurityBody> {
  // ── 体检状态 ──
  CheckupReport? _report;
  bool _running = false;
  SecurityCheckupService? _cachedService; // P1 #5：缓存体检引擎，避免重复构建

  // ── 密钥健康状态 ──
  List<KeyHealthInfo> _health = const [];
  bool _loadingHealth = false;

  // ── 审计状态 ──
  List<AuditEvent> _audit = const [];
  bool _auditLoading = true;
  int _auditLimit = 12; // P2 #9：可扩展的分页 limit

  // ── P1 #6：FutureBuilder 的 Future 在 initState 中创建，避免每次 build 重建 ──
  late final Future<AppLockService> _lockFuture;
  late final Future<LocalPolicyProvider> _policyFuture;

  @override
  void initState() {
    super.initState();
    // 进页自动体检 + 加载健康 + 加载审计
    _runCheckup();
    _loadHealth();
    _loadAudit();
    // 缓存 Future，避免 build 时重复 load
    _lockFuture = AppLockService.instance != null
        ? Future.value(AppLockService.instance!)
        : AppLockService.load();
    _policyFuture = LocalPolicyProvider.instance != null
        ? Future.value(LocalPolicyProvider.instance!)
        : LocalPolicyProvider.load();
  }

  SettingsProvider get _settings => context.read<SettingsProvider>();

  // ─────────────────────────────────────────── 体检引擎（P1 #5 缓存 + P2 #10 异步 list）

  /// 组装体检引擎：4 个扫描器。结果缓存到 [_cachedService]，一次修复流程只构建一次。
  Future<SecurityCheckupService> _buildService() async {
    final cached = _cachedService;
    if (cached != null) return cached;

    final prefs = await SharedPreferences.getInstance();
    final secure =
        SecureStorage.isInitialized ? SecureStorage.instance : null;

    final knownProviders = _settings.providerConfigs.keys.toSet();
    final knownServices = <String>{
      ..._settings.searchServices.map((s) => s.id),
      ..._settings.ttsServices.map((s) => s.id),
    };

    // P2 #10：listSync → list 异步，避免阻塞 UI 线程
    final logDir = Logger.logDir;
    Future<List<File>> logs() async {
      if (logDir == null || !await logDir.exists()) return const [];
      final entities = await logDir.list().toList();
      return entities
          .whereType<File>()
          .where((f) => f.path.endsWith('.log'))
          .toList();
    }

    Future<List<File>> backups() async {
      try {
        final dir = await AppDirectories.getAppDataDirectory();
        if (!await dir.exists()) return const [];
        final entities = await dir.list().toList();
        return entities.whereType<File>().where((f) {
          final n = f.path.toLowerCase();
          return n.endsWith('.json') || n.endsWith('.bak');
        }).toList();
      } catch (_) {
        return const [];
      }
    }

    final svc = SecurityCheckupService([
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
    _cachedService = svc;
    return svc;
  }

  Future<void> _runCheckup() async {
    final l10n = context.l10n;
    setState(() => _running = true);
    try {
      final svc = await _buildService();
      if (!mounted) return;
      final report = await svc.run(L10nCheckupStrings(l10n));
      if (!mounted) return;
      setState(() => _report = report);
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  /// 一键修复全部可修项（带确认）。
  Future<void> _autoFix() async {
    final l10n = context.l10n;
    final report = _report;
    if (report == null) return;
    final fixable = report.fixable;
    if (fixable.isEmpty) {
      _snack(l10n.checkupFixNone);
      return;
    }
    final confirmed = await AppDialog.confirm(
      context,
      title: l10n.checkupAutoFixConfirmTitle,
      message: l10n.checkupAutoFixConfirmBody(fixable.length),
      confirmText: l10n.checkupFix,
      cancelText: MaterialLocalizations.of(context).cancelButtonLabel,
    );
    if (!confirmed) return;
    final svc = await _buildService();
    final fixedCount = await svc.fix(fixable);
    // P3 #14：自动修复记录明细，每个 finding 的 title 和 severity
    for (final f in fixable) {
      CredentialAuditLogger.record(
        'fix',
        'checkup:${f.scannerId}',
        detail: '${f.title} (${f.severity.name})',
      );
    }
    if (!mounted) return;
    _snack('${l10n.checkupFixSuccess}（$fixedCount/${fixable.length} 项）',
        type: NotificationType.success);
    await _runCheckup();
    await _loadHealth();
  }

  /// P0 #1：修复单条 finding（原代码错误地修复了全部）。
  Future<void> _fixSingle(CheckupFinding f) async {
    if (!f.autoFixable) return;
    final svc = await _buildService();
    final ok = await svc.fix([f]);
    // P3 #14：记录单条修复明细
    CredentialAuditLogger.record(
      'fix',
      'checkup:${f.scannerId}',
      ok: ok > 0,
      detail: '${f.title} (${f.severity.name})',
    );
    if (!mounted) return;
    _snack(
      ok > 0 ? '已修复：${f.title}' : '修复失败：${f.title}',
      type: ok > 0 ? NotificationType.success : NotificationType.error,
    );
    await _runCheckup();
    await _loadHealth();
  }

  // ─────────────────────────────────────────── 密钥健康

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

  Future<void> _markRotated(KeyHealthInfo info) async {
    final l10n = context.l10n;
    if (!SecureStorage.isInitialized) return;
    final svc = KeyHealthService(SecureStorage.instance);
    final ok = await svc.markRotated(info.providerId);
    if (!mounted) return;
    // P3 #17：markRotated 失败也记录审计
    CredentialAuditLogger.record(
      'markRotated',
      'provider:${info.providerId}',
      ok: ok,
    );
    _snack(
      ok ? l10n.rotateMarked : '标记轮换失败',
      type: ok ? NotificationType.success : NotificationType.error,
    );
    if (ok) await _loadHealth();
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

  // ─────────────────────────────────────────── 审计日志

  Future<void> _loadAudit() async {
    setState(() => _auditLoading = true);
    try {
      final events = await CredentialAuditLogger.recent(limit: _auditLimit);
      if (!mounted) return;
      setState(() => _audit = events);
    } finally {
      if (mounted) setState(() => _auditLoading = false);
    }
  }

  /// P2 #9：加载更多审计事件。
  Future<void> _loadMoreAudit(int limit) async {
    _auditLimit = limit;
    await _loadAudit();
  }

  /// P0 #2：清除审计日志前要求生物识别验证。
  Future<void> _clearAudit() async {
    final l10n = context.l10n;
    final confirmed = await AppDialog.confirm(
      context,
      title: l10n.auditClear,
      message: l10n.auditClearConfirm,
      confirmText: l10n.auditClear,
      cancelText: MaterialLocalizations.of(context).cancelButtonLabel,
      danger: true,
    );
    if (!confirmed) return;
    // P0 #2：清除审计属于敏感操作，门禁开启时要求生物识别
    final lock = AppLockService.instance;
    if (lock != null && lock.enabled) {
      final authed = await lock.verifyWith('验证身份以清除审计日志');
      if (!authed) {
        _snack(l10n.appLockAuthFailed, type: NotificationType.error);
        return;
      }
    }
    await CredentialAuditLogger.clear();
    await _loadAudit();
  }

  void _snack(String msg, {NotificationType type = NotificationType.info}) {
    if (!mounted) return;
    showAppSnackBar(context, message: msg, type: type);
  }

  // ─────────────────────────────────────────── 页面组装

  @override
  Widget build(BuildContext context) {
    return AppListView(
      bottomPadding: AppGap.xl,
      children: [
        // 安全评分仪表盘（新功能 1）
        SecurityScoreCard(
          result: SecurityScoreResult.compute(
            report: _report,
            health: _health,
            lockEnabled: AppLockService.instance?.enabled ?? false,
            allowlistEnabled: LocalPolicyProvider.instance?.enabled ?? false,
          ),
          loading: _running || _loadingHealth,
        ),
        const SizedBox(height: AppGap.sm),
        // ① 安全体检
        SecurityCheckupSection(
          report: _report,
          running: _running,
          onRunCheckup: _runCheckup,
          onAutoFix: _autoFix,
          onFixSingle: _fixSingle,
        ),
        // ② 密钥健康
        SecurityKeyHealthSection(
          health: _health,
          loading: _loadingHealth,
          settings: _settings,
          onMarkRotated: _markRotated,
          onGotoProvider: _gotoProvider,
        ),
        // ③ 隐私门禁
        SecurityAppLockSection(
          lockFuture: _lockFuture,
          onLockChanged: () => setState(() {}),
        ),
        // ④ 白名单策略
        SecurityPolicySection(
          policyFuture: _policyFuture,
          onPolicyChanged: () => setState(() {}),
        ),
        // ⑤ 最近安全事件
        SecurityAuditSection(
          audit: _audit,
          loading: _auditLoading,
          onLoadMore: _loadMoreAudit,
          onClear: _clearAudit,
          currentLimit: _auditLimit,
          hasMore: _audit.length >= _auditLimit,
        ),
      ],
    );
  }
}
