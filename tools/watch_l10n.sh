#!/usr/bin/env bash
# 监听 arb 变更自动 gen-l10n：保存翻译 → 热重载即见新文案。
# 依赖 inotifywait（sudo apt install inotify-tools）；无 inotify 时降级为轮询。
set -euo pipefail
cd "$(dirname "$0")/.."
echo "监听 lib/l10n/*.arb 变更（Ctrl+C 退出）…"
if command -v inotifywait >/dev/null 2>&1; then
  while true; do
    inotifywait -q -e close_write,modify lib/l10n/*.arb >/dev/null 2>&1 || true
    flutter gen-l10n && echo "🔄 l10n 已重新生成 $(date +%H:%M:%S)"
  done
else
  echo "（未检测到 inotifywait，使用 2s 轮询）"
  while true; do
    flutter gen-l10n >/dev/null 2>&1 && true
    sleep 2
  done
fi
