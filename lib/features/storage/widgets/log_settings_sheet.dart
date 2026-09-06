import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../icons/lucide_adapter.dart';
import '../../../l10n/app_localizations.dart';
import 'storage_ios_widgets.dart';

/// 日志设置底部弹窗：保存响应输出 / 省略大载荷 / 自动删除 / 日志大小上限。
class LogSettingsSheet extends StatefulWidget {
  const LogSettingsSheet({super.key});

  @override
  State<LogSettingsSheet> createState() => _LogSettingsSheetState();
}

class _LogSettingsSheetState extends State<LogSettingsSheet> {
  bool _saveResponse = true;
  bool _omitLarge = true;
  int _autoDeleteDays = 0; // 0 = 不启用
  int _sizeLimitMB = 50;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _saveResponse = prefs.getBool('log_save_response') ?? true;
      _omitLarge = prefs.getBool('log_omit_large') ?? true;
      _autoDeleteDays = prefs.getInt('log_auto_delete_days') ?? 0;
      _sizeLimitMB = prefs.getInt('log_size_limit_mb') ?? 50;
    });
  }

  Future<void> _setBool(String key, bool v) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, v);
    if (mounted) setState(() {});
  }

  Widget _navRow(BuildContext context, {
    required IconData icon,
    required String label,
    required String value,
    required VoidCallback onTap,
  }) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        child: Row(
          children: [
            SizedBox(width: 26, child: Icon(icon, size: 18, color: cs.onSurface.withOpacity(0.7))),
            const SizedBox(width: 10),
            Expanded(child: Text(label, style: const TextStyle(fontSize: 15))),
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Text(
                value,
                style: TextStyle(fontSize: 13, color: cs.onSurface.withOpacity(0.6)),
              ),
            ),
            Icon(Lucide.ChevronRight, size: 16, color: cs.onSurface.withOpacity(0.6)),
          ],
        ),
      ),
    );
  }

  Widget _switchRow(BuildContext context, {
    required IconData icon,
    required String label,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: () => onChanged(!value),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        child: Row(
          children: [
            SizedBox(width: 26, child: Icon(icon, size: 18, color: cs.onSurface.withOpacity(0.7))),
            const SizedBox(width: 10),
            Expanded(child: Text(label, style: const TextStyle(fontSize: 15))),
            Switch.adaptive(value: value, onChanged: onChanged),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final themeDark = Theme.of(context).brightness == Brightness.dark;
    final bg = themeDark ? Colors.white10 : Colors.white.withOpacity(0.96);

    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: cs.onSurface.withOpacity(0.2),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(Lucide.X, size: 18, color: Colors.transparent),
                Expanded(
                  child: Center(
                    child: Text(
                      l10n.logSettingsTitle,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
                InkWell(
                  onTap: () => Navigator.of(context).pop(),
                  child: const Padding(
                    padding: EdgeInsets.all(2),
                    child: Icon(Lucide.X, size: 18),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Container(
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(12),
                border: storageCardBorder(context),
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  _switchRow(
                    context,
                    icon: Lucide.Save,
                    label: l10n.logSettingsSaveResponse,
                    value: _saveResponse,
                    onChanged: (v) {
                      setState(() => _saveResponse = v);
                      _setBool('log_save_response', v);
                    },
                  ),
                  Divider(height: 6, thickness: 0.6, indent: 48, endIndent: 12,
                      color: cs.outlineVariant.withOpacity(0.18)),
                  _switchRow(
                    context,
                    icon: Lucide.Scissors,
                    label: l10n.logSettingsOmitLarge,
                    value: _omitLarge,
                    onChanged: (v) {
                      setState(() => _omitLarge = v);
                      _setBool('log_omit_large', v);
                    },
                  ),
                  Divider(height: 6, thickness: 0.6, indent: 48, endIndent: 12,
                      color: cs.outlineVariant.withOpacity(0.18)),
                  _navRow(
                    context,
                    icon: Lucide.CalendarClock,
                    label: l10n.logSettingsAutoDelete,
                    value: _autoDeleteDays == 0
                        ? l10n.logSettingsAutoDeleteNone
                        : l10n.logSettingDays(_autoDeleteDays),
                    onTap: () => _pickDays(l10n),
                  ),
                  Divider(height: 6, thickness: 0.6, indent: 48, endIndent: 12,
                      color: cs.outlineVariant.withOpacity(0.18)),
                  _navRow(
                    context,
                    icon: Lucide.Gauge,
                    label: l10n.logSettingsSizeLimit,
                    value: l10n.logSettingSizeText(_sizeLimitMB),
                    onTap: () => _pickSize(l10n),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickDays(AppLocalizations l10n) async {
    final opts = [0, 3, 7, 14, 30];
    final prefs = await SharedPreferences.getInstance();
    await _sheetPicker(
      context,
      title: l10n.logSettingsAutoDelete,
      options: [
        for (final d in opts)
          (
            d == 0 ? l10n.logSettingsAutoDeleteNone : l10n.logSettingDays(d),
            d == _autoDeleteDays,
            () { setState(() => _autoDeleteDays = d); prefs.setInt('log_auto_delete_days', d); },
          ),
      ],
    );
  }

  Future<void> _pickSize(AppLocalizations l10n) async {
    final opts = [20, 50, 100, 200, 500];
    final prefs = await SharedPreferences.getInstance();
    await _sheetPicker(
      context,
      title: l10n.logSettingsSizeLimit,
      options: [
        for (final s in opts)
          (
            l10n.logSettingSizeText(s),
            s == _sizeLimitMB,
            () { setState(() => _sizeLimitMB = s); prefs.setInt('log_size_limit_mb', s); },
          ),
      ],
    );
  }

  Future<void> _sheetPicker(
    BuildContext context, {
    required String title,
    required List<(String, bool, VoidCallback)> options,
  }) async {
    final cs = Theme.of(context).colorScheme;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: cs.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: cs.onSurface.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              const SizedBox(height: 12),
              Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              const SizedBox(height: 12),
              for (final o in options)
                ListTile(
                  title: Text(o.$1),
                  trailing: o.$2 ? Icon(Lucide.Check, color: cs.primary, size: 20) : null,
                  onTap: () {
                    o.$3();
                    Navigator.of(ctx).pop();
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }
}