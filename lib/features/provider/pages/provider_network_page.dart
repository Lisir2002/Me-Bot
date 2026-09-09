import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/providers/settings_provider.dart';
import '../../../l10n/build_context_l10n.dart';
import '../../../shared/widgets/app_page.dart';
import '../../../shared/widgets/ios_switch.dart';
import '../../../theme/design_tokens.dart';

/// 供应商「网络」设置页。
///
/// 已迁移到 AppPage 槽位骨架：
/// - 手写 Scaffold + AppBar + ListView.padding → AppPage(title/bodyPadding/body)
/// - 返回键由 AppPage 统一提供（showBack 默认 true），删除页面私有 IconButton
/// - 魔法数字 padding/间距/圆角 → AppPagePadding / AppGap / AppRadius
/// - 未使用 states: 槽位（本页无一次性 Future 加载），保持即时保存 UX
class ProviderNetworkPage extends StatefulWidget {
  const ProviderNetworkPage({
    super.key,
    required this.providerKey,
    required this.providerDisplayName,
  });
  final String providerKey;
  final String providerDisplayName;

  @override
  State<ProviderNetworkPage> createState() => _ProviderNetworkPageState();
}

class _ProviderNetworkPageState extends State<ProviderNetworkPage> {
  bool _proxyEnabled = false;
  final _proxyHostCtrl = TextEditingController();
  final _proxyPortCtrl = TextEditingController(text: '8080');
  final _proxyUserCtrl = TextEditingController();
  final _proxyPassCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    final settings = context.read<SettingsProvider>();
    final cfg =
        settings.getProviderConfig(widget.providerKey, defaultName: widget.providerDisplayName);
    _proxyEnabled = cfg.proxyEnabled ?? false;
    _proxyHostCtrl.text = cfg.proxyHost ?? '';
    _proxyPortCtrl.text = cfg.proxyPort ?? '8080';
    _proxyUserCtrl.text = cfg.proxyUsername ?? '';
    _proxyPassCtrl.text = cfg.proxyPassword ?? '';
  }

  @override
  void dispose() {
    _proxyHostCtrl.dispose();
    _proxyPortCtrl.dispose();
    _proxyUserCtrl.dispose();
    _proxyPassCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AppPage(
      title: l10n.providerDetailPageNetworkTab,
      // AppPagePadding.content = LTRB(16, 12, 16, 16)，与原 ListView padding 完全一致
      bodyPadding: AppPagePadding.content,
      // 引擎默认 scrollable: true，会把 body 包进 ListView（含键盘避让），
      // 因此这里直接给 Column，不要自己再包 ListView，避免嵌套滚动。
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _switchRow(
            title: l10n.providerDetailPageEnableProxyTitle,
            value: _proxyEnabled,
            onChanged: (v) {
              setState(() => _proxyEnabled = v);
              _saveNetwork();
            },
          ),
          if (_proxyEnabled) ...[
            SizedBox(height: AppGap.sm),
            _inputRow(
              label: l10n.providerDetailPageHostLabel,
              controller: _proxyHostCtrl,
              hint: '127.0.0.1',
              onChanged: (_) => _saveNetwork(),
            ),
            SizedBox(height: AppGap.sm),
            _inputRow(
              label: l10n.providerDetailPagePortLabel,
              controller: _proxyPortCtrl,
              hint: '8080',
              onChanged: (_) => _saveNetwork(),
            ),
            SizedBox(height: AppGap.sm),
            _inputRow(
              label: l10n.providerDetailPageUsernameOptionalLabel,
              controller: _proxyUserCtrl,
              onChanged: (_) => _saveNetwork(),
            ),
            SizedBox(height: AppGap.sm),
            _inputRow(
              label: l10n.providerDetailPagePasswordOptionalLabel,
              controller: _proxyPassCtrl,
              obscure: true,
              onChanged: (_) => _saveNetwork(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _switchRow({
    required String title,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Row(
      children: [
        Expanded(child: Text(title, style: const TextStyle(fontSize: 15))),
        IosSwitch(value: value, onChanged: onChanged),
      ],
    );
  }

  Widget _inputRow({
    required String label,
    required TextEditingController controller,
    String? hint,
    bool obscure = false,
    ValueChanged<String>? onChanged,
  }) {
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
          onChanged: onChanged,
          decoration: InputDecoration(
            hintText: hint,
            filled: true,
            fillColor: isDark ? Colors.white10 : const Color(0xFFF2F3F5),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadius.md),
              borderSide: BorderSide(color: Colors.transparent),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadius.md),
              borderSide: BorderSide(color: Colors.transparent),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadius.md),
              borderSide: BorderSide(color: cs.primary.withOpacity(0.4)),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _saveNetwork() async {
    final settings = context.read<SettingsProvider>();
    final old =
        settings.getProviderConfig(widget.providerKey, defaultName: widget.providerDisplayName);
    final cfg = old.copyWith(
      proxyEnabled: _proxyEnabled,
      proxyHost: _proxyHostCtrl.text.trim(),
      proxyPort: _proxyPortCtrl.text.trim(),
      proxyUsername: _proxyUserCtrl.text.trim(),
      proxyPassword: _proxyPassCtrl.text.trim(),
    );
    await settings.setProviderConfig(widget.providerKey, cfg);
    // Silent auto-save (no snackbar) to match immediate-save UX
    if (!mounted) return;
  }
}
