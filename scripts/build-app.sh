#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."
swift build -c release
app="$PWD/dist/JustClick.app"
mkdir -p "$app/Contents/MacOS"
cp .build/release/JustClick "$app/Contents/MacOS/JustClick"
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>JustClick</string>
<key>CFBundleIdentifier</key><string>local.justclick.app</string>
<key>CFBundleName</key><string>JustClick</string>
<key>CFBundleDisplayName</key><string>JustClick</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.10.0</string>
<key>CFBundleVersion</key><string>22</string>
<key>NSScreenCaptureUsageDescription</key><string>仅在输入框无法通过焦点和辅助功能定位时，本地识别当前窗口的输入区域，不上传截图。</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
mkdir -p "$app/Contents/Resources/Licenses"
cp LICENSE "$app/Contents/Resources/Licenses/JustClick-MIT.txt"
cp THIRD_PARTY_LICENSES/* "$app/Contents/Resources/Licenses/"
mkdir -p "$app/Contents/Resources/history"
cp scripts/history/discover.py "$app/Contents/Resources/history/discover.py"
signing_identity="${JUSTCLICK_SIGNING_IDENTITY:--}"
if [[ "$signing_identity" == '-' ]]; then
  print -u2 '注意：当前为临时签名。修改应用后 macOS 授权可能失效；发行构建请设置 JUSTCLICK_SIGNING_IDENTITY 为固定签名证书。'
fi
codesign --force --sign "$signing_identity" --identifier local.justclick.app "$app"
codesign --verify --deep --strict "$app"
print "Built: $app"
