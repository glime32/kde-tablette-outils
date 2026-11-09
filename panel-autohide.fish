#!/usr/bin/env fish
# panel-autohide : bascule la barre des tâches Plasma entre masquage auto
# et toujours visible (raccourci Meta+H + bouton dans la barre).
#
# Le mode tablette ne touche plus à la barre : quand elle est cachée, on la
# rejoint en glissant le doigt depuis le bas de l'écran (script KWin
# secours-tablette). Avant, un service surveillait le clavier toutes les 2 s
# pour forcer la barre visible ; il est retiré à l'installation.
#
# Usage :
#   fish panel-autohide.fish install   installe le script et le petit wrapper du raccourci
#   panel-autohide.fish toggle         bascule masquage auto / toujours visible
#   panel-autohide.fish apply          applique le mode choisi maintenant
#   panel-autohide.fish status         affiche le mode choisi

set -g STATE_DIR   "$HOME/.local/state/panel-autohide"
set -g WANTED_FILE "$STATE_DIR/wanted"
set -g DEST        "$HOME/.local/bin/panel-autohide.fish"
set -g WRAPPER     "$HOME/.local/bin/toggle-panel-autohide.sh"
set -g OLD_UNIT    "panel-autohide-watch.service"
set -g ERRORS      0

function say
    set_color cyan
    echo "▶ $argv"
    set_color normal
end

function ok
    set_color green
    echo "  ✔ $argv"
    set_color normal
end

function fail
    set_color red
    echo "  ✘ $argv"
    set_color normal
    set -g ERRORS (math $ERRORS + 1)
end

# mode choisi, gardé dans un fichier
function wanted_mode
    if test -f $WANTED_FILE
        set -l m (string trim (cat $WANTED_FILE))
        if contains -- $m autohide none
            echo $m
            return
        end
    end
    echo autohide
end

# appliquer à toutes les barres
function apply_mode
    set -l js 'var ps = panels(); for (var i = 0; i < ps.length; i++) { ps[i].hiding = "MODE"; }'
    set js (string replace MODE $argv[1] -- $js)
    busctl --user call org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell evaluateScript s "$js" >/dev/null 2>&1
end

function do_install
    say "Vérification"
    if not string match -q '*KDE*' -- "$XDG_CURRENT_DESKTOP"
        fail "Pas une session KDE"
        exit 1
    end
    for cmd in busctl fish
        command -q $cmd; or fail "Commande manquante : $cmd"
    end
    test $ERRORS -gt 0; and exit 1

    say "Installation"
    mkdir -p $HOME/.local/bin $STATE_DIR
    set -l src (realpath (status filename))
    if not test -e $DEST; or not cmp -s $src $DEST
        cp $src $DEST
    end
    chmod +x $DEST
    ok "$DEST installé"

    # petit wrapper sh : c'est lui qu'appellent le raccourci et le bouton
    printf '%s\n' '#!/bin/sh' 'exec fish "$HOME/.local/bin/panel-autohide.fish" toggle' >$WRAPPER
    chmod +x $WRAPPER
    ok "$WRAPPER créé"

    test -f $WANTED_FILE; or echo autohide >$WANTED_FILE

    # ancienne version : service qui surveillait le clavier
    if systemctl --user cat $OLD_UNIT >/dev/null 2>&1
        systemctl --user disable --now $OLD_UNIT >/dev/null 2>&1
        rm -f $HOME/.config/systemd/user/$OLD_UNIT
        systemctl --user daemon-reload
        ok "ancien $OLD_UNIT retiré"
    end

    apply_mode (wanted_mode)
    echo
    echo "  • Pour le raccourci : Paramètres > Clavier > Raccourcis > Ajouter une commande"
    echo "    -> $WRAPPER, puis Meta+H"
end

switch "$argv[1]"
    case install
        do_install

    case toggle
        mkdir -p $STATE_DIR
        if test (wanted_mode) = autohide
            echo none >$WANTED_FILE
        else
            echo autohide >$WANTED_FILE
        end
        apply_mode (wanted_mode)

    case apply
        apply_mode (wanted_mode)

    case status
        echo "Mode choisi : "(wanted_mode)

    case '*'
        echo "Usage : panel-autohide.fish install|toggle|apply|status"
        exit 1
end
