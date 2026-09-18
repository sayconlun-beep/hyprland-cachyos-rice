// The rice menu (Super+Space), modelled on Omarchy's: one panel with nested
// sections - Apps, Capture, Style, Settings, Tools, System - read from
// menu.jsonc (see the top of that file for the entry format).
//
// Typing searches every level at once, apps included; each hit shows the path
// it lives under. Enter or → opens a submenu, ← / Backspace (with the search
// empty) goes back up, Escape clears the search, then goes up, then closes.
//
// The settings hub (SettingsMenu.qml) draws the "settings" branch through
// hubRows() and run(), so the two never drift apart.
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Services.UPower

Scope {
    id: root

    property bool open: false
    property var targetScreen: null
    property string path: ""          // the submenu on show; "" is the top
    property string query: ""
    property int sel: 0
    property string confirming: ""    // id of the row waiting for a second Enter

    // Wired up by shell.qml.
    property var visualiser: null
    property var clock: null
    property var lyrics: null
    property var controlCenter: null
    property var notifications: null
    property var dashboard: null
    property var capture: null
    property var captureMenu: null
    property var binds: null
    property var displays: null
    property var themePicker: null

    readonly property string home: Quickshell.env("HOME")
    readonly property string file: Quickshell.shellDir + "/menu.jsonc"

    // Everything in menu.jsonc, each with `parent` added; `present` holds the
    // `requires` paths that exist.
    property var all: []
    property var present: ({})
    property string loadError: ""

    // Only the entries that should show: requires met, for them and every
    // entry above them (the D&D table's rows go with the D&D table).
    readonly property var items: {
        const gone = all.filter(e => e.requires && !present[expand(e.requires)]).map(e => e.id)
        return all.filter(e => !gone.some(g => e.id === g || e.id.startsWith(g + ".")))
    }

    readonly property var apps: {
        const seen = {}
        return DesktopEntries.applications.values
            .filter(a => !a.noDisplay && !seen[a.id] && (seen[a.id] = true))
            .sort((a, b) => a.name.localeCompare(b.name))
            .map(a => ({ id: "app:" + a.id, label: a.name, hint: a.genericName || a.comment || "",
                         appIcon: a.icon || "application-x-executable", app: a,
                         keywords: (a.keywords || []).join(" ") + " " + (a.categories || []).join(" ") }))
    }

    // Named themes (rice-theme list --json), re-read on every open.
    property var themeList: []
    readonly property var themes: themeList.map(t => ({
        id: "theme:" + t.id, label: t.name, theme: t.id, current: t.current,
        hint: t.id === "wallpaper" ? "colours from the wallpaper on screen"
            : t.mode + " · " + t.backgrounds + " wallpaper" + (t.backgrounds === 1 ? "" : "s"),
        icon: t.accent ? "" : "image", swatch: t.accent || "",
        run: [home + "/.local/bin/rice-theme", "set", t.id], keywords: "theme"
    }))

    Process {
        id: themeRead
        command: [root.home + "/.local/bin/rice-theme", "list", "--json"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.themeList = JSON.parse(text) } catch (e) { console.warn("rice-theme list: " + e) }
            }
        }
    }

    readonly property var rows: query.trim() ? search(query) : childrenOf(path)

    onQueryChanged: { sel = 0; confirming = "" }
    onPathChanged: { sel = 0; confirming = "" }
    onSelChanged: confirming = ""

    // ------------------------------------------------------------ the tree --
    function expand(p) {
        return typeof p === "string" && (p === "~" || p.startsWith("~/")) ? home + p.slice(1) : p
    }

    function find(id) {
        return items.find(e => e.id === id) || null
    }

    function isMenu(e) {
        return !!e && (!!e.source || items.some(c => c.parent === e.id))
    }

    function shown(e) {
        return e.when !== "recording" || (capture && capture.recording)
    }

    function childrenOf(id) {
        const e = find(id)
        if (e && e.source === "apps")
            return apps
        return items.filter(c => c.parent === id && shown(c))
    }

    function trail(e) {
        const names = []
        for (let p = e.parent; p; p = find(p) ? find(p).parent : "") {
            const f = find(p)
            if (!f)
                break
            names.unshift(f.label)
        }
        return names.join(" › ")
    }

    // Every word must match somewhere; label hits rank first. Settings repeats
    // a few entries from other branches, so the same command shows once.
    function search(q) {
        const words = q.toLowerCase().split(/\s+/).filter(w => w)
        const seen = {}
        const hits = []
        const consider = (e, where) => {
            const hay = [e.label, e.hint, where, e.keywords].join(" ").toLowerCase()
            if (!words.every(w => hay.includes(w)))
                return
            const key = e.app || e.theme ? e.id : e.label + "|" + (e.action || JSON.stringify(e.run || e.sh || e.id))
            if (seen[key])
                return
            seen[key] = true
            const label = e.label.toLowerCase()
            const rank = label.startsWith(words[0]) ? 0 : words.every(w => label.includes(w)) ? 1 : 2
            hits.push({ rank: rank + (e.app ? 0.5 : 0), n: hits.length, row: Object.assign({}, e, { where: where }) })
        }
        for (const e of items)
            if (shown(e))
                consider(e, trail(e))
        const appsLabel = (find("apps") || { label: "Apps" }).label
        for (const a of apps)
            consider(a, appsLabel)
        // Themes are searchable here too; picking one applies it straight away.
        const themesAt = find("style.theme")
        for (const t of themes)
            consider(t, themesAt ? [trail(themesAt), themesAt.label].filter(s => s).join(" › ") : "Themes")
        hits.sort((a, b) => a.rank - b.rank || a.n - b.n)      // file order within a rank
        return hits.slice(0, 80).map(h => h.row)
    }

    // The settings hub's rows: each child submenu is a section.
    function hubRows(id) {
        const out = []
        for (const c of childrenOf(id)) {
            if (isMenu(c))
                for (const g of childrenOf(c.id))
                    out.push(Object.assign({ section: c.label }, g))
            else
                out.push(Object.assign({ section: "" }, c))
        }
        return out
    }

    // ------------------------------------------------------------- loading --
    // JSONC: drop // and /* */ comments outside strings, then trailing commas.
    function stripJsonc(s) {
        let out = "", inStr = false
        for (let i = 0; i < s.length; i++) {
            const c = s[i]
            if (inStr) {
                out += c
                if (c === "\\") out += s[++i]
                else if (c === '"') inStr = false
            } else if (c === '"') {
                inStr = true
                out += c
            } else if (c === "/" && s[i + 1] === "/") {
                while (i < s.length && s[i] !== "\n") i++
                out += "\n"
            } else if (c === "/" && s[i + 1] === "*") {
                const end = s.indexOf("*/", i + 2)
                i = end < 0 ? s.length : end + 1
            } else {
                out += c
            }
        }
        return out.replace(/,(\s*[\]}])/g, "$1")
    }

    function load(text) {
        try {
            const list = JSON.parse(stripJsonc(text))
            all = list.filter(e => e && e.id && e.label).map(e => Object.assign({}, e, {
                parent: e.id.includes(".") ? e.id.slice(0, e.id.lastIndexOf(".")) : ""
            }))
            loadError = ""
            const paths = all.filter(e => e.requires).map(e => expand(e.requires))
            if (paths.length) {
                requiresCheck.command = ["sh", "-c", 'for p; do [ -e "$p" ] && printf "%s\\n" "$p"; done', "sh"].concat(paths)
                requiresCheck.running = true
            }
        } catch (err) {
            loadError = "menu.jsonc: " + err
            console.warn(loadError)
        }
    }

    FileView {
        path: root.file
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.load(text())
    }

    Process {
        id: requiresCheck
        stdout: StdioCollector {
            onStreamFinished: {
                const p = {}
                for (const line of text.split("\n"))
                    if (line)
                        p[line] = true
                root.present = p
            }
        }
    }

    // --------------------------------------------------------- live values --
    property string mode: "dark"

    FileView {
        path: root.home + "/.cache/rice/mode"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: root.mode = text().trim() === "light" ? "light" : "dark"
    }

    readonly property var profileNames: ["Power saver", "Balanced", "Performance"]

    function valueOf(e) {
        switch (e.value) {
        case "visualiser": return visualiser && visualiser.enabled ? "On" : "Off"
        case "clock":      return clock && clock.enabled ? "On" : "Off"
        case "lyrics":     return lyrics && lyrics.enabled ? "On" : "Off"
        case "power":      return profileNames[PowerProfiles.profile] ?? "…"
        case "mode":       return mode === "light" ? "Light" : "Dark"
        case "theme":      return (themeList.find(t => t.current) || { name: "" }).name
        case "recording":  return capture && capture.recording ? capture.elapsedText : ""
        }
        return undefined
    }

    // -------------------------------------------------------------- running --
    function doAction(name) {
        switch (name) {
        case "dashboard":         return dashboard.show()
        case "capture.menu":      return captureMenu.show()
        case "capture.screen":    return capture.screenshot("screen")
        case "capture.window":    return capture.screenshot("window")
        case "capture.area":      return capture.screenshot("area")
        case "record.screen":     return capture.record("screen")
        case "record.area":       return capture.record("area")
        case "record.stop":       return capture.stop()
        case "themes":            return themePicker.show("themes")
        case "displays":          return displays.show()
        case "keybinds":          return binds.show()
        case "controlcenter":     return controlCenter.show()
        case "notifications":     return notifications.show()
        case "visualiser.toggle": return visualiser.toggle()
        case "clock.toggle":      return clock.toggle()
        case "lyrics.toggle":     return lyrics.toggle()
        case "shell.reload":      return Quickshell.reload(true)
        case "mode.toggle":
            mode = mode === "dark" ? "light" : "dark"     // the file confirms it
            return Quickshell.execDetached([home + "/.local/bin/rice-wallpaper", "mode", mode])
        case "power.cycle": {
            const order = [PowerProfile.PowerSaver, PowerProfile.Balanced]
            if (PowerProfiles.hasPerformanceProfile)
                order.push(PowerProfile.Performance)
            PowerProfiles.profile = order[(order.indexOf(PowerProfiles.profile) + 1) % order.length]
            return
        }
        }
        console.warn("RiceMenu: unknown action " + name)
    }

    function run(e) {
        if (e.app) {
            if (e.app.runInTerminal)
                Quickshell.execDetached(["kitty", "-e"].concat(Array.from(e.app.command)))
            else
                e.app.execute()
        } else if (e.action) {
            doAction(e.action)
        } else if (e.run) {
            Quickshell.execDetached(e.run.map(expand))
        } else if (e.sh) {
            Quickshell.execDetached(["sh", "-c", e.sh])
        }
    }

    function activate(e) {
        if (!e)
            return
        if (isMenu(e)) {
            enter(e.id)
            return
        }
        if (e.confirm && confirming !== e.id) {
            confirming = e.id
            return
        }
        confirming = ""
        if (!e.keep)
            close()
        run(e)
    }

    function enter(id) {
        query = ""
        path = id
    }

    function back() {
        if (!path)
            return close()
        const e = find(path)
        const from = path
        path = e ? e.parent : ""
        sel = Math.max(0, rows.findIndex(r => r.id === from))
    }

    // ---------------------------------------------------------- open/close --
    function show(at) {
        path = at && find(at) ? at : ""
        query = ""
        themeRead.running = true
        sel = 0
        confirming = ""
        if (open)
            return
        targetScreen = focusedScreen()
        open = true
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

    // Omarchy's look, a size smaller: a narrow bordered panel, mono text, a
    // "Go…" prompt you type straight into, and rows that are only icon, label
    // and chevron (search hits add where they live, dimmed).
    readonly property int rowHeight: 38
    readonly property int maxRows: 9

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
            WlrLayershell.namespace: "rice-menu"
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

            MouseArea {
                anchors.fill: parent
                onClicked: root.close()
            }

            Rectangle {
                id: panel
                anchors.centerIn: parent
                width: root.query ? 460 : 320
                height: prompt.height + 30 + Math.min(Math.max(root.rows.length, 1), root.maxRows) * (root.rowHeight + 2)
                radius: 8
                color: Theme.surface_container_low
                border.width: 2
                border.color: Theme.alpha(Theme.on_surface, 0.85)
                clip: true

                opacity: 0
                Component.onCompleted: {
                    opacity = 1
                    input.forceActiveFocus()
                }
                Behavior on opacity {
                    NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
                }
                Behavior on height {
                    NumberAnimation { duration: 110; easing.type: Easing.OutCubic }
                }
                Behavior on width {
                    NumberAnimation { duration: 110; easing.type: Easing.OutCubic }
                }

                MouseArea {
                    anchors.fill: parent        // clicks inside do not close
                }

                // ------------------------------------------------ prompt --
                Item {
                    id: prompt
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.topMargin: 14
                    anchors.leftMargin: 20
                    anchors.rightMargin: 20
                    height: 30

                    TextInput {
                        id: input
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.query
                        onTextChanged: root.query = text
                        color: Theme.on_surface
                        selectionColor: Theme.alpha(Theme.primary, 0.35)
                        font.family: Theme.mono
                        font.pixelSize: 15
                        font.weight: Font.Bold
                        clip: true
                        // No caret over the "Go…" prompt; it shows once you type.
                        cursorDelegate: Rectangle {
                            width: 2
                            color: Theme.on_surface
                            visible: input.text.length > 0
                        }

                        Keys.onPressed: event => {
                            const n = root.rows.length
                            const cur = root.rows[root.sel]
                            switch (event.key) {
                            case Qt.Key_Down: case Qt.Key_Tab:
                                if (n) root.sel = (root.sel + 1) % n; break
                            case Qt.Key_Up: case Qt.Key_Backtab:
                                if (n) root.sel = (root.sel - 1 + n) % n; break
                            case Qt.Key_PageDown:
                                root.sel = Math.min(n - 1, root.sel + root.maxRows); break
                            case Qt.Key_PageUp:
                                root.sel = Math.max(0, root.sel - root.maxRows); break
                            case Qt.Key_Return: case Qt.Key_Enter:
                                root.activate(cur); break
                            case Qt.Key_Right:
                                if (text || !root.isMenu(cur)) return
                                root.enter(cur.id); break
                            case Qt.Key_Left: case Qt.Key_Backspace:
                                if (text) return
                                root.back(); break
                            case Qt.Key_Escape:
                                if (text) root.query = ""
                                else root.back()
                                break
                            default:
                                return
                            }
                            event.accepted = true
                        }
                    }

                    // "Go…" at the top, the submenu's name inside one.
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: !input.text
                        text: (root.path ? (root.find(root.path) || { label: "Go" }).label : "Go") + "…"
                        color: Theme.alpha(Theme.on_surface, 0.8)
                        font: input.font

                        MouseArea {
                            anchors.fill: parent
                            enabled: !!root.path
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.back()
                        }
                    }
                }

                // ------------------------------------------------- rows --
                ListView {
                    id: list
                    anchors.top: prompt.bottom
                    anchors.topMargin: 6
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    anchors.bottomMargin: 10
                    clip: true
                    spacing: 2
                    boundsBehavior: Flickable.StopAtBounds
                    model: root.rows
                    currentIndex: root.sel
                    highlightMoveDuration: 0
                    onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Contain)

                    Text {
                        anchors.centerIn: parent
                        visible: !root.rows.length
                        text: root.loadError || (root.query ? "No match" : "Empty")
                        color: root.loadError ? Theme.error : Theme.on_surface_variant
                        font.family: Theme.mono
                        font.pixelSize: 13
                    }

                    delegate: Rectangle {
                        id: row
                        required property var modelData
                        required property int index
                        readonly property bool selected: index === root.sel
                        readonly property bool asking: root.confirming === modelData.id
                        readonly property bool menu: root.isMenu(modelData)
                        readonly property var value: modelData.current ? "current" : root.valueOf(modelData)

                        width: ListView.view.width
                        height: root.rowHeight
                        radius: 6
                        color: asking ? Theme.alpha(Theme.error, 0.3)
                            : selected ? Theme.alpha(Theme.on_surface, 0.2) : "transparent"

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 14
                            anchors.rightMargin: 12
                            spacing: 14

                            MenuIcon {
                                Layout.preferredWidth: 20
                                icon: row.modelData.icon || ""
                                appIcon: row.modelData.appIcon || ""
                                swatch: row.modelData.swatch || ""
                                size: 16
                                color: row.asking ? Theme.error : Theme.on_surface
                            }

                            Text {
                                Layout.fillWidth: !root.query
                                elide: Text.ElideRight
                                text: row.asking ? row.modelData.label + "? Enter" : row.modelData.label
                                color: row.asking ? Theme.error : Theme.on_surface
                                font.family: Theme.mono
                                font.pixelSize: 14
                                font.weight: Font.Bold
                            }

                            // Search hits only: where the entry lives.
                            Text {
                                visible: !!root.query
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                                text: row.modelData.where || ""
                                color: Theme.alpha(Theme.on_surface, 0.45)
                                font.family: Theme.mono
                                font.pixelSize: 11
                            }

                            Text {
                                visible: row.value !== undefined && row.value !== ""
                                text: row.value || ""
                                color: row.value === "Off" ? Theme.alpha(Theme.on_surface, 0.45) : Theme.primary
                                font.family: Theme.mono
                                font.pixelSize: 12
                                font.weight: Font.Bold
                            }

                            LucideIcon {
                                visible: row.menu
                                icon: "chevron-right"
                                size: 14
                                color: Theme.alpha(Theme.on_surface, 0.7)
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onPositionChanged: root.sel = row.index    // not onEntered: rows slide under a still cursor
                            onClicked: root.activate(row.modelData)
                        }
                    }
                }
            }
        }
    }
}
