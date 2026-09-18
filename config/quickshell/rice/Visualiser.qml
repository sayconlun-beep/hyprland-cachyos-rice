// Desktop visualiser: cava along the bottom edge of every monitor, on the
// BOTTOM layer - above the wallpaper, under every window - on every workspace.
//
// cava only does the maths here. It runs once, in raw mode, printing one line
// of bar levels per frame; the bars are drawn by Qt, which is what allows
// rounded, slightly see-through bars at exact pixel spacing. (The kitty panel
// this replaced could do none of that: terminal cells have no alpha, and cava
// spaces bars in whole columns.)
//
// Square, see-through bars rise from the bottom edge, bass on the left, each
// with a brighter top edge; in silence a row of short stubs is left. The
// colour runs left to right across the palette (primary -> secondary ->
// tertiary), so wallpaper previews recolour it.
// cava's pulse input follows the default output, headphones included.
//
//   qs -c rice ipc call visualiser toggle      (Super+Shift+V)
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

Scope {
    id: root

    property bool enabled: true

    readonly property int bandHeight: 400      // logical px, up from the bottom edge
    readonly property int barWidth: 28
    readonly property int barGap: 3
    readonly property real barOpacity: 0.45
    readonly property int capHeight: 2         // the brighter top edge
    readonly property int minBar: 4            // the stubs left in silence

    // One cava feeds every monitor, so the bar count comes from the widest.
    readonly property int count: {
        let widest = 0
        for (const s of Quickshell.screens)
            widest = Math.max(widest, s.width)
        return Math.max(2, Math.floor((widest + barGap) / (barWidth + barGap)))
    }

    property var levels: []

    readonly property string configPath: Quickshell.env("HOME") + "/.cache/rice/cava-visualiser.conf"

    function toggle() {
        enabled = !enabled
    }

    // Written before each start, because the bar count depends on the monitors.
    function writeConfig() {
        cavaConf.setText(`# Written by Visualiser.qml - regenerated on every start.
[general]
framerate = 60
autosens = 1
bars = ${count}

[input]
method = pulse
source = auto

[output]
method = raw
raw_target = /dev/stdout
data_format = ascii
ascii_max_range = 1000
bar_delimiter = 59
frame_delimiter = 10
channels = mono
mono_option = average

[smoothing]
noise_reduction = 60
`)
    }

    function start() {
        if (!enabled || cava.running)
            return
        writeConfig()
        cava.running = true
    }

    onEnabledChanged: {
        if (enabled) {
            start()
        } else {
            restart.stop()
            cava.running = false
            levels = []
        }
    }
    onCountChanged: if (cava.running) cava.running = false   // restarts with the new count
    Component.onCompleted: start()

    FileView {
        id: cavaConf
        path: root.configPath
        preload: false
        atomicWrites: false
    }

    Process {
        id: cava
        command: ["cava", "-p", root.configPath]
        stdout: SplitParser {
            onRead: data => {
                const parts = data.split(";")
                const out = new Array(root.count)
                for (let i = 0; i < root.count; i++)
                    out[i] = (parseInt(parts[i]) || 0) / 1000
                root.levels = out
            }
        }
        onExited: {
            root.levels = []
            if (root.enabled)
                restart.start()                // cava died or the count changed
        }
    }

    // The colour at x (0..1) across the screen.
    function colourAt(t) {
        const a = t < 0.5 ? Theme.primary : Theme.secondary
        const b = t < 0.5 ? Theme.secondary : Theme.tertiary
        const u = t < 0.5 ? t * 2 : (t - 0.5) * 2
        return Qt.rgba(a.r + (b.r - a.r) * u, a.g + (b.g - a.g) * u, a.b + (b.b - a.b) * u, 1)
    }

    Timer {
        id: restart
        interval: 1500
        onTriggered: root.start()
    }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: panel
            required property var modelData

            screen: modelData
            visible: root.enabled
            anchors {
                bottom: true
                left: true
                right: true
            }
            implicitHeight: root.bandHeight
            exclusionMode: ExclusionMode.Ignore
            color: "transparent"
            mask: Region {}                    // never takes a click from the desktop
            WlrLayershell.layer: WlrLayer.Bottom
            WlrLayershell.namespace: "rice-visualiser"
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

            Item {
                id: bars
                readonly property real total: root.count * (root.barWidth + root.barGap) - root.barGap

                anchors.fill: parent

                Repeater {
                    model: root.count

                    Item {
                        required property int index
                        readonly property real level: root.levels[index] || 0
                        readonly property color colour: root.colourAt(root.count > 1 ? index / (root.count - 1) : 0)

                        x: (bars.width - bars.total) / 2 + index * (root.barWidth + root.barGap)
                        width: root.barWidth
                        height: Math.max(root.minBar, level * bars.height)
                        y: bars.height - height

                        Rectangle {
                            anchors.fill: parent
                            color: parent.colour
                            opacity: root.barOpacity
                        }

                        Rectangle {
                            width: parent.width
                            height: root.capHeight
                            color: parent.colour
                            opacity: 0.85
                        }
                    }
                }
            }
        }
    }
}
