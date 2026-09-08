import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:http/io_client.dart';
import 'package:socks5_proxy/socks_client.dart' as socks;

import '../../../l10n/app_localizations.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../shared/widgets/app_page.dart';
import '../../../shared/widgets/app_sheet.dart';
import '../../../shared/widgets/ios_switch.dart';
import '../../../shared/widgets/ios_tactile.dart';
import '../../../shared/widgets/card_surface.dart';
import '../../../theme/design_tokens.dart';

/// 全局网络代理设置页。
///
/// 已迁移到 AppPage 槽位骨架：
/// - Scaffold + AppBar + ListView → AppPage(title/leading/body)，body 用 Column(stretch)
/// - padding LTRB(16,12,16,16) → fromLTRB(AppGap.md, AppGap.sm, AppGap.md, AppGap.md)
/// - **私有 `_TactileIconButton` → 共享 `IosIconButton`**（删除私有副本）
/// - **代理类型选择：手写 `showModalBottomSheet` → `showAppSheet` + `AppSheet`**
/// - 删除死代码 `_divider`（全文件无引用）
/// - `_sheetOption` 里未使用的 `isDark` 一并移除
///
/// 注：6 / 10 / 14 / 48 等数值在设计 Token 中无精确对应，保留字面量并就近注释。
class NetworkProxyPage extends StatefulWidget {
  const NetworkProxyPage({super.key});

  @override
  State<NetworkProxyPage> createState() => _NetworkProxyPageState();
}

class _NetworkProxyPageState extends State<NetworkProxyPage> {
  late final TextEditingController _hostCtl;
  late final TextEditingController _portCtl;
  late final TextEditingController _userCtl;
  late final TextEditingController _passCtl;
  final FocusNode _hostFn = FocusNode();
  final FocusNode _portFn = FocusNode();
  final FocusNode _userFn = FocusNode();
  final FocusNode _passFn = FocusNode();

  String _type = 'http';
  bool _enabled = false;

  final TextEditingController _testUrlCtl = TextEditingController(text: 'https://www.google.com');
  bool _testing = false;
  String? _testErr;
  bool? _ok;

  @override
  void initState() {
    super.initState();
    final sp = context.read<SettingsProvider>();
    _enabled = sp.globalProxyEnabled;
    _type = sp.globalProxyType;
    _hostCtl = TextEditingController(text: sp.globalProxyHost);
    _portCtl = TextEditingController(text: sp.globalProxyPort);
    _userCtl = TextEditingController(text: sp.globalProxyUsername);
    _passCtl = TextEditingController(text: sp.globalProxyPassword);
    _hostFn.addListener(() { if (!_hostFn.hasFocus) sp.setGlobalProxyHost(_hostCtl.text); });
    _portFn.addListener(() { if (!_portFn.hasFocus) sp.setGlobalProxyPort(_portCtl.text); });
    _userFn.addListener(() { if (!_userFn.hasFocus) sp.setGlobalProxyUsername(_userCtl.text); });
    _passFn.addListener(() { if (!_passFn.hasFocus) sp.setGlobalProxyPassword(_passCtl.text); });
  }

  @override
  void dispose() {
    _hostCtl.dispose();
    _portCtl.dispose();
    _userCtl.dispose();
    _passCtl.dispose();
    _hostFn.dispose();
    _portFn.dispose();
    _userFn.dispose();
    _passFn.dispose();
    _testUrlCtl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    return AppPage(
      title: l10n.settingsPageNetworkProxy,
      leading: Tooltip(
        message: l10n.settingsPageBackButton,
        child: IosIconButton(
          haptics: true,
          icon: Lucide.ArrowLeft,
          color: cs.onSurface,
          size: 22,
          minSize: 44,
          semanticLabel: l10n.settingsPageBackButton,
          onTap: () => Navigator.of(context).maybePop(),
        ),
      ),
      bodyPadding: const EdgeInsets.fromLTRB(AppGap.md, AppGap.sm, AppGap.md, AppGap.md),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _sectionCard(children: [
            Padding(
              // 10 无精确 token
              padding: const EdgeInsets.symmetric(horizontal: AppGap.sm, vertical: 10),
              child: Row(
                children: [
                  Expanded(child: Text(l10n.networkProxyEnableLabel, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600))),
                  IosSwitch(
                    value: _enabled,
                    onChanged: (v) async {
                      setState(() => _enabled = v);
                      await context.read<SettingsProvider>().setGlobalProxyEnabled(v);
                    },
                  ),
                ],
              ),
            ),
            _labeledField(
              context,
              label: l10n.networkProxyType,
              child: _ProxyTypeSheetField(
                value: _type,
                onChanged: (v) async {
                  if (v == null) return;
                  setState(() => _type = v);
                  await context.read<SettingsProvider>().setGlobalProxyType(v);
                },
              ),
            ),
            _labeledField(
              context,
              label: l10n.networkProxyServerHost,
              child: TextField(
                controller: _hostCtl,
                focusNode: _hostFn,
                decoration: _deskInputDecoration(context).copyWith(hintText: '127.0.0.1'),
              ),
            ),
            _labeledField(
              context,
              label: l10n.networkProxyPort,
              child: TextField(
                controller: _portCtl,
                focusNode: _portFn,
                keyboardType: TextInputType.number,
                decoration: _deskInputDecoration(context).copyWith(hintText: '8080'),
              ),
            ),
            _labeledField(
              context,
              label: l10n.networkProxyUsername,
              child: TextField(
                controller: _userCtl,
                focusNode: _userFn,
                decoration: _deskInputDecoration(context).copyWith(hintText: l10n.networkProxyOptionalHint),
              ),
            ),
            _labeledField(
              context,
              label: l10n.networkProxyPassword,
              child: TextField(
                controller: _passCtl,
                focusNode: _passFn,
                obscureText: true,
                decoration: _deskInputDecoration(context).copyWith(hintText: l10n.networkProxyOptionalHint),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(AppGap.sm, AppGap.xs, AppGap.sm, 10),
              child: Text(l10n.networkProxyPriorityNote, style: TextStyle(fontSize: 12, color: cs.onSurface.withOpacity(0.6))),
            ),
          ]),
          const SizedBox(height: AppGap.sm),
          // 连接测试区
          Padding(
            padding: const EdgeInsets.fromLTRB(AppGap.sm, AppGap.xxxs, AppGap.sm, 6),
            child: Text(l10n.networkProxyTestHeader, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          ),
          _sectionCard(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(AppGap.sm, AppGap.xs, AppGap.sm, AppGap.xxs),
              child: TextField(
                controller: _testUrlCtl,
                decoration: _deskInputDecoration(context).copyWith(hintText: l10n.networkProxyTestUrlHint),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(AppGap.sm, AppGap.xxs, AppGap.sm, 10),
              child: Align(
                alignment: Alignment.centerRight,
                child: _DeskIosButton(
                  label: _testing ? l10n.networkProxyTesting : l10n.networkProxyTestButton,
                  filled: false,
                  dense: true,
                  // TODO(优化)：_DeskIosButton.onTap 若改为可空，这里传 `_testing ? null : _onTest`
                  // 可让按钮在测试中自动置灰，比空回调更规范。
                  onTap: _testing ? (){} : _onTest,
                ),
              ),
            ),
          ]),
          if (_ok == true)
            Padding(
              padding: const EdgeInsets.fromLTRB(AppGap.sm, AppGap.xs, AppGap.sm, 0),
              child: Text(l10n.networkProxyTestSuccess, style: TextStyle(color: Colors.green.shade600, fontWeight: FontWeight.w600)),
            ),
          if (_ok == false)
            Padding(
              padding: const EdgeInsets.fromLTRB(AppGap.sm, AppGap.xs, AppGap.sm, 0),
              child: Text(l10n.networkProxyTestFailed(_testErr ?? ''), style: TextStyle(color: cs.error)),
            ),
        ],
      ),
    );
  }

  Future<void> _onTest() async {
    final l10n = AppLocalizations.of(context)!;
    final url = _testUrlCtl.text.trim();
    if (url.isEmpty) {
      setState(() { _ok = false; _testErr = l10n.networkProxyNoUrl; });
      return;
    }
    setState(() { _testing = true; _ok = null; _testErr = null; });
    try {
      final host = _hostCtl.text.trim();
      final port = int.tryParse(_portCtl.text.trim()) ?? 8080;
      final user = _userCtl.text.trim();
      final pass = _passCtl.text;
      final io = HttpClient();
      if (_type == 'socks5') {
        try {
          final proxies = <socks.ProxySettings>[
            socks.ProxySettings(InternetAddress(host), port,
                username: user.isNotEmpty ? user : null, password: pass),
          ];
          socks.SocksTCPClient.assignToHttpClient(io, proxies);
        } catch (_) {}
      } else {
        io.findProxy = (_) => 'PROXY $host:$port';
        if (user.isNotEmpty) {
          io.addProxyCredentials(host, port, '', HttpClientBasicCredentials(user, pass));
        }
      }
      final client = IOClient(io);
      final res = await client.get(Uri.parse(url)).timeout(const Duration(seconds: 8));
      client.close();
      setState(() { _testing = false; _ok = (res.statusCode >= 200 && res.statusCode < 400); _testErr = _ok == true ? null : 'HTTP ${res.statusCode}'; });
    } catch (e) {
      setState(() { _testing = false; _ok = false; _testErr = e.toString(); });
    }
  }
}

/// 代理类型下拉选择器（点击弹出 AppSheet）。
class _ProxyTypeSheetField extends StatelessWidget {
  const _ProxyTypeSheetField({required this.value, required this.onChanged});
  final String value;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fillColor = isDark ? Colors.white10 : const Color(0xFFF7F7F9);

    String labelOf(String v) {
      switch (v) {
        case 'https': return l10n.networkProxyTypeHttps;
        case 'socks5': return l10n.networkProxyTypeSocks5;
        case 'http':
        default: return l10n.networkProxyTypeHttp;
      }
    }

    Future<void> openSheet() async {
      // 手写 showModalBottomSheet → showAppSheet + AppSheet（统一圆角/底色/键盘避让）
      final selected = await showAppSheet<String>(
        context: context,
        builder: AppSheet(
          children: [
            _sheetOption(context, text: l10n.networkProxyTypeHttp, selected: value == 'http',
                onTap: () => Navigator.of(context).pop('http')),
            _sheetDivider(context),
            _sheetOption(context, text: l10n.networkProxyTypeHttps, selected: value == 'https',
                onTap: () => Navigator.of(context).pop('https')),
            _sheetDivider(context),
            _sheetOption(context, text: l10n.networkProxyTypeSocks5, selected: value == 'socks5',
                onTap: () => Navigator.of(context).pop('socks5')),
          ],
        ),
      );
      if (selected != null) onChanged(selected);
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: openSheet,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: AppGap.sm, vertical: AppGap.sm),
        decoration: BoxDecoration(
          color: fillColor,
          // 10 无精确 token（AppRadius.sm=8 / md=12），保留字面量
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: cs.outlineVariant.withOpacity(0.12), width: 0.6),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                labelOf(value),
                style: TextStyle(fontSize: 14, color: cs.onSurface.withOpacity(0.88)),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Icon(Icons.keyboard_arrow_down_rounded, size: 18, color: cs.onSurface.withOpacity(0.55)),
          ],
        ),
      ),
    );
  }

  Widget _sheetOption(BuildContext ctx,
      {required String text, required bool selected, required VoidCallback onTap}) {
    final cs = Theme.of(ctx).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppGap.xxs),
      child: SizedBox(
        height: 48,
        child: IosCardPress(
          borderRadius: BorderRadius.circular(14),
          baseColor: cs.surface,
          duration: const Duration(milliseconds: 220),
          onTap: onTap,
          padding: const EdgeInsets.symmetric(horizontal: AppGap.sm),
          child: Row(
            children: [
              Expanded(child: Text(text, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500))),
              if (selected) Icon(Icons.check, size: 18, color: cs.primary),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sheetDivider(BuildContext ctx) {
    final cs = Theme.of(ctx).colorScheme;
    final isDark = Theme.of(ctx).brightness == Brightness.dark;
    return Divider(height: 1, thickness: 0.6, indent: AppGap.sm, endIndent: AppGap.sm,
        color: cs.outlineVariant.withOpacity(isDark ? 0.10 : 0.08));
  }
}

Widget _sectionCard({required List<Widget> children}) {
  return Builder(builder: (context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final Color bg = isDark ? Colors.white10 : Colors.white.withOpacity(0.96);
    return Container(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: AppCardSurface.border(context),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppGap.xxs),
        child: Column(children: children),
      ),
    );
  });
}

Widget _labeledField(BuildContext context, {required String label, required Widget child}) {
  final cs = Theme.of(context).colorScheme;
  return Padding(
    padding: const EdgeInsets.fromLTRB(AppGap.sm, 10, AppGap.sm, AppGap.xs),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text(label, style: TextStyle(fontSize: 12.5, color: cs.onSurface.withOpacity(0.7))),
        ),
        child,
      ],
    ),
  );
}

/// 与桌面端一致的输入框样式。
InputDecoration _deskInputDecoration(BuildContext context) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  final cs = Theme.of(context).colorScheme;
  return InputDecoration(
    isDense: true,
    filled: true,
    fillColor: isDark ? Colors.white10 : const Color(0xFFF7F7F9),
    hintStyle: TextStyle(fontSize: 14, color: cs.onSurface.withOpacity(0.5)),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: cs.outlineVariant.withOpacity(0.12), width: 0.6),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: cs.outlineVariant.withOpacity(0.12), width: 0.6),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: cs.primary.withOpacity(0.35), width: 0.8),
    ),
    contentPadding: const EdgeInsets.symmetric(horizontal: AppGap.sm, vertical: 10),
  );
}

class _DeskIosButton extends StatefulWidget {
  const _DeskIosButton({required this.label, required this.filled, required this.dense, required this.onTap});
  final String label; final bool filled; final bool dense; final VoidCallback onTap;
  @override State<_DeskIosButton> createState() => _DeskIosButtonState();
}

class _DeskIosButtonState extends State<_DeskIosButton> {
  bool _pressed = false;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme; final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = widget.filled ? Colors.white : cs.onSurface.withOpacity(0.9);
    final bg = widget.filled
        ? cs.primary
        : (isDark ? Colors.white.withOpacity(0.06) : Colors.black.withOpacity(0.05));
    final borderColor = widget.filled ? Colors.transparent : cs.outlineVariant.withOpacity(isDark ? 0.22 : 0.18);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _pressed ? 0.98 : 1.0,
        duration: const Duration(milliseconds: 110),
        curve: Curves.easeOutCubic,
        child: Container(
          padding: EdgeInsets.symmetric(
              vertical: widget.dense ? AppGap.xs : AppGap.sm, horizontal: AppGap.sm),
          alignment: Alignment.center,
          decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(color: borderColor)),
          child: Text(widget.label,
              style: TextStyle(color: textColor, fontWeight: FontWeight.w600, fontSize: widget.dense ? 13 : 14)),
        ),
      ),
    );
  }
}
