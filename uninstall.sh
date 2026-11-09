#!/usr/bin/env bash
set -uo pipefail
~/.local/bin/clavier-garde on >/dev/null 2>&1   # remet clavier et pavé avant de partir
systemctl --user disable --now clavier-garde.service
rm -f ~/.config/systemd/user/clavier-garde.service ~/.local/bin/clavier-garde ~/.local/bin/tablet-toggle \
  ~/.local/share/applications/tablet-toggle.desktop ~/.local/bin/panel-autohide.fish ~/.local/bin/toggle-panel-autohide.sh
kwriteconfig6 --file kwinrc --group Plugins --key secours-tabletteEnabled false
rm -rf ~/.local/share/kwin/scripts/secours-tablette
qdbus6 org.kde.KWin /KWin reconfigure 2>/dev/null
systemctl --user daemon-reload
echo "Désinstallé."
