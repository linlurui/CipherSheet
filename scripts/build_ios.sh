#!/usr/bin/env bash
# 构建 iOS app（device 或 simulator），自动同步合并静态库
# 用法: ./scripts/build_ios.sh [device|simulator|ipa]   （默认 simulator，便于本地测试）
# 注意：device/ipa 需要有效的开发者证书与 provisioning profile
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJ_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
TARGET="${1:-simulator}"

DLCORE_BUILD="${DL_CORE_BUILD_DIR:-/Volumes/workspace/project/ccait/decentri-license/dl-core/build-all}"
THIRDPARTY="${DL_THIRDPARTY:-$HOME/dl-thirdparty}"
FRAMEWORK_DIR="$PROJ_DIR/ios/Frameworks"

mkdir -p "$FRAMEWORK_DIR"

# 重新合并 device fat archive（dl-core + ssl + crypto + curl）
combine_device() {
  echo "[lipo] 合并 device 静态库..."
  libtool -static -o "$FRAMEWORK_DIR/libdecentrilicense-device.a" \
    "$DLCORE_BUILD/ios/ios-arm64/libdecentrilicense.a" \
    "$THIRDPARTY/openssl-ios/ios-arm64/lib/libssl.a" \
    "$THIRDPARTY/openssl-ios/ios-arm64/lib/libcrypto.a" \
    "$THIRDPARTY/curl-ios/ios-arm64/lib/libcurl.a" 2>&1 | grep -v "no symbols" || true
}

combine_simulator() {
  echo "[lipo] 合并 simulator 静态库..."
  libtool -static -o /tmp/dl-sim-arm64.a \
    "$DLCORE_BUILD/ios/iossimulator-arm64/libdecentrilicense.a" \
    "$THIRDPARTY/openssl-ios/iossimulator-arm64/lib/libssl.a" \
    "$THIRDPARTY/openssl-ios/iossimulator-arm64/lib/libcrypto.a" \
    "$THIRDPARTY/curl-ios/iossimulator-arm64/lib/libcurl.a" 2>&1 | grep -v "no symbols" || true
  libtool -static -o /tmp/dl-sim-x86_64.a \
    "$DLCORE_BUILD/ios/iossimulator-x86_64/libdecentrilicense.a" \
    "$THIRDPARTY/openssl-ios/iossimulator-x86_64/lib/libssl.a" \
    "$THIRDPARTY/openssl-ios/iossimulator-x86_64/lib/libcrypto.a" \
    "$THIRDPARTY/curl-ios/iossimulator-x86_64/lib/libcurl.a" 2>&1 | grep -v "no symbols" || true
  lipo -create /tmp/dl-sim-arm64.a /tmp/dl-sim-x86_64.a \
    -output "$FRAMEWORK_DIR/libdecentrilicense-simulator.a"
}

[ -f "$FRAMEWORK_DIR/libdecentrilicense-device.a" ]    || combine_device
[ -f "$FRAMEWORK_DIR/libdecentrilicense-simulator.a" ] || combine_simulator

cd "$PROJ_DIR"

# pod install（首次或 podspec 变更时必要）
if [ ! -d "$PROJ_DIR/ios/Pods/DecentriLicense" ] || [ "$FRAMEWORK_DIR/DecentriLicense.podspec" -nt "$PROJ_DIR/ios/Podfile.lock" ]; then
  echo "[pod] pod install"
  cd "$PROJ_DIR/ios" && pod install --repo-update 2>&1 | tail -10
  cd "$PROJ_DIR"
fi

case "$TARGET" in
  simulator)
    echo "[build] flutter build ios --simulator --debug"
    flutter build ios --simulator --debug
    OUT="$PROJ_DIR/build/ios/iphonesimulator/Runner.app"
    ;;
  device)
    echo "[build] flutter build ios --release --no-codesign"
    flutter build ios --release --no-codesign
    OUT="$PROJ_DIR/build/ios/iphoneos/Runner.app"
    ;;
  ipa)
    echo "[build] flutter build ipa --release"
    flutter build ipa --release
    OUT="$PROJ_DIR/build/ios/ipa"
    ;;
  *) echo "未知 target: $TARGET (支持 simulator / device / ipa)"; exit 1 ;;
esac

if [ -e "$OUT" ]; then
  echo "[done] $OUT"
  ls -la "$OUT" 2>/dev/null | head -5
fi
