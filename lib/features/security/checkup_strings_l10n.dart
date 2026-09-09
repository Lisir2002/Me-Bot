import '../../../core/services/security/checkup_scanner.dart';
import '../../../l10n/app_localizations.dart';

/// [CheckupStrings] 的 l10n 实现：展示层组装体检服务时注入。
///
/// 生命周期：每次 `_runCheckup()` 现场构造、用完即弃，不跨 build 持有，
/// 语言切换后下次体检即用新文案（因此下方字段不构成“缓存”问题）。
/// 文件列表类参数在此 join，分隔符固定 `, `（arb 文案里以占位符嵌入）。
class L10nCheckupStrings implements CheckupStrings {
  const L10nCheckupStrings(this._l);

  // 短命注入对象（见类注释），非跨帧缓存：
  // ignore: l10n_no_field_cache
  final AppLocalizations _l;

  static const String _sep = ', ';

  @override
  String scannerErrorTitle(String scannerTitle) =>
      _l.checkupScannerErrorTitle(scannerTitle);

  @override
  String scannerErrorDetail() => _l.checkupScannerErrorDetail;

  @override
  String backupPlaintextTitle(int count) =>
      _l.checkupBackupPlaintextTitle(count);

  @override
  String backupPlaintextDetail(List<String> files) =>
      _l.checkupBackupPlaintextDetail(files.join(_sep));

  @override
  String legacyKeysTitle() => _l.checkupLegacyKeysTitle;

  @override
  String legacyKeysDetail(int count, List<String> keys) =>
      _l.checkupLegacyKeysDetail(count, keys.join(_sep));

  @override
  String legacyKeysFixHint() => _l.checkupLegacyKeysFixHint;

  @override
  String legacyPlaintextTitle() => _l.checkupLegacyPlaintextTitle;

  @override
  String legacyPlaintextDetail(int suspectCount) =>
      _l.checkupLegacyPlaintextDetail(suspectCount);

  @override
  String logLeakTitle() => _l.checkupLogLeakTitle;

  @override
  String logLeakDetail(int files, int lines) =>
      _l.checkupLogLeakDetail(files, lines);

  @override
  String orphanTitle(int count) => _l.checkupOrphanTitle(count);

  @override
  String orphanDetail() => _l.checkupOrphanDetail;

  @override
  String orphanFixHint() => _l.checkupOrphanFixHint;
}
