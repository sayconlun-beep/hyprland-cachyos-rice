// Themes & wallpapers panel, in two steps (Super+Shift+W; `themes openWalls`
// over IPC starts on step 2).
//
//   1 themes      a cover-flow after Omarchy's picker, centred on screen: the
//                 chosen one big in the middle, bordered in its accent, the
//                 rest as slivers. ← → browse, type to filter, Enter / ↓ / a
//                 click on the middle card picks it. Esc closes.
//   2 wallpapers  the cover-flow glides up and the theme's wallpapers slide in
//                 below - Omarchy's plus yours that `rice-theme sort` filed
//                 there ("Wallpaper", colours from the picture, lists the whole
//                 of ~/Pictures/Wallpapers). The big card previews the one
//                 you are on. ← → browse, Enter applies; Esc / ↑ / Backspace
//                 go back to step 1 to look at another theme.
//
// Enter runs `rice-theme set <theme> <wallpaper>`. Each theme opens on the
// wallpaper it had last. The catalog comes from `rice-theme list --json
// --walls` (after `rice-theme sort`); the last one is kept, so the picker shows
// at once and refreshes underneath.
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

Scope {
    id: root

    property bool open: false
    property var targetScreen: null
    property var list: []              // rice-theme-match catalog --walls
    property string query: ""
    property int sel: 0                // theme, in `shown`
    property int wallSel: 0            // wallpaper, in chosen.walls
    property string row: "themes"      // which row the arrows move: themes | walls
    property bool loading: false
    property bool touched: false       // moved since opening: a refresh must not re-select

    readonly property string home: Quickshell.env("HOME")
    readonly property var shown: {
        const q = query.trim().toLowerCase()
        return q ? list.filter(t => t.name.toLowerCase().includes(q) || t.id.includes(q)) : list
    }
    readonly property var chosen: shown.length ? shown[Math.min(sel, shown.length - 1)] : null
    readonly property var walls: chosen && chosen.walls ? chosen.walls : []
    readonly property var wall: walls.length ? walls[Math.min(wallSel, walls.length - 1)] : null

    onQueryChanged: { sel = 0; row = "themes"; touched = true }
    onChosenChanged: selectThemeWall()

    function show(focus) {
        if (open) {
            row = focus === "walls" ? "walls" : "themes"
            return
        }
        targetScreen = focusedScreen()
        query = ""                      // before `row`: clearing a filter resets it
        row = focus === "walls" ? "walls" : "themes"
        touched = false
        selectCurrent()
        loading = list.length === 0
        reader.running = true
        open = true
    }

    function close() {
        open = false
    }

    function toggle(focus) {
        open ? close() : show(focus)
    }

    function selectCurrent() {
        const i = list.findIndex(t => t.current)
        sel = i < 0 ? 0 : i
        selectThemeWall()
    }

    // The wallpaper the theme had last (the one on screen for the current theme).
    function selectThemeWall() {
        const i = walls.findIndex(w => chosen && w.path === chosen.wallpaper)
        wallSel = i < 0 ? 0 : i
    }

    function step(d) {
        touched = true
        if (row === "walls") {
            const n = walls.length
            if (n)
                wallSel = Math.max(0, Math.min(n - 1, wallSel + d))
        } else {
            const n = shown.length
            if (n)
                sel = Math.max(0, Math.min(n - 1, sel + d))
        }
    }

    // Step 1 -> 2: show the chosen theme's wallpapers.
    function pickTheme() {
        if (chosen && walls.length) {
            touched = true
            row = "walls"
        }
    }

    function apply() {
        const t = chosen
        if (!t)
            return
        close()
        Quickshell.execDetached([home + "/.local/bin/rice-theme", "set", t.id].concat(wall ? [wall.path] : []))
    }

    function focusedScreen() {
        const name = Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : ""
        const screens = Quickshell.screens
        for (let i = 0; i < screens.length; i++)
            if (screens[i].name === name)
                return screens[i]
        return screens[0]
    }

    Process {
        id: reader
        // File any new wallpapers into their themes first (~0.15 s when there
        // are none); new thumbnails are made on the way.
        command: ["sh", "-c", '"$0" sort --quiet; exec "$0" list --json --walls', root.home + "/.local/bin/rice-theme"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const keepWall = root.wall ? root.wall.path : ""
                    root.list = JSON.parse(text)
                    // The cached list may have had an older "current": until
                    // you move, follow the fresh one.
                    if (!root.touched && !root.query) {
                        root.selectCurrent()
                    } else if (keepWall) {
                        const i = root.walls.findIndex(w => w.path === keepWall)
                        if (i >= 0)
                            root.wallSel = i
                    }
                } catch (e) {
                    console.warn("ThemePicker: rice-theme list: " + e)
                }
                root.loading = false
            }
        }
    }

    LazyLoader {
        active: root.open

        PanelWindow {
            id: win
            screen: root.targetScreen
            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }
            exclusionMode: ExclusionMode.Ignore
            color: Theme.alpha("#000000", 0.5)
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "rice-themes"
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

            // The theme cards: 16:9 like Omarchy's preview screenshots.
            readonly property real cardW: Math.round(Math.min(width * 0.44, 1300))
            readonly property real cardH: Math.round(cardW * 9 / 16)
            readonly property bool picking: root.row === "walls"
            readonly property real cardY: picking ? Math.round(height * 0.1)
                : Math.round((height - cardH) / 2 - height * 0.04)
            readonly property real sliver: Math.round(cardW * 0.06)
            readonly property real sideScale: 0.88
            // The wallpaper strip.
            readonly property real thumbW: Math.round(Math.min(width * 0.12, 260))
            readonly property real thumbH: Math.round(thumbW * 9 / 16)
            readonly property real stripY: cardY + cardH + 118
            readonly property color accent: root.chosen && root.chosen.accent ? root.chosen.accent : Theme.primary

            MouseArea {
                anchors.fill: parent
                onClicked: root.close()
                onWheel: wheel => root.step(wheel.angleDelta.y > 0 || wheel.angleDelta.x > 0 ? -1 : 1)
            }

            Item {
                id: stage
                anchors.fill: parent
                opacity: 0
                Component.onCompleted: {
                    opacity = 1
                    input.forceActiveFocus()
                }
                Behavior on opacity {
                    NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
                }

                // Typing filters the themes; nothing is drawn for the field itself.
                TextInput {
                    id: input
                    width: 0
                    height: 0
                    opacity: 0
                    text: root.query
                    onTextChanged: root.query = text
                    Keys.onPressed: event => {
                        switch (event.key) {
                        case Qt.Key_Left:
                            root.step(-1); break
                        case Qt.Key_Right:
                            root.step(1); break
                        case Qt.Key_H:
                            if (text) return
                            root.step(-1); break
                        case Qt.Key_L:
                            if (text) return
                            root.step(1); break
                        case Qt.Key_Up: case Qt.Key_K:
                            if (event.key === Qt.Key_K && text) return
                            root.row = "themes"; break
                        case Qt.Key_Down: case Qt.Key_J:
                            if (event.key === Qt.Key_J && text) return
                            root.pickTheme(); break
                        case Qt.Key_Backspace:
                            if (text || root.row !== "walls") return
                            root.row = "themes"; break
                        case Qt.Key_Home:
                            if (root.row === "walls") root.wallSel = 0; else root.sel = 0
                            break
                        case Qt.Key_End:
                            if (root.row === "walls") root.wallSel = Math.max(0, root.walls.length - 1)
                            else root.sel = Math.max(0, root.shown.length - 1)
                            break
                        case Qt.Key_Return: case Qt.Key_Enter:
                            if (root.row === "walls") root.apply()
                            else root.pickTheme()
                            break
                        case Qt.Key_Escape:
                            if (text) root.query = ""
                            else if (root.row === "walls") root.row = "themes"
                            else root.close()
                            break
                        default:
                            return
                        }
                        event.accepted = true
                    }
                }

                // ------------------------------------------------ themes --
                Repeater {
                    model: root.shown

                    Item {
                        id: card
                        required property var modelData
                        required property int index
                        readonly property int d: index - root.sel
                        readonly property int ad: Math.abs(d)
                        readonly property bool centre: d === 0
                        readonly property real s: centre ? 1 : win.sideScale
                        readonly property real cx: win.width / 2
                            + (centre ? 0 : Math.sign(d) * (win.cardW / 2 - win.cardW * s / 2 + win.sliver * ad))
                        // The middle card previews the wallpaper being picked.
                        readonly property string picture: centre && root.row === "walls" && root.wall
                            ? root.wall.card : modelData.preview

                        visible: ad <= 6
                        width: win.cardW
                        height: win.cardH
                        x: cx - width / 2
                        y: win.cardY
                        scale: s

                        Behavior on y {
                            NumberAnimation { duration: 260; easing.type: Easing.OutCubic }
                        }
                        z: 100 - ad

                        Behavior on x {
                            NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
                        }
                        Behavior on scale {
                            NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
                        }

                        transform: Rotation {
                            origin.x: card.d < 0 ? card.width : 0
                            origin.y: card.height / 2
                            axis { x: 0; y: 1; z: 0 }
                            angle: card.centre ? 0 : (card.d < 0 ? 8 : -8)
                            Behavior on angle {
                                NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
                            }
                        }

                        Rectangle {
                            anchors.fill: parent
                            color: Theme.surface_container_lowest
                            clip: true

                            Image {
                                anchors.fill: parent
                                source: card.picture ? "file://" + card.picture : ""
                                sourceSize.width: 1280
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                                cache: true
                            }

                            Rectangle {
                                anchors.fill: parent
                                color: "#000000"
                                opacity: card.centre ? 0 : Math.min(0.2 + card.ad * 0.08, 0.6)
                                Behavior on opacity {
                                    NumberAnimation { duration: 220 }
                                }
                            }
                        }

                        Rectangle {
                            anchors.fill: parent
                            anchors.margins: card.centre ? -3 : -1
                            color: "transparent"
                            border.width: card.centre ? 3 : 1
                            border.color: card.centre ? (card.modelData.accent || Theme.primary) : Theme.alpha("#000000", 0.6)
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (card.centre && root.row === "themes")
                                    root.pickTheme()
                                else {
                                    root.touched = true
                                    root.sel = card.index
                                    root.row = "themes"
                                }
                            }
                        }
                    }
                }

                // Theme name, then what it is.
                Text {
                    id: nameText
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: win.cardY + win.cardH + 22
                    Behavior on y {
                        NumberAnimation { duration: 260; easing.type: Easing.OutCubic }
                    }
                    text: root.chosen ? root.chosen.name : root.loading ? "" : root.list.length ? "No matches" : ""
                    color: "#ffffff"
                    font.family: Theme.font
                    font.pixelSize: 22
                    font.weight: Font.Bold
                    style: Text.Raised
                    styleColor: Theme.alpha("#000000", 0.55)
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.top: nameText.bottom
                    anchors.topMargin: 4
                    text: root.query ? root.query
                        : root.chosen ? (root.chosen.id === "wallpaper" ? "colours from the picture" : root.chosen.mode)
                            + "  ·  " + root.chosen.count + " wallpaper" + (root.chosen.count === 1 ? "" : "s")
                            + (root.chosen.current ? "  ·  current" : "")
                        : ""
                    color: Theme.alpha("#ffffff", 0.7)
                    font.family: root.query ? Theme.mono : Theme.font
                    font.pixelSize: 13
                    style: Text.Raised
                    styleColor: Theme.alpha("#000000", 0.55)
                }

                // --------------------------------------------- wallpapers --
                Item {
                    id: strip
                    x: 0
                    // slides up into place with the step, and away again
                    y: win.picking ? win.stripY : win.stripY + 60
                    opacity: win.picking ? 1 : 0
                    visible: opacity > 0
                    Behavior on y {
                        NumberAnimation { duration: 260; easing.type: Easing.OutCubic }
                    }
                    Behavior on opacity {
                        NumberAnimation { duration: 200 }
                    }
                    width: win.width
                    height: win.thumbH * 1.1

                    Repeater {
                        model: root.walls

                        Item {
                            id: thumb
                            required property var modelData
                            required property int index
                            readonly property bool picked: index === root.wallSel
                            readonly property bool onScreen: root.chosen && root.chosen.current
                                && modelData.path === root.chosen.wallpaper

                            visible: Math.abs(index - root.wallSel) <= 8
                            width: win.thumbW
                            height: win.thumbH
                            x: win.width / 2 - width / 2 + (index - root.wallSel) * (win.thumbW + 14)
                            y: 0
                            scale: picked ? 1.1 : 1
                            z: picked ? 2 : 1
                            opacity: picked ? 1 : 0.7

                            Behavior on x {
                                NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
                            }
                            Behavior on scale {
                                NumberAnimation { duration: 160 }
                            }
                            Behavior on opacity {
                                NumberAnimation { duration: 160 }
                            }

                            Rectangle {
                                anchors.fill: parent
                                color: Theme.surface_container_lowest
                                clip: true

                                Image {
                                    anchors.fill: parent
                                    source: "file://" + thumb.modelData.thumb
                                    sourceSize.width: 384
                                    fillMode: Image.PreserveAspectCrop
                                    asynchronous: true
                                    cache: true
                                }
                            }

                            Rectangle {
                                anchors.fill: parent
                                anchors.margins: thumb.picked ? -3 : -1
                                color: "transparent"
                                border.width: thumb.picked ? (root.row === "walls" ? 3 : 2) : 1
                                border.color: thumb.picked ? win.accent : Theme.alpha("#000000", 0.6)
                            }

                            // yours (sorted in) vs the theme's own
                            Rectangle {
                                visible: thumb.modelData.mine && root.chosen && root.chosen.id !== "wallpaper"
                                anchors.left: parent.left
                                anchors.bottom: parent.bottom
                                anchors.margins: 6
                                width: mineText.implicitWidth + 10
                                height: 16
                                radius: 3
                                color: Theme.alpha("#000000", 0.6)
                                Text {
                                    id: mineText
                                    anchors.centerIn: parent
                                    text: "yours"
                                    color: "#ffffff"
                                    font.family: Theme.font
                                    font.pixelSize: 10
                                }
                            }

                            // on screen now
                            Rectangle {
                                visible: thumb.onScreen
                                anchors.right: parent.right
                                anchors.top: parent.top
                                anchors.margins: 6
                                width: 10
                                height: 10
                                radius: 5
                                color: win.accent
                                border.width: 1
                                border.color: "#000000"
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (thumb.picked && root.row === "walls")
                                        root.apply()
                                    else {
                                        root.touched = true
                                        root.wallSel = thumb.index
                                        root.row = "walls"
                                    }
                                }
                            }
                        }
                    }
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: win.stripY + win.thumbH * 1.1 + 16
                    opacity: strip.opacity
                    visible: strip.visible
                    text: root.wall ? root.wall.name + "   ·   " + (root.wallSel + 1) + " of " + root.walls.length
                        : root.loading ? "Loading…" : ""
                    color: Theme.alpha("#ffffff", 0.9)
                    font.family: Theme.font
                    font.pixelSize: 14
                    style: Text.Raised
                    styleColor: Theme.alpha("#000000", 0.55)
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 34
                    text: win.picking
                        ? "←  →  wallpapers       enter  apply       esc  back to the themes"
                        : "←  →  themes       enter  see its wallpapers       type to filter       esc  close"
                    color: Theme.alpha("#ffffff", 0.5)
                    font.family: Theme.font
                    font.pixelSize: 12
                    style: Text.Raised
                    styleColor: Theme.alpha("#000000", 0.55)
                }
            }
        }
    }
}
