// A menu row's icon, whichever kind menu.jsonc gives: a Lucide name from
// ./icons ("palette"), a Nerd Font glyph, an app's theme icon (appIcon), or a
// colour swatch (swatch: a theme's accent).
import QtQuick
import Quickshell

Item {
    id: root

    property string icon: ""
    property string appIcon: ""
    property string swatch: ""
    property int size: 18
    property color color: Theme.primary

    readonly property bool lucide: !appIcon && !swatch && /^[a-z0-9-]+$/.test(icon)

    implicitWidth: size
    implicitHeight: size

    LucideIcon {
        anchors.centerIn: parent
        visible: root.lucide
        icon: root.lucide ? root.icon : ""
        size: root.size
        color: root.color
    }

    Text {
        anchors.centerIn: parent
        visible: !root.appIcon && !root.swatch && !root.lucide
        text: root.lucide ? "" : root.icon
        color: root.color
        font.family: Theme.mono
        font.pixelSize: root.size
    }

    Rectangle {
        anchors.centerIn: parent
        visible: !!root.swatch
        width: root.size - 2
        height: width
        radius: width / 2
        color: root.swatch || "transparent"
        border.width: 1
        border.color: Theme.alpha(Theme.on_surface, 0.5)
    }

    Image {
        anchors.centerIn: parent
        visible: !!root.appIcon
        width: root.size + 6
        height: root.size + 6
        sourceSize.width: width * 2
        sourceSize.height: height * 2
        asynchronous: true
        fillMode: Image.PreserveAspectFit
        source: !root.appIcon ? ""
            : root.appIcon.startsWith("/") ? "file://" + root.appIcon
            : (Quickshell.iconPath(root.appIcon, true) || Quickshell.iconPath("application-x-executable"))
    }
}
