#!/bin/bash
cd "$(dirname "$0")" || exit 1
if ! bash ios/setup-ios.sh; then
  echo ""
  read -r -p "Исправь указанную выше ошибку. Нажми Enter, чтобы закрыть окно."
  exit 1
fi
