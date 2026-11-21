#!/usr/bin/env bash
# 编译 DeadAd（DNS 系统级去广告 App + DNSProxy 扩展），产出未签名 IPA。
set -euo pipefail
cd "$(dirname "$0")"

command -v xcodebuild >/dev/null 2>&1 || { echo "需要 Xcode" >&2; exit 1; }
command -v xcodegen >/dev/null 2>&1 || { echo "需要 xcodegen" >&2; exit 1; }

echo "==> 生成 Xcode 工程"
xcodegen generate

echo "==> 编译（先不签名）"
xcodebuild \
  -project DeadAd.xcodeproj \
  -scheme DeadAd \
  -configuration Release \
  -sdk iphoneos \
  -derivedDataPath build \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  build

APP="build/Build/Products/Release-iphoneos/DeadAd.app"
if [ ! -d "$APP" ]; then
  echo "编译产物不存在：$APP" >&2
  exit 1
fi

chmod +x "$APP/DeadAd" || true
chmod +x "$APP/PlugIns/DNSProxy.appex/DNSProxy" 2>/dev/null || true

echo "==> Ad-hoc 签名并把 Network Extension 权限写进二进制"
codesign --force --sign - --timestamp=none \
  --entitlements Entitlements/DNSProxy.entitlements \
  "$APP/PlugIns/DNSProxy.appex"
codesign --force --sign - --timestamp=none \
  --entitlements Entitlements/DeadAd.entitlements \
  "$APP"

echo "==> 打包 IPA"
rm -rf build/Payload build/DeadAd.ipa
mkdir -p build/Payload
cp -R "$APP" build/Payload/
(
  cd build
  zip -qry DeadAd.ipa Payload
)

echo "✅ 完成：$(pwd)/build/DeadAd.ipa"
