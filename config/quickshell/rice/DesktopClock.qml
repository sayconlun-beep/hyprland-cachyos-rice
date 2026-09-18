// Desktop clock: the date, then a light time with seconds - centred in the upper
// part of every monitor, on the BOTTOM layer (on the wallpaper, under windows),
// so it shows whenever the desktop does. Takes no clicks.
//
//   qs -c rice ipc call clock toggle      (or the settings hub)
import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland

Scope {
    id: root

    property bool enabled: true

    readonly property bool use24h: false       // the bar shows 12-hour, so this does too
    readonly property real topFraction: 0.12   // band top, as a share of screen height
    readonly property int timeSize: 96
    readonly property int dateSize: 20

    property date now: new Date()

    function toggle() {
        enabled = !enabled
    }

    // Ticks on the second - the time shows seconds.
    Timer {
        running: root.enabled
        repeat: true
        interval: 1000
        triggeredOnStart: true
        onTriggered: root.now = new Date()
    }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            required property var modelData

            screen: modelData
            visible: root.enabled
            anchors {
                top: true
                left: true
                right: true
            }
            margins.top: Math.round(modelData.height * root.topFraction)
            implicitHeight: root.timeSize + root.dateSize + 90
            exclusionMode: ExclusionMode.Ignore
            color: "transparent"
            mask: Region {}
            WlrLayershell.layer: WlrLayer.Bottom
            WlrLayershell.namespace: "rice-clock"
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

            Item {
                anchors.fill: parent

                // A soft shadow keeps it readable on bright wallpapers.
                layer.enabled: true
                layer.effect: MultiEffect {
                    shadowEnabled: true
                    shadowColor: Qt.rgba(0, 0, 0, 0.55)
                    shadowBlur: 0.9
                    shadowVerticalOffset: 3
                }

                // Compact, after the user's reference video: a small monospace
                // date on top, then a light time with seconds.
                Column {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.top: parent.top
                    anchors.topMargin: 10
                    spacing: 2

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: Qt.formatDateTime(root.now, "dddd, MMMM d, yyyy")
                        color: Theme.on_surface
                        opacity: 0.65
                        font.family: Theme.mono
                        font.pixelSize: root.dateSize
                    }

                    Row {
                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: 8

                        // The accent colour, so the clock follows the wallpaper's palette.
                        Text {
                            id: time
                            text: Qt.formatDateTime(root.now, root.use24h ? "HH:mm:ss" : "h:mm:ss")
                            color: Theme.primary
                            Behavior on color {
                                ColorAnimation { duration: 400 }
                            }
                            font.family: Theme.font
                            font.pixelSize: root.timeSize
                            font.weight: Font.Light
                            font.features: { "tnum": 1 }    // digits keep their width
                        }

                        Text {
                            visible: !root.use24h
                            anchors.baseline: time.baseline
                            text: Qt.formatDateTime(root.now, "AP")
                            color: Theme.primary
                            Behavior on color {
                                ColorAnimation { duration: 400 }
                            }
                            opacity: 0.7
                            font.family: Theme.font
                            font.pixelSize: Math.round(root.timeSize * 0.24)
                            font.weight: Font.Normal
                        }
                    }
                }
            }
        }
    }
}
