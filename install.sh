#!/usr/bin/env bash
# Installe le faux mode tablette : démon clavier-garde, bouton « Basculer Clavier »,
# geste du bas (script KWin) et bascule de la barre (Meta+H).
set -euo pipefail
cd "$(dirname "$0")"

command -v cargo >/dev/null || { echo "cargo introuvable : installe rust (sudo pacman -S rust)"; exit 1; }
(cd clavier-garde && cargo build --release --locked)

install -Dm755 clavier-garde/target/release/clavier-garde ~/.local/bin/clavier-garde
install -Dm755 tablet-toggle ~/.local/bin/tablet-toggle
sed "s|^Exec=.*|Exec=$HOME/.local/bin/tablet-toggle|" tablet-toggle.desktop > "${TMPDIR:-/tmp}/tablet-toggle.desktop"
install -Dm644 "${TMPDIR:-/tmp}/tablet-toggle.desktop" ~/.local/share/applications/tablet-toggle.desktop
install -Dm644 clavier-garde.service ~/.config/systemd/user/clavier-garde.service

d=~/.local/share/kwin/scripts/secours-tablette
install -Dm644 kwin/secours-tablette/metadata.json "$d/metadata.json"
install -Dm644 kwin/secours-tablette/contents/code/main.js "$d/contents/code/main.js"
kwriteconfig6 --file kwinrc --group Plugins --key secours-tabletteEnabled true
# zone de toucher des bords : 8 px par défaut, trop fin pour un doigt
kwriteconfig6 --file kwinrc --group ScreenEdges --key TouchTarget 20
qdbus6 org.kde.KWin /KWin reconfigure 2>/dev/null || true

fish panel-autohide.fish install

systemctl --user daemon-reload
systemctl --user enable clavier-garde.service
systemctl --user restart clavier-garde.service
command -v kbuildsycoca6 >/dev/null && kbuildsycoca6 >/dev/null 2>&1 || true

echo "Installé. Épingle « Basculer Clavier » dans la barre des tâches."
pacman -Q plasma-keyboard >/dev/null 2>&1 || echo "Conseil : sudo pacman -S plasma-keyboard pour avoir un clavier à l'écran en mode tablette."
