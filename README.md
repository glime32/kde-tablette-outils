<p align="center"><img src="docs/banner-kde-tablette-outils.png" alt="kde-tablette-outils" width="100%"></p>

<p align="center"><img src="https://img.shields.io/badge/platform-KDE%20Plasma%206%20·%20Wayland-000000?style=flat-square" alt="platform"> <img src="https://img.shields.io/badge/device-2--in--1%20laptops-610089?style=flat-square" alt="device"> <img src="https://img.shields.io/badge/rust-2021-dea584?style=flat-square" alt="rust"> <img src="https://img.shields.io/badge/license-MIT-610089?style=flat-square" alt="license"></p>

<p align="center"><a href="README.fr.md">🇫🇷 Version française</a></p>

**A manual tablet mode for a 2-in-1 laptop on KDE Plasma 6 (Wayland)** — made for my Lenovo Yoga 7 2-in-1 14ILL10.

On this model KDE's tablet mode never triggers when you fold the screen: `lenovo_ymc` sees the switch, but the Intel Sensor Hub has no firmware for this model in linux-firmware yet, so there's no accelerometer. I switch by hand, with a button on the taskbar.

## What tablet mode does

One tap on "Basculer Clavier":

- turns off the built-in keyboard, the touchpad and the Fn keys (airplane, camera, mic, brightness…), so the folded screen resting on the keyboard types nothing;
- sets Plasma's virtual keyboard (`plasma-keyboard`) as input method if it is installed, so it pops up when you touch a text field;
- keeps screen edges active in fullscreen: **swiping up from the bottom edge** opens the application menu (like the Windows key) and leaves fullscreen.

A second tap puts everything back. Nothing else is ever turned off — not the power button, the lid, the touchscreen, the pen, nor plugged-in keyboards or mice. Devices are picked by exact name in the `OFF` constant at the top of `clavier-garde/src/main.rs` (those of my laptop; see below to adapt it).

Two safety nets: a new session starts in PC mode, and so does closing and reopening the lid. I once got stuck with no keyboard and no touchpad; never again.

## Pieces

| File | Role |
|---|---|
| `clavier-garde/` | the daemon, in Rust. It sleeps until called: no timer, ~4 MB of RAM, zero CPU. |
| `tablet-toggle` + `tablet-toggle.desktop` | the "Basculer Clavier" button: a single D-Bus call to the daemon (or the daemon itself if it isn't running). |
| `kwin/secours-tablette/` | KWin script for the bottom swipe. It is only registered while the panel isn't visible (hidden, or under a fullscreen app), because KWin swallows touches that start inside the edge area. |
| `panel-autohide.fish` | toggles the panel between auto-hide and always visible (Meta+H). |

D-Bus interface of the daemon (session bus):

```
org.glime.Tablette  /org/glime/Tablette
  Basculer() -> b        Tablette(b on) -> b        Etat() -> b      (b = tablet mode)
```

Command line: `clavier-garde basculer|on|off|etat` (`on` = keyboard back on) or `tablet-toggle [toggle|on|off|status]`.

<p align="center"><img src="docs/tablette-terminal.png" width="760" alt="clavier-garde from the command line"></p>

## Install

```bash
git clone https://github.com/glime32/kde-tablette-outils
cd kde-tablette-outils
./install.sh
```

Needs Rust (`sudo pacman -S rust`) and fish for `panel-autohide.fish`. The script builds the daemon, installs the button, the `clavier-garde.service` user unit and the KWin script, and sets the screen-edge touch area to 20 px (default 8 is too thin for a finger). Then pin "Basculer Clavier" to the taskbar. For the on-screen keyboard: `sudo pacman -S plasma-keyboard`.

Uninstall with `./uninstall.sh` (turns the keyboard back on first).

To find your device names:

```bash
busctl --user get-property org.kde.KWin /org/kde/KWin/InputDevice org.kde.KWin.InputDeviceManager devicesSysNames
busctl --user get-property org.kde.KWin /org/kde/KWin/InputDevice/event3 org.kde.KWin.InputDevice name
```

## panel-autohide

`panel-autohide.fish toggle` switches every panel between *auto-hide* and *always visible* and remembers the choice. Bind it in *Settings → Keyboard → Shortcuts → Add command* → `~/.local/bin/toggle-panel-autohide.sh`.

Before the bottom swipe existed, a service polled the keyboard every 2 s to force the panel visible in tablet mode. It's gone: tablet mode leaves the panel alone, and `install` removes the old service if it finds it.

## Good to know

- the virtual keyboard is the `InputMethod` key of `[Wayland]` in `kwinrc`; the previous value is saved in `~/.local/state/panel-autohide/methode-saisie-pc` and restored in PC mode;
- `kwriteconfig6 --notify` is enough for KWin to pick up the input method, no restart needed;
- an auto-hidden panel's edge is only 1 px tall on KWin's side, so you can't reveal it with a finger — hence the swipe;
- panels are driven with `evaluateScript` on `org.kde.PlasmaShell` (`panels()[i].hiding = "autohide" | "none"`).
