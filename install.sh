#!/usr/bin/env bash
set -euo pipefail

# maw インストーラ

MAW_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="${HOME}/.local/bin"

echo "[maw] インストールを開始します..."

# インストール先ディレクトリ作成
mkdir -p "$INSTALL_DIR"

# シンボリックリンク作成
if [[ -L "${INSTALL_DIR}/maw" ]] || [[ -f "${INSTALL_DIR}/maw" ]]; then
  rm -f "${INSTALL_DIR}/maw"
fi

ln -s "${MAW_DIR}/bin/maw" "${INSTALL_DIR}/maw"

echo "[maw] インストール完了: ${INSTALL_DIR}/maw -> ${MAW_DIR}/bin/maw"

# PATH チェック
if ! echo "$PATH" | tr ':' '\n' | grep -qx "$INSTALL_DIR"; then
  echo ""
  echo "[maw] PATH に ${INSTALL_DIR} を追加してください:"
  echo ""
  echo "  # bash"
  echo "  echo 'export PATH=\"\${HOME}/.local/bin:\${PATH}\"' >> ~/.bashrc"
  echo ""
  echo "  # zsh"
  echo "  echo 'export PATH=\"\${HOME}/.local/bin:\${PATH}\"' >> ~/.zshrc"
fi

echo ""
echo "[maw] 使い方: maw --help"
