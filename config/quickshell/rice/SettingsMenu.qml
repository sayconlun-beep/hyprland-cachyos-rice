// Settings hub: the bar's gear (or Super+,) drops a panel down under the bar
// listing every settings panel there is - the rice's own and the system's.
//
// Picking an entry closes the hub and opens that panel. Entries that are a
// switch rather than a panel (visualiser, power profile) change in place and
// keep the hub open, showing their new state.
//
// The list itself is the "settings" branch of menu.jsonc, shared with the
// rice menu (Super+Space); each child submenu there is a section here.
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland

Scope {
    id: root

    property bool open: false
    property int sel: 0
    property var targetScreen: null

    // RiceMenu, wired up by shell.qml: the hub lists its "settings" branch
    // (menu.jsonc) and runs entries through it.
    property var menu: null

    readonly property var entries: menu ? menu.hubRows("settings") : []

    function show() {
        if (open)
            return
        targetScreen = focusedScreen()
        sel = 0
        open = true
    }

    function close() {
        open = false
    }

    function toggle() {
        open ? close() : show()
    }

    function activate(e) {
        if (!e)
            return
        if (!e.keep)
            close()
        menu.run(e)
    }

    function focusedScreen() {
        const name = Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : ""
        const screens = Quickshell.screens
        for (let i = 0; i < screens.length; i++)
            if (screens[i].name === name)
                return screens[i]
        return screens[0]
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
            // Over the bar too (the panel is pushed below it), so clicking the
            // bar closes the menu: exclusive focus sends every click here.
            exclusionMode: ExclusionMode.Ignore
            color: "transparent"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "rice-settings"
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

            // Anywhere outside the panel closes it.
            MouseArea {
                anchors.fill: parent
                onClicked: root.close()
            }

            Rectangle {
                id: panel
                anchors.top: parent.top
                anchors.right: parent.right
                anchors.topMargin: Theme.barHeight + 8
                anchors.rightMargin: 10
                width: 400
                height: Math.min(content.implicitHeight + 24, parent.height - Theme.barHeight - 20)
                radius: 22
                color: Theme.alpha(Theme.surface_container, 0.96)
                border.width: 1
                border.color: Theme.alpha(Theme.outline_variant, 0.7)

                transformOrigin: Item.TopRight
                opacity: 0
                scale: 0.96
                Component.onCompleted: {
                    opacity = 1
                    scale = 1
                    keys.forceActiveFocus()
                }
                Behavior on opacity {
                    NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
                }
                Behavior on scale {
                    NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
                }

                MouseArea {
                    anchors.fill: parent       // clicks inside do not close
                }

                Item {
                    id: keys
                    focus: true
                    Keys.onPressed: event => {
                        const n = root.entries.length
                        switch (event.key) {
                        case Qt.Key_Down: case Qt.Key_J: case Qt.Key_Tab:
                            root.sel = (root.sel + 1) % n; break
                        case Qt.Key_Up: case Qt.Key_K: case Qt.Key_Backtab:
                            root.sel = (root.sel - 1 + n) % n; break
                        case Qt.Key_Return: case Qt.Key_Enter: case Qt.Key_Space:
                            root.activate(root.entries[root.sel]); break
                        case Qt.Key_Escape:
                            root.close(); break
                        default:
                            return
                        }
                        event.accepted = true
                    }
                }

                Flickable {
                    id: flick
                    anchors.fill: parent
                    anchors.margins: 12
                    contentHeight: content.implicitHeight
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds

                    function ensureVisible(item) {
                        const p = item.mapToItem(content, 0, 0)
                        if (p.y < contentY)
                            contentY = Math.max(0, p.y - 30)
                        else if (p.y + item.height > contentY + height)
                            contentY = Math.min(contentHeight - height, p.y + item.height - height)
                    }

                    ColumnLayout {
                        id: content
                        width: flick.width
                        spacing: 2

                        Repeater {
                            model: root.entries

                            ColumnLayout {
                                id: entry
                                required property var modelData
                                required property int index
                                readonly property bool firstOfSection: index === 0
                                    || root.entries[index - 1].section !== modelData.section
                                readonly property bool selected: index === root.sel
                                readonly property var value: root.menu.valueOf(modelData)

                                Layout.fillWidth: true
                                spacing: 2

                                Text {
                                    visible: entry.firstOfSection
                                    Layout.topMargin: entry.index === 0 ? 4 : 12
                                    Layout.bottomMargin: 2
                                    Layout.leftMargin: 12
                                    text: entry.modelData.section
                                    color: Theme.primary
                                    font.family: Theme.font
                                    font.pixelSize: 12
                                    font.weight: Font.Bold
                                    font.capitalization: Font.AllUppercase
                                    font.letterSpacing: 1.2
                                }

                                Rectangle {
                                    id: row
                                    Layout.fillWidth: true
                                    implicitHeight: 38
                                    radius: 12
                                    color: entry.selected ? Theme.alpha(Theme.primary, 0.16) : "transparent"
                                    border.width: entry.selected ? 1 : 0
                                    border.color: Theme.alpha(Theme.primary, 0.5)

                                    Connections {
                                        target: entry
                                        function onSelectedChanged() {
                                            if (entry.selected)
                                                flick.ensureVisible(row)
                                        }
                                    }

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 12
                                        anchors.rightMargin: 10
                                        spacing: 12

                                        MenuIcon {
                                            Layout.preferredWidth: 22
                                            icon: entry.modelData.icon || ""
                                            size: 18
                                        }

                                        Text {
                                            text: entry.modelData.label
                                            color: Theme.on_surface
                                            font.family: Theme.font
                                            font.pixelSize: 14
                                        }

                                        Text {
                                            Layout.fillWidth: true
                                            elide: Text.ElideRight
                                            text: entry.modelData.hint || ""
                                            color: Theme.on_surface_variant
                                            font.family: Theme.font
                                            font.pixelSize: 12
                                        }

                                        Rectangle {
                                            visible: entry.value !== undefined
                                            implicitWidth: valueText.implicitWidth + 18
                                            implicitHeight: 24
                                            radius: 12
                                            color: entry.value === "Off"
                                                ? Theme.surface_container_highest
                                                : Theme.alpha(Theme.primary, 0.22)

                                            Text {
                                                id: valueText
                                                anchors.centerIn: parent
                                                text: entry.value || ""
                                                color: entry.value === "Off" ? Theme.on_surface_variant : Theme.primary
                                                font.family: Theme.font
                                                font.pixelSize: 12
                                                font.weight: Font.DemiBold
                                            }
                                        }
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onEntered: root.sel = entry.index
                                        onClicked: root.activate(entry.modelData)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
