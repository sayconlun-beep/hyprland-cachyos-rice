// Display arrangement (Settings › Displays, or `qs -c rice ipc call displays
// toggle`): every enabled output drawn to scale, dragged into place like
// Windows' display settings. A dropped screen snaps flush against the nearest
// edge of another one, lining up with its top, bottom or centre when close.
//
// Apply hands the whole layout to rice-monitor-ctl.py arrange, which shifts it
// so its top-left is 0,0, applies it live and saves it to conf.d/10-monitors.lua.
// Mode, scale and VRR stay in the rofi menu (rice-settings displays).
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

Scope {
    id: root

    property bool open: false
    property var targetScreen: null
    property var outputs: []          // enabled outputs, as listed by rice-monitor-ctl.py
    property var disabledNames: []
    property var layout: ({})         // name -> {x, y} in logical px, as arranged here
    property var saved: ({})          // the layout as it is live
    property string selected: ""
    property string message: ""
    property bool busy: false
    property bool identifying: false

    readonly property string ctl: Quickshell.env("HOME") + "/.local/bin/rice-monitor-ctl.py"
    readonly property bool dirty: {
        for (const o of outputs) {
            const a = layout[o.name], b = saved[o.name]
            if (!a || !b || a.x - minX() !== b.x - savedMinX() || a.y - minY() !== b.y - savedMinY())
                return true
        }
        return false
    }

    function show() {
        if (open)
            return
        targetScreen = focusedScreen()
        message = ""
        open = true
        load()
    }

    function close() {
        open = false
    }

    function toggle() {
        open ? close() : show()
    }

    function focusedScreen() {
        const name = Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : ""
        const screens = Quickshell.screens
        for (let i = 0; i < screens.length; i++)
            if (screens[i].name === name)
                return screens[i]
        return screens[0]
    }

    function load() {
        lister.running = true
    }

    // Layout px of an output: scaled, and swapped when it is rotated 90/270.
    function logical(o) {
        const s = o.live.scale || 1
        let w = Math.round(o.live.width / s), h = Math.round(o.live.height / s)
        if ((o.live.transform || 0) % 2)
            [w, h] = [h, w]
        return { w: w, h: h }
    }

    function parse(text) {
        let data
        try {
            data = JSON.parse(text)
        } catch (e) {
            message = "Could not read the displays"
            return
        }
        const outs = [], off = [], pos = {}
        for (const o of data.outputs) {
            if (o.disabled) {
                off.push(o.connector)
                continue
            }
            const size = logical(o)
            outs.push({
                name: o.connector,
                model: o.model || o.description,
                w: size.w,
                h: size.h,
                pxw: o.live.width,
                pxh: o.live.height,
                refresh: o.live.refresh,
                scale: o.live.scale,
                focused: o.focused
            })
            pos[o.connector] = { x: o.live.x, y: o.live.y }
        }
        outs.sort((a, b) => pos[a.name].x - pos[b.name].x || pos[a.name].y - pos[b.name].y)
        // Positions before outputs: the canvas bindings index layout by output.
        saved = pos
        layout = JSON.parse(JSON.stringify(pos))
        disabledNames = off
        outputs = outs
        if (!outs.some(o => o.name === selected))
            selected = outs.length ? (outs.find(o => o.focused) || outs[0]).name : ""
    }

    function output(name) {
        return outputs.find(o => o.name === name)
    }

    function minX() { return Math.min(...outputs.map(o => layout[o.name] ? layout[o.name].x : 0)) }
    function minY() { return Math.min(...outputs.map(o => layout[o.name] ? layout[o.name].y : 0)) }
    function savedMinX() { return Math.min(...outputs.map(o => saved[o.name] ? saved[o.name].x : 0)) }
    function savedMinY() { return Math.min(...outputs.map(o => saved[o.name] ? saved[o.name].y : 0)) }

    function overlaps(ax, ay, aw, ah, bx, by, bw, bh) {
        return ax < bx + bw && bx < ax + aw && ay < by + bh && by < ay + ah
    }

    // Where `name` lands if dropped at (px, py): flush against a side of some
    // other output, sharing at least a bit of that edge, not overlapping any
    // output, and as close to the drop point as that allows. `pull` is how far
    // (in layout px) an edge is drawn into alignment with its neighbour's.
    function snap(name, px, py, pull) {
        const d = output(name)
        const others = outputs.filter(o => o.name !== name)
        if (!others.length)
            return { x: 0, y: 0 }
        const align = (v, targets) => {
            let best = v, bestGap = pull
            for (const t of targets)
                if (Math.abs(v - t) <= bestGap) {
                    best = t
                    bestGap = Math.abs(v - t)
                }
            return best
        }
        const candidates = []
        for (const o of others) {
            const p = layout[o.name]
            const shareX = Math.min(100, d.w, o.w), shareY = Math.min(100, d.h, o.h)
            // Left or right of o: y slides along its side.
            for (const x of [p.x - d.w, p.x + o.w]) {
                let y = Math.max(p.y - d.h + shareY, Math.min(py, p.y + o.h - shareY))
                y = align(y, [p.y, p.y + o.h - d.h, p.y + Math.round((o.h - d.h) / 2)])
                candidates.push({ x: x, y: y })
            }
            // Above or below o: x slides along its edge.
            for (const y of [p.y - d.h, p.y + o.h]) {
                let x = Math.max(p.x - d.w + shareX, Math.min(px, p.x + o.w - shareX))
                x = align(x, [p.x, p.x + o.w - d.w, p.x + Math.round((o.w - d.w) / 2)])
                candidates.push({ x: x, y: y })
            }
        }
        let best = null, bestDist = Infinity
        for (const c of candidates) {
            if (others.some(o => overlaps(c.x, c.y, d.w, d.h, layout[o.name].x, layout[o.name].y, o.w, o.h)))
                continue
            const dist = Math.hypot(c.x - px, c.y - py)
            if (dist < bestDist) {
                best = c
                bestDist = dist
            }
        }
        return best || layout[name]
    }

    function place(name, x, y) {
        const next = JSON.parse(JSON.stringify(layout))
        next[name] = { x: Math.round(x), y: Math.round(y) }
        layout = next
    }

    function revert() {
        layout = JSON.parse(JSON.stringify(saved))
        message = ""
    }

    function apply() {
        if (!dirty || busy)
            return
        const args = outputs.map(o => `${o.name}=${layout[o.name].x - minX()}x${layout[o.name].y - minY()}`)
        busy = true
        message = "Applying…"
        arranger.command = [ctl, "arrange"].concat(args)
        arranger.running = true
    }

    function identify() {
        identifying = true
        identifyTimer.restart()
    }

    function number(name) {
        return outputs.findIndex(o => o.name === name) + 1
    }

    // Plugging a screen in or out while the panel is open: show the new set,
    // unless there is an arrangement waiting to be applied.
    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (root.open && !root.dirty && (event.name === "monitoraddedv2" || event.name === "monitorremovedv2"))
                root.load()
        }
    }

    Timer {
        id: identifyTimer
        interval: 2500
        onTriggered: root.identifying = false
    }

    Process {
        id: lister
        command: [root.ctl, "list"]
        stdout: StdioCollector {
            onStreamFinished: root.parse(text)
        }
    }

    Process {
        id: arranger
        stdout: StdioCollector {
            id: arrangeOut
        }
        stderr: StdioCollector {
            id: arrangeErr
        }
        onExited: code => {
            root.busy = false
            if (code === 0) {
                root.message = "Arrangement applied and saved"
            } else {
                let detail = arrangeErr.text.trim()
                try {
                    detail = JSON.parse(arrangeOut.text).detail || detail
                } catch (e) {}
                root.message = "Not applied: " + (detail || "rice-monitor-ctl.py failed")
            }
            root.load()
        }
    }

    // Identify: a big number on every screen, matching the tiles in the panel.
    Variants {
        model: root.identifying ? Quickshell.screens : []

        PanelWindow {
            required property var modelData
            screen: modelData
            anchors {
                top: true
                left: true
            }
            margins {
                top: 60
                left: 60
            }
            implicitWidth: badge.implicitWidth
            implicitHeight: badge.implicitHeight
            exclusionMode: ExclusionMode.Ignore
            color: "transparent"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "rice-displays-identify"

            Rectangle {
                id: badge
                implicitWidth: badgeRow.implicitWidth + 60
                implicitHeight: 190
                radius: 30
                color: Theme.alpha(Theme.surface_container, 0.94)
                border.width: 2
                border.color: Theme.primary

                RowLayout {
                    id: badgeRow
                    anchors.centerIn: parent
                    spacing: 26

                    Text {
                        text: root.number(modelData.name) || "?"
                        color: Theme.primary
                        font.family: Theme.font
                        font.pixelSize: 120
                        font.weight: Font.Bold
                    }

                    ColumnLayout {
                        spacing: 4
                        Text {
                            text: modelData.name
                            color: Theme.on_surface
                            font.family: Theme.font
                            font.pixelSize: 30
                            font.weight: Font.DemiBold
                        }
                        Text {
                            text: root.output(modelData.name) ? root.output(modelData.name).model : ""
                            color: Theme.on_surface_variant
                            font.family: Theme.font
                            font.pixelSize: 20
                        }
                    }
                }
            }
        }
    }

    component PillButton: Rectangle {
        id: pill
        property string label
        property bool primary: false
        signal clicked

        implicitWidth: pillText.implicitWidth + 40
        implicitHeight: 42
        radius: 21
        opacity: enabled ? 1 : 0.4
        color: primary ? Theme.primary
             : pillMouse.containsMouse && enabled ? Theme.surface_container_highest : Theme.surface_container_high
        border.width: primary ? 0 : 1
        border.color: Theme.outline_variant

        Text {
            id: pillText
            anchors.centerIn: parent
            text: pill.label
            color: pill.primary ? Theme.on_primary : Theme.on_surface
            font.family: Theme.font
            font.pixelSize: 15
            font.weight: Font.DemiBold
        }

        MouseArea {
            id: pillMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: pill.clicked()
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
            WlrLayershell.namespace: "rice-displays"
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

            Rectangle {
                anchors.fill: parent
                color: Qt.rgba(0, 0, 0, 0.5)
                MouseArea {
                    anchors.fill: parent
                    onClicked: root.close()
                }
            }

            Rectangle {
                id: card
                anchors.centerIn: parent
                width: Math.min(parent.width - 100, 1100)
                height: Math.min(parent.height - 100, 760)
                radius: 26
                color: Theme.alpha(Theme.surface_container, 0.96)
                border.width: 1
                border.color: Theme.alpha(Theme.outline_variant, 0.7)
                focus: true
                Keys.onPressed: event => {
                    if (event.key === Qt.Key_Escape)
                        root.close()
                    else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
                        root.apply()
                    else
                        return
                    event.accepted = true
                }
                Component.onCompleted: forceActiveFocus()

                MouseArea {
                    anchors.fill: parent        // keep clicks on the card from closing it
                }

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 28
                    spacing: 18

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 16

                        Text {
                            text: "󰍹"
                            color: Theme.primary
                            font.family: Theme.mono
                            font.pixelSize: 30
                        }

                        ColumnLayout {
                            spacing: 2
                            Text {
                                text: "Displays"
                                color: Theme.on_surface
                                font.family: Theme.font
                                font.pixelSize: 26
                                font.weight: Font.Bold
                            }
                            Text {
                                text: "Drag the screens to match how they sit on your desk"
                                color: Theme.on_surface_variant
                                font.family: Theme.font
                                font.pixelSize: 15
                            }
                        }

                        Item { Layout.fillWidth: true }

                        PillButton {
                            label: "Identify"
                            onClicked: root.identify()
                        }
                    }

                    // The arrangement, to scale and centred in the canvas.
                    Rectangle {
                        id: canvas
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        radius: 18
                        color: Theme.surface_container_low
                        border.width: 1
                        border.color: Theme.alpha(Theme.outline_variant, 0.6)
                        clip: true

                        // One scale for the whole session, sized so any arrangement
                        // of these screens fits - so tiles don't resize mid-drag.
                        readonly property real unit: {
                            const outs = root.outputs
                            if (!outs.length)
                                return 0.1
                            const sumW = outs.reduce((s, o) => s + o.w, 0), sumH = outs.reduce((s, o) => s + o.h, 0)
                            const maxW = Math.max(...outs.map(o => o.w)), maxH = Math.max(...outs.map(o => o.h))
                            return Math.min((width - 60) / (sumW + maxW * 0.4), (height - 60) / (sumH + maxH * 0.4),
                                            (width - 60) / (maxW * 2.2), 0.2)
                        }
                        readonly property real originX: {
                            const outs = root.outputs
                            if (!outs.length)
                                return 0
                            const l = root.layout
                            const lo = Math.min(...outs.map(o => l[o.name].x)), hi = Math.max(...outs.map(o => l[o.name].x + o.w))
                            return width / 2 - (lo + hi) / 2 * unit
                        }
                        readonly property real originY: {
                            const outs = root.outputs
                            if (!outs.length)
                                return 0
                            const l = root.layout
                            const lo = Math.min(...outs.map(o => l[o.name].y)), hi = Math.max(...outs.map(o => l[o.name].y + o.h))
                            return height / 2 - (lo + hi) / 2 * unit
                        }

                        MouseArea {
                            anchors.fill: parent
                        }

                        Text {
                            anchors.centerIn: parent
                            visible: !root.outputs.length
                            text: "Reading displays…"
                            color: Theme.on_surface_variant
                            font.family: Theme.font
                            font.pixelSize: 16
                        }

                        Repeater {
                            model: root.outputs

                            Rectangle {
                                id: tile
                                required property var modelData
                                readonly property bool isSelected: root.selected === modelData.name
                                readonly property var at: root.layout[modelData.name] || { x: 0, y: 0 }
                                property bool dragging: false

                                width: modelData.w * canvas.unit
                                height: modelData.h * canvas.unit
                                x: canvas.originX + at.x * canvas.unit
                                y: canvas.originY + at.y * canvas.unit
                                z: dragging ? 10 : isSelected ? 5 : 1
                                radius: 10
                                color: dragging ? Theme.primary_container
                                     : isSelected ? Theme.alpha(Theme.primary_container, 0.75) : Theme.surface_container_highest
                                border.width: isSelected ? 3 : 1
                                border.color: isSelected ? Theme.primary : Theme.outline_variant
                                scale: dragging ? 1.02 : 1

                                Behavior on x {
                                    enabled: !tile.dragging
                                    NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
                                }
                                Behavior on y {
                                    enabled: !tile.dragging
                                    NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
                                }

                                ColumnLayout {
                                    anchors.centerIn: parent
                                    width: parent.width - 16
                                    spacing: 2

                                    Text {
                                        Layout.alignment: Qt.AlignHCenter
                                        text: root.number(tile.modelData.name)
                                        color: tile.isSelected ? Theme.primary : Theme.on_surface
                                        font.family: Theme.font
                                        font.pixelSize: Math.max(18, Math.min(56, tile.height * 0.32))
                                        font.weight: Font.Bold
                                    }
                                    Text {
                                        Layout.fillWidth: true
                                        horizontalAlignment: Text.AlignHCenter
                                        elide: Text.ElideRight
                                        text: tile.modelData.name
                                        color: Theme.on_surface
                                        font.family: Theme.font
                                        font.pixelSize: 14
                                        font.weight: Font.DemiBold
                                    }
                                    Text {
                                        Layout.fillWidth: true
                                        horizontalAlignment: Text.AlignHCenter
                                        elide: Text.ElideRight
                                        visible: tile.height > 110
                                        text: tile.modelData.model
                                        color: Theme.on_surface_variant
                                        font.family: Theme.font
                                        font.pixelSize: 12
                                    }
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                                    drag.target: tile
                                    drag.threshold: 4
                                    onPressed: {
                                        root.selected = tile.modelData.name
                                        root.message = ""
                                    }
                                    drag.onActiveChanged: {
                                        if (drag.active) {
                                            tile.dragging = true
                                            return
                                        }
                                        const u = canvas.unit
                                        const dropped = root.snap(tile.modelData.name,
                                                                  (tile.x - canvas.originX) / u,
                                                                  (tile.y - canvas.originY) / u,
                                                                  14 / u)
                                        tile.dragging = false
                                        root.place(tile.modelData.name, dropped.x, dropped.y)
                                        // Put the bindings back: the drag overwrote x and y.
                                        tile.x = Qt.binding(() => canvas.originX + tile.at.x * canvas.unit)
                                        tile.y = Qt.binding(() => canvas.originY + tile.at.y * canvas.unit)
                                    }
                                }
                            }
                        }
                    }

                    // The selected screen, then the actions.
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 12

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 3

                            Text {
                                readonly property var o: root.output(root.selected)
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                                text: o ? `${root.number(o.name)}  ·  ${o.name}  ·  ${o.model}` : ""
                                color: Theme.on_surface
                                font.family: Theme.font
                                font.pixelSize: 16
                                font.weight: Font.DemiBold
                            }
                            Text {
                                readonly property var o: root.output(root.selected)
                                readonly property var p: o ? root.layout[o.name] : null
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                                text: o && p ? `${o.pxw}×${o.pxh} @ ${Math.round(o.refresh)} Hz  ·  scale ${o.scale}`
                                               + `  ·  position ${p.x - root.minX()}, ${p.y - root.minY()}`
                                               + (root.disabledNames.length ? `  ·  off: ${root.disabledNames.join(", ")}` : "")
                                             : ""
                                color: Theme.on_surface_variant
                                font.family: Theme.font
                                font.pixelSize: 14
                            }
                            Text {
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                                visible: text !== ""
                                text: root.message
                                color: root.message.startsWith("Not applied") ? Theme.error : Theme.tertiary
                                font.family: Theme.font
                                font.pixelSize: 14
                            }
                        }

                        PillButton {
                            label: "Resolution, scale, VRR…"
                            onClicked: {
                                root.close()
                                Quickshell.execDetached([Quickshell.env("HOME") + "/.local/bin/rice-settings", "displays"])
                            }
                        }
                        PillButton {
                            label: "Revert"
                            enabled: root.dirty && !root.busy
                            onClicked: root.revert()
                        }
                        PillButton {
                            label: root.busy ? "Applying…" : "Apply"
                            primary: true
                            enabled: root.dirty && !root.busy
                            onClicked: root.apply()
                        }
                    }
                }
            }
        }
    }
}
