// Wallhaven browser (Super+Ctrl+W): search wallhaven.cc with the filters and
// sorting laid out in the header, results in a thumbnail grid underneath that
// loads more as you scroll. Clicking a result downloads it into the wallpaper
// folder as wallhaven-<id>.<ext> and applies it with `rice-wallpaper set`
// (or, with a Theme filter on, pins it to that theme and applies it there),
// which re-themes everything - this panel included, as it stays open.
// Right-click opens the wallpaper's page instead.
//
// Filters take effect as soon as they change and are saved to
// ~/.config/rice/wallhaven.json. An API key goes in there too ("apikey") -
// wallhaven only needs one for NSFW.
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Widgets

Scope {
    id: root

    property bool open: false
    property var targetScreen: null

    // Saved filters
    property string query: ""
    property bool general: true
    property bool anime: true
    property bool people: false
    property bool sfw: true
    property bool sketchy: false
    property bool nsfw: false
    property string sorting: "toplist"
    property string order: "desc"
    property string topRange: "1M"
    property string atleast: "2560x1440"
    property string ratios: "landscape"
    property string colour: ""
    property string themeFilter: ""    // a rice theme id: keep results whose colours fit it
    property string apikey: ""
    property bool settingsLoaded: false

    // Results
    property int page: 0
    property int lastPage: 0
    property int total: 0
    property string seed: ""           // keeps random sorting stable across pages
    property bool loading: false
    property string error: ""
    property int generation: 0         // replies to a superseded search are dropped
    property var library: ({})         // ids already in the wallpaper folder
    property string downloading: ""
    property string applied: ""

    readonly property string home: Quickshell.env("HOME")
    readonly property string bin: home + "/.local/bin/"
    readonly property string wallDir: Quickshell.env("RICE_WALLPAPER_DIR") || home + "/Pictures/Wallpapers"
    readonly property string settingsPath: home + "/.config/rice/wallhaven.json"
    readonly property var savedKeys: ["query", "general", "anime", "people", "sfw", "sketchy", "nsfw",
        "sorting", "order", "topRange", "atleast", "ratios", "colour", "themeFilter", "apikey"]

    readonly property var sorts: [
        { id: "relevance", label: "Relevance" }, { id: "date_added", label: "Newest" },
        { id: "hot", label: "Hot" }, { id: "toplist", label: "Toplist" },
        { id: "views", label: "Views" }, { id: "favorites", label: "Favourites" },
        { id: "random", label: "Random" }
    ]
    readonly property var ranges: [
        { id: "1d", label: "Day" }, { id: "3d", label: "3 days" }, { id: "1w", label: "Week" },
        { id: "1M", label: "Month" }, { id: "3M", label: "3 months" }, { id: "6M", label: "6 months" },
        { id: "1y", label: "Year" }
    ]
    readonly property var resolutions: [
        { id: "", label: "Any" }, { id: "1920x1080", label: "1080p+" }, { id: "2560x1440", label: "1440p+" },
        { id: "3440x1440", label: "Ultrawide+" }, { id: "3840x2160", label: "4K+" }
    ]
    readonly property var ratioOptions: [
        { id: "", label: "Any" }, { id: "landscape", label: "Landscape" }, { id: "portrait", label: "Portrait" },
        { id: "16x9", label: "16:9" }, { id: "16x10", label: "16:10" }, { id: "21x9", label: "21:9" }
    ]
    // The colours wallhaven's API accepts.
    readonly property var colours: ["660000", "990000", "cc0000", "cc3333", "ea4c88", "993399", "663399",
        "333399", "0066cc", "0099cc", "66cccc", "77cc33", "669900", "336600", "666600", "999900", "cccc33",
        "ffff00", "ffcc33", "ff9900", "ff6600", "cc6633", "996633", "663300", "000000", "999999", "cccccc",
        "ffffff", "424153"]

    function show() {
        if (open)
            return
        targetScreen = focusedScreen()
        open = true
        libraryLister.running = true
        themeLister.running = true
        if (settingsLoaded && results.count === 0)
            search()
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

    // ------------------------------------------------------ theme matching --
    // The same score as rice-theme-match (which files wallpapers into themes),
    // run on the colours wallhaven reports for each result, most common first.
    property var themes: []            // [{id, name, accent, background, palette, lab...}]
    readonly property var chosenTheme: themes.find(t => t.id === themeFilter) || null

    function lab(hex) {
        const h = hex.replace("#", "")
        const lin = v => { v /= 255; return v <= 0.04045 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4) }
        const r = lin(parseInt(h.slice(0, 2), 16)), g = lin(parseInt(h.slice(2, 4), 16)), b = lin(parseInt(h.slice(4, 6), 16))
        const f = t => t > 0.008856 ? Math.cbrt(t) : 7.787 * t + 16 / 116
        const x = f((0.4124 * r + 0.3576 * g + 0.1805 * b) / 0.95047)
        const y = f(0.2126 * r + 0.7152 * g + 0.0722 * b)
        const z = f((0.0193 * r + 0.1192 * g + 0.9505 * b) / 1.08883)
        return [(116 * y - 16) * 0.5, 500 * (x - y), 200 * (y - z)]    // lightness counts half
    }

    function dist(a, b) {
        return Math.hypot(a[0] - b[0], a[1] - b[1], a[2] - b[2])
    }

    function nearest(c, set) {
        let m = Infinity
        for (const p of set)
            m = Math.min(m, dist(c, p))
        return m
    }

    function themeScore(cols, t) {
        const n = cols.length
        let forward = 0, wsum = 0
        cols.forEach((c, i) => { const w = n - i; forward += w * nearest(c, t.labAll); wsum += w })
        return forward / wsum + 0.25 * (nearest(t.labBg, cols) + nearest(t.labAccent, cols))
    }

    // Best theme first.
    function rankThemes(hexes) {
        if (!hexes || !hexes.length || !themes.length)
            return []
        const cols = hexes.map(lab)
        return themes.map(t => ({ t: t, s: themeScore(cols, t) })).sort((a, b) => a.s - b.s).map(x => x.t)
    }

    function bits(a, b, c) {
        return (a ? "1" : "0") + (b ? "1" : "0") + (c ? "1" : "0")
    }

    function searchUrl(p) {
        let u = "https://wallhaven.cc/api/v1/search?q=" + encodeURIComponent(query.trim())
            + "&categories=" + bits(general, anime, people)
            + "&purity=" + bits(sfw, sketchy, nsfw && apikey !== "")
            + "&sorting=" + sorting + "&order=" + order + "&page=" + p
        if (sorting === "toplist")
            u += "&topRange=" + topRange
        if (atleast)
            u += "&atleast=" + atleast
        if (ratios)
            u += "&ratios=" + ratios
        // Not with a Theme filter: wallhaven's colour search only matches an exact
        // entry of its 29-colour palette in the image, and returned nothing even
        // for a month's toplist in Tokyo Night's nearest blue. Themes are matched
        // here instead, on every result's colours.
        if (colour && !chosenTheme)
            u += "&colors=" + colour
        if (sorting === "random" && seed && p > 1)
            u += "&seed=" + seed
        if (apikey)
            u += "&apikey=" + encodeURIComponent(apikey)
        return u
    }

    function search() {
        refilter.stop()
        generation++
        results.clear()
        page = 0
        lastPage = 0
        total = 0
        seed = ""
        error = ""
        if (bits(general, anime, people) === "000") {
            error = "Pick at least one category"
            return
        }
        if (bits(sfw, sketchy, nsfw && apikey !== "") === "000") {
            error = "Pick at least one purity level"
            return
        }
        fetchPage(1)
    }

    function more() {
        if (!loading && !error && page > 0 && page < lastPage)
            fetchPage(page + 1)
    }

    property int shownThisRun: 0       // results kept since the last search or scroll
    property int pagesThisRun: 0

    function fetchPage(p, chained) {
        const gen = generation
        if (!chained) {
            shownThisRun = 0
            pagesThisRun = 0
        }
        pagesThisRun++
        loading = true
        const xhr = new XMLHttpRequest()
        xhr.onreadystatechange = () => {
            if (xhr.readyState !== XMLHttpRequest.DONE || gen !== root.generation)
                return
            root.loading = false
            if (xhr.status === 429) {
                root.error = "Rate limited by wallhaven - give it a minute"
                return
            }
            if (xhr.status === 401) {
                root.error = "wallhaven rejected the API key"
                return
            }
            if (xhr.status !== 200) {
                root.error = xhr.status ? `Search failed (HTTP ${xhr.status})` : "Search failed - offline?"
                return
            }
            try {
                const d = JSON.parse(xhr.responseText)
                for (const w of d.data) {
                    const ranked = root.rankThemes(w.colors)
                    // A Theme filter keeps results with that theme in their top 3.
                    if (root.chosenTheme && ranked.slice(0, 3).indexOf(root.chosenTheme) < 0)
                        continue
                    root.shownThisRun++
                    root.results.append({
                        wid: w.id,
                        thumb: w.thumbs.large,
                        full: w.path,
                        link: w.url,
                        resolution: w.resolution,
                        favorites: w.favorites,
                        category: w.category,
                        purity: w.purity,
                        size: w.file_size,
                        themeName: ranked.length ? ranked[0].name : "",
                        themeAccent: ranked.length ? ranked[0].accent : ""
                    })
                }
                root.page = d.meta.current_page
                root.lastPage = d.meta.last_page
                root.total = d.meta.total
                if (d.meta.seed)
                    root.seed = d.meta.seed
                // Filtering can leave a page nearly empty: fetch on, a few
                // pages at most (wallhaven allows 45 requests a minute).
                if (root.chosenTheme && root.shownThisRun < 18 && root.page < root.lastPage && root.pagesThisRun < 6)
                    root.fetchPage(root.page + 1, true)
            } catch (e) {
                root.error = "Unexpected reply from wallhaven"
            }
        }
        xhr.open("GET", searchUrl(p))
        xhr.send()
    }

    // A filter changed: save it and search again, coalescing quick clicks.
    function setFilter(name, value) {
        root[name] = value
        saveTimer.restart()
        refilter.restart()
    }

    // Into the collection, then applied: with a Theme filter it is pinned to
    // that theme and shown as one of its wallpapers (the theme's exact colours);
    // otherwise it is applied from the collection, coloured from the picture,
    // and `rice-theme sort` files it under whichever theme it matches.
    function download(w) {
        if (downloading)
            return
        const name = `wallhaven-${w.wid}.${w.full.split(".").pop()}`
        const dest = `${wallDir}/${name}`
        downloading = w.wid
        error = ""
        const fetch = 'mkdir -p "${2%/*}" && if [ ! -s "$2" ]; then curl -fsSL --max-time 180 -o "$2.part" "$1" '
            + '|| { rm -f "$2.part"; exit 1; }; mv "$2.part" "$2"; fi; '
        downloader.command = themeFilter
            ? ["sh", "-c", fetch + '"$3" pin "$2" "$4" && exec "$3" set "$4" "$5/$4/backgrounds/mine-$6"',
               "sh", w.full, dest, bin + "rice-theme", themeFilter, home + "/.config/rice/themes", name]
            : ["sh", "-c", fetch + 'exec "$3" set "$2"', "sh", w.full, dest, bin + "rice-wallpaper"]
        downloader.running = true
    }

    function sizeText(bytes) {
        return bytes >= 1048576 ? (bytes / 1048576).toFixed(1) + " MB" : Math.round(bytes / 1024) + " KB"
    }

    function statusText() {
        if (error)
            return error
        if (downloading)
            return chosenTheme ? `Downloading into ${chosenTheme.name}…` : "Downloading and applying…"
        if (loading && page === 0)
            return "Searching…"
        if (page === 0)
            return ""
        if (total === 0)
            return "Nothing found"
        if (chosenTheme)
            return `${results.count} that suit ${chosenTheme.name}` + (loading ? " · looking…" : ` · ${page} of ${lastPage} pages searched`)
        return `${total.toLocaleString(Qt.locale(), "f", 0)} wallpapers · page ${page} of ${lastPage}`
    }

    ListModel {
        id: resultModel
    }
    property alias results: resultModel

    Timer {
        id: refilter
        interval: 300
        onTriggered: root.search()
    }

    Timer {
        id: saveTimer
        interval: 500
        onTriggered: {
            const out = {}
            for (const k of root.savedKeys)
                out[k] = root[k]
            settingsFile.setText(JSON.stringify(out, null, 2) + "\n")
        }
    }

    FileView {
        id: settingsFile
        path: root.settingsPath
        preload: false
    }

    Process {
        id: settingsReader
        running: true
        command: ["cat", root.settingsPath]
        stdout: StdioCollector {
            onStreamFinished: {
                if (text.trim()) {
                    try {
                        const s = JSON.parse(text)
                        for (const k of root.savedKeys)
                            if (s[k] !== undefined && typeof s[k] === typeof root[k])
                                root[k] = s[k]
                    } catch (e) {
                        console.warn("Wallhaven: unreadable settings:", e)
                    }
                }
                root.settingsLoaded = true
                if (root.open && root.results.count === 0)
                    root.search()
            }
        }
    }

    Process {
        id: themeLister
        command: [root.bin + "rice-theme", "list", "--json"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.themes = JSON.parse(text).filter(t => t.id !== "wallpaper" && t.accent).map(t => Object.assign({}, t, {
                        labAll: t.palette.map(root.lab), labBg: root.lab(t.background), labAccent: root.lab(t.accent)
                    }))
                } catch (e) {
                    console.warn("Wallhaven: rice-theme list: " + e)
                }
                // A saved Theme filter can only apply once the themes are here.
                if (root.themeFilter && root.open && root.settingsLoaded)
                    root.search()
            }
        }
    }

    Process {
        id: libraryLister
        command: ["find", root.wallDir, "-maxdepth", "1", "-name", "wallhaven-*"]
        stdout: StdioCollector {
            onStreamFinished: {
                const ids = {}
                for (const line of text.split("\n")) {
                    const m = /\/wallhaven-([A-Za-z0-9]+)\.[^\/]+$/.exec(line)
                    if (m)
                        ids[m[1]] = true
                }
                root.library = ids
            }
        }
    }

    Process {
        id: downloader
        onExited: code => {
            const id = root.downloading
            root.downloading = ""
            if (code === 0) {
                root.applied = id
                const lib = Object.assign({}, root.library)
                lib[id] = true
                root.library = lib
            } else {
                root.error = "Download failed"
            }
        }
    }

    component Chip: Rectangle {
        id: chip

        property string label: ""
        property bool on: false
        property bool active: true
        property string dot: ""            // a colour swatch before the label (theme accents)

        signal clicked

        implicitHeight: 32
        implicitWidth: chipText.implicitWidth + 28 + (dot ? 16 : 0)
        radius: 16
        color: on ? Theme.primary : chipArea.containsMouse ? Theme.alpha(Theme.primary, 0.16) : Theme.surface_container_high
        border.width: on ? 0 : 1
        border.color: Theme.alpha(Theme.outline_variant, 0.8)
        opacity: active ? 1 : 0.4
        Behavior on color {
            ColorAnimation { duration: 120 }
        }

        Rectangle {
            visible: !!chip.dot
            anchors.verticalCenter: parent.verticalCenter
            x: 12
            width: 10
            height: 10
            radius: 5
            color: chip.dot || "transparent"
            border.width: 1
            border.color: Theme.alpha(chip.on ? Theme.on_primary : Theme.on_surface, 0.4)
        }

        Text {
            id: chipText
            anchors.centerIn: parent
            anchors.horizontalCenterOffset: chip.dot ? 8 : 0
            text: chip.label
            color: chip.on ? Theme.on_primary : Theme.on_surface
            font.family: Theme.font
            font.pixelSize: 14
            font.weight: chip.on ? Font.DemiBold : Font.Normal
        }

        MouseArea {
            id: chipArea
            anchors.fill: parent
            hoverEnabled: true
            enabled: chip.active
            cursorShape: Qt.PointingHandCursor
            onClicked: chip.clicked()
        }
    }

    component FilterRow: RowLayout {
        id: filterRow

        property string title: ""
        default property alias chips: flow.data

        Layout.fillWidth: true
        spacing: 14

        Text {
            Layout.preferredWidth: 92
            Layout.alignment: Qt.AlignTop
            topPadding: 7
            text: filterRow.title
            color: Theme.on_surface_variant
            font.family: Theme.font
            font.pixelSize: 14
            font.weight: Font.DemiBold
        }

        Flow {
            id: flow
            Layout.fillWidth: true
            spacing: 8
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
            WlrLayershell.namespace: "rice-wallhaven"
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

            Rectangle {
                anchors.fill: parent
                color: Qt.rgba(0, 0, 0, 0.35)
                MouseArea {
                    anchors.fill: parent
                    onClicked: root.close()
                }
            }

            Rectangle {
                id: card
                anchors.centerIn: parent
                width: Math.min(parent.width - 100, 1560)
                height: Math.min(parent.height - 100, 1120)
                radius: 26
                color: Theme.alpha(Theme.surface_container, 0.97)
                border.width: 1
                border.color: Theme.alpha(Theme.outline_variant, 0.7)

                opacity: 0
                scale: 0.97
                Component.onCompleted: {
                    opacity = 1
                    scale = 1
                }
                Behavior on opacity {
                    NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
                }
                Behavior on scale {
                    NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
                }

                MouseArea {
                    anchors.fill: parent        // keep clicks on the card from closing it
                }

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 28
                    spacing: 18

                    // Title + search
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 16

                        LucideIcon {
                            icon: "image"
                            size: 28
                            color: Theme.primary
                        }

                        Text {
                            text: "Wallhaven"
                            color: Theme.on_surface
                            font.family: Theme.font
                            font.pixelSize: 26
                            font.weight: Font.Bold
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 44
                            Layout.leftMargin: 10
                            radius: 22
                            color: Theme.surface_container_high
                            border.width: 1
                            border.color: search.activeFocus ? Theme.primary : Theme.outline_variant

                            LucideIcon {
                                id: searchIcon
                                anchors.left: parent.left
                                anchors.leftMargin: 16
                                anchors.verticalCenter: parent.verticalCenter
                                icon: "search"
                                size: 18
                                color: Theme.on_surface_variant
                            }

                            Text {
                                anchors.fill: search
                                verticalAlignment: Text.AlignVCenter
                                visible: !search.text
                                text: "Search wallhaven - tags, #tag, @user, like:id…  (empty searches everything)"
                                color: Theme.on_surface_variant
                                font.family: Theme.font
                                font.pixelSize: 16
                            }

                            TextInput {
                                id: search
                                anchors.fill: parent
                                anchors.leftMargin: 46
                                anchors.rightMargin: 18
                                verticalAlignment: TextInput.AlignVCenter
                                clip: true
                                focus: true
                                text: root.query
                                color: Theme.on_surface
                                selectionColor: Theme.primary_container
                                font.family: Theme.font
                                font.pixelSize: 16
                                Component.onCompleted: {
                                    forceActiveFocus()
                                    selectAll()
                                }
                                onAccepted: {
                                    root.query = text
                                    saveTimer.restart()
                                    root.search()
                                }
                                Keys.onEscapePressed: root.close()
                            }
                        }

                        DashButton {
                            icon: "search"
                            accent: true
                            size: 44
                            onClicked: {
                                root.query = search.text
                                saveTimer.restart()
                                root.search()
                            }
                        }

                        DashButton {
                            icon: "x"
                            size: 44
                            onClicked: root.close()
                        }
                    }

                    // Filters
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: filters.implicitHeight + 32
                        radius: 18
                        color: Theme.alpha(Theme.surface_container_low, 0.8)

                        ColumnLayout {
                            id: filters
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.margins: 16
                            spacing: 10

                            FilterRow {
                                title: "Categories"
                                Chip { label: "General"; on: root.general; onClicked: root.setFilter("general", !root.general) }
                                Chip { label: "Anime"; on: root.anime; onClicked: root.setFilter("anime", !root.anime) }
                                Chip { label: "People"; on: root.people; onClicked: root.setFilter("people", !root.people) }

                                Item { width: 26; height: 32 }

                                Text {
                                    height: 32
                                    verticalAlignment: Text.AlignVCenter
                                    text: "Purity"
                                    color: Theme.on_surface_variant
                                    font.family: Theme.font
                                    font.pixelSize: 14
                                    font.weight: Font.DemiBold
                                    rightPadding: 6
                                }
                                Chip { label: "SFW"; on: root.sfw; onClicked: root.setFilter("sfw", !root.sfw) }
                                Chip { label: "Sketchy"; on: root.sketchy; onClicked: root.setFilter("sketchy", !root.sketchy) }
                                Chip {
                                    label: root.apikey ? "NSFW" : "NSFW (needs API key)"
                                    on: root.nsfw && root.apikey !== ""
                                    active: root.apikey !== ""
                                    onClicked: root.setFilter("nsfw", !root.nsfw)
                                }
                            }

                            FilterRow {
                                title: "Sort by"
                                Repeater {
                                    model: root.sorts
                                    Chip {
                                        required property var modelData
                                        label: modelData.label
                                        on: root.sorting === modelData.id
                                        onClicked: root.setFilter("sorting", modelData.id)
                                    }
                                }

                                Item { width: 14; height: 32 }

                                Chip {
                                    label: root.order === "desc" ? "↓  Descending" : "↑  Ascending"
                                    active: root.sorting !== "random"
                                    onClicked: root.setFilter("order", root.order === "desc" ? "asc" : "desc")
                                }
                            }

                            FilterRow {
                                title: "Top of the"
                                visible: root.sorting === "toplist"
                                Repeater {
                                    model: root.ranges
                                    Chip {
                                        required property var modelData
                                        label: modelData.label
                                        on: root.topRange === modelData.id
                                        onClicked: root.setFilter("topRange", modelData.id)
                                    }
                                }
                            }

                            FilterRow {
                                title: "Resolution"
                                Repeater {
                                    model: root.resolutions
                                    Chip {
                                        required property var modelData
                                        label: modelData.label
                                        on: root.atleast === modelData.id
                                        onClicked: root.setFilter("atleast", modelData.id)
                                    }
                                }

                                Item { width: 26; height: 32 }

                                Text {
                                    height: 32
                                    verticalAlignment: Text.AlignVCenter
                                    text: "Ratio"
                                    color: Theme.on_surface_variant
                                    font.family: Theme.font
                                    font.pixelSize: 14
                                    font.weight: Font.DemiBold
                                    rightPadding: 6
                                }
                                Repeater {
                                    model: root.ratioOptions
                                    Chip {
                                        required property var modelData
                                        label: modelData.label
                                        on: root.ratios === modelData.id
                                        onClicked: root.setFilter("ratios", modelData.id)
                                    }
                                }
                            }

                            FilterRow {
                                title: "Colour"
                                visible: root.themeFilter === ""     // a Theme filter picks the colour
                                Chip { label: "Any"; on: root.colour === ""; onClicked: root.setFilter("colour", "") }
                                Repeater {
                                    model: root.colours
                                    Rectangle {
                                        required property string modelData
                                        readonly property bool picked: root.colour === modelData
                                        width: 32
                                        height: 32
                                        radius: 16
                                        color: "#" + modelData
                                        border.width: picked ? 3 : 1
                                        border.color: picked ? Theme.primary : Theme.alpha(Theme.on_surface, 0.25)
                                        scale: swatchArea.containsMouse ? 1.12 : 1
                                        Behavior on scale {
                                            NumberAnimation { duration: 100 }
                                        }
                                        MouseArea {
                                            id: swatchArea
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: root.setFilter("colour", parent.picked ? "" : parent.modelData)
                                        }
                                    }
                                }
                            }

                            FilterRow {
                                title: "Theme"
                                Chip { label: "Any"; on: root.themeFilter === ""; onClicked: root.setFilter("themeFilter", "") }
                                Repeater {
                                    model: root.themes
                                    Chip {
                                        required property var modelData
                                        label: modelData.name
                                        dot: modelData.accent
                                        on: root.themeFilter === modelData.id
                                        onClicked: root.setFilter("themeFilter", on ? "" : modelData.id)
                                    }
                                }
                            }
                        }
                    }

                    // Status
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 10

                        Text {
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            text: root.statusText()
                            color: root.error ? Theme.error : Theme.on_surface_variant
                            font.family: Theme.font
                            font.pixelSize: 15
                        }

                        Text {
                            text: "Click  apply     Right-click  open page     Esc  close"
                            color: Theme.on_surface_variant
                            font.family: Theme.font
                            font.pixelSize: 14
                        }
                    }

                    // Results
                    GridView {
                        id: grid
                        readonly property int columns: Math.max(2, Math.floor(width / 290))

                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        model: results
                        cellWidth: width / columns
                        cellHeight: Math.round(cellWidth * 0.66)
                        boundsBehavior: Flickable.StopAtBounds
                        onAtYEndChanged: if (atYEnd) root.more()
                        onCountChanged: if (count === 0) positionViewAtBeginning()

                        delegate: Item {
                            id: tile
                            required property string wid
                            required property string thumb
                            required property string full
                            required property string link
                            required property string resolution
                            required property int favorites
                            required property string category
                            required property string purity
                            required property int size
                            required property string themeName
                            required property string themeAccent
                            readonly property bool owned: root.library[wid] === true
                            readonly property bool busy: root.downloading === wid

                            width: grid.cellWidth
                            height: grid.cellHeight

                            ClippingRectangle {
                                anchors.fill: parent
                                anchors.margins: 7
                                radius: 14
                                color: Theme.surface_container_high
                                border.width: root.applied === tile.wid ? 3 : 0
                                border.color: Theme.primary
                                scale: tileArea.containsMouse ? 1.03 : 1
                                Behavior on scale {
                                    NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
                                }

                                Image {
                                    id: thumbImage
                                    anchors.fill: parent
                                    source: tile.thumb
                                    fillMode: Image.PreserveAspectCrop
                                    asynchronous: true
                                    opacity: status === Image.Ready ? 1 : 0
                                    Behavior on opacity {
                                        NumberAnimation { duration: 200 }
                                    }
                                }

                                // Hover details
                                Rectangle {
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.bottom: parent.bottom
                                    height: 46
                                    opacity: tileArea.containsMouse ? 1 : 0
                                    Behavior on opacity {
                                        NumberAnimation { duration: 140 }
                                    }
                                    gradient: Gradient {
                                        GradientStop { position: 0.0; color: "transparent" }
                                        GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.75) }
                                    }

                                    Text {
                                        anchors.left: parent.left
                                        anchors.bottom: parent.bottom
                                        anchors.margins: 10
                                        text: `${tile.resolution}  ·  ${root.sizeText(tile.size)}`
                                        color: "white"
                                        font.family: Theme.font
                                        font.pixelSize: 13
                                        font.weight: Font.DemiBold
                                    }

                                    Row {
                                        anchors.right: parent.right
                                        anchors.bottom: parent.bottom
                                        anchors.margins: 10
                                        spacing: 5
                                        LucideIcon {
                                            anchors.verticalCenter: parent.verticalCenter
                                            icon: "star"
                                            size: 13
                                            color: "white"
                                        }
                                        Text {
                                            text: tile.favorites
                                            color: "white"
                                            font.family: Theme.font
                                            font.pixelSize: 13
                                        }
                                    }
                                }

                                // The theme it fits best (what `rice-theme sort` would pick)
                                Rectangle {
                                    visible: !!tile.themeName
                                    anchors.top: parent.top
                                    anchors.left: parent.left
                                    anchors.margins: 8
                                    width: tagRow.implicitWidth + 16
                                    height: 22
                                    radius: 11
                                    color: Qt.rgba(0, 0, 0, 0.6)
                                    Row {
                                        id: tagRow
                                        anchors.centerIn: parent
                                        spacing: 6
                                        Rectangle {
                                            anchors.verticalCenter: parent.verticalCenter
                                            width: 8
                                            height: 8
                                            radius: 4
                                            color: tile.themeAccent || "white"
                                        }
                                        Text {
                                            text: tile.themeName
                                            color: "white"
                                            font.family: Theme.font
                                            font.pixelSize: 11
                                            font.weight: Font.DemiBold
                                        }
                                    }
                                }

                                // Already in the folder
                                Rectangle {
                                    visible: tile.owned && !tile.busy
                                    anchors.top: parent.top
                                    anchors.right: parent.right
                                    anchors.margins: 8
                                    width: 26
                                    height: 26
                                    radius: 13
                                    color: Theme.primary
                                    LucideIcon {
                                        anchors.centerIn: parent
                                        icon: "check"
                                        size: 15
                                        color: Theme.on_primary
                                    }
                                }

                                Rectangle {
                                    anchors.fill: parent
                                    visible: tile.busy
                                    color: Qt.rgba(0, 0, 0, 0.5)
                                    LucideIcon {
                                        anchors.centerIn: parent
                                        icon: "loader-circle"
                                        size: 34
                                        color: "white"
                                        RotationAnimation on rotation {
                                            running: tile.busy
                                            from: 0
                                            to: 360
                                            duration: 900
                                            loops: Animation.Infinite
                                        }
                                    }
                                }
                            }

                            MouseArea {
                                id: tileArea
                                anchors.fill: parent
                                hoverEnabled: true
                                acceptedButtons: Qt.LeftButton | Qt.RightButton
                                cursorShape: root.downloading ? Qt.BusyCursor : Qt.PointingHandCursor
                                onClicked: mouse => {
                                    if (mouse.button === Qt.RightButton)
                                        Quickshell.execDetached(["xdg-open", tile.link])
                                    else
                                        root.download(tile)
                                }
                            }
                        }

                        footer: Item {
                            width: grid.width
                            height: root.page > 0 && root.page < root.lastPage ? 60 : 0
                            visible: height > 0

                            Chip {
                                anchors.centerIn: parent
                                label: root.loading ? "Loading…" : "Load more"
                                active: !root.loading
                                onClicked: root.more()
                            }
                        }
                    }
                }
            }
        }
    }
}
