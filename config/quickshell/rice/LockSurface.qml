// The lock screen's content, shared by the real lock (one per monitor) and
// the preview window. See Lock.qml for the safety notes.
//
// Laid out like a Frieren-themed login screen - one column on the left over
// the current wallpaper, undimmed:
//
//   CACHYOS / ──◇── / theme name, a big clock and the date, the user, the
//   password pill (the eye shows it), Unlock; "Locked" and small power
//   buttons along the bottom.
//
// What's playing and what Steam is downloading stay at the bottom right.
import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Widgets

Item {
    id: surface

    property var lock
    property bool preview: false
    property date now: new Date()
    property string armed: ""               // restart / poweroff waiting for a second click
    property string osName: "Linux"
    property string themeName: ""
    property bool reveal: false             // the eye: show the password as typed

    // The column: centred on the left fifth of the screen, a fifth wide.
    readonly property real colW: Math.round(Math.min(width * 0.2, 480))
    readonly property real colX: Math.round(width * 0.2 - colW / 2)
    readonly property real u: height / 100  // 1% of the height
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

    FileView {
        path: "/etc/os-release"
        onLoaded: {
            const m = /^PRETTY_NAME="?([^"\n]*)"?/m.exec(text())
            if (m)
                surface.osName = m[1].replace(/ Linux$/, "")
        }
    }

    // The rice's theme ("tokyo-night" -> "Tokyo Night"); none for the wallpaper theme.
    FileView {
        path: surface.home + "/.cache/rice/theme"
        printErrors: false
        onLoaded: surface.themeName = text().trim().replace(/[-_]+/g, " ").replace(/\b\w/g, c => c.toUpperCase())
        onLoadFailed: surface.themeName = ""
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
    // The wallpaper as it is, sharp and undimmed; only a soft shade behind the
    // column so white text stays readable on a bright picture.
    Image {
        anchors.fill: parent
        source: "file://" + surface.home + "/.cache/rice/wallpaper"
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: false
    }

    Rectangle {
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        width: parent.width * 0.5
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0; color: Qt.rgba(0, 0, 0, 0.30) }
            GradientStop { position: 0.55; color: Qt.rgba(0, 0, 0, 0.12) }
            GradientStop { position: 1.0; color: "transparent" }
        }
    }

    MouseArea {
        anchors.fill: parent
        onClicked: input.forceActiveFocus()
    }

    // ----------------------------------------------------------- the column --
    Item {
        id: column
        anchors.fill: parent

        layer.enabled: true
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: Qt.rgba(0, 0, 0, 0.6)
            shadowBlur: 0.8
            shadowVerticalOffset: 2
        }

        // Title: the OS in spaced serif capitals, a rule, the theme's name.
        Column {
            x: surface.colX
            width: surface.colW
            y: Math.round(surface.u * 15)
            spacing: Math.round(surface.u * 0.6)

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: surface.osName.toUpperCase()
                color: "white"
                font.family: "Noto Serif"
                font.pixelSize: Math.round(surface.u * 3.6)
                font.letterSpacing: Math.round(surface.u * 0.9)
            }

            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: Math.round(surface.u * 0.8)

                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: surface.colW * 0.24
                    height: 1
                    color: Qt.rgba(1, 1, 1, 0.7)
                }
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.round(surface.u * 0.8)
                    height: width
                    rotation: 45
                    color: "transparent"
                    border.width: 1
                    border.color: Qt.rgba(1, 1, 1, 0.85)
                }
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: surface.colW * 0.24
                    height: 1
                    color: Qt.rgba(1, 1, 1, 0.7)
                }
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: surface.themeName || "Welcome back"
                color: "white"
                font.family: "Noto Serif"
                font.pixelSize: Math.round(surface.u * 2.3)
                font.letterSpacing: 0.5
            }
        }

        // The clock and date.
        Column {
            x: surface.colX
            width: surface.colW
            y: Math.round(surface.u * 25.5)
            spacing: 0

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: Qt.formatTime(surface.now, "h:mm")
                color: Qt.rgba(1, 1, 1, 0.88)
                font.family: Theme.font
                font.pixelSize: Math.round(surface.u * 10)
                font.weight: Font.Light
                font.features: { "tnum": 1 }
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: Qt.formatDate(surface.now, "dddd d MMMM")
                color: Qt.rgba(1, 1, 1, 0.9)
                font.family: Theme.font
                font.pixelSize: Math.round(surface.u * 2.4)
                font.weight: Font.Light
                font.letterSpacing: 1.5
            }
        }

        // User, password, Login.
        ColumnLayout {
            x: surface.colX
            width: surface.colW
            y: Math.round(surface.u * 52)
            spacing: Math.round(surface.u * 1.6)

            // (user)  name - the name centred in the row, like the field below
            Item {
                Layout.fillWidth: true
                implicitHeight: Math.round(surface.u * 3.4)

                LucideIcon {
                    anchors.verticalCenter: parent.verticalCenter
                    x: Math.round(surface.u * 1.4)
                    icon: "user"
                    size: Math.round(surface.u * 1.5)
                    color: "white"
                }

                Text {
                    anchors.centerIn: parent
                    text: (Quickshell.env("USER") || "").toUpperCase()
                    color: "white"
                    font.family: Theme.font
                    font.pixelSize: Math.round(surface.u * 1.25)
                    font.weight: Font.Bold
                    font.letterSpacing: 1
                }
            }

            // (eye)  password, in a pill
            Rectangle {
                id: field
                Layout.fillWidth: true
                implicitHeight: Math.round(surface.u * 3.4)
                radius: height / 2
                color: Qt.rgba(1, 1, 1, input.activeFocus ? 0.14 : 0.08)
                border.width: 1.5
                border.color: surface.lock && surface.lock.error ? Theme.error
                    : Qt.rgba(1, 1, 1, input.activeFocus ? 0.75 : 0.45)
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

                LucideIcon {
                    id: eye
                    anchors.verticalCenter: parent.verticalCenter
                    x: Math.round(surface.u * 1.4)
                    icon: surface.reveal ? "eye-off" : "eye"
                    size: Math.round(surface.u * 1.5)
                    color: "white"
                    opacity: eyeArea.containsMouse ? 1 : 0.8

                    MouseArea {
                        id: eyeArea
                        anchors.fill: parent
                        anchors.margins: -8
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            surface.reveal = !surface.reveal
                            input.forceActiveFocus()
                        }
                    }
                }

                TextInput {
                    id: input
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: eye.right
                    anchors.right: parent.right
                    anchors.leftMargin: Math.round(surface.u * 1)
                    anchors.rightMargin: Math.round(surface.u * 2.9)   // stay centred against the eye
                    horizontalAlignment: TextInput.AlignHCenter
                    echoMode: surface.reveal ? TextInput.Normal : TextInput.Password
                    passwordCharacter: "•"
                    color: "white"
                    font.family: Theme.font
                    font.pixelSize: Math.round(surface.u * 1.35)
                    font.letterSpacing: surface.reveal ? 0 : 2
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
                        anchors.centerIn: parent
                        visible: !input.text
                        text: "Password"
                        color: "white"
                        opacity: 0.5
                        font.family: Theme.font
                        font.pixelSize: input.font.pixelSize
                    }
                }
            }

            // Login
            Rectangle {
                Layout.fillWidth: true
                Layout.topMargin: Math.round(surface.u * 1)
                implicitHeight: Math.round(surface.u * 3.4)
                radius: height / 2
                color: Qt.rgba(1, 1, 1, loginArea.pressed ? 0.42 : loginArea.containsMouse ? 0.34 : 0.26)
                Behavior on color {
                    ColorAnimation { duration: 120 }
                }

                Row {
                    anchors.centerIn: parent
                    spacing: 8

                    LucideIcon {
                        id: spinner
                        anchors.verticalCenter: parent.verticalCenter
                        visible: surface.lock && surface.lock.busy
                        icon: "loader-circle"
                        size: Math.round(surface.u * 1.4)
                        color: "white"
                        NumberAnimation on rotation {
                            running: spinner.visible
                            from: 0
                            to: 360
                            duration: 900
                            loops: Animation.Infinite
                        }
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: surface.lock && surface.lock.busy ? "Unlocking" : "Unlock"
                        color: "white"
                        font.family: Theme.font
                        font.pixelSize: Math.round(surface.u * 1.3)
                        font.weight: Font.DemiBold
                    }
                }

                MouseArea {
                    id: loginArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: surface.lock.submit(input.text)
                }
            }

            Text {
                Layout.alignment: Qt.AlignHCenter
                Layout.preferredHeight: Math.round(surface.u * 2)
                text: surface.lock ? surface.lock.error : ""
                color: Theme.error
                font.family: Theme.font
                font.pixelSize: Math.round(surface.u * 1.2)
                font.weight: Font.DemiBold
            }
        }

        // Session, and the power buttons, small, along the bottom.
        Row {
            x: surface.colX
            y: Math.round(surface.u * 92)
            spacing: Math.round(surface.u * 1.6)

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: surface.armed === "reboot" ? "Click again to restart"
                    : surface.armed === "poweroff" ? "Click again to power off"
                    : surface.preview ? "Preview - Esc closes" : "Locked"
                color: surface.armed ? Theme.error : "white"
                opacity: surface.armed ? 1 : 0.85
                font.family: Theme.font
                font.pixelSize: Math.round(surface.u * 1.1)
            }

            Repeater {
                model: [
                    { action: "suspend", icon: "moon" },
                    { action: "reboot", icon: "rotate-ccw" },
                    { action: "poweroff", icon: "power" }
                ]

                LucideIcon {
                    required property var modelData
                    anchors.verticalCenter: parent.verticalCenter
                    icon: modelData.icon
                    size: Math.round(surface.u * 1.5)
                    color: surface.armed === modelData.action ? Theme.error : "white"
                    opacity: surface.preview ? 0.35 : powerArea.containsMouse || surface.armed === modelData.action ? 1 : 0.65

                    MouseArea {
                        id: powerArea
                        anchors.fill: parent
                        anchors.margins: -8
                        hoverEnabled: true
                        cursorShape: surface.preview ? Qt.ArrowCursor : Qt.PointingHandCursor
                        onClicked: surface.power(modelData.action)
                    }
                }
            }
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
}
