#!/usr/bin/env bash
# l10n 一条龙：护栏检查 → 生成产物（本地开发/构建前必跑）
set -euo pipefail
cd "$(dirname "$0")/.."
python3 tools/check_l10n.py
flutter gen-l10n
echo "✅ l10n 同步完成（产物已生成，不入库）"
