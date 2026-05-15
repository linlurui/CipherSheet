#!/usr/bin/env bash
# 构建 Android APK / AAB，自动同步 jniLibs
# 用法: ./scripts/build_android.sh [apk|appbundle]   （默认 apk）
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJ_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
TARGET="${1:-apk}"

# 同步 jniLibs（4 个 ABI）
echo "[sync] 同步 jniLibs..."
JNI_DIR="$PROJ_DIR/android/app/src/main/jniLibs"
for abi in arm64-v8a armeabi-v7a x86 x86_64; do
  src="$PROJ_DIR/native/android/$abi/libdecentrilicense.so"
  dst_dir="$JNI_DIR/$abi"
  if [ -f "$src" ]; then
    mkdir -p "$dst_dir"
    cp -f "$src" "$dst_dir/"
    echo "  ✓ $abi"
  else
    echo "  ⚠ 缺少 $src，请先运行 ./scripts/sync_native_libs.sh"
  fi
done

cd "$PROJ_DIR"
echo "[build] flutter build $TARGET --release"
case "$TARGET" in
  apk)
    flutter build apk --release
    OUT="$PROJ_DIR/build/app/outputs/flutter-apk/app-release.apk"
    ;;
  appbundle|aab)
    flutter build appbundle --release
    OUT="$PROJ_DIR/build/app/outputs/bundle/release/app-release.aab"
    ;;
  *) echo "未知 target: $TARGET (支持 apk / appbundle)"; exit 1 ;;
esac

if [ -f "$OUT" ]; then
  echo "[done] $OUT"
  ls -lh "$OUT"
else
  echo "[warn] 产物未找到，请查看 build/ 目录"
fi
