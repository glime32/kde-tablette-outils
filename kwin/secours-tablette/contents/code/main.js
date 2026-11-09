// Geste du bas : glisser le doigt depuis le bas de l'écran vers le haut ouvre le
// menu des applications (comme la touche Windows) et sort du plein écran.
// Le geste n'est posé QUE quand la barre n'est pas visible (cachée, ou sous une
// appli plein écran) : sinon KWin avalerait les touchers sur le bas de la barre.
// Coût : zéro au repos, KWin n'appelle ce code que sur un changement de fenêtre.
var pose = false;

function barreVisible() {
    var l = workspace.stackingOrder;
    for (var i = 0; i < l.length; i++) {
        if (l[i].dock && !l[i].hidden && !l[i].minimized) {
            return true;
        }
    }
    return false;
}

function pleinEcran() {
    var w = workspace.activeWindow;
    return w !== null && w !== undefined && w.fullScreen;
}

function geste() {
    var w = workspace.activeWindow;
    if (w && w.fullScreen) {
        w.fullScreen = false;
    }
    callDBus("org.kde.plasmashell", "/PlasmaShell", "org.kde.PlasmaShell", "activateLauncherMenu");
}

function maj() {
    var besoin = pleinEcran() || !barreVisible();
    if (besoin === pose) {
        return;
    }
    if (besoin) {
        registerTouchScreenEdge(KWin.ElectricBottom, geste);
    } else {
        unregisterTouchScreenEdge(KWin.ElectricBottom);
    }
    pose = besoin;
}

function suivre(w) {
    w.fullScreenChanged.connect(maj);
    if (w.dock) {
        w.hiddenChanged.connect(maj);
    }
}

var liste = workspace.stackingOrder;
for (var i = 0; i < liste.length; i++) {
    suivre(liste[i]);
}
workspace.windowAdded.connect(function (w) { suivre(w); maj(); });
workspace.windowRemoved.connect(maj);
workspace.windowActivated.connect(maj);
maj();
