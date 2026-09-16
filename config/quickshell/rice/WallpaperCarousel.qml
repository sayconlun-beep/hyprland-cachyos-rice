// Wallpaper carousel (Super+Shift+W): a curved wall of cards over the selected
// wallpaper, dimmed. Every card slides along the wall; the one arriving in the
// middle changes from the wallpaper you just left to its own with the chosen
// transition effect, and applying plays that same effect over the whole
// desktop before handing over to awww.
//
//   ← →  browse     Tab / Shift+Tab  effect     Space  replay the effect
//   Enter  apply    type  filter by name        Esc  clear the filter, then close
//
// The effects are one shader, shaders/transition.frag (compiled to .qsb by
// shaders/compile.sh); the choice is kept in ~/.cache/rice/transition.
// Nothing on the desktop changes until Enter. Then a Bottom-layer window per
// screen (above awww, under windows and the bar) runs the effect from the old
// wallpaper to the new one; `rice-wallpaper commit` swaps awww and re-themes
// halfway through, and the windows go once it has finished, so what they
// uncover is already the new wallpaper.
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

Scope {
    id: root

    property bool open: false
    property bool closing: false
    property bool loading: false
    property var walls: []             // [{path, name, thumb, colors}]
    property int index: 0
    property string filter: ""
    property string current: ""        // the wallpaper on screen
    property int effect: 9             // burn
    property var targetScreen: null

    // Applying
    property bool applying: false
    property string applyFrom: ""
    property string applyTo: ""
    property bool committed: false
    property bool commitDone: false
    property int effectsDone: 0

    readonly property string home: Quickshell.env("HOME")
    readonly property string bin: home + "/.local/bin/"
    readonly property string shader: "file://" + Quickshell.shellDir + "/shaders/transition.frag.qsb"
    readonly property var effects: ["glitch", "dissolve", "ripple", "shatter", "crt",
        "pixelate", "swirl", "flow", "slide", "burn"]
    readonly property var shown: filter ? walls.filter(w => w.name.toLowerCase().includes(filter)) : walls
    readonly property var wall: shown.length ? shown[Math.max(0, Math.min(index, shown.length - 1))] : null

    function show() {
        if (open && !closing)
            return
        closeTimer.stop()
        closing = false
        if (open)                      // reopened mid fade-out
            return
        targetScreen = focusedScreen()
        filter = ""
        index = Math.max(0, walls.findIndex(w => w.path === current))
        loading = walls.length === 0
        open = true
        lister.running = true
    }

    function toggle() {
        open && !closing ? cancel() : show()
    }

    function cancel() {
        if (!open || closing)
            return
        closing = true
        closeTimer.restart()
    }

    function commit() {
        if (!open || closing || !wall)
            return
        const path = wall.path
        cancel()
        if (path === current || applying)
            return
        applyFrom = current
        applyTo = path
        committed = false
        commitDone = false
        effectsDone = 0
        applying = true
        applySafety.restart()
    }

    function step(d) {
        if (shown.length && !closing)
            index = (index + d + shown.length) % shown.length
    }

    function setFilter(f) {
        const keep = wall ? wall.path : current
        filter = f
        index = Math.max(0, shown.findIndex(w => w.path === keep))
    }

    function setEffect(i) {
        effect = (i + effects.length) % effects.length
        effectFile.setText(effects[effect] + "\n")
    }

    function startCommit() {
        if (committed)
            return
        committed = true
        worker.command = [bin + "rice-wallpaper", "commit", applyTo]
        worker.running = true
    }

    function maybeFinishApply() {
        if (applying && commitDone && effectsDone >= Quickshell.screens.length) {
            applySafety.stop()
            applying = false
        }
    }

    function smooth(e0, e1, x) {
        const t = Math.max(0, Math.min(1, (x - e0) / (e1 - e0)))
        return t * t * (3 - 2 * t)
    }

    // values[n] is the value n cards out from the middle; in between, a straight line.
    function table(values, a) {
        const last = values.length - 1
        const i = Math.min(Math.floor(a), last - 1)
        const f = Math.min(a - i, 1)
        return values[i] + (values[i + 1] - values[i]) * f
    }

    function focusedScreen() {
        const name = Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : ""
        const screens = Quickshell.screens
        for (let i = 0; i < screens.length; i++)
            if (screens[i].name === name)
                return screens[i]
        return screens[0]
    }

    Timer {
        id: closeTimer
        interval: 200
        onTriggered: {
            root.open = false
            root.closing = false
        }
    }

    // If an image never loads or rice-wallpaper hangs, don't leave the
    // transition window covering the desktop.
    Timer {
        id: applySafety
        interval: 8000
        onTriggered: {
            root.startCommit()
            root.applying = false
        }
    }

    FileView {
        id: effectFile
        path: root.home + "/.cache/rice/transition"
        onLoaded: {
            const i = root.effects.indexOf(text().trim())
            if (i >= 0)
                root.effect = i
        }
    }

    Process {
        id: worker
        onExited: {
            root.current = root.applyTo
            root.commitDone = true
            root.maybeFinishApply()
        }
    }

    Process {
        id: lister
        command: [root.bin + "rice-wallpaper", "palettes"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const data = JSON.parse(text)
                    const first = root.walls.length === 0
                    root.current = data.current
                    if (JSON.stringify(data.walls) !== JSON.stringify(root.walls))
                        root.walls = data.walls
                    if (first)
                        root.index = Math.max(0, root.shown.findIndex(w => w.path === data.current))
                } catch (e) {
                    console.warn("WallpaperCarousel: bad list:", e)
                }
                root.loading = false
            }
        }
    }

    LazyLoader {
        active: root.open

        PanelWindow {
            screen: root.targetScreen
            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }
            exclusionMode: ExclusionMode.Ignore
            color: "transparent"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "rice-wallpaper"
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

            Item {
                id: stage

                readonly property real cardW: Math.min(width * 0.3, 1000)
                readonly property real cardH: cardW / 1.6
                readonly property real cx: width / 2
                readonly property real cy: height * 0.42
                readonly property bool hasWalls: root.shown.length > 0
                property real appear: 0
                property real intro: 0          // cards appearing, 0 -> 1
                // The thumbnail of the card last in the middle: the next card to
                // arrive changes from this to its own image.
                property Item selectedThumb: null

                signal replayRequested

                anchors.fill: parent
                focus: true
                opacity: root.closing ? 0 : appear
                Behavior on opacity {
                    NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
                }

                Component.onCompleted: {
                    forceActiveFocus()
                    appear = 1
                    if (hasWalls)
                        introAnim.start()
                }
                onHasWallsChanged: if (hasWalls && intro === 0 && !introAnim.running) introAnim.start()

                NumberAnimation {
                    id: introAnim
                    target: stage
                    property: "intro"
                    from: 0
                    to: 1
                    duration: 820
                }

                Keys.onPressed: event => {
                    event.accepted = true
                    if (root.closing)
                        return
                    const k = event.key
                    const mods = event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier)
                    if (k === Qt.Key_Left)
                        root.step(-1)
                    else if (k === Qt.Key_Right)
                        root.step(1)
                    else if (k === Qt.Key_Home)
                        root.index = 0
                    else if (k === Qt.Key_End)
                        root.index = root.shown.length - 1
                    else if (k === Qt.Key_Tab) {
                        root.setEffect(root.effect + 1)
                        stage.replayRequested()
                    } else if (k === Qt.Key_Backtab) {
                        root.setEffect(root.effect - 1)
                        stage.replayRequested()
                    } else if (k === Qt.Key_Space)
                        stage.replayRequested()
                    else if (k === Qt.Key_Return || k === Qt.Key_Enter)
                        root.commit()
                    else if (k === Qt.Key_Escape)
                        root.filter ? root.setFilter("") : root.cancel()
                    else if (k === Qt.Key_Backspace)
                        root.setFilter(root.filter.slice(0, -1))
                    else if (!mods && event.text && event.text.trim())
                        root.setFilter(root.filter + event.text.toLowerCase())
                    else
                        event.accepted = false
                }

                Rectangle {
                    anchors.fill: parent
                    color: "black"
                }

                // The wallpaper on screen, dimmed.
                Image {
                    anchors.fill: parent
                    source: root.current ? "file://" + root.current : ""
                    fillMode: Image.PreserveAspectCrop
                    sourceSize.width: width
                    sourceSize.height: height
                    asynchronous: true
                    opacity: status === Image.Ready ? 0.3 : 0
                    Behavior on opacity {
                        NumberAnimation { duration: 250 }
                    }
                }

                Rectangle {
                    anchors.fill: parent
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: Qt.rgba(0, 0, 0, 0.35) }
                        GradientStop { position: 0.35; color: "transparent" }
                        GradientStop { position: 0.7; color: "transparent" }
                        GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.45) }
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: root.cancel()
                }

                Text {
                    x: 30
                    y: 24
                    text: "~/Pictures/Wallpapers" + (root.filter ? "   /   " + root.filter + "▏" : "")
                    color: Theme.alpha(Theme.on_surface, 0.55)
                    font.family: Theme.font
                    font.pixelSize: 14
                }

                Text {
                    anchors.right: parent.right
                    anchors.rightMargin: 30
                    y: 24
                    text: root.shown.length ? `${root.index + 1} of ${root.shown.length}` : ""
                    color: Theme.alpha(Theme.on_surface, 0.55)
                    font.family: Theme.font
                    font.pixelSize: 14
                }

                // The wall of cards.
                Item {
                    id: ring

                    property real pos: root.index
                    Behavior on pos {
                        NumberAnimation { duration: 340; easing.type: Easing.OutCubic }
                    }

                    anchors.fill: parent

                    WheelHandler {
                        onWheel: event => {
                            const d = event.angleDelta.y !== 0 ? event.angleDelta.y : event.angleDelta.x
                            root.step(d > 0 ? -1 : 1)
                        }
                    }

                    Repeater {
                        model: root.shown

                        Item {
                            id: card
                            required property var modelData
                            required property int index
                            readonly property real o: index - ring.pos
                            readonly property real a: Math.abs(o)
                            readonly property real side: o < 0 ? -1 : 1
                            readonly property bool selected: index === root.index
                            // Cards appear from the middle outwards.
                            readonly property real p: Math.max(0, Math.min(1, stage.intro * 1.6 - 0.15 - Math.min(a, 6) * 0.075))
                            property Item fromThumb: null   // what it changes from on arrival
                            property real change: 1         // that change, 0 -> 1

                            // Arriving in the middle: change from the card that was
                            // there. Only the new card acts, so the order the two
                            // cards hear about the new index doesn't matter.
                            function arrive() {
                                fromThumb = stage.selectedThumb
                                stage.selectedThumb = thumb
                                if (stage.intro >= 1)
                                    play()
                            }

                            function play() {
                                changeAnim.stop()
                                change = 0
                                changeAnim.start()
                            }

                            onSelectedChanged: {
                                if (selected) {
                                    arrive()
                                } else {
                                    changeAnim.stop()
                                    change = 1
                                }
                            }
                            Component.onCompleted: if (selected) stage.selectedThumb = thumb

                            Connections {
                                target: stage
                                function onReplayRequested() {
                                    if (card.selected)
                                        card.play()
                                }
                            }

                            NumberAnimation {
                                id: changeAnim
                                target: card
                                property: "change"
                                from: 0
                                to: 1
                                duration: root.effect === 0 ? 460 : 580
                            }

                            // The wall curves towards you: side cards are squeezed
                            // flat and only slightly tilted, outer edge nearer, so
                            // they stay smaller than the middle one (a real 3D
                            // rotation this big makes their near edges huge).
                            visible: a < 4.5
                            width: stage.cardW
                            height: stage.cardH
                            x: stage.cx - width / 2 + side * root.table([0, 0.73, 1.23, 1.62, 1.95], a) * stage.cardW
                            y: stage.cy - height / 2
                            z: 100 - a
                            scale: root.table([1, 0.93, 0.7, 0.55, 0.45], a)
                            opacity: 1 - root.smooth(3.2, 4.4, a)
                            transform: [
                                Scale {
                                    origin.x: card.width / 2
                                    origin.y: card.height / 2
                                    xScale: root.table([1, 0.52, 0.56, 0.6, 0.6], card.a)
                                },
                                Rotation {
                                    origin.x: card.width / 2
                                    origin.y: card.height / 2
                                    axis { x: 0; y: 1; z: 0 }
                                    angle: -card.side * root.table([0, 16, 14, 12, 12], card.a)
                                }
                            ]

                            Image {
                                id: thumb
                                anchors.fill: parent
                                source: "file://" + card.modelData.thumb
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                                visible: false
                            }

                            ShaderEffect {
                                readonly property bool introducing: card.p < 1
                                anchors.fill: parent
                                property var fromImage: introducing || !card.fromThumb ? thumb : card.fromThumb
                                property var toImage: thumb
                                property real progress: introducing ? card.p : card.change
                                property real mode: root.effect
                                property real aspect: width / Math.max(1, height)
                                property real seed: card.index * 7.3
                                property real blank: introducing || !card.fromThumb ? 1 : 0
                                fragmentShader: root.shader
                            }

                            Rectangle {
                                anchors.fill: parent
                                color: "black"
                                opacity: Math.min(card.a, 4) * 0.12 * card.p
                            }

                            // The outline travels with the selected card; it shows
                            // before the cards themselves have appeared.
                            Rectangle {
                                anchors.fill: parent
                                anchors.margins: -2
                                color: "transparent"
                                border.width: 1.5
                                border.color: Theme.primary
                                opacity: card.selected ? 1 : 0
                                Behavior on opacity {
                                    NumberAnimation { duration: 180 }
                                }
                            }

                            // A spark running along the bottom edge while it changes.
                            Rectangle {
                                width: parent.width * 0.14
                                height: 3
                                x: (parent.width - width) * card.change
                                y: parent.height - 1
                                color: Theme.primary
                                opacity: card.selected && changeAnim.running ? 1 : 0
                                Behavior on opacity {
                                    NumberAnimation { duration: 200 }
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: card.selected ? root.commit() : root.index = card.index
                            }
                        }
                    }
                }

                Column {
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: stage.cy + stage.cardH / 2 + 60
                    spacing: 14

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: root.wall ? root.wall.path.split("/").pop()
                            : root.loading ? "Building thumbnails…"
                            : root.filter ? `Nothing matches “${root.filter}”`
                            : "No wallpapers in ~/Pictures/Wallpapers"
                        color: Theme.on_surface
                        font.family: Theme.font
                        font.pixelSize: 20
                    }

                    Row {
                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: 8
                        Repeater {
                            model: root.wall ? ["primary", "secondary", "tertiary", "primary_container",
                                "surface_container_highest"] : []
                            Rectangle {
                                required property string modelData
                                width: 10
                                height: 10
                                radius: 5
                                color: root.wall.colors[modelData] ?? "transparent"
                                Behavior on color {
                                    ColorAnimation { duration: 300 }
                                }
                            }
                        }
                    }
                }

                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 78
                    spacing: 34

                    Repeater {
                        model: root.effects

                        Text {
                            required property string modelData
                            required property int index
                            readonly property bool active: index === root.effect
                            text: modelData
                            color: active ? Theme.primary : Theme.alpha(Theme.on_surface, effectArea.containsMouse ? 0.8 : 0.42)
                            font.family: Theme.font
                            font.pixelSize: 15
                            font.weight: active ? Font.DemiBold : Font.Normal

                            MouseArea {
                                id: effectArea
                                anchors.fill: parent
                                anchors.margins: -8
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    root.setEffect(parent.index)
                                    stage.replayRequested()
                                }
                            }
                        }
                    }
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 44
                    text: "←  →  browse       tab  effect       space  replay       enter  apply       type to filter       esc  close"
                    color: Theme.alpha(Theme.on_surface, 0.3)
                    font.family: Theme.font
                    font.pixelSize: 12
                }
            }
        }
    }

    // Applying: the effect over the real desktop, on every screen.
    LazyLoader {
        active: root.applying

        Variants {
            model: Quickshell.screens

            PanelWindow {
                id: fx
                required property var modelData
                property real progress: 0
                property bool done: false
                readonly property real dpr: modelData.devicePixelRatio || 1

                screen: modelData
                anchors {
                    top: true
                    bottom: true
                    left: true
                    right: true
                }
                exclusionMode: ExclusionMode.Ignore
                color: "transparent"
                mask: Region {}
                WlrLayershell.layer: WlrLayer.Bottom
                WlrLayershell.namespace: "rice-wallpaper-transition"
                WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

                function ok(img) {
                    return img.source.toString() === "" || img.status === Image.Ready || img.status === Image.Error
                }

                function tryStart() {
                    if (!done && !fxAnim.running && progress === 0 && ok(fromFull) && ok(toFull))
                        fxAnim.start()
                }

                // awww should be showing the new image by the time this ends.
                onProgressChanged: if (progress >= 0.5) root.startCommit()
                Component.onCompleted: Qt.callLater(tryStart)

                Image {
                    id: fromFull
                    anchors.fill: parent
                    source: root.applyFrom ? "file://" + root.applyFrom : ""
                    fillMode: Image.PreserveAspectCrop
                    sourceSize.width: fx.modelData.width * fx.dpr
                    sourceSize.height: fx.modelData.height * fx.dpr
                    asynchronous: true
                    onStatusChanged: fx.tryStart()
                }

                Image {
                    id: toFull
                    anchors.fill: parent
                    source: "file://" + root.applyTo
                    fillMode: Image.PreserveAspectCrop
                    sourceSize.width: fx.modelData.width * fx.dpr
                    sourceSize.height: fx.modelData.height * fx.dpr
                    asynchronous: true
                    onStatusChanged: fx.tryStart()
                }

                // Rendered copies, so the shader gets the images cropped the way
                // awww crops them rather than the whole files.
                ShaderEffectSource {
                    id: fromTex
                    anchors.fill: parent
                    sourceItem: fromFull
                    hideSource: true
                    visible: false
                }

                ShaderEffectSource {
                    id: toTex
                    anchors.fill: parent
                    sourceItem: toFull
                    hideSource: true
                    visible: false
                }

                ShaderEffect {
                    anchors.fill: parent
                    property var fromImage: fromTex
                    property var toImage: toTex
                    property real progress: fx.progress
                    property real mode: root.effect
                    property real aspect: width / Math.max(1, height)
                    property real seed: 42
                    property real blank: 0
                    fragmentShader: root.shader
                }

                NumberAnimation {
                    id: fxAnim
                    target: fx
                    property: "progress"
                    from: 0
                    to: 1
                    duration: root.effect === 0 ? 700 : 900
                    onFinished: {
                        fx.done = true
                        root.effectsDone++
                        root.maybeFinishApply()
                    }
                }

                // Start anyway if an image is slow to decode.
                Timer {
                    interval: 2500
                    running: true
                    onTriggered: if (!fx.done && !fxAnim.running) fxAnim.start()
                }
            }
        }
    }
}
