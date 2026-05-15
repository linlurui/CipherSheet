#!/usr/bin/env bash
# 构建 Linux 应用，并将 .so 嵌入 bundle/lib/
# 用法: ./scripts/build_linux.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJ_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
NATIVE_DIR="$PROJ_DIR/native/linux-x86_64"

if [ ! -f "$NATIVE_DIR/libdecentrilicense.so" ]; then
  echo "错误：缺少 $NATIVE_DIR/libdecentrilicense.so"
  echo "请先运行 ./scripts/sync_native_libs.sh"
  exit 1
fi

cd "$PROJ_DIR"
echo "[build] flutter build linux --release"
flutter build linux --release

# Flutter Linux 默认 rpath 是 $ORIGIN/lib，把 .so 放到 bundle/lib/
BUNDLE_DIR="$PROJ_DIR/build/linux/x64/release/bundle"
if [ ! -d "$BUNDLE_DIR" ]; then
  echo "错误：构建产物不存在 $BUNDLE_DIR"
  exit 1
fi

mkdir -p "$BUNDLE_DIR/lib"
cp -f "$NATIVE_DIR/libdecentrilicense.so" "$BUNDLE_DIR/lib/"
# 同时放一份到可执行文件同级目录（兜底）
cp -f "$NATIVE_DIR/libdecentrilicense.so" "$BUNDLE_DIR/"

echo "[done] Bundle: $BUNDLE_DIR"
ls -la "$BUNDLE_DIR/lib/"
