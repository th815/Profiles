#!/usr/bin/env bash
# Sub-Store Surge 模块「本地化 + TextEncoder polyfill」构建脚本
#
# 背景：Sub-Store 的 bundle 里存在未加 typeof 守卫的 `new TextEncoder()` 调用。
# Surge 的 jsc / 部分 webview 引擎不保证提供全局 TextEncoder / TextDecoder，
# 一旦缺失会在脚本加载或运行期抛 ReferenceError，导致 sub.store 打不开。
# 解决办法：在每个 bundle 前面拼一段「有则不覆盖」的 polyfill。
#
# 产物写入 scripts/<版本号>/ 目录（不可变 URL）。
# 原因：Surge 按 URL 缓存脚本，重装模块也不会重新拉取同一个 URL。若沿用固定
# 文件名，内容升级后 Surge 仍会使用旧的缓存副本，表现为「模块已重装、脚本也在
# 跑，但 /api/utils/env 一直返回旧版本号」。版本进 URL 即可彻底消除该问题。
#
# 用法：
#   ./build-poly.sh                 # 读取配置中的当前版本并重新构建（原地刷新）
#   ./build-poly.sh 2.36.57         # 升级到指定版本
#   ./build-poly.sh latest          # 跟随上游最新 release（不推荐长期用）
#   ./build-poly.sh 2.36.57 --keep  # 升级但保留旧版本目录
#
# 脚本会依次完成：下载 → 语法自检 → 拼接 polyfill → 写入 scripts/<版本号>/
#                → 改写 Surge.sgmodule 的 script-path → 清理旧版本目录

set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
POLYFILL="$DIR/textencoder-polyfill.js"
MODULE="$DIR/config/Surge.sgmodule"
SCRIPTS_DIR="$DIR/scripts"
REPO_RAW="https://raw.githubusercontent.com/th815/Profiles/main/Sub-Store/scripts"

ASSETS=(sub-store-0.min.js sub-store-1.min.js cron-sync-artifacts.min.js)

# ---------------------------------------------------------------- 参数解析
KEEP_OLD=0
VERSION=""
for arg in "$@"; do
  case "$arg" in
    --keep|--no-prune) KEEP_OLD=1 ;;
    -h|--help)         sed -n '2,26p' "${BASH_SOURCE[0]}"; exit 0 ;;
    *)                 VERSION="$arg" ;;
  esac
done

# ---------------------------------------------------------------- 依赖检查
command -v curl >/dev/null || { echo "!! 需要 curl"; exit 1; }
[[ -f "$POLYFILL" ]] || { echo "!! 缺少 $POLYFILL"; exit 1; }
[[ -f "$MODULE"   ]] || { echo "!! 缺少 $MODULE"; exit 1; }

NODE=""
if command -v node >/dev/null 2>&1; then
  NODE=node
else
  for cand in "$HOME"/.workbuddy/binaries/node/versions/*/bin/node; do
    [[ -x "$cand" ]] && { NODE="$cand"; break; }
  done
fi
[[ -n "$NODE" ]] || { echo "!! 需要 node（用于语法自检）"; exit 1; }

# ---------------------------------------------------------------- 版本解析
if [[ -z "$VERSION" ]]; then
  VERSION="$(grep -oE 'scripts/[0-9]+\.[0-9]+\.[0-9]+/' "$MODULE" | head -1 | cut -d/ -f2)"
  [[ -n "$VERSION" ]] || { echo "!! 无法从配置推断当前版本，请显式传入版本号"; exit 1; }
  echo "==> 未指定版本，按配置中的当前版本 $VERSION 重新构建"
fi

if [[ "$VERSION" == "latest" ]]; then
  VERSION="$(curl -fsSL https://api.github.com/repos/sub-store-org/Sub-Store/releases/latest \
             | grep -oE '"tag_name": *"[^"]+"' | head -1 | cut -d'"' -f4)"
  VERSION="${VERSION#v}"
  [[ -n "$VERSION" ]] || { echo "!! 无法解析上游最新版本号"; exit 1; }
  echo "==> 上游最新版本：$VERSION"
fi

BASE="https://github.com/sub-store-org/Sub-Store/releases/download/$VERSION"
OUT_DIR="$SCRIPTS_DIR/$VERSION"

echo "==> Sub-Store $VERSION"
echo "    产物目录：$OUT_DIR"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$OUT_DIR"

# ---------------------------------------------------------------- 下载 + 构建
for asset in "${ASSETS[@]}"; do
  poly_name="${asset%.min.js}.poly.js"

  echo "  下载 $asset"
  curl -fsSL --retry 3 --retry-delay 2 -o "$TMP/$asset" "$BASE/$asset"

  # 语法自检，避免把坏包写进仓库
  "$NODE" --check "$TMP/$asset" 2>/dev/null || {
    echo "  !! $asset 语法检查失败，已跳过，保留上一版"
    continue
  }

  # polyfill 置于最前，保证在 bundle 任何代码求值前完成注入
  cat "$POLYFILL" "$TMP/$asset" > "$TMP/$poly_name"
  "$NODE" --check "$TMP/$poly_name" || { echo "  !! $poly_name 拼接后语法异常"; exit 1; }

  mv "$TMP/$poly_name" "$OUT_DIR/$poly_name"
  printf '  %-32s %8s bytes\n' "$poly_name" "$(wc -c < "$OUT_DIR/$poly_name" | tr -d ' ')"
done

# ---------------------------------------------------------------- 改写配置
echo "==> 更新 $MODULE 中的 script-path"
# 兼容 GNU sed 与 BSD sed
if sed --version >/dev/null 2>&1; then SED_I=(sed -i); else SED_I=(sed -i ''); fi
"${SED_I[@]}" -E "s#Sub-Store/scripts/[0-9]+\.[0-9]+\.[0-9]+/#Sub-Store/scripts/$VERSION/#g" "$MODULE"

grep -oE 'https://raw\.githubusercontent\.com/[^,]+\.poly\.js' "$MODULE" | while read -r url; do
  printf '     %s\n' "$url"
done

# 校验：所有引用都指向新版本
bad="$(grep -oE 'scripts/[0-9]+\.[0-9]+\.[0-9]+/' "$MODULE" | sort -u | grep -v "^scripts/$VERSION/$" || true)"
[[ -z "$bad" ]] || { echo "  !! 配置中仍残留旧版本路径：$bad"; exit 1; }

# ---------------------------------------------------------------- 清理旧版本
if [[ "$KEEP_OLD" -eq 0 ]]; then
  for d in "$SCRIPTS_DIR"/*/; do
    [[ -d "$d" ]] || continue
    name="$(basename "$d")"
    [[ "$name" == "$VERSION" ]] && continue
    if git -C "$DIR/.." ls-files --error-unmatch "$d" >/dev/null 2>&1; then
      git -C "$DIR/.." rm -r -q "$d"
    else
      rm -rf "$d"
    fi
    echo "  已移除旧版本目录：$name"
  done
else
  echo "  --keep：保留旧版本目录"
fi

# ---------------------------------------------------------------- 收尾提示
cat <<EOF

==> 完成。下一步：

  1. 确认无误后提交并推送（脚本文件须推送到远端，raw 链接才生效）
  2. Surge 中【删除】旧模块后重新安装，不能点「更新」，否则沿用旧参数表

  模块地址：
    https://raw.githubusercontent.com/th815/Profiles/main/Sub-Store/config/Surge.sgmodule

  验证（浏览器打开，注意是 http）：
    http://sub.store/api/utils/env
    应返回 "version":"$VERSION"
EOF
