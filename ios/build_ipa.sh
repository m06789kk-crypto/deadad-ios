#!/usr/bin/env bash
# 在 macOS 上把 DeadAd 编成未签名 IPA（之后用 Sideloadly / AltStore / TrollStore 自签安装）。
# 依赖：Xcode 命令行工具 + xcodegen（brew install xcodegen）。
set -euo pipefail
cd "$(dirname "$0")"

if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "需要 Xcode：先安装 Xcode 并执行 sudo xcode-select -s /Applications/Xcode.app" >&2
  exit 1
fi

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "需要 xcodegen：brew install xcodegen" >&2
  exit 1
fi

echo "==> 生成 Xcode 工程"
xcodegen generate

echo "==> 编译（不签名）"
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

echo "==> 打包 IPA"
rm -rf build/Payload build/DeadAd.ipa
mkdir -p build/Payload
cp -R "$APP" build/Payload/
(
  cd build
  zip -qry DeadAd.ipa Payload
)

echo "✅ 完成：$(pwd)/build/DeadAd.ipa"
echo "   下一步：用 Sideloadly / AltStore 签名安装，或直接丢给 TrollStore。"
