#!/usr/bin/env bash
# installe tablet-toggle et son lanceur (panel-autohide s'installe avec : fish panel-autohide.fish install)
set -euo pipefail
cd "$(dirname "$0")"
install -Dm755 tablet-toggle ~/.local/bin/tablet-toggle
sed "s|^Exec=.*|Exec=$HOME/.local/bin/tablet-toggle|" tablet-toggle.desktop > /tmp/tablet-toggle.desktop
install -Dm644 /tmp/tablet-toggle.desktop ~/.local/share/applications/tablet-toggle.desktop
command -v kbuildsycoca6 >/dev/null && kbuildsycoca6 >/dev/null 2>&1 || true
echo "tablet-toggle installé. Épingle « Basculer clavier » dans la barre des tâches."
