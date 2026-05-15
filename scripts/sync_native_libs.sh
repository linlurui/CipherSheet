#!/usr/bin/env bash
# 把 native/ 里的库推送到 Flutter 各平台集成目录
# 用法: ./scripts/sync_native_libs.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJ_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
NATIVE="$PROJ_DIR/native"

copy_if_exists() {
  local src="$1" dst="$2"
  if [ -f "$src" ]; then
    cp -f "$src" "$dst"
    echo "  ✓ $(basename "$src")"
  fi
}

# Android jniLibs
echo "[sync] Android jniLibs ..."
for abi in arm64-v8a armeabi-v7a x86 x86_64; do
  mkdir -p "$PROJ_DIR/android/app/src/main/jniLibs/$abi"
  copy_if_exists "$NATIVE/android/$abi/libdecentrilicense.so" \
                 "$PROJ_DIR/android/app/src/main/jniLibs/$abi/libdecentrilicense.so"
done

# iOS Frameworks
echo "[sync] iOS Frameworks ..."
mkdir -p "$PROJ_DIR/ios/Frameworks"
copy_if_exists "$NATIVE/ios/ios-arm64/libdecentrilicense.a" \
               "$PROJ_DIR/ios/Frameworks/libdecentrilicense-device.a"
SIM_ARM64="$NATIVE/ios/iossimulator-arm64/libdecentrilicense.a"
SIM_X86="$NATIVE/ios/iossimulator-x86_64/libdecentrilicense.a"
if [ -f "$SIM_ARM64" ] && [ -f "$SIM_X86" ]; then
  lipo -create "$SIM_ARM64" "$SIM_X86" \
       -output "$PROJ_DIR/ios/Frameworks/libdecentrilicense-simulator.a"
  echo "  ✓ libdecentrilicense-simulator.a (fat: arm64 + x86_64)"
elif [ -f "$SIM_ARM64" ]; then
  copy_if_exists "$SIM_ARM64" "$PROJ_DIR/ios/Frameworks/libdecentrilicense-simulator.a"
fi

echo "[sync] 完成 ✅"
