#!/usr/bin/env bash
# Sub-Store Surge 模块「本地化 + TextEncoder polyfill」构建脚本
#
# 背景：Sub-Store 的 bundle 里存在未加 typeof 守卫的 `new TextEncoder()` 调用。
# Surge 的 jsc / 部分 webview 引擎不保证提供全局 TextEncoder / TextDecoder，
# 一旦缺失会在脚本加载或运行期抛 ReferenceError，导致 sub.store 打不开。
# 解决办法：在每个 bundle 前面拼一段「有则不覆盖」的 polyfill。
#
# 用法：
#   ./build-poly.sh            # 使用脚本内固定的 VERSION
#   ./build-poly.sh 2.36.56    # 指定版本
#   ./build-poly.sh latest     # 跟随上游最新 release（不推荐长期用）

set -euo pipefail

VERSION="${1:-2.36.56}"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
POLYFILL="$DIR/textencoder-polyfill.js"

if [[ "$VERSION" == "latest" ]]; then
  BASE="https://github.com/sub-store-org/Sub-Store/releases/latest/download"
else
  BASE="https://github.com/sub-store-org/Sub-Store/releases/download/$VERSION"
fi

# 需要处理的三个 bundle
ASSETS=(sub-store-0.min.js sub-store-1.min.js cron-sync-artifacts.min.js)

command -v curl >/dev/null || { echo "需要 curl"; exit 1; }
[[ -f "$POLYFILL" ]] || { echo "缺少 $POLYFILL"; exit 1; }

echo "==> Sub-Store $VERSION"
for asset in "${ASSETS[@]}"; do
  target="$DIR/$asset"
  poly="$DIR/${asset%.min.js}.poly.js"

  echo "  下载 $asset"
  curl -fsSL --retry 3 --retry-delay 2 -o "$target" "$BASE/$asset"

  # 语法自检，避免把坏包写进仓库
  node --check "$target" 2>/dev/null || {
    echo "  !! $asset 语法检查失败，已跳过，保留上一版"
    rm -f "$target"
    continue
  }

  # polyfill 置于最前，保证在 bundle 任何代码求值前完成注入
  cat "$POLYFILL" "$target" > "$poly"
  node --check "$poly" || { echo "  !! $poly 拼接后语法异常"; exit 1; }

  printf '  %-32s %s bytes\n' "$asset" "$(wc -c < "$target" | tr -d ' ')"
  printf '  %-32s %s bytes\n' "$(basename "$poly")" "$(wc -c < "$poly" | tr -d ' ')"
done

echo "==> 完成。请确认 Surge.sgmodule 中的 script-path 指向 .poly.js 文件。"
