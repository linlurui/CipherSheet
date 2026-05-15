#!/usr/bin/env bash
# 构建 macOS 应用，并将原生库嵌入 .app/Contents/MacOS/
# 用法: ./scripts/build_macos.sh [arm64|x86_64]    （默认 arm64）
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJ_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ARCH="${1:-arm64}"

case "$ARCH" in
  arm64)   NATIVE_DIR="$PROJ_DIR/native/macos-arm64"   ;;
  x86_64)  NATIVE_DIR="$PROJ_DIR/native/macos-x86_64"  ;;
  *) echo "未知架构: $ARCH (支持 arm64/x86_64)"; exit 1 ;;
esac

if [ ! -f "$NATIVE_DIR/libdecentrilicense.dylib" ]; then
  echo "错误：缺少 $NATIVE_DIR/libdecentrilicense.dylib"
  echo "请先运行 ./scripts/sync_native_libs.sh"
  exit 1
fi

cd "$PROJ_DIR"
echo "[build] flutter build macos --release"
flutter build macos --release

APP_DIR="$PROJ_DIR/build/macos/Build/Products/Release/ciphersheet.app"
MACOS_DIR="$APP_DIR/Contents/MacOS"

if [ ! -d "$APP_DIR" ]; then
  echo "错误：构建产物不存在 $APP_DIR"
  exit 1
fi

echo "[embed] 复制原生库到 $MACOS_DIR"
cp -f "$NATIVE_DIR/"*.dylib "$MACOS_DIR/"

# 修复 install_name，确保 dyld 从 @executable_path 加载
for dylib in "$MACOS_DIR/"libdecentrilicense.dylib "$MACOS_DIR/"libssl.3.dylib "$MACOS_DIR/"libcrypto.3.dylib; do
  [ -f "$dylib" ] || continue
  install_name_tool -id "@executable_path/$(basename "$dylib")" "$dylib" 2>/dev/null || true
done

# 修复每个嵌入 dylib 对 ssl/crypto 的引用 -> @executable_path
# 既包括 libdecentrilicense.dylib，也包括 libssl.3.dylib 自身对 libcrypto.3.dylib 的引用
fix_deps() {
  local target="$1"
  [ -f "$target" ] || return 0
  for dep_name in libssl.3.dylib libcrypto.3.dylib; do
    # 匹配任意路径前缀：@rpath/ 、/opt/homebrew/... 、@loader_path/... 等
    while read -r old; do
      [ -z "$old" ] && continue
      if [ -f "$MACOS_DIR/$dep_name" ]; then
        install_name_tool -change "$old" "@executable_path/$dep_name" "$target" 2>/dev/null \
          && echo "  ✓ [$( basename "$target")] $old -> @executable_path/$dep_name"
      fi
    done < <(otool -L "$target" | awk 'NR>1 {print $1}' | grep -E "/$dep_name$" || true)
  done
}

for f in "$MACOS_DIR/"libdecentrilicense.dylib "$MACOS_DIR/"libssl.3.dylib "$MACOS_DIR/"libcrypto.3.dylib; do
  fix_deps "$f"
done

# 重新签名（dylib 修改后需要重新签名）
codesign --force --sign - "$MACOS_DIR/"*.dylib 2>/dev/null || true
codesign --force --deep --sign - "$APP_DIR" 2>/dev/null || true

echo "[done] 应用: $APP_DIR"
echo "[verify] libdecentrilicense.dylib 依赖："
otool -L "$MACOS_DIR/libdecentrilicense.dylib" | head -10
