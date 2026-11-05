<p align="center"><img src="docs/banner-kde-tablette-outils.png" alt="kde-tablette-outils" width="100%"></p>

<p align="center"><img src="https://img.shields.io/badge/platform-KDE%20Plasma%206%20·%20Wayland-000000?style=flat-square" alt="platform"> <img src="https://img.shields.io/badge/device-2--in--1%20laptops-610089?style=flat-square" alt="device"> <img src="https://img.shields.io/badge/license-MIT-610089?style=flat-square" alt="license"></p>

<p align="center"><a href="README.md">🇬🇧 English version</a></p>

Deux petits outils pour utiliser un PC 2-en-1 en mode tablette sous KDE Plasma 6 (Wayland), faits pour mon Lenovo Yoga 7 2-in-1 14ILL10.

Sur ce modèle, le mode tablette de KDE ne s'active jamais quand on replie l'écran : le pilote `lenovo_ymc` voit bien l'interrupteur, mais l'Intel Sensor Hub n'a pas encore de firmware pour ce modèle dans linux-firmware, donc pas d'accéléromètre ni de bascule automatique. Je gère ça à la main.

## tablet-toggle

Coupe ou rallume le clavier et le pavé tactile intégrés d'un coup, via l'interface D-Bus de KWin (`org.kde.KWin.InputDevice.enabled`). Pas besoin de root.

```bash
install -Dm755 tablet-toggle ~/.local/bin/tablet-toggle
install -Dm644 tablet-toggle.desktop ~/.local/share/applications/tablet-toggle.desktop
```

Puis épingler « Basculer clavier » dans la barre des tâches pour avoir un bouton au tactile.

- `tablet-toggle` : bascule
- `tablet-toggle on` : force le retour du clavier

Les noms des périphériques sont ceux de mon PC. Pour les tiens :

```bash
for p in $(busctl --user tree org.kde.KWin --list | grep InputDevice/event); do
  busctl --user get-property org.kde.KWin $p org.kde.KWin.InputDevice name
done
```

et les mettre dans `TABLET_TOGGLE_DEVICES`, séparés par `|`.

## panel-autohide

Bascule la barre des tâches entre *masquage automatique* et *toujours visible* (raccourci Meta+H et bouton).

En plus, un petit service surveille le clavier : dès qu'il est coupé (mode tablette forcé dans les paramètres, ou `tablet-toggle`), la barre est forcée visible. Je l'ai ajouté après m'être retrouvé bloqué avec clavier et pavé tactile coupés et une barre cachée : impossible de m'en sortir sans souris.

```bash
fish panel-autohide.fish install
panel-autohide.fish status     # pour voir ce qui est détecté
```

Le raccourci se règle dans *Paramètres → Clavier → Raccourcis → Ajouter une commande* → `~/.local/bin/toggle-panel-autohide.sh`. (L'écrire directement dans `kglobalshortcutsrc` ne marche qu'après une reconnexion.)

Le service vérifie l'état toutes les 2 s et ne parle à Plasma que quand le mode change.

## À savoir

- dans `kwinrc`, `TabletMode` vaut `on` / `off` / `auto` (pas `yes`/`no`) ;
- les panneaux se pilotent avec `evaluateScript` sur `org.kde.PlasmaShell` (`panels()[i].hiding = "autohide" | "none"`).
