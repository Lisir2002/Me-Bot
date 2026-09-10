// ──────────────────────────────────────────────────────────────
// 迁移到 AppPage 骨架（批次 4 第 3 页，1533 → 见下方行数）
//
//   Scaffold + AppBar + ListView   → AppPage(title / leading / actions / body)
//   _iosSectionCard / _iosDivider  → AppSectionCard / AppSectionDivider（shared）
//   _TactileRow / _AnimatedPressColor → IosTactileRow / IosPressColor
//   _TactileIconButton             → IosIconButton(haptics: true, minSize: 44)
//   showModalBottomSheet ×3 中收敛 2 个 → showAppSheet（新增/编辑/操作表）
//
// ⚠️ body 是 Column + CrossAxisAlignment.stretch —— scrollable 模式下子部件拿到
//    「无界高度 + 紧凑宽度」，不 stretch 卡片会缩到内容宽度（清单 3d）。
// ⚠️ `_addService` 的弹层**保留手写 showModalBottomSheet**：它需要
//    `constraints: maxHeight(0.85h)`（showAppSheet 不支持 constraints），
//    且内容是 AnimatedSize + AnimatedSwitcher + Flexible 的自绘结构，
//    套进 AppSheet 的 SingleChildScrollView 会双重滚动（见经验 #19 同类判断）。
// ⚠️ `_showServiceActions` 是无把手、行满宽的操作表 → 不用 AppSheet 组件
//    （经验 #19），只换 showAppSheet 外壳；**原弹层 isScrollControlled 是默认
//    false，必须显式传**（经验 #20）。
//
// 保留私有的：`_SmallTactileIcon`（0.9/0.6/0.3 透明度阶梯 + enabled，经验 #16）、
// `_sheetOption` / `_sheetDivider`（弹层内行样式，leading 可选、无右箭头，见经验 #15）、
// `_BrandBadge` / `_ServiceIcon` / `_AddServiceBottomSheet` / `_EditServiceSheet`。
//
// 清掉的死代码（基线 14 条 warning 中 9 条）：`_selectService`（0 引用）、
// `_iosProviderRow` 里未使用的 `selected`、`_getServiceIcon` / `_getServiceStatus`
// （0 引用）、`_AddServiceBottomSheetState.build` 里未使用的 `isDark`、
// `_brandBadgeForName`（0 引用 + `// ignore: unused_element` 掩盖）、
// `_BrandBadge.build` 的 4 处无效 `!`、2 个重复 import。
// ──────────────────────────────────────────────────────────────
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../core/services/search/search_service.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../l10n/build_context_l10n.dart';
import '../../../shared/widgets/app_page.dart';
import '../../../shared/widgets/app_section.dart';
import '../../../shared/widgets/app_sheet.dart';
import '../../../shared/widgets/ios_tactile.dart';
import '../../../shared/widgets/snackbar.dart';
import '../../../theme/design_tokens.dart';
import '../../../utils/brand_assets.dart';
import '../../../core/services/haptics.dart';

class SearchServicesPage extends StatefulWidget {
  const SearchServicesPage({super.key});

  @override
  State<SearchServicesPage> createState() => _SearchServicesPageState();
}

class _SearchServicesPageState extends State<SearchServicesPage> {
  List<SearchServiceOptions> _services = [];
  int _selectedIndex = 0;
  final Map<String, bool> _testing = <String, bool>{}; // serviceId -> testing
  // Use SettingsProvider for connection results; keep only local testing spinner state

  @override
  void initState() {
    super.initState();
    final settings = context.read<SettingsProvider>();
    _services = List.from(settings.searchServices);
    _selectedIndex = settings.searchServiceSelected;
    // Do not auto test here; rely on app-start tests. Users can test manually.
  }

  void _addService() {
    // ⚠️ 保留手写 showModalBottomSheet：需要 constraints(maxHeight 0.85h)，
    // 且内容是 AnimatedSize + AnimatedSwitcher + Flexible 的自绘结构。
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      backgroundColor: Colors.transparent,
      builder: (context) => _AddServiceBottomSheet(
        onAdd: (service) {
          setState(() {
            _services.add(service);
          });
          _saveChanges();
        },
      ),
    );
  }

  void _editService(int index) {
    final service = _services[index];
    // 外层换 showAppSheet：统一圆角/surface 背景/SafeArea/键盘避让
    // （_EditServiceSheet 自身因此不再包 SafeArea 与 viewInsets Padding）。
    showAppSheet<void>(
      context: context,
      builder: _EditServiceSheet(
        service: service,
        onSave: (updated) {
          setState(() {
            _services[index] = updated;
          });
          _saveChanges();
        },
      ),
    );
  }

  void _deleteService(int index) {
    if (_services.length <= 1) {
      final l10n = context.l10n;
      showAppSnackBar(
        context,
        message: l10n.searchServicesPageAtLeastOneServiceRequired,
        type: NotificationType.warning,
      );
      return;
    }

    setState(() {
      _services.removeAt(index);
      if (_selectedIndex >= _services.length) {
        _selectedIndex = _services.length - 1;
      } else if (_selectedIndex > index) {
        _selectedIndex--;
      }
    });
    _saveChanges();
  }

  void _saveChanges() {
    final settings = context.read<SettingsProvider>();
    context.read<SettingsProvider>().updateSettings(
      settings.copyWith(
        searchServices: _services,
        searchServiceSelected: _selectedIndex,
      ),
    );
  }

  Future<void> _testConnection(int index) async {
    if (index < 0 || index >= _services.length) return;
    final s = _services[index];
    final id = s.id;
    setState(() {
      _testing[id] = true;
    });
    try {
      final svc = SearchService.getService(s);
      final settings = context.read<SettingsProvider>();
      // Use a tiny search to validate connectivity
      final common = SearchCommonOptions(
        resultSize: 1,
        timeout: settings.searchCommonOptions.timeout,
      );
      await svc.search(
        query: 'connectivity test',
        commonOptions: common,
        serviceOptions: s,
      );
      settings.setSearchConnection(id, true);
    } catch (_) {
      context.read<SettingsProvider>().setSearchConnection(id, false);
    } finally {
      if (mounted) {
        setState(() {
          _testing[id] = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final l10n = context.l10n;

    return AppPage(
      title: l10n.searchServicesPageTitle,
      backgroundColor: cs.surface,
      leading: Tooltip(
        message: l10n.searchServicesPageBackTooltip,
        child: IosIconButton(
          haptics: true,
          icon: Lucide.ArrowLeft,
          color: cs.onSurface,
          size: 22,
          minSize: 44,
          onTap: () => Navigator.of(context).maybePop(),
        ),
      ),
      actions: [
        Tooltip(
          message: l10n.searchServicesPageAddProvider,
          child: IosIconButton(
            haptics: true,
            icon: Lucide.Plus,
            color: cs.onSurface,
            size: 22,
            minSize: 44,
            onTap: _addService,
          ),
        ),
        const SizedBox(width: AppGap.sm),
      ],
      bodyPadding: const EdgeInsets.fromLTRB(AppGap.md, AppGap.sm, AppGap.md, AppGap.xl),
      // ⚠️ scrollable 模式下子部件拿到「无界高度 + 紧凑宽度」，
      // Column 必须 stretch，否则卡片缩到内容宽度。
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _sectionHeader(l10n.searchServicesPageSearchProviders, cs, first: true),
          AppSectionCard(children: [
            for (int i = 0; i < _services.length; i++) ...[
              _iosProviderRow(context, index: i),
              if (i != _services.length - 1) const AppSectionDivider(),
            ],
          ]),
          const SizedBox(height: AppGap.md),
          _sectionHeader(l10n.searchServicesPageGeneralOptions, cs),
          _buildCommonOptionsSection(context),
        ],
      ),
    );
  }

  Widget _sectionHeader(String text, ColorScheme cs, {bool first = false}) => Padding(
        // 18 / 6 无精确 token（md=16 / lg=20、xs=8），保留字面量
        padding: EdgeInsets.fromLTRB(AppGap.sm, first ? AppGap.xxxs : 18, AppGap.sm, 6),
        child: Text(text, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: cs.onSurface.withOpacity(0.8))),
      );

  Widget _buildCommonOptionsSection(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final settings = context.watch<SettingsProvider>();
    final common = settings.searchCommonOptions;
    final l10n = context.l10n;

    Widget stepper({required int value, required VoidCallback onMinus, required VoidCallback onPlus, String? unit}) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _SmallTactileIcon(
            icon: Lucide.Minus,
            onTap: onMinus,
            enabled: true,
          ),
          const SizedBox(width: AppGap.xs),
          Text(unit == null ? '$value' : '$value$unit', style: TextStyle(fontSize: 14, color: cs.onSurface.withOpacity(0.8))),
          const SizedBox(width: AppGap.xs),
          _SmallTactileIcon(
            icon: Lucide.Plus,
            onTap: onPlus,
            enabled: true,
          ),
        ],
      );
    }

    // 原 _TactileRow(onTap: null) 包裹 → onTapDown 从未挂上、pressed 恒 false，
    // _AnimatedPressColor 退化为一次颜色透传。直接展开为静态行（死分支，经验 #31）。
    Widget staticRow({required IconData icon, required String label, required Widget trailing}) {
      final c = cs.onSurface.withOpacity(0.9);
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppGap.sm, vertical: 11),
        child: Row(
          children: [
            SizedBox(width: 36, child: Icon(icon, size: 18, color: c)),
            const SizedBox(width: AppGap.sm),
            Expanded(child: Text(label, style: TextStyle(fontSize: 15, color: c))),
            trailing,
          ],
        ),
      );
    }

    return AppSectionCard(children: [
      staticRow(
        icon: Lucide.ListOrdered,
        label: l10n.searchServicesPageMaxResults,
        trailing: stepper(
          value: common.resultSize,
          onMinus: common.resultSize > 1
              ? () => context.read<SettingsProvider>().updateSettings(
                    settings.copyWith(
                      searchCommonOptions: SearchCommonOptions(resultSize: common.resultSize - 1, timeout: common.timeout),
                    ),
                  )
              : () {},
          onPlus: common.resultSize < 20
              ? () => context.read<SettingsProvider>().updateSettings(
                    settings.copyWith(
                      searchCommonOptions: SearchCommonOptions(resultSize: common.resultSize + 1, timeout: common.timeout),
                    ),
                  )
              : () {},
        ),
      ),
      const AppSectionDivider(),
      staticRow(
        icon: Lucide.History,
        label: l10n.searchServicesPageTimeoutSeconds,
        trailing: stepper(
          value: common.timeout ~/ 1000,
          onMinus: common.timeout > 1000
              ? () => context.read<SettingsProvider>().updateSettings(
                    settings.copyWith(
                      searchCommonOptions: SearchCommonOptions(resultSize: common.resultSize, timeout: common.timeout - 1000),
                    ),
                  )
              : () {},
          onPlus: common.timeout < 30000
              ? () => context.read<SettingsProvider>().updateSettings(
                    settings.copyWith(
                      searchCommonOptions: SearchCommonOptions(resultSize: common.resultSize, timeout: common.timeout + 1000),
                    ),
                  )
              : () {},
        ),
      ),
    ]);
  }

  Widget _iosProviderRow(BuildContext context, {required int index}) {
    final s = _services[index];
    final cs = Theme.of(context).colorScheme;
    final name = SearchService.getService(s).name;
    // Connection/testing status for capsule
    final l10n = context.l10n;
    final testing = _testing[s.id] == true;
    final conn = context.watch<SettingsProvider>().searchConnection[s.id];
    String statusText;
    Color statusBg;
    Color statusFg;
    if (testing) {
      statusText = l10n.searchServicesPageTestingStatus;
      statusBg = cs.primary.withOpacity(0.12);
      statusFg = cs.primary;
    } else if (conn == true) {
      statusText = l10n.searchServicesPageConnectedStatus;
      statusBg = Colors.green.withOpacity(0.12);
      statusFg = Colors.green;
    } else if (conn == false) {
      statusText = l10n.searchServicesPageFailedStatus;
      statusBg = Colors.orange.withOpacity(0.12);
      statusFg = Colors.orange;
    } else {
      statusText = l10n.searchServicesPageNotTestedStatus;
      statusBg = cs.onSurface.withOpacity(0.06);
      statusFg = cs.onSurface.withOpacity(0.7);
    }
    // 原实现是外层 _TactileRow(tap) + 内层 GestureDetector(longPress) 两层手势，
    // 合并到 IosTactileRow 的 onTap/onLongPress 后行为一致（点按 → 编辑，长按 → 操作表）。
    // 本行原本 haptics: false（点按无触觉），长按也无 —— 保持 false。
    return IosTactileRow(
      haptics: false,
      onTap: () => _editService(index),
      onLongPress: () => _showServiceActions(context, index),
      builder: (ctx, pressed) {
        final base = cs.onSurface.withOpacity(0.9);
        return IosPressColor(
          pressed: pressed,
          base: base,
          builder: (c) {
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppGap.sm, vertical: 11),
              child: Row(
                children: [
                  SizedBox(width: 36, child: Center(child: _BrandBadge.forService(s, size: 22))),
                  const SizedBox(width: AppGap.sm),
                  Expanded(
                    child: Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 15, color: c, fontWeight: FontWeight.w600),
                    ),
                  ),
                  if (s is! BingLocalOptions && statusText.isNotEmpty) ...[
                    const SizedBox(width: AppGap.xs),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: AppGap.xs, vertical: 3),
                      decoration: BoxDecoration(
                        color: statusBg,
                        borderRadius: BorderRadius.circular(AppRadius.circular),
                      ),
                      child: Text(
                        statusText,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11, color: statusFg),
                      ),
                    ),
                  ],
                  const SizedBox(width: AppGap.xs),
                  Icon(Lucide.ChevronRight, size: 16, color: c),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _showServiceActions(BuildContext context, int index) async {
    final l10n = context.l10n;
    // 无把手、行满宽的操作表 → 不套 AppSheet 组件（经验 #19），
    // 只用 showAppSheet 收敛圆角/背景/SafeArea。
    // ⚠️ 原弹层 isScrollControlled 是默认 false，必须显式传（经验 #20）。
    await showAppSheet<void>(
      context: context,
      isScrollControlled: false,
      builder: Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _sheetOption(context, icon: Lucide.Activity, label: l10n.searchServicesPageTestConnectionTooltip, onTap: () {
              Navigator.of(context).pop();
              _testConnection(index);
            }),
            _sheetDivider(context),
            _sheetOption(context, icon: Lucide.Trash2, label: l10n.providerDetailPageDeleteButton, onTap: () {
              Navigator.of(context).pop();
              _deleteService(index);
            }),
          ],
        ),
      ),
    );
  }
}

class _BrandBadge extends StatelessWidget {
  const _BrandBadge({required this.name, this.size = 20});
  final String name;
  final double size;

  static Widget forService(SearchServiceOptions s, {double size = 24}) {
    final n = _nameForService(s);
    return _BrandBadge(name: n, size: size);
  }

  static String _nameForService(SearchServiceOptions s) {
    if (s is BingLocalOptions) return 'bing';
    if (s is TavilyOptions) return 'tavily';
    if (s is ExaOptions) return 'exa';
    if (s is ZhipuOptions) return 'zhipu';
    if (s is SearXNGOptions) return 'searxng';
    if (s is LinkUpOptions) return 'linkup';
    if (s is BraveOptions) return 'brave';
    if (s is MetasoOptions) return 'metaso';
    if (s is OllamaOptions) return 'ollama';
    if (s is JinaOptions) return 'jina';
    if (s is PerplexityOptions) return 'perplexity';
    if (s is BochaOptions) return 'bocha';
    return 'search';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // Use BrandAssets to get the icon path
    final asset = BrandAssets.assetForName(name);
    final bg = isDark ? Colors.white10 : cs.primary.withOpacity(0.1);
    if (asset != null) {
      if (asset.endsWith('.svg')) {
        final isColorful = asset.contains('color');
        final ColorFilter? tint = (isDark && !isColorful) ? const ColorFilter.mode(Colors.white, BlendMode.srcIn) : null;
        return Container(
          width: size,
          height: size,
          decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
          alignment: Alignment.center,
          child: SvgPicture.asset(asset, width: size * 0.62, height: size * 0.62, colorFilter: tint),
        );
      } else {
        return Container(
          width: size,
          height: size,
          decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
          alignment: Alignment.center,
          child: Image.asset(asset, width: size * 0.62, height: size * 0.62, fit: BoxFit.contain),
        );
      }
    }
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
      alignment: Alignment.center,
      child: Text(name.isNotEmpty ? name.characters.first.toUpperCase() : '?', style: TextStyle(color: cs.primary, fontWeight: FontWeight.w700, fontSize: size * 0.42)),
    );
  }
}

// Add Service Bottom Sheet - iOS Style
class _AddServiceBottomSheet extends StatefulWidget {
  final Function(SearchServiceOptions) onAdd;

  const _AddServiceBottomSheet({required this.onAdd});

  @override
  State<_AddServiceBottomSheet> createState() => _AddServiceBottomSheetState();
}

class _AddServiceBottomSheetState extends State<_AddServiceBottomSheet> {
  String? _selectedType;
  final _formKey = GlobalKey<FormState>();
  final Map<String, TextEditingController> _controllers = {};

  @override
  void dispose() {
    for (var controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SafeArea(
          child: AnimatedSize(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOutCubic,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
              // Handle bar
              Container(
                margin: const EdgeInsets.only(top: 12, bottom: 4),
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: cs.onSurface.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // Title with animation
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                transitionBuilder: (child, animation) {
                  return FadeTransition(
                    opacity: animation,
                    child: child,
                  );
                },
                child: Padding(
                  key: ValueKey<String?>(_selectedType),
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                  child: Text(
                    _selectedType == null ? l10n.searchServicesAddDialogTitle : _getServiceName(_selectedType!),
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                  ),
                ),
              ),

              // Service type selection or form with fade animation
              Flexible(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  transitionBuilder: (child, animation) {
                    return FadeTransition(
                      opacity: animation,
                      child: child,
                    );
                  },
                  child: _selectedType == null
                      ? _buildServiceTypeList()
                      : _buildFormView(),
                ),
              ),
            ],
          ),
        ),
      ),
      ),
    );
  }

  Widget _buildServiceTypeList() {
    final l10n = context.l10n;
    final services = [
      {'type': 'bing_local', 'name': l10n.searchServiceNameBingLocal},
      {'type': 'tavily', 'name': l10n.searchServiceNameTavily},
      {'type': 'exa', 'name': l10n.searchServiceNameExa},
      {'type': 'zhipu', 'name': l10n.searchServiceNameZhipu},
      {'type': 'searxng', 'name': l10n.searchServiceNameSearXNG},
      {'type': 'linkup', 'name': l10n.searchServiceNameLinkUp},
      {'type': 'brave', 'name': l10n.searchServiceNameBrave},
      {'type': 'metaso', 'name': l10n.searchServiceNameMetaso},
      {'type': 'jina', 'name': l10n.searchServiceNameJina},
      {'type': 'ollama', 'name': l10n.searchServiceNameOllama},
      {'type': 'perplexity', 'name': l10n.searchServiceNamePerplexity},
      {'type': 'bocha', 'name': l10n.searchServiceNameBocha},
    ];
    // no_manual_listview_padding 白名单：添加搜索服务底部弹层内的服务类型选择列表（shrinkWrap），随 AnimatedSwitcher 切换，非页面级列表
    return ListView.builder(
      key: const ValueKey('service_list'),
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      shrinkWrap: true,
      itemCount: services.length,
      itemBuilder: (context, index) {
        final item = services[index];
        return Column(children: [
          _sheetOption(
            context,
            icon: Lucide.Globe,
            label: item['name'] as String,
            leading: _ServiceIcon(type: item['type'] as String, name: item['name'] as String, size: 36),
            bgOnPress: false,
            onTap: () {
              setState(() => _selectedType = item['type'] as String);
            },
          ),
          if (index != services.length - 1) _sheetDivider(context),
        ]);
      },
    );
  }

  String _getServiceName(String type) {
    final l10n = context.l10n;
    switch (type) {
      case 'bing_local': return l10n.searchServiceNameBingLocal;
      case 'tavily': return l10n.searchServiceNameTavily;
      case 'exa': return l10n.searchServiceNameExa;
      case 'zhipu': return l10n.searchServiceNameZhipu;
      case 'searxng': return l10n.searchServiceNameSearXNG;
      case 'linkup': return l10n.searchServiceNameLinkUp;
      case 'brave': return l10n.searchServiceNameBrave;
      case 'metaso': return l10n.searchServiceNameMetaso;
      case 'jina': return l10n.searchServiceNameJina;
      case 'ollama': return l10n.searchServiceNameOllama;
      case 'perplexity': return l10n.searchServiceNamePerplexity;
      case 'bocha': return l10n.searchServiceNameBocha;
      default: return '';
    }
  }

  Widget _buildFormView() {
    final l10n = context.l10n;

    return SingleChildScrollView(
      key: const ValueKey('form_view'),
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: Form(
        key: _formKey,
        child: Column(
          children: [
            ..._buildFieldsForType(_selectedType!),
            const SizedBox(height: AppGap.xl),
            // Add button
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () {
                  if (_formKey.currentState!.validate()) {
                    final service = _createService();
                    widget.onAdd(service);
                    Navigator.pop(context);
                  }
                },
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                ),
                child: Text(
                  l10n.searchServicesAddDialogAdd,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildFieldsForType(String type) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    Widget buildTextField({
      required String key,
      required String label,
      String? hint,
      bool obscureText = false,
      String? Function(String?)? validator,
    }) {
      _controllers[key] ??= TextEditingController();
      return Container(
        decoration: BoxDecoration(
          color: cs.surfaceVariant.withOpacity(isDark ? 0.18 : 0.5),
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: TextFormField(
          controller: _controllers[key],
          obscureText: obscureText,
          style: const TextStyle(fontSize: 16),
          decoration: InputDecoration(
            labelText: label,
            hintText: hint,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadius.md),
              borderSide: BorderSide.none,
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          ),
          validator: validator,
        ),
      );
    }

    switch (type) {
      case 'bing_local':
        return [
          Container(
            padding: const EdgeInsets.all(AppGap.md),
            decoration: BoxDecoration(
              color: cs.surfaceVariant.withOpacity(isDark ? 0.18 : 0.5),
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: Row(
              children: [
                Icon(Lucide.Search, size: 20, color: cs.primary),
                const SizedBox(width: AppGap.sm),
                Expanded(
                  child: Text(
                    l10n.searchServiceNameBingLocal,
                    style: TextStyle(
                      fontSize: 14,
                      color: cs.onSurface.withOpacity(0.8),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ];
      case 'tavily':
      case 'exa':
      case 'zhipu':
      case 'linkup':
      case 'brave':
      case 'metaso':
      case 'jina':
      case 'ollama':
      case 'perplexity':
      case 'bocha':
        return [
          buildTextField(
            key: 'apiKey',
            label: 'API Key',
            validator: (value) {
              if (value == null || value.isEmpty) {
                return l10n.searchServicesAddDialogApiKeyRequired;
              }
              return null;
            },
          ),
        ];
      case 'searxng':
        return [
          buildTextField(
            key: 'url',
            label: l10n.searchServicesAddDialogInstanceUrl,
            validator: (value) {
              if (value == null || value.isEmpty) {
                return l10n.searchServicesAddDialogUrlRequired;
              }
              return null;
            },
          ),
          const SizedBox(height: AppGap.sm),
          buildTextField(
            key: 'engines',
            label: l10n.searchServicesAddDialogEnginesOptional,
            hint: 'google,duckduckgo',
          ),
          const SizedBox(height: AppGap.sm),
          buildTextField(
            key: 'language',
            label: l10n.searchServicesAddDialogLanguageOptional,
            hint: 'en-US',
          ),
          const SizedBox(height: AppGap.sm),
          buildTextField(
            key: 'username',
            label: l10n.searchServicesAddDialogUsernameOptional,
          ),
          const SizedBox(height: AppGap.sm),
          buildTextField(
            key: 'password',
            label: l10n.searchServicesAddDialogPasswordOptional,
            obscureText: true,
          ),
        ];
      default:
        return [];
    }
  }

  SearchServiceOptions _createService() {
    final uuid = const Uuid();
    final id = uuid.v4().substring(0, 8);

    switch (_selectedType) {
      case 'bing_local':
        return BingLocalOptions(id: id);
      case 'tavily':
        return TavilyOptions(
          id: id,
          apiKey: _controllers['apiKey']!.text,
        );
      case 'exa':
        return ExaOptions(
          id: id,
          apiKey: _controllers['apiKey']!.text,
        );
      case 'zhipu':
        return ZhipuOptions(
          id: id,
          apiKey: _controllers['apiKey']!.text,
        );
      case 'searxng':
        return SearXNGOptions(
          id: id,
          url: _controllers['url']!.text,
          engines: _controllers['engines']!.text,
          language: _controllers['language']!.text,
          username: _controllers['username']!.text,
          password: _controllers['password']!.text,
        );
      case 'linkup':
        return LinkUpOptions(
          id: id,
          apiKey: _controllers['apiKey']!.text,
        );
      case 'brave':
        return BraveOptions(
          id: id,
          apiKey: _controllers['apiKey']!.text,
        );
      case 'metaso':
        return MetasoOptions(
          id: id,
          apiKey: _controllers['apiKey']!.text,
        );
      case 'jina':
        return JinaOptions(
          id: id,
          apiKey: _controllers['apiKey']!.text,
        );
      case 'ollama':
        return OllamaOptions(
          id: id,
          apiKey: _controllers['apiKey']!.text,
        );
      case 'perplexity':
        return PerplexityOptions(
          id: id,
          apiKey: _controllers['apiKey']!.text,
        );
      case 'bocha':
        return BochaOptions(
          id: id,
          apiKey: _controllers['apiKey']!.text,
        );
      default:
        return BingLocalOptions(id: id);
    }
  }
}

// Edit Service Bottom Sheet (iOS style)
class _EditServiceSheet extends StatefulWidget {
  final SearchServiceOptions service;
  final Function(SearchServiceOptions) onSave;

  const _EditServiceSheet({
    required this.service,
    required this.onSave,
  });

  @override
  State<_EditServiceSheet> createState() => _EditServiceSheetState();
}

class _EditServiceSheetState extends State<_EditServiceSheet> {
  final _formKey = GlobalKey<FormState>();
  final Map<String, TextEditingController> _controllers = {};

  @override
  void initState() {
    super.initState();
    _initControllers();
  }

  void _initControllers() {
    final service = widget.service;
    if (service is TavilyOptions) {
      _controllers['apiKey'] = TextEditingController(text: service.apiKey);
    } else if (service is ExaOptions) {
      _controllers['apiKey'] = TextEditingController(text: service.apiKey);
    } else if (service is ZhipuOptions) {
      _controllers['apiKey'] = TextEditingController(text: service.apiKey);
    } else if (service is SearXNGOptions) {
      _controllers['url'] = TextEditingController(text: service.url);
      _controllers['engines'] = TextEditingController(text: service.engines);
      _controllers['language'] = TextEditingController(text: service.language);
      _controllers['username'] = TextEditingController(text: service.username);
      _controllers['password'] = TextEditingController(text: service.password);
    } else if (service is LinkUpOptions) {
      _controllers['apiKey'] = TextEditingController(text: service.apiKey);
    } else if (service is BraveOptions) {
      _controllers['apiKey'] = TextEditingController(text: service.apiKey);
    } else if (service is MetasoOptions) {
      _controllers['apiKey'] = TextEditingController(text: service.apiKey);
    } else if (service is OllamaOptions) {
      _controllers['apiKey'] = TextEditingController(text: service.apiKey);
    } else if (service is JinaOptions) {
      _controllers['apiKey'] = TextEditingController(text: service.apiKey);
    } else if (service is BochaOptions) {
      _controllers['apiKey'] = TextEditingController(text: service.apiKey);
    }
  }

  @override
  void dispose() {
    for (var controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final searchService = SearchService.getService(widget.service);
    final cs = Theme.of(context).colorScheme;
    // ⚠️ SafeArea 与键盘避让由外层 showAppSheet 提供，这里只保留四周留白
    // （bottom 16 + showAppSheet 的 AnimatedPadding(viewInsets) == 原来的 viewInsets + 16）。
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppGap.md, AppGap.sm, AppGap.md, AppGap.md),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(color: cs.onSurface.withOpacity(0.2), borderRadius: BorderRadius.circular(AppRadius.circular)),
            ),
          ),
          // Title (match Add sheet style: centered name)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
            child: Center(
              child: Text(
                searchService.name,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
            ),
          ),
          Form(
            key: _formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: _buildFields(),
              ),
            ),
          ),
          const SizedBox(height: AppGap.sm),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () {
                if (_formKey.currentState!.validate()) {
                  final updated = _updateService();
                  widget.onSave(updated);
                  Navigator.of(context).pop();
                }
              },
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
              ),
              child: Text(l10n.searchServicesEditDialogSave, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildFields() {
    final l10n = context.l10n;
    final service = widget.service;
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    Widget buildTextField({
      required String key,
      required String label,
      String? hint,
      bool obscureText = false,
      String? Function(String?)? validator,
    }) {
      _controllers[key] = _controllers[key] ?? TextEditingController();
      return Container(
        decoration: BoxDecoration(
          color: cs.surfaceVariant.withOpacity(isDark ? 0.18 : 0.5),
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: TextFormField(
          controller: _controllers[key],
          obscureText: obscureText,
          style: const TextStyle(fontSize: 16),
          decoration: InputDecoration(
            labelText: label,
            hintText: hint,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadius.md),
              borderSide: BorderSide.none,
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          ),
          validator: validator,
        ),
      );
    }

    if (service is BingLocalOptions) {
      return [Text(l10n.searchServicesEditDialogBingLocalNoConfig)];
    } else if (service is TavilyOptions ||
        service is ExaOptions ||
        service is ZhipuOptions ||
        service is LinkUpOptions ||
        service is BraveOptions ||
        service is MetasoOptions ||
        service is OllamaOptions ||
        service is JinaOptions ||
        service is BochaOptions) {
      return [
        buildTextField(
          key: 'apiKey',
          label: 'API Key',
          validator: (value) {
            if (value == null || value.isEmpty) {
              return l10n.searchServicesEditDialogApiKeyRequired;
            }
            return null;
          },
        ),
      ];
    } else if (service is SearXNGOptions) {
      return [
        buildTextField(
          key: 'url',
          label: l10n.searchServicesEditDialogInstanceUrl,
          validator: (value) {
            if (value == null || value.isEmpty) {
              return l10n.searchServicesEditDialogUrlRequired;
            }
            return null;
          },
        ),
        const SizedBox(height: AppGap.sm),
        buildTextField(
          key: 'engines',
          label: l10n.searchServicesEditDialogEnginesOptional,
          hint: 'google,duckduckgo',
        ),
        const SizedBox(height: AppGap.sm),
        buildTextField(
          key: 'language',
          label: l10n.searchServicesEditDialogLanguageOptional,
          hint: 'en-US',
        ),
        const SizedBox(height: AppGap.sm),
        buildTextField(
          key: 'username',
          label: l10n.searchServicesEditDialogUsernameOptional,
        ),
        const SizedBox(height: AppGap.sm),
        buildTextField(
          key: 'password',
          label: l10n.searchServicesEditDialogPasswordOptional,
          obscureText: true,
        ),
      ];
    }

    return [];
  }

  SearchServiceOptions _updateService() {
    final service = widget.service;

    if (service is TavilyOptions) {
      return TavilyOptions(
        id: service.id,
        apiKey: _controllers['apiKey']!.text,
      );
    } else if (service is ExaOptions) {
      return ExaOptions(
        id: service.id,
        apiKey: _controllers['apiKey']!.text,
      );
    } else if (service is ZhipuOptions) {
      return ZhipuOptions(
        id: service.id,
        apiKey: _controllers['apiKey']!.text,
      );
    } else if (service is SearXNGOptions) {
      return SearXNGOptions(
        id: service.id,
        url: _controllers['url']!.text,
        engines: _controllers['engines']!.text,
        language: _controllers['language']!.text,
        username: _controllers['username']!.text,
        password: _controllers['password']!.text,
      );
    } else if (service is LinkUpOptions) {
      return LinkUpOptions(
        id: service.id,
        apiKey: _controllers['apiKey']!.text,
      );
    } else if (service is BraveOptions) {
      return BraveOptions(
        id: service.id,
        apiKey: _controllers['apiKey']!.text,
      );
    } else if (service is MetasoOptions) {
      return MetasoOptions(
        id: service.id,
        apiKey: _controllers['apiKey']!.text,
      );
    } else if (service is OllamaOptions) {
      return OllamaOptions(
        id: service.id,
        apiKey: _controllers['apiKey']!.text,
      );
    } else if (service is JinaOptions) {
      return JinaOptions(
        id: service.id,
        apiKey: _controllers['apiKey']!.text,
      );
    } else if (service is PerplexityOptions) {
      return PerplexityOptions(
        id: service.id,
        apiKey: _controllers['apiKey']!.text,
        country: service.country,
        searchDomainFilter: service.searchDomainFilter,
        maxTokensPerPage: service.maxTokensPerPage,
      );
    } else if (service is BochaOptions) {
      return BochaOptions(
        id: service.id,
        apiKey: _controllers['apiKey']!.text,
        freshness: service.freshness,
        summary: service.summary,
        include: service.include,
        exclude: service.exclude,
      );
    }

    return service;
  }
}

// Service Icon Widget - Uses BrandAssets
class _ServiceIcon extends StatelessWidget {
  const _ServiceIcon({
    required this.type,
    required this.name,
    this.size = 40,
  });

  final String type;  // Service type like 'bing_local', 'tavily', etc.
  final String name;  // Display name for fallback
  final double size;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // Use type for matching, not the localized name
    final matchName = _getMatchName(type);
    final asset = BrandAssets.assetForName(matchName);
    final bg = isDark ? Colors.white10 : cs.primary.withOpacity(0.1);

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
      ),
      alignment: Alignment.center,
      child: asset != null
          ? _buildAssetIcon(asset, size, isDark)
          : _buildLetterIcon(name, size, cs),
    );
  }

  Widget _buildAssetIcon(String asset, double size, bool isDark) {
    final iconSize = size * 0.62;
    if (asset.endsWith('.svg')) {
      final isColorful = asset.contains('color');
      final ColorFilter? tint = (isDark && !isColorful)
          ? const ColorFilter.mode(Colors.white, BlendMode.srcIn)
          : null;
      return SvgPicture.asset(
        asset,
        width: iconSize,
        height: iconSize,
        colorFilter: tint,
      );
    } else {
      return Image.asset(
        asset,
        width: iconSize,
        height: iconSize,
        fit: BoxFit.contain,
      );
    }
  }

  Widget _buildLetterIcon(String name, double size, ColorScheme cs) {
    return Text(
      name.isNotEmpty ? name.characters.first.toUpperCase() : '?',
      style: TextStyle(
        color: cs.primary,
        fontWeight: FontWeight.w700,
        fontSize: size * 0.42,
      ),
    );
  }

  // Map service type to name for BrandAssets matching
  String _getMatchName(String type) {
    switch (type) {
      case 'bing_local':
        return 'bing';
      case 'tavily':
        return 'tavily';
      case 'exa':
        return 'exa';
      case 'zhipu':
        return 'zhipu';
      case 'searxng':
        return 'searxng';
      case 'linkup':
        return 'linkup';
      case 'brave':
        return 'brave';
      case 'metaso':
        return 'metaso';
      case 'jina':
        return 'jina';
      case 'ollama':
        return 'ollama';
      case 'bocha':
        return 'bocha';
      default:
        return type;
    }
  }
}

// --- Sheet helpers (align with settings page) ---

/// 弹层内的选项行：leading 可选（图标 / 自定义部件 / 退化为右箭头）、无右箭头、
/// 可选按压底色。与 `AppNavRow` 的差异见经验 #15 —— 保留私有。
Widget _sheetOption(
  BuildContext context, {
  required String label,
  required VoidCallback onTap,
  IconData? icon,
  Widget? leading,
  bool bgOnPress = true,
}) {
  final cs = Theme.of(context).colorScheme;
  final isDark = Theme.of(context).brightness == Brightness.dark;
  return IosTactileRow(
    haptics: true,
    onTap: onTap,
    builder: (ctx, pressed) {
      final base = cs.onSurface;
      final bgTarget = (bgOnPress && pressed)
          ? (isDark ? Colors.white.withOpacity(0.06) : Colors.black.withOpacity(0.05))
          : Colors.transparent;
      return IosPressColor(
        pressed: pressed,
        base: base,
        builder: (c) {
          return AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            color: bgTarget,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                SizedBox.square(
                  dimension: 36,
                  child: Center(child: leading ?? Icon(icon ?? Lucide.ChevronRight, size: 20, color: c)),
                ),
                const SizedBox(width: AppGap.sm),
                Expanded(child: Text(label, style: TextStyle(fontSize: 15, color: c))),
              ],
            ),
          );
        },
      );
    },
  );
}

Widget _sheetDivider(BuildContext context) {
  final cs = Theme.of(context).colorScheme;
  // height 1 / indent 56 与 AppSectionDivider（height 6 / indent 54）形状不同，保留字面量
  return Divider(height: 1, thickness: 0.6, indent: 56, endIndent: 16, color: cs.outlineVariant.withOpacity(0.18));
}

/// 步进器用的 ± 小图标键：0.9 / 0.6 按压 / 0.3 禁用的透明度阶梯，无按压底色，
/// 与 `IosIconButton` 的「向白/黑混合 + 按压底色」语义不同 → 保留私有（经验 #16）。
class _SmallTactileIcon extends StatefulWidget {
  const _SmallTactileIcon({required this.icon, required this.onTap, this.enabled = true});
  final IconData icon;
  final VoidCallback onTap;
  final bool enabled;
  @override
  State<_SmallTactileIcon> createState() => _SmallTactileIconState();
}

class _SmallTactileIconState extends State<_SmallTactileIcon> {
  bool _pressed = false;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final c = widget.enabled ? cs.onSurface.withOpacity(_pressed ? 0.6 : 0.9) : cs.onSurface.withOpacity(0.3);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: widget.enabled ? (_) => setState(() => _pressed = true) : null,
      onTapUp: widget.enabled ? (_) => setState(() => _pressed = false) : null,
      onTapCancel: widget.enabled ? () => setState(() => _pressed = false) : null,
      onTap: widget.enabled
          ? () {
              Haptics.soft();
              widget.onTap();
            }
          : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        child: Icon(widget.icon, size: 18, color: c),
      ),
    );
  }
}
