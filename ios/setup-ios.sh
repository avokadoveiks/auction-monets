#!/bin/bash
# =================================================================
# setup-ios.sh — Один запуск → готовый Xcode проект
# Запускать на Mac с установленным Xcode
# =================================================================

set -e
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
ok()  { echo -e "${GREEN}✓ $1${NC}"; }
err() { echo -e "${RED}✗ $1${NC}"; exit 1; }
inf() { echo -e "${YELLOW}→ $1${NC}"; }

echo ""
echo "  🪙  АУКЦИОН МОНЕТ — iOS сборка"
echo "  ================================"
echo ""

# ── 1. Проверяем инструменты ──────────────────────────────────
inf "Проверяем зависимости..."
command -v node  >/dev/null || err "Node.js не установлен → https://nodejs.org"
command -v xcode-select >/dev/null || err "Xcode не установлен → App Store"
xcodebuild -version >/dev/null 2>&1 || err "Xcode Command Line Tools нужны: xcode-select --install"
ok "Node $(node -v) | Xcode $(xcodebuild -version | head -1)"

# ── 2. Создаём структуру ─────────────────────────────────────
inf "Создаём папки..."
mkdir -p www src

# Копируем игру в www
if [ -f "src/index.html" ]; then
    cp src/index.html www/index.html
    ok "index.html скопирован"
elif [ -f "index.html" ]; then
    cp index.html www/index.html
    ok "index.html скопирован"
else
    err "Не найден index.html — положи файл игры рядом со скриптом"
fi

# ── 3. Устанавливаем пакеты ───────────────────────────────────
inf "npm install..."
npm install
ok "Пакеты установлены"

# ── 4. Инициализируем Capacitor если нужно ────────────────────
if [ ! -d "ios" ]; then
    inf "Добавляем iOS платформу..."
    npx cap add ios
    ok "iOS платформа добавлена"
else
    ok "iOS платформа уже есть"
fi

# ── 5. Синхронизируем код в Xcode ─────────────────────────────
inf "Синхронизируем в Xcode проект..."
npx cap sync ios
ok "Синхронизация готова"

# ── 6. Копируем иконки ────────────────────────────────────────
ICON_DIR="ios/App/App/Assets.xcassets/AppIcon.appiconset"
if [ -d "icons" ] && [ -d "$ICON_DIR" ]; then
    inf "Копируем иконки приложения..."
    cp icons/*.png "$ICON_DIR/"
    cp icons/Contents.json "$ICON_DIR/"
    ok "Иконки установлены (${ICON_DIR})"
else
    echo "  ℹ  Иконки: положи папку 'icons' рядом со скриптом"
fi

# ── 7. Настройки Info.plist ───────────────────────────────────
PLIST="ios/App/App/Info.plist"
inf "Настраиваем Info.plist..."

# Запрет ротации — только landscape (игра горизонтальная)
/usr/libexec/PlistBuddy -c "Delete :UISupportedInterfaceOrientations" "$PLIST" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :UISupportedInterfaceOrientations array" "$PLIST"
/usr/libexec/PlistBuddy -c "Add :UISupportedInterfaceOrientations:0 string UIInterfaceOrientationLandscapeLeft"  "$PLIST"
/usr/libexec/PlistBuddy -c "Add :UISupportedInterfaceOrientations:1 string UIInterfaceOrientationLandscapeRight" "$PLIST"

# iPad landscape
/usr/libexec/PlistBuddy -c "Delete :UISupportedInterfaceOrientations~ipad" "$PLIST" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :UISupportedInterfaceOrientations~ipad array" "$PLIST"
/usr/libexec/PlistBuddy -c "Add :UISupportedInterfaceOrientations~ipad:0 string UIInterfaceOrientationLandscapeLeft"  "$PLIST"
/usr/libexec/PlistBuddy -c "Add :UISupportedInterfaceOrientations~ipad:1 string UIInterfaceOrientationLandscapeRight" "$PLIST"

# Прячем статус-бар на iPhone
/usr/libexec/PlistBuddy -c "Set :UIStatusBarHidden true" "$PLIST" 2>/dev/null || \
/usr/libexec/PlistBuddy -c "Add :UIStatusBarHidden bool true"  "$PLIST"

# Имя приложения
/usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName 'Аукцион Монет'" "$PLIST" 2>/dev/null || \
/usr/libexec/PlistBuddy -c "Add :CFBundleDisplayName string 'Аукцион Монет'" "$PLIST"

ok "Info.plist настроен (landscape, без статус-бара)"

# ── 8. Открываем Xcode ───────────────────────────────────────
echo ""
inf "Открываем Xcode..."
npx cap open ios
echo ""
echo "  ✅  ГОТОВО!"
echo ""
echo "  В Xcode:"
echo "  1. Выбери Team (Signing & Capabilities)"
echo "  2. Поменяй Bundle ID: com.auktsionmonet.app → твой"
echo "  3. Product → Archive → Distribute App"
echo ""
echo "  Документация: https://capacitorjs.com/docs/ios"
