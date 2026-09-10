import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../l10n/build_context_l10n.dart';
import '../../../shared/widgets/app_page.dart';
import '../../../theme/design_tokens.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../shared/widgets/app_section.dart';

/// Google Fonts 选择器。
///
/// 已迁移到 AppPage 槽位骨架：
/// - Scaffold + AppBar + 自定义返回键 → AppPage(title/body)，返回键由引擎统一提供
/// - ⚠️ body 内含 Expanded(ListView.builder) 需撑满剩余高度 → 必须 scrollable: false
///   且 bodyPadding 置零（外层 padding 会挤压 Expanded 可用高度）
/// - 魔法数字 padding/圆角 → AppGap / AppRadius
///
/// 附带修复（非迁移必需，可单独回退）：
/// - 字体清单原为每次 build 都 GoogleFonts.asMap() + 建表 + 排序 1500+ 项，
///   而筛选输入会 setState → 每敲一个字符就全量重建一次。改为静态缓存。
/// - 原 itemCount / itemBuilder 各调一次 _filtered()，等于每帧重复全量过滤。改为只算一次。
class GoogleFontsPickerPage extends StatefulWidget {
  const GoogleFontsPickerPage({super.key, required this.title});
  final String title;

  @override
  State<GoogleFontsPickerPage> createState() => _GoogleFontsPickerPageState();
}

class _GoogleFontsPickerPageState extends State<GoogleFontsPickerPage> {
  late final TextEditingController _filterCtrl;

  /// 字体清单是常量数据：缓存一份，避免每次 build 都重建并排序整个 map。
  static final List<String> _allFonts = GoogleFonts.asMap().keys.toList()
    ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

  @override
  void initState() {
    super.initState();
    _filterCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _filterCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    // 只算一次，供 itemCount 与 itemBuilder 复用
    final filtered = _filtered(_allFonts);

    return AppPage(
      title: widget.title,
      // body 自带 Expanded 列表 → 必须 false，否则 Expanded 在 ListView 内会抛错
      scrollable: false,
      bodyPadding: AppPagePadding.zero,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(AppGap.md, AppGap.sm, AppGap.md, AppGap.xs),
            child: TextField(
              controller: _filterCtrl,
              decoration: InputDecoration(
                hintText: l10n.fontPickerFilterHint,
                isDense: true,
                filled: true,
                fillColor: Theme.of(context).brightness == Brightness.dark
                    ? Colors.white10
                    : Colors.white,
                contentPadding: const EdgeInsets.symmetric(horizontal: AppGap.sm, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  borderSide: BorderSide(color: cs.outlineVariant.withOpacity(0.28), width: 0.8),
                ),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: filtered.length,
              itemBuilder: (context, i) {
                final fam = filtered[i];
                return AppNavRow(
                  icon: Lucide.FileText,
                  label: fam,
                  // 字形预览样张：任何语言下展示相同样张，非可翻译文案
                  // ignore: hardcoded_ui_string
                  detailBuilder: (_) => Text('Aa字', style: GoogleFonts.getFont(fam, fontSize: 18)),
                  onTap: () => Navigator.of(context).pop(fam),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  List<String> _filtered(List<String> all) {
    final q = _filterCtrl.text.trim().toLowerCase();
    if (q.isEmpty) return all;
    return all.where((e) => e.toLowerCase().contains(q)).toList();
  }
}
