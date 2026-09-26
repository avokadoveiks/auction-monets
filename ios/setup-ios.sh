#!/bin/bash
# Run from any directory on a Mac with Xcode, Node.js and CocoaPods.
set -euo pipefail
cd "$(dirname "$0")"

fail() { echo "Ошибка: $1" >&2; exit 1; }
[ "$(uname -s)" = "Darwin" ] || fail "Для сборки iOS нужен Mac с Xcode."
command -v node >/dev/null || fail "Установи Node.js: https://nodejs.org"
command -v npm >/dev/null || fail "npm не найден."
command -v pod >/dev/null || fail "Установи CocoaPods: https://guides.cocoapods.org/using/getting-started.html"
xcodebuild -version >/dev/null 2>&1 || fail "Установи Xcode и выбери его в Xcode → Settings → Locations → Command Line Tools."

echo "Установка зависимостей..."
npm ci
npm run build

if [ ! -d "ios/App" ]; then
  npx cap add ios
fi

# Keep the existing landscape layout; CSS handles safe-area insets.
PLIST="ios/App/App/Info.plist"
for KEY in UISupportedInterfaceOrientations 'UISupportedInterfaceOrientations~ipad'; do
  /usr/libexec/PlistBuddy -c "Delete :$KEY" "$PLIST" 2>/dev/null || true
  /usr/libexec/PlistBuddy -c "Add :$KEY array" "$PLIST"
  /usr/libexec/PlistBuddy -c "Add :$KEY:0 string UIInterfaceOrientationLandscapeLeft" "$PLIST"
  /usr/libexec/PlistBuddy -c "Add :$KEY:1 string UIInterfaceOrientationLandscapeRight" "$PLIST"
done
/usr/libexec/PlistBuddy -c "Set :UIStatusBarHidden true" "$PLIST" 2>/dev/null || /usr/libexec/PlistBuddy -c "Add :UIStatusBarHidden bool true" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :UIViewControllerBasedStatusBarAppearance false" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :UIRequiresFullScreen true" "$PLIST" 2>/dev/null || /usr/libexec/PlistBuddy -c "Add :UIRequiresFullScreen bool true" "$PLIST"

npx cap sync ios
echo "Открываю Xcode. Для симулятора выбери iPhone и нажми Run."
echo "Для своего iPhone выбери Apple Team в Signing & Capabilities."
npx cap open ios
