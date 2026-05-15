#!/usr/bin/env bash
# 构建 macOS Universal Binary（arm64 + x86_64 合并），可在两种架构 Mac 上原生运行
# 用法: ./scripts/build_macos_universal.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJ_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# 先确保两个架构的库都已就位
for arch in arm64 x86_64; do
  if [ ! -f "$PROJ_DIR/native/macos-$arch/libdecentrilicense.dylib" ]; then
    echo "错误：缺少 native/macos-$arch/libdecentrilicense.dylib"
    echo "请先运行 ./scripts/sync_native_libs.sh"
    exit 1
  fi
done

# 创建 universal 目录，合并 dylib
UNIV_DIR="$PROJ_DIR/native/macos-universal"
mkdir -p "$UNIV_DIR"

echo "[lipo] 合并 dylib 到 universal binary..."
for libname in libdecentrilicense.dylib libssl.3.dylib libcrypto.3.dylib; do
  arm_lib="$PROJ_DIR/native/macos-arm64/$libname"
  x86_lib="$PROJ_DIR/native/macos-x86_64/$libname"
  if [ -f "$arm_lib" ] && [ -f "$x86_lib" ]; then
    lipo -create "$arm_lib" "$x86_lib" -output "$UNIV_DIR/$libname"
    chmod u+w "$UNIV_DIR/$libname"
    echo "  ✓ $libname (arm64+x86_64)"
  elif [ -f "$arm_lib" ]; then
    cp -f "$arm_lib" "$UNIV_DIR/$libname"
    echo "  · $libname (仅 arm64)"
  fi
done

# 用 Flutter 构建（Flutter macOS 默认产出 universal）
cd "$PROJ_DIR"
echo "[build] flutter build macos --release"
flutter build macos --release

APP_DIR="$PROJ_DIR/build/macos/Build/Products/Release/ciphersheet.app"
MACOS_DIR="$APP_DIR/Contents/MacOS"
NATIVE_DIR="$UNIV_DIR"

echo "[embed] 复制 universal 库到 $MACOS_DIR"
cp -f "$NATIVE_DIR/"*.dylib "$MACOS_DIR/"

# install_name + 依赖修复（同 build_macos.sh）
for dylib in "$MACOS_DIR/"libdecentrilicense.dylib "$MACOS_DIR/"libssl.3.dylib "$MACOS_DIR/"libcrypto.3.dylib; do
  [ -f "$dylib" ] || continue
  install_name_tool -id "@executable_path/$(basename "$dylib")" "$dylib" 2>/dev/null || true
done

fix_deps() {
  local target="$1"
  [ -f "$target" ] || return 0
  for dep_name in libssl.3.dylib libcrypto.3.dylib; do
    while read -r old; do
      [ -z "$old" ] && continue
      if [ -f "$MACOS_DIR/$dep_name" ]; then
        install_name_tool -change "$old" "@executable_path/$dep_name" "$target" 2>/dev/null \
          && echo "  ✓ [$(basename "$target")] $old -> @executable_path/$dep_name"
      fi
    done < <(otool -L "$target" | awk 'NR>1 {print $1}' | grep -E "/$dep_name$" || true)
  done
}

for f in "$MACOS_DIR/"libdecentrilicense.dylib "$MACOS_DIR/"libssl.3.dylib "$MACOS_DIR/"libcrypto.3.dylib; do
  fix_deps "$f"
done

codesign --force --sign - "$MACOS_DIR/"*.dylib 2>/dev/null || true
codesign --force --deep --sign - "$APP_DIR" 2>/dev/null || true

echo "[done] Universal app: $APP_DIR"
echo "[verify] 架构："
lipo -info "$MACOS_DIR/libdecentrilicense.dylib"
lipo -info "$MACOS_DIR/ciphersheet"
