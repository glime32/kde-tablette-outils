// clavier-garde: fake tablet mode, all in one sleeping process (Rust port).
//
// No timer: it only wakes on a D-Bus call or a logind signal.
//   D-Bus (session): org.glime.Tablette  /org/glime/Tablette
//       Basculer() -> b     Tablette(b on) -> b     Etat() -> b      (b = tablet mode)
//   Command line: clavier-garde basculer|on|off|etat
//       (goes through the daemon if it runs, otherwise does the work and exits)
//
// Tablet mode (the panel keeps its setting: the bottom swipe reaches it):
//   1. screen edges stay active in fullscreen (bottom swipe = menu + panel)
//   2. virtual keyboard (plasma-keyboard) as input method, if installed
//   3. turns off ONLY the devices listed in OFF below
// Safety nets: session start = PC mode; lid closed then reopened = PC mode.

use dbus::arg::{PropMap, RefArg, Variant};
use dbus::blocking::stdintf::org_freedesktop_dbus::{Properties, PropertiesPropertiesChanged};
use dbus::blocking::Connection;
use dbus::channel::MatchingReceiver;
use dbus::message::{MatchRule, SignalArgs};
use dbus_crossroads::Crossroads;
use std::collections::BTreeMap;
use std::path::PathBuf;
use std::process::Command;
use std::sync::{Arc, Mutex};
use std::thread;
use std::time::Duration;

// Turned off in tablet mode, by exact name. NEVER: power button, lid, tablet
// switch, touchscreen, pen, nor external keyboards/mice.
const OFF: [&str; 5] = [
    "AT Translated Set 2 keyboard",   // built-in keyboard
    "ELAN06FA:00 04F3:327E Touchpad", // touchpad
    "ELAN06FA:00 04F3:327E Mouse",    // touchpad (2nd node)
    "Ideapad extra buttons",          // Fn: airplane, camera, mic, Fn+Q, star…
    "Video Bus",                      // Fn: brightness
];
const KEYBOARD: &str = OFF[0];
const VIRTUAL_KEYBOARDS: [&str; 2] = [
    "/usr/share/applications/org.kde.plasma.keyboard.desktop",
    "/usr/share/applications/plasma-keyboard.desktop",
];
const KWIN: &str = "org.kde.KWin";
const DEV: &str = "org.kde.KWin.InputDevice";
const NAME: &str = "org.glime.Tablette";
const PATH: &str = "/org/glime/Tablette";
const T: Duration = Duration::from_secs(4);

fn state_dir() -> PathBuf {
    PathBuf::from(std::env::var("HOME").unwrap_or_default()).join(".local/state/panel-autohide")
}

struct Garde {
    bus: Connection,
    notif_id: u32,
}

type Devices = BTreeMap<String, Vec<String>>;

impl Garde {
    fn new() -> Result<Self, dbus::Error> {
        Ok(Garde { bus: Connection::new_session()?, notif_id: 0 })
    }

    /// {name: [D-Bus paths]} for the names of OFF that are present
    fn devices(&self) -> Result<Devices, dbus::Error> {
        let manager = self.bus.with_proxy(KWIN, "/org/kde/KWin/InputDevice", T);
        let sysnames: Vec<String> = manager.get("org.kde.KWin.InputDeviceManager", "devicesSysNames")?;
        let mut found = Devices::new();
        for sys in sysnames {
            let path = format!("/org/kde/KWin/InputDevice/{sys}");
            let Ok(name) = self.bus.with_proxy(KWIN, &path, T).get::<String>(DEV, "name") else { continue };
            if OFF.contains(&name.as_str()) {
                found.entry(name).or_default().push(path);
            }
        }
        Ok(found)
    }

    fn in_tablet(&self, devs: &Devices) -> Result<bool, dbus::Error> {
        for path in devs.get(KEYBOARD).into_iter().flatten() {
            if !self.bus.with_proxy(KWIN, path, T).get::<bool>(DEV, "enabled")? {
                return Ok(true);
            }
        }
        Ok(false)
    }

    fn in_tablet_safe(&self) -> bool {
        self.devices().and_then(|d| self.in_tablet(&d)).unwrap_or(false)
    }

    fn enable(&self, devs: &Devices, on: bool) {
        for path in devs.values().flatten() {
            if let Err(e) = self.bus.with_proxy(KWIN, path, T).set(DEV, "enabled", on) {
                eprintln!("activer {path} {e}");
            }
        }
    }

    fn screen_edges_in_fullscreen(&self, on: bool) {
        let v = if on { "true" } else { "false" };
        if kconf_read("ScreenEdges", "RemainActiveOnFullscreen") != v {
            kconf_write("ScreenEdges", "RemainActiveOnFullscreen", Some(v));
            let _: Result<(), _> = self.bus.with_proxy(KWIN, "/KWin", T).method_call("org.kde.KWin", "reconfigure", ());
        }
    }

    fn notify(&mut self, icon: &str, title: &str, body: &str) {
        let mut hints = PropMap::new();
        hints.insert("transient".into(), Variant(Box::new(true) as Box<dyn RefArg>));
        let r: Result<(u32,), _> = self.bus.with_proxy("org.freedesktop.Notifications", "/org/freedesktop/Notifications", T).method_call(
            "org.freedesktop.Notifications",
            "Notify",
            ("Mode tablette", self.notif_id, icon, title, body, Vec::<String>::new(), hints, 2500i32),
        );
        if let Ok((id,)) = r {
            self.notif_id = id;
        }
    }

    fn to_tablet(&mut self) -> Result<bool, dbus::Error> {
        let devs = self.devices()?;
        if devs.get(KEYBOARD).map_or(true, |v| v.is_empty()) {
            self.notify("dialog-error", "Mode tablette", "Clavier introuvable, rien n'a été changé.");
            return Ok(false);
        }
        self.screen_edges_in_fullscreen(true);
        virtual_keyboard(true);
        self.enable(&devs, false);
        self.notify("input-tablet", "Mode tablette", "Clavier, pavé et touches Fn coupés. Glisse depuis le bas de l'écran pour le menu.");
        Ok(true)
    }

    fn to_pc(&mut self, quiet: bool) -> Result<bool, dbus::Error> {
        let devs = self.devices()?;
        let was = self.in_tablet(&devs)?;
        self.enable(&devs, true); // always turn everything back on, even a half-off state
        self.screen_edges_in_fullscreen(false);
        virtual_keyboard(false);
        if was && !quiet {
            self.notify("input-keyboard", "Mode PC", "Clavier, pavé tactile et touches Fn rallumés.");
        }
        Ok(false)
    }

    // never lets an error kill the daemon
    fn set(&mut self, tablet: bool) -> bool {
        let r = if tablet { self.to_tablet() } else { self.to_pc(false) };
        r.unwrap_or_else(|e| {
            eprintln!("regler {e}");
            self.in_tablet_safe()
        })
    }
}

fn kconf_read(group: &str, key: &str) -> String {
    Command::new("kreadconfig6")
        .args(["--file", "kwinrc", "--group", group, "--key", key])
        .output()
        .map(|o| String::from_utf8_lossy(&o.stdout).trim().to_string())
        .unwrap_or_default()
}

fn kconf_write(group: &str, key: &str, value: Option<&str>) {
    let mut cmd = Command::new("kwriteconfig6");
    cmd.args(["--notify", "--file", "kwinrc", "--group", group, "--key", key]);
    match value {
        Some(v) => cmd.arg(v),
        None => cmd.arg("--delete"),
    };
    let _ = cmd.status();
}

fn virtual_keyboard(on: bool) {
    let Some(vk) = VIRTUAL_KEYBOARDS.iter().find(|f| std::path::Path::new(f).exists()) else { return };
    let current = kconf_read("Wayland", "InputMethod");
    let saved = state_dir().join("methode-saisie-pc");
    if on {
        if current != *vk {
            let _ = std::fs::create_dir_all(state_dir());
            let _ = std::fs::write(&saved, &current);
            kconf_write("Wayland", "InputMethod", Some(vk));
        }
    } else if current == *vk {
        let old = std::fs::read_to_string(&saved).map(|s| s.trim().to_string()).unwrap_or_default();
        kconf_write("Wayland", "InputMethod", if old.is_empty() { None } else { Some(&old) });
    }
}

// daemon

fn daemon() -> Result<(), dbus::Error> {
    let garde = Arc::new(Mutex::new(Garde::new()?));
    let bus = Connection::new_session()?;
    let reply = bus.request_name(NAME, false, false, true)?;
    if reply != dbus::blocking::stdintf::org_freedesktop_dbus::RequestNameReply::PrimaryOwner {
        eprintln!("nom {NAME} déjà pris : un autre démon tourne");
        return Ok(());
    }

    let mut cr = Crossroads::new();
    let iface = cr.register(NAME, |b| {
        b.method("Basculer", (), ("tablette",), |_, g: &mut Arc<Mutex<Garde>>, ()| {
            let mut g = g.lock().unwrap();
            let on = !g.in_tablet_safe();
            Ok((g.set(on),))
        });
        b.method("Tablette", ("on",), ("tablette",), |_, g: &mut Arc<Mutex<Garde>>, (on,): (bool,)| Ok((g.lock().unwrap().set(on),)));
        b.method("Etat", (), ("tablette",), |_, g: &mut Arc<Mutex<Garde>>, ()| Ok((g.lock().unwrap().in_tablet_safe(),)));
    });
    cr.insert(PATH, &[iface], garde.clone());

    // lid closed then reopened = PC mode (logind, system bus, in its own thread)
    let g = garde.clone();
    thread::spawn(move || {
        let Ok(system) = Connection::new_system() else { return };
        let mut closed = false;
        let sender: dbus::strings::BusName = "org.freedesktop.login1".into();
        let path: dbus::Path = "/org/freedesktop/login1".into();
        let rule = PropertiesPropertiesChanged::match_rule(Some(&sender), Some(&path)).static_clone();
        let g2 = g.clone();
        let _ = system.add_match(rule, move |p: PropertiesPropertiesChanged, _, _| {
            if let Some(&now_closed) = dbus::arg::prop_cast::<bool>(&p.changed_properties, "LidClosed") {
                if closed && !now_closed {
                    let g3 = g2.clone();
                    thread::spawn(move || {
                        thread::sleep(Duration::from_millis(1500));
                        g3.lock().unwrap().set(false);
                    });
                }
                closed = now_closed;
            }
            true
        });
        loop {
            if system.process(Duration::from_secs(3600)).is_err() {
                return;
            }
        }
    });

    // session start = PC mode (once KWin and Plasma are ready)
    let g = garde.clone();
    thread::spawn(move || {
        thread::sleep(Duration::from_secs(3));
        let mut g = g.lock().unwrap();
        if g.in_tablet_safe() {
            g.set(false);
        } else if let Err(e) = g.to_pc(true) {
            eprintln!("demarrage {e}");
        }
    });

    bus.start_receive(
        MatchRule::new_method_call(),
        Box::new(move |msg, conn| {
            let _ = cr.handle_message(msg, conn);
            true
        }),
    );
    loop {
        bus.process(Duration::from_secs(3600))?;
    }
}

fn cli(cmd: &str) -> i32 {
    let (method, arg) = match cmd {
        "basculer" | "toggle" => ("Basculer", None),
        "on" => ("Tablette", Some(false)), // « on » = keyboard back on
        "off" => ("Tablette", Some(true)), // « off » = keyboard off
        "etat" | "status" => ("Etat", None),
        _ => {
            println!("usage : clavier-garde [basculer|on|off|etat]");
            return 2;
        }
    };
    let via_daemon = Connection::new_session().ok().and_then(|bus| {
        let p = bus.with_proxy(NAME, PATH, T);
        let r: Result<(bool,), _> = match arg {
            Some(on) => p.method_call(NAME, method, (on,)),
            None => p.method_call(NAME, method, ()),
        };
        r.ok().map(|(b,)| b)
    });
    // daemon absent: do the work here
    let tablet = via_daemon.unwrap_or_else(|| match Garde::new() {
        Ok(mut g) => match cmd {
            "etat" | "status" => g.in_tablet_safe(),
            "basculer" | "toggle" => {
                let on = !g.in_tablet_safe();
                g.set(on)
            }
            _ => g.set(cmd == "off"),
        },
        Err(_) => false,
    });
    println!("{}", if tablet { "mode tablette" } else { "mode PC" });
    0
}

fn main() {
    let args: Vec<String> = std::env::args().collect();
    if let Some(cmd) = args.get(1) {
        std::process::exit(cli(cmd));
    }
    if let Err(e) = daemon() {
        eprintln!("clavier-garde : {e}");
        std::process::exit(1);
    }
}
