#!/usr/bin/env fish
# panel-autohide : bascule la barre des tâches Plasma entre masquage auto
# et toujours visible (raccourci Meta+H + bouton dans la barre).
#
# En plus, quand le clavier intégré est coupé (mode tablette forcé par ex.),
# la barre est forcée visible pour pouvoir s'en sortir au tactile.
# Je me suis déjà retrouvé bloqué sans clavier ni pavé tactile, d'où ce garde-fou.
#
# Usage :
#   fish panel-autohide.fish install   installe tout (script, bouton, service)
#   panel-autohide.fish toggle         bascule masquage auto / toujours visible
#   panel-autohide.fish status         affiche ce qui est détecté
#   panel-autohide.fish apply          applique le mode voulu maintenant
#   panel-autohide.fish watch          surveille le clavier (lancé par le service)

set -g STATE_DIR   "$HOME/.local/state/panel-autohide"
set -g WANTED_FILE "$STATE_DIR/wanted"
set -g DEST        "$HOME/.local/bin/panel-autohide.fish"
set -g WRAPPER     "$HOME/.local/bin/toggle-panel-autohide.sh"
set -g UNIT_DIR    "$HOME/.config/systemd/user"
set -g UNIT_NAME   "panel-autohide-watch.service"
set -g ERRORS      0
set -g KBD_CACHE

# --- affichage ---
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

function warn
    set_color yellow
    echo "  ! $argv"
    set_color normal
end

function fail
    set_color red
    echo "  ✘ $argv"
    set_color normal
    set -g ERRORS (math $ERRORS + 1)
end

# --- mode choisi par l'utilisateur, gardé dans un fichier ---
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

# --- détection du clavier ---
# chemins D-Bus des claviers que KWin connaît
function kbd_paths
    for dev in (busctl --user tree org.kde.KWin 2>/dev/null | string match -r '/org/kde/KWin/InputDevice/event[0-9]+')
        if busctl --user get-property org.kde.KWin $dev org.kde.KWin.InputDevice alphaNumericKeyboard 2>/dev/null | string match -q 'b true'
            echo $dev
        end
    end
end

# renvoie 0 si le clavier est coupé
function keyboard_disabled
    # mode tablette forcé = KWin coupe clavier et pavé tactile
    # (attention : la valeur c'est on/off/auto, pas yes/no)
    set -l tm (kreadconfig6 --file kwinrc --group Input --key TabletMode 2>/dev/null)
    if test "$tm" = on
        return 0
    end
    for dev in $KBD_CACHE
        if busctl --user get-property org.kde.KWin $dev org.kde.KWin.InputDevice enabled 2>/dev/null | string match -q 'b false'
            return 0
        end
    end
    return 1
end

# mode vraiment appliqué : visible si pas de clavier, sinon le mode choisi
function effective_mode
    if keyboard_disabled
        echo none
    else
        wanted_mode
    end
end

# --- appliquer à toutes les barres ---
function apply_mode
    set -l js 'var ps = panels(); for (var i = 0; i < ps.length; i++) { ps[i].hiding = "MODE"; }'
    set js (string replace MODE $argv[1] -- $js)
    busctl --user call org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell evaluateScript s "$js" >/dev/null 2>&1
end

# --- installation ---
function do_install
    say "Vérification"
    if not string match -q '*KDE*' -- "$XDG_CURRENT_DESKTOP"
        fail "Pas une session KDE"
        exit 1
    end
    for cmd in busctl kreadconfig6 systemctl fish
        if command -q $cmd
            ok "$cmd trouvé"
        else
            fail "Commande manquante : $cmd"
        end
    end
    test $ERRORS -gt 0; and exit 1

    say "Installation du script"
    mkdir -p $HOME/.local/bin $UNIT_DIR $STATE_DIR
    or begin
        fail "Impossible de créer les dossiers"
        exit 1
    end

    set -l src (realpath (status filename))
    if not test -e $DEST; or not cmp -s $src $DEST
        cp $src $DEST
    end
    chmod +x $DEST
    if fish -n $DEST
        ok "$DEST installé"
    else
        fail "Erreur de syntaxe dans $DEST"
        exit 1
    end

    # petit wrapper sh : c'est lui qu'appellent le raccourci et le bouton
    printf '%s\n' '#!/bin/sh' 'exec fish "$HOME/.local/bin/panel-autohide.fish" toggle' >$WRAPPER
    chmod +x $WRAPPER
    if sh -n $WRAPPER
        ok "$WRAPPER créé"
    else
        fail "$WRAPPER invalide"
    end

    if not test -f $WANTED_FILE
        echo autohide >$WANTED_FILE
    end

    say "Service de surveillance du clavier"
    set -l fish_bin (command -s fish)
    printf '%s\n' \
        '[Unit]' \
        'Description=Garde la barre Plasma visible quand le clavier est désactivé' \
        '' \
        '[Service]' \
        "ExecStart=$fish_bin %h/.local/bin/panel-autohide.fish watch" \
        'Restart=on-failure' \
        'RestartSec=5' \
        '' \
        '[Install]' \
        'WantedBy=default.target' \
        >$UNIT_DIR/$UNIT_NAME

    systemctl --user daemon-reload
    systemctl --user enable $UNIT_NAME >/dev/null 2>&1
    systemctl --user restart $UNIT_NAME
    sleep 3
    if systemctl --user is-active --quiet $UNIT_NAME
        ok "Service actif (lancé à chaque session)"
    else
        fail "Le service ne démarre pas : journalctl --user -u $UNIT_NAME -n 20"
    end

    say "État"
    do_status

    echo
    if test $ERRORS -eq 0
        set_color green
        echo "Terminé sans erreur."
        set_color normal
        echo "  • Pour le raccourci : Paramètres > Clavier > Raccourcis > Ajouter une commande"
        echo "    -> $WRAPPER, puis Meta+H"
        echo "  • Vérifier à tout moment : panel-autohide.fish status"
    else
        set_color red
        echo "Terminé avec $ERRORS erreur(s), voir les lignes ✘."
        set_color normal
        exit 1
    end
end

function do_status
    set -g KBD_CACHE (kbd_paths)
    echo "  Mode voulu              : "(wanted_mode)
    echo "  TabletMode (kwinrc)     : "(kreadconfig6 --file kwinrc --group Input --key TabletMode 2>/dev/null)
    echo "  Claviers vus par KWin   : "(count $KBD_CACHE)
    for dev in $KBD_CACHE
        echo "    $dev -> "(busctl --user get-property org.kde.KWin $dev org.kde.KWin.InputDevice enabled 2>&1)
    end
    if keyboard_disabled
        echo "  Clavier désactivé       : OUI, barre forcée visible"
    else
        echo "  Clavier désactivé       : non"
    end
    echo "  Mode effectif           : "(effective_mode)
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
        set -g KBD_CACHE (kbd_paths)
        apply_mode (effective_mode)

    case apply
        set -g KBD_CACHE (kbd_paths)
        apply_mode (effective_mode)

    case status
        do_status

    case watch
        mkdir -p $STATE_DIR
        set -l last ""
        set -l n 0
        while true
            # on relit la liste des claviers toutes les 60 s (ou tant qu'elle est vide)
            if test (math $n % 30) -eq 0; or test (count $KBD_CACHE) -eq 0
                set -g KBD_CACHE (kbd_paths)
            end
            set -l mode (effective_mode)
            if test "$mode" != "$last"
                # on ne retient le mode que si Plasma a répondu, sinon on réessaie
                if apply_mode $mode
                    set last $mode
                end
            end
            set n (math $n + 1)
            sleep 2
        end

    case '*'
        echo "Usage : panel-autohide.fish install|toggle|status|apply|watch"
        exit 1
end
