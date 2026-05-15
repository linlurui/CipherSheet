#!/usr/bin/env bash
# 构建 Windows 应用，并将 .dll 复制到 Release 目录
# 用法: ./scripts/build_windows.sh
# 注意：需要在 Windows 主机或 Wine 环境下运行 flutter build windows
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJ_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
NATIVE_DIR="$PROJ_DIR/native/windows-x86_64"

if [ ! -f "$NATIVE_DIR/libdecentrilicense.dll" ]; then
  echo "错误：缺少 $NATIVE_DIR/libdecentrilicense.dll"
  echo "请先运行 ./scripts/sync_native_libs.sh"
  exit 1
fi

cd "$PROJ_DIR"
echo "[build] flutter build windows --release"
flutter build windows --release

RELEASE_DIR="$PROJ_DIR/build/windows/x64/runner/Release"
if [ ! -d "$RELEASE_DIR" ]; then
  # 不同 Flutter 版本输出位置可能不同，尝试备用
  RELEASE_DIR="$PROJ_DIR/build/windows/runner/Release"
fi
if [ ! -d "$RELEASE_DIR" ]; then
  echo "错误：找不到 Windows 构建产物目录"
  exit 1
fi

# Dart FFI 在 Windows 上加载 'decentrilicense.dll'（无 lib 前缀）
cp -f "$NATIVE_DIR/libdecentrilicense.dll" "$RELEASE_DIR/decentrilicense.dll"
# 同时保留带前缀的一份兜底
cp -f "$NATIVE_DIR/libdecentrilicense.dll" "$RELEASE_DIR/"

echo "[done] Release: $RELEASE_DIR"
ls -la "$RELEASE_DIR/"*.dll
