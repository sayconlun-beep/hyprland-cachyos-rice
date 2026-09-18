// The lock screen's content, shared by the real lock (one per monitor) and
// the preview window. See Lock.qml for the safety notes.
import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets

Item {
    id: surface

    property var lock
    property bool preview: false
    property date now: new Date()
    property string armed: ""               // restart / poweroff waiting for a second click

    readonly property string home: Quickshell.env("HOME")

    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: surface.now = new Date()
    }

    Timer {
        id: disarm
        interval: 3000
        onTriggered: surface.armed = ""
    }

    Connections {
        target: surface.lock
        function onFailed() {
            input.text = ""
            shake.restart()
            input.forceActiveFocus()
        }
    }

    function power(action) {
        if (surface.preview)
            return
        if (action !== "suspend" && armed !== action) {
            armed = action
            disarm.restart()
            return
        }
        armed = ""
        Quickshell.execDetached(["systemctl", action])
    }

    // ------------------------------------------------------------ backdrop --
    Image {
        id: wallpaper
        anchors.fill: parent
        source: "file://" + surface.home + "/.cache/rice/wallpaper"
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: false
        visible: false
    }

    // A light blur, so the wallpaper still reads as itself, and a scrim that
    // is darker only where the text sits (top clock, bottom power row).
    MultiEffect {
        anchors.fill: parent
        source: wallpaper
        blurEnabled: true
        blur: 0.3
        blurMax: 40
        brightness: -0.05
        saturation: 0.15
    }

    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.0; color: Qt.rgba(0, 0, 0, 0.30) }
            GradientStop { position: 0.35; color: Qt.rgba(0, 0, 0, 0.12) }
            GradientStop { position: 0.7; color: Qt.rgba(0, 0, 0, 0.18) }
            GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.50) }
        }
    }

    MouseArea {
        anchors.fill: parent
        onClicked: input.forceActiveFocus()
    }

    // --------------------------------------------------------------- clock --
    // The desktop clock (DesktopClock.qml), in the same place and style.
    Item {
        anchors.fill: parent

        layer.enabled: true
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: Qt.rgba(0, 0, 0, 0.55)
            shadowBlur: 0.9
            shadowVerticalOffset: 3
        }

        Column {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            anchors.topMargin: Math.round(surface.height * 0.12) + 10
            spacing: 2

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: Qt.formatDate(surface.now, "dddd, MMMM d, yyyy")
                color: Theme.on_surface
                opacity: 0.65
                font.family: Theme.mono
                font.pixelSize: 20
            }

            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 8

                Text {
                    id: bigTime
                    text: Qt.formatTime(surface.now, "h:mm:ss")
                    color: Theme.primary
                    font.family: Theme.font
                    font.pixelSize: 96
                    font.weight: Font.Light
                    font.features: { "tnum": 1 }
                }

                Text {
                    anchors.baseline: bigTime.baseline
                    text: Qt.formatTime(surface.now, "AP")
                    color: Theme.primary
                    opacity: 0.7
                    font.family: Theme.font
                    font.pixelSize: 23
                }
            }
        }
    }

    // ------------------------------------------------------------- content --
    // Username and password, sitting just above the power buttons.
    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: powerRow.top
        anchors.bottomMargin: 28
        width: 440
        spacing: 12

        layer.enabled: true
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: "black"
            shadowOpacity: 0.55
            shadowBlur: 0.9
            shadowVerticalOffset: 2
        }

        Text {
            Layout.alignment: Qt.AlignHCenter
            text: Quickshell.env("USER") || ""
            color: "white"
            font.family: Theme.font
            font.pixelSize: 17
            font.weight: Font.DemiBold
        }

        Rectangle {
            id: field
            Layout.alignment: Qt.AlignHCenter
            implicitWidth: 360
            implicitHeight: 52
            radius: 10
            color: Theme.alpha(Theme.surface_container, 0.55)
            border.width: 2
            border.color: surface.lock && surface.lock.error ? Theme.error : Theme.primary
            Behavior on border.color {
                ColorAnimation { duration: 150 }
            }

            transform: Translate { id: shakeOffset }

            SequentialAnimation {
                id: shake
                NumberAnimation { target: shakeOffset; property: "x"; to: -14; duration: 50 }
                NumberAnimation { target: shakeOffset; property: "x"; to: 14; duration: 70 }
                NumberAnimation { target: shakeOffset; property: "x"; to: -9; duration: 60 }
                NumberAnimation { target: shakeOffset; property: "x"; to: 9; duration: 60 }
                NumberAnimation { target: shakeOffset; property: "x"; to: 0; duration: 50 }
            }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 22
                anchors.rightMargin: 7
                spacing: 12

                LucideIcon {
                    icon: "lock"
                    size: 18
                    color: "white"
                    opacity: 0.8
                }

                TextInput {
                    id: input
                    Layout.fillWidth: true
                    echoMode: TextInput.Password
                    passwordCharacter: "●"
                    color: "white"
                    font.family: Theme.font
                    font.pixelSize: 18
                    clip: true
                    focus: true
                    enabled: !(surface.lock && surface.lock.busy)
                    Component.onCompleted: forceActiveFocus()
                    onTextChanged: if (text && surface.lock) surface.lock.error = ""
                    Keys.onReturnPressed: surface.lock.submit(text)
                    Keys.onEnterPressed: surface.lock.submit(text)
                    Keys.onEscapePressed: {
                        if (text)
                            text = ""
                        else if (surface.preview)
                            surface.lock.endPreview()
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: !input.text
                        text: "Password"
                        color: "white"
                        opacity: 0.45
                        font: input.font
                    }
                }

                Rectangle {
                    implicitWidth: 38
                    implicitHeight: 38
                    radius: 7
                    color: Theme.primary

                    LucideIcon {
                        id: submitIcon
                        anchors.centerIn: parent
                        icon: surface.lock && surface.lock.busy ? "loader-circle" : "arrow-right"
                        size: 18
                        color: Theme.on_primary

                        NumberAnimation on rotation {
                            running: surface.lock && surface.lock.busy
                            from: 0
                            to: 360
                            duration: 900
                            loops: Animation.Infinite
                            onRunningChanged: if (!running) submitIcon.rotation = 0
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: surface.lock.submit(input.text)
                    }
                }
            }
        }

        Text {
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredHeight: 20
            text: surface.lock ? surface.lock.error : ""
            color: Theme.error
            font.family: Theme.font
            font.pixelSize: 14
            font.weight: Font.DemiBold
        }

        Text {
            Layout.alignment: Qt.AlignHCenter
            visible: surface.preview
            text: "Preview - nothing is locked. Try your password, or Esc to close."
            color: "white"
            opacity: 0.75
            font.family: Theme.font
            font.pixelSize: 13
        }

    }

    // ------------------------------------------------------ bottom right --
    // What's playing and what Steam is downloading.
    ColumnLayout {
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 40
        spacing: 12

        layer.enabled: true
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: "black"
            shadowOpacity: 0.55
            shadowBlur: 0.9
            shadowVerticalOffset: 2
        }

        // What's playing
        Rectangle {
            Layout.alignment: Qt.AlignRight
            visible: MediaState.player !== null
            implicitWidth: Math.min(nowRow.implicitWidth + 30, 440)
            implicitHeight: 48
            radius: 10
            color: Theme.alpha(Theme.surface_container, 0.5)

            RowLayout {
                id: nowRow
                anchors.fill: parent
                anchors.leftMargin: 18
                anchors.rightMargin: 6
                spacing: 12

                LucideIcon {
                    icon: "music"
                    size: 16
                    color: Theme.primary
                }

                Text {
                    Layout.maximumWidth: 320
                    text: MediaState.title + (MediaState.artist ? "  ·  " + MediaState.artist : "")
                    elide: Text.ElideRight
                    color: "white"
                    font.family: Theme.font
                    font.pixelSize: 14
                }

                DashButton {
                    icon: MediaState.playing ? "pause" : "play"
                    size: 36
                    iconSize: 16
                    accent: true
                    onClicked: MediaState.toggle()
                }
            }
        }
        // What Steam is downloading
        Rectangle {
            Layout.alignment: Qt.AlignRight
            visible: SteamDownloads.active
            implicitWidth: 440
            implicitHeight: 84
            radius: 20
            color: Theme.alpha(Theme.surface_container, 0.5)
            border.width: 1
            border.color: Theme.alpha(Theme.primary, 0.25)

            RowLayout {
                anchors.fill: parent
                anchors.margins: 12
                spacing: 14

                ClippingRectangle {
                    implicitWidth: 128
                    implicitHeight: 60
                    radius: 10
                    color: Theme.alpha(Theme.primary, 0.15)

                    Image {
                        id: steamArt
                        anchors.fill: parent
                        source: SteamDownloads.art ? "file://" + SteamDownloads.art : ""
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        sourceSize.width: 256
                        visible: status === Image.Ready
                    }

                    LucideIcon {
                        anchors.centerIn: parent
                        visible: steamArt.status !== Image.Ready
                        icon: "download"
                        size: 22
                        color: Theme.primary
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 6

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        Text {
                            Layout.fillWidth: true
                            text: SteamDownloads.name
                            elide: Text.ElideRight
                            color: "white"
                            font.family: Theme.font
                            font.pixelSize: 14
                            font.weight: Font.DemiBold
                        }

                        Text {
                            text: SteamDownloads.status === "Downloading"
                                  ? Math.floor(SteamDownloads.progress * 100) + "%"
                                  : SteamDownloads.status
                            color: Theme.primary
                            font.family: Theme.font
                            font.pixelSize: 14
                            font.weight: Font.Bold
                            font.features: { "tnum": 1 }
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 6
                        radius: 3
                        color: Theme.alpha("white", 0.15)

                        Rectangle {
                            width: parent.width * SteamDownloads.progress
                            height: parent.height
                            radius: 3
                            color: Theme.primary
                            Behavior on width {
                                NumberAnimation { duration: 600; easing.type: Easing.OutCubic }
                            }
                        }
                    }

                    Text {
                        Layout.fillWidth: true
                        text: [SteamDownloads.rate > 0 && SteamDownloads.status === "Downloading"
                                   ? (SteamDownloads.rate / 8).toFixed(1) + " MB/s" : "",
                               SteamDownloads.etaText].filter(x => x).join("  ·  ") || "Steam"
                        elide: Text.ElideRight
                        color: "white"
                        opacity: 0.7
                        font.family: Theme.font
                        font.pixelSize: 12
                        font.features: { "tnum": 1 }
                    }
                }
            }
        }
    }

    // ---------------------------------------------------------------- power --
    Row {
        id: powerRow
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 50
        spacing: 26
        opacity: surface.preview ? 0.4 : 1

        Repeater {
            model: [
                { action: "suspend", icon: "moon", label: "Suspend" },
                { action: "reboot", icon: "rotate-ccw", label: "Restart" },
                { action: "poweroff", icon: "power", label: "Power off" }
            ]

            Column {
                required property var modelData
                readonly property bool isArmed: surface.armed === modelData.action
                spacing: 8

                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 56
                    height: 56
                    radius: 28
                    color: isArmed ? Theme.error
                         : powerArea.containsMouse ? Theme.alpha(Theme.primary, 0.35) : Theme.alpha(Theme.surface_container, 0.5)

                    LucideIcon {
                        anchors.centerIn: parent
                        icon: modelData.icon
                        size: 22
                        color: isArmed ? Theme.on_error : "white"
                    }

                    MouseArea {
                        id: powerArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: surface.preview ? Qt.ArrowCursor : Qt.PointingHandCursor
                        onClicked: surface.power(modelData.action)
                    }
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: isArmed ? "Click again" : modelData.label
                    color: "white"
                    opacity: 0.8
                    font.family: Theme.font
                    font.pixelSize: 12
                }
            }
        }
    }
}
