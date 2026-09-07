import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/ios_tactile.dart';
import '../../../shared/widgets/app_sheet.dart';
import '../../../core/services/haptics.dart';

Future<void> showReasoningBudgetSheet(BuildContext context) async {
  await showAppSheet(context: context, builder: const _ReasoningBudgetSheet());
}

class _ReasoningBudgetSheet extends StatefulWidget {
  const _ReasoningBudgetSheet();
  @override
  State<_ReasoningBudgetSheet> createState() => _ReasoningBudgetSheetState();
}

class _ReasoningBudgetSheetState extends State<_ReasoningBudgetSheet> {
  late int? _selected;
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    final s = context.read<SettingsProvider>();
    _selected = s.thinkingBudget ?? -1;
    _controller = TextEditingController(text: (_selected ?? -1).toString());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _select(int value) {
    setState(() {
      _selected = value;
      _controller.text = value.toString();
    });
    context.read<SettingsProvider>().setThinkingBudget(value);
  }

  int _bucket(int? n) {
    if (n == null) return -1; // treat as auto in UI bucketting
    if (n == -1) return -1;
    if (n < 1024) return 0;
    if (n < 16000) return 1024;
    if (n < 32000) return 16000;
    return 32000;
  }

  String _bucketName(BuildContext context, int? n) {
    final l10n = AppLocalizations.of(context)!;
    final b = _bucket(n);
    switch (b) {
      case 0:
        return l10n.reasoningBudgetSheetOff;
      case -1:
        return l10n.reasoningBudgetSheetAuto;
      case 1024:
        return l10n.reasoningBudgetSheetLight;
      case 16000:
        return l10n.reasoningBudgetSheetMedium;
      default:
        return l10n.reasoningBudgetSheetHeavy;
    }
  }

  Widget _tile(IconData icon, String title, int value, {String? subtitle, bool deepthink = false}) {
    final cs = Theme.of(context).colorScheme;
    final active = _bucket(_selected) == value;
    final Color iconColor = active ? cs.primary : cs.onSurface.withOpacity(0.7);
    final Color onColor = active ? cs.primary : cs.onSurface;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: SizedBox(
        height: 48,
        child: IosCardPress(
          borderRadius: BorderRadius.circular(14),
          baseColor: cs.surface,
          duration: const Duration(milliseconds: 260),
          onTap: () {
            Haptics.light();
            _select(value);
            Navigator.of(context).maybePop();
          },
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              deepthink
                  ? SvgPicture.asset(
                      'assets/icons/deepthink.svg',
                      width: 18,
                      height: 18,
                      colorFilter: ColorFilter.mode(iconColor, BlendMode.srcIn),
                    )
                  : Icon(icon, size: 20, color: iconColor),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: onColor),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (active) Icon(Lucide.Check, size: 18, color: cs.primary) else const SizedBox(width: 18),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return AppSheet(
      children: [
        _tile(Lucide.X, l10n.reasoningBudgetSheetOff, 0),
        _tile(Lucide.Settings2, l10n.reasoningBudgetSheetAuto, -1),
        _tile(Lucide.Brain, l10n.reasoningBudgetSheetLight, 1024, deepthink: true),
        _tile(Lucide.Brain, l10n.reasoningBudgetSheetMedium, 16000, deepthink: true),
        _tile(Lucide.Brain, l10n.reasoningBudgetSheetHeavy, 32000, deepthink: true),
      ],
    );
  }
}
