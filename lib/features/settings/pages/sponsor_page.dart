import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '../../../icons/lucide_adapter.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/app_page.dart';
import '../../../shared/widgets/app_states.dart';
import '../../../shared/widgets/ios_tactile.dart';
import '../../../theme/design_tokens.dart';
import '../widgets/settings_ios_widgets.dart';

/// 赞助页。
///
/// 已迁移到 AppPage 槽位骨架：
/// - Scaffold + AppBar + 手写 ListView → AppPage(title/leading/body)，
///   ListView 交给引擎的 scrollable，body 直接给 Column
/// - padding LTRB(16,12,16,16) → AppPagePadding.content
/// - 私有 `_TactileIconButton` → 共享 `IosIconButton`（checklist 第 8 条），并删除本文件的私有副本
/// - FutureBuilder 的 loading/empty → AppLoading / AppEmpty
///
/// ⚠️ 为什么不用 `states:` 槽位：本页的 Future 只负责「赞助者列表」这一块，
///   而 `states:` 会替换整页内容区（上方的「赞助方式」卡片会被吞掉）。
///   `states:` 仅适用于「整页就是一个 Future」的页面，局部 Future 请用手动三态组件。
class SponsorPage extends StatefulWidget {
  const SponsorPage({super.key});

  @override
  State<SponsorPage> createState() => _SponsorPageState();
}

class _SponsorPageState extends State<SponsorPage> {
  late Future<_SponsorData> _future;

  @override
  void initState() {
    super.initState();
    _future = _fetchSponsors();
  }

  Future<_SponsorData> _fetchSponsors() async {
    final ts = DateTime.now().millisecondsSinceEpoch;
    final uri = Uri.parse('https://minime-core.psycheas.top/sponsor.json?minime-core=$ts');
    try {
      final res = await http.get(uri).timeout(const Duration(seconds: 12));
      if (res.statusCode >= 200 && res.statusCode < 300) {
        final obj = jsonDecode(res.body) as Map<String, dynamic>;
        final updatedAt = (obj['updatedAt'] as String?) ?? '';
        final list = (obj['sponsors'] as List?) ?? const [];
        final sponsors = <_Sponsor>[];
        for (final e in list) {
          if (e is Map<String, dynamic>) {
            final name = (e['name'] as String?)?.trim() ?? '';
            final avatar = (e['avatar'] as String?)?.trim() ?? '';
            final since = (e['since'] as String?)?.trim() ?? '';
            if (name.isEmpty || avatar.isEmpty) continue;
            sponsors.add(_Sponsor(name: name, avatar: avatar, since: since));
          }
        }
        return _SponsorData(updatedAt: updatedAt, sponsors: sponsors);
      }
    } catch (_) {}
    return const _SponsorData(updatedAt: '', sponsors: <_Sponsor>[]);
  }

  // iOS-style header (neutral color)
  Widget _header(BuildContext context, String text, {bool first = false}) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.fromLTRB(AppGap.sm, first ? AppGap.xxxs : 18, AppGap.sm, 6),
      child: Text(text,
          style:
              TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: cs.onSurface.withOpacity(0.8))),
    );
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);
    try {
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        await launchUrl(uri, mode: LaunchMode.platformDefault);
      }
    } catch (_) {
      await launchUrl(uri);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final wechatQrUrl = isDark
        ? 'https://c.img.dasctf.com/LightPicture/2025/10/ee10ae78acbd01f3.png'
        : 'https://c.img.dasctf.com/LightPicture/2025/10/6ba60ac0f2f8e2b4.png';

    return AppPage(
      title: l10n.settingsPageSponsor,
      // 保留自定义返回 Tooltip 文案，但改用共享 IosIconButton
      leading: Tooltip(
        message: l10n.settingsPageBackButton,
        child: IosIconButton(
          haptics: true,
          icon: Lucide.ArrowLeft,
          color: cs.onSurface,
          size: 22,
          minSize: 44,
          onTap: () => Navigator.of(context).maybePop(),
        ),
      ),
      bodyPadding: AppPagePadding.content,
      body: Column(
        children: [
          _header(context, l10n.sponsorPageMethodsSectionTitle, first: true),
          SettingsSectionCard(children: [
            SettingsNavRow(
              haptics: false,              icon: Lucide.Heart,
              label: l10n.sponsorPageAfdianTitle,
              onTap: () async {
                final uri = Uri.parse('https://afdian.com/a/minime-core');
                if (!await launchUrl(uri, mode: LaunchMode.platformDefault)) {
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                }
              },
            ),
            const SettingsDivider(),
            SettingsNavRow(
              haptics: false,              icon: Lucide.Link,
              label: l10n.sponsorPageWeChatTitle,
              onTap: () async {
                final uri = Uri.parse(wechatQrUrl);
                if (!await launchUrl(uri, mode: LaunchMode.platformDefault)) {
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                }
              },
            ),
          ]),

          const SizedBox(height: AppGap.sm),
          _header(context, l10n.sponsorPageSponsorsSectionTitle),
          FutureBuilder<_SponsorData>(
            future: _future,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const AppLoading(verticalPadding: 40);
              }
              final data =
                  snapshot.data ?? const _SponsorData(updatedAt: '', sponsors: <_Sponsor>[]);
              final sponsors = data.sponsors;
              if (sponsors.isEmpty) {
                return AppEmpty(
                  message: l10n.sponsorPageEmpty,
                  verticalPadding: AppGap.xxl,
                );
              }
              return LayoutBuilder(
                builder: (context, constraints) {
                  final w = constraints.maxWidth;
                  // Aim ~5-6 avatars per row
                  int cross = (w >= 480) ? 6 : 5;
                  final itemSize = (w - 24 - (cross - 1) * 10) / cross; // 12 padding each side, 10 spacing
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(AppGap.sm, 0, AppGap.sm, AppGap.sm),
                    child: GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: cross,
                        crossAxisSpacing: 10,
                        mainAxisSpacing: 10,
                        childAspectRatio: itemSize / (52 + 28), // avatar 52 + space for name
                      ),
                      itemCount: sponsors.length,
                      itemBuilder: (context, i) {
                        final s = sponsors[i];
                        return _SponsorTile(s: s);
                      },
                    ),
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }
}

class _Sponsor {
  final String name;
  final String avatar;
  final String since;
  const _Sponsor({required this.name, required this.avatar, required this.since});
}

class _SponsorData {
  final String updatedAt;
  final List<_Sponsor> sponsors;
  const _SponsorData({required this.updatedAt, required this.sponsors});
}

class _SponsorTile extends StatelessWidget {
  const _SponsorTile({required this.s});
  final _Sponsor s;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: cs.outlineVariant.withOpacity(0.4)),
          ),
          child: ClipOval(
            child: Image.network(
              s.avatar,
              fit: BoxFit.cover,
              width: 52,
              height: 52,
              errorBuilder: (_, __, ___) => Container(
                color: cs.surface,
                alignment: Alignment.center,
                child: Icon(Icons.person, color: cs.onSurface.withOpacity(0.5)),
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        SizedBox(
          height: 18,
          child: Text(
            s.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, color: cs.onSurface.withOpacity(0.9)),
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }
}
