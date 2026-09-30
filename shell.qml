//@ pragma UseQApplication
//@ pragma AppId dev.mock.island
//@ pragma ShellId mock-island

import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

ShellRoot {
    id: app

    readonly property string projectDir: Quickshell.env("MOCK_ISLAND_DIR") !== ""
        ? Quickshell.env("MOCK_ISLAND_DIR")
        : Quickshell.env("HOME") + "/Projects/mock-island"
    readonly property string bridge: projectDir + "/backend/ai_bridge.py"

    property bool shown: false
    property string targetScreen: ""
    signal focusRequested(string screenName)
    signal refreshRequested(string screenName)

    function openOn(screenName) {
        targetScreen = screenName || ""
        shown = true
        refreshRequested(targetScreen)
        focusRequested(targetScreen)
    }

    function closeIsland() {
        shown = false
    }

    IpcHandler {
        target: "mockIsland"

        function toggle(screenName: string): string {
            if (app.shown) {
                app.closeIsland()
                return "CLOSED"
            }
            app.openOn(screenName)
            return "OPEN"
        }

        function open(screenName: string): string {
            app.openOn(screenName)
            return "OPEN"
        }

        function close(): string {
            app.closeIsland()
            return "CLOSED"
        }

        function status(): string {
            return app.shown ? "OPEN" : "CLOSED"
        }
    }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: panel
            required property var modelData
            screen: modelData

            property bool busy: false
            property bool cancelRequested: false
            property bool pendingSendAfterConfig: false
            property string pendingPrompt: ""
            property string lastPrompt: ""
            property string streamPending: ""
            property string responseText: ""
            property bool advancedOpen: false
            property bool modelPickerOpen: false
            property bool showApiKey: false
            property string providerName: "mock"
            property string modelName: "mock-1"
            property string statusLabel: "Listo"
            property string probeMessage: "Mock listo · modo demo"
            property string catalogError: ""
            property bool providerOnline: true
            property bool providerLocal: true
            property bool providerHasKey: false
            property bool providerNeedsKey: false
            property bool providerSupportsKey: false
            property var providerModels: []
            property int modelCount: providerModels.length
            property bool hasResponse: responseText.length > 0
            property bool hasError: errorText.text.length > 0
            property double lastActivityMs: 0
            property real baseWindowHeight: advancedOpen ? 520 : (hasResponse ? 460 : (hasError ? 180 : 88))
            property real windowHeight: baseWindowHeight
            readonly property string mockMood: errorText.text !== "" ? "error" : (busy ? "thinking" : (!providerOnline ? "offline" : (hasResponse ? "happy" : "idle")))

            property color primary: "#9fc9ff"
            property color surface: "#11161c"
            property color surfaceContainer: "#171d24"
            property color surfaceHigh: "#1f2731"
            property color surfaceHighest: "#27313d"
            property color textColor: "#edf3fb"
            property color mutedColor: "#a9b4c0"
            property color outlineColor: "#51606f"
            property color errorColor: "#ffb4ab"

            visible: app.shown && (app.targetScreen === "" || screen.name === app.targetScreen)
            color: "transparent"
            implicitHeight: visible ? windowHeight + 16 : 1

            WlrLayershell.namespace: "mock-island"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.exclusiveZone: 0
            WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

            anchors {
                left: true
                right: true
                bottom: true
            }

            Behavior on implicitHeight {
                NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
            }

            mask: Region { item: islandCard }

            Rectangle {
                id: islandCard
                width: Math.min(860, panel.width - 40)
                height: panel.windowHeight
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 8
                radius: 24
                color: panel.surfaceContainer
                border.width: 1
                border.color: Qt.rgba(panel.primary.r, panel.primary.g, panel.primary.b, 0.30)
                clip: true

                opacity: panel.visible ? 1 : 0
                scale: panel.visible ? 1 : 0.96
                Behavior on opacity { NumberAnimation { duration: 130 } }
                Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutBack } }
                Behavior on height { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

                Rectangle {
                    anchors.fill: parent
                    radius: parent.radius
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: Qt.rgba(panel.primary.r, panel.primary.g, panel.primary.b, 0.065) }
                        GradientStop { position: 0.46; color: "transparent" }
                    }
                    z: -1
                }

                // Cabecera compacta: conserva la identidad de Mock v1.
                Item {
                    id: topRow
                    height: 76
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.leftMargin: 14
                    anchors.rightMargin: 14

                    Rectangle {
                        id: mascot
                        property bool blinking: false
                        property real lookX: 0
                        width: 52
                        height: 52
                        radius: 17
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        color: panel.busy
                            ? Qt.rgba(panel.primary.r, panel.primary.g, panel.primary.b, 0.18)
                            : panel.surfaceHigh
                        border.width: 1
                        border.color: panel.mockMood === "error"
                            ? Qt.rgba(panel.errorColor.r, panel.errorColor.g, panel.errorColor.b, 0.55)
                            : Qt.rgba(panel.primary.r, panel.primary.g, panel.primary.b, 0.16)
                        transformOrigin: Item.Center

                        SequentialAnimation on scale {
                            running: panel.visible
                            loops: Animation.Infinite
                            NumberAnimation { to: panel.busy ? 1.045 : 1.018; duration: panel.busy ? 420 : 1500; easing.type: Easing.InOutSine }
                            NumberAnimation { to: 1.0; duration: panel.busy ? 420 : 1500; easing.type: Easing.InOutSine }
                        }

                        SequentialAnimation on rotation {
                            running: panel.visible && panel.busy
                            loops: Animation.Infinite
                            NumberAnimation { to: -1.8; duration: 300; easing.type: Easing.InOutSine }
                            NumberAnimation { to: 1.8; duration: 600; easing.type: Easing.InOutSine }
                            NumberAnimation { to: 0; duration: 300; easing.type: Easing.InOutSine }
                        }

                        SequentialAnimation on lookX {
                            running: panel.visible && !mascotMouse.containsMouse && !panel.busy
                            loops: Animation.Infinite
                            PauseAnimation { duration: 1400 }
                            NumberAnimation { to: 1.6; duration: 170; easing.type: Easing.OutCubic }
                            PauseAnimation { duration: 650 }
                            NumberAnimation { to: -1.3; duration: 210; easing.type: Easing.OutCubic }
                            PauseAnimation { duration: 900 }
                            NumberAnimation { to: 0; duration: 170; easing.type: Easing.OutCubic }
                        }

                        Timer {
                            id: blinkTimer
                            running: panel.visible
                            repeat: true
                            interval: 2300
                            onTriggered: {
                                mascot.blinking = true
                                blinkReset.restart()
                                interval = 1700 + Math.floor(Math.random() * 3000)
                            }
                        }
                        Timer {
                            id: blinkReset
                            interval: 105
                            repeat: false
                            onTriggered: mascot.blinking = false
                        }

                        // Cara original, simple y reconocible: evolución directa de v1.
                        Rectangle {
                            id: face
                            width: 34
                            height: 28
                            radius: 11
                            anchors.centerIn: parent
                            color: panel.textColor
                            anchors.verticalCenterOffset: panel.busy ? -1 : 0

                            Rectangle {
                                width: 4
                                height: mascot.blinking ? 1 : (panel.busy ? 7 : 5)
                                radius: 2
                                x: 9 + mascot.lookX
                                y: mascot.blinking ? 13 : 10
                                color: panel.surface
                                Behavior on height { NumberAnimation { duration: 70 } }
                                Behavior on x { NumberAnimation { duration: 90 } }
                            }
                            Rectangle {
                                width: 4
                                height: mascot.blinking ? 1 : (panel.busy ? 7 : 5)
                                radius: 2
                                x: 21 + mascot.lookX
                                y: mascot.blinking ? 13 : 10
                                color: panel.surface
                                Behavior on height { NumberAnimation { duration: 70 } }
                                Behavior on x { NumberAnimation { duration: 90 } }
                            }
                            Rectangle {
                                width: panel.mockMood === "happy" ? 10 : (panel.mockMood === "error" ? 12 : 8)
                                height: 2
                                radius: 1
                                anchors.horizontalCenter: parent.horizontalCenter
                                y: 20
                                color: panel.mockMood === "error" ? panel.errorColor : Qt.rgba(panel.surface.r, panel.surface.g, panel.surface.b, 0.58)
                                rotation: panel.mockMood === "error" ? 180 : 0
                                Behavior on width { NumberAnimation { duration: 130 } }
                            }
                        }

                        Rectangle {
                            width: 11
                            height: 11
                            radius: 6
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.rightMargin: -2
                            anchors.topMargin: -2
                            color: panel.busy ? panel.primary : (panel.providerOnline ? panel.primary : panel.errorColor)
                            opacity: 0.9
                            SequentialAnimation on opacity {
                                running: panel.busy
                                loops: Animation.Infinite
                                NumberAnimation { to: 0.35; duration: 450 }
                                NumberAnimation { to: 1.0; duration: 450 }
                            }
                        }

                        MouseArea {
                            id: mascotMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onPositionChanged: mouse => mascot.lookX = Math.max(-1.8, Math.min(1.8, (mouse.x - width / 2) / 10))
                            onExited: mascot.lookX = 0
                            onClicked: panel.advancedOpen = !panel.advancedOpen
                        }
                    }

                    Column {
                        id: identity
                        anchors.left: mascot.right
                        anchors.leftMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        width: 92
                        spacing: 1

                        Text {
                            text: "Mock"
                            color: panel.textColor
                            font.pixelSize: 14
                            font.weight: Font.DemiBold
                        }
                        Text {
                            text: panel.busy ? "Pensando…" : panel.statusLabel
                            color: panel.busy ? panel.primary : panel.mutedColor
                            font.pixelSize: 10
                            elide: Text.ElideRight
                            width: parent.width
                        }
                    }

                    Rectangle {
                        id: providerChip
                        anchors.left: identity.right
                        anchors.leftMargin: 6
                        anchors.verticalCenter: parent.verticalCenter
                        width: Math.max(86, providerText.implicitWidth + 26)
                        height: 34
                        radius: 12
                        color: providerMouse.containsMouse ? panel.surfaceHighest : panel.surfaceHigh
                        border.width: 1
                        border.color: Qt.rgba(1, 1, 1, 0.06)

                        Text {
                            id: providerText
                            anchors.centerIn: parent
                            text: panel.providerName
                            color: panel.primary
                            font.pixelSize: 10
                            font.weight: Font.DemiBold
                        }

                        MouseArea {
                            id: providerMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                panel.advancedOpen = true
                                Qt.callLater(function() { providerSettingsButton.forceActiveFocus ? providerSettingsButton.forceActiveFocus() : modelSearch.forceActiveFocus() })
                            }
                        }
                    }

                    TextField {
                        id: promptField
                        anchors.left: providerChip.right
                        anchors.leftMargin: 8
                        anchors.right: advancedButton.left
                        anchors.rightMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        height: 42
                        placeholderText: "Pregúntale algo a Mock…"
                        color: panel.textColor
                        placeholderTextColor: panel.mutedColor
                        font.pixelSize: 13
                        selectByMouse: true
                        background: Rectangle {
                            radius: 14
                            color: panel.surfaceHigh
                            border.width: promptField.activeFocus ? 1 : 0
                            border.color: panel.primary
                        }
                        onAccepted: panel.sendPrompt()
                    }

                    Rectangle {
                        id: advancedButton
                        width: 40
                        height: 42
                        radius: 13
                        anchors.right: sendButton.left
                        anchors.rightMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        color: panel.advancedOpen || settingsMouse.containsMouse ? panel.surfaceHighest : panel.surfaceHigh
                        border.width: panel.advancedOpen ? 1 : 0
                        border.color: Qt.rgba(panel.primary.r, panel.primary.g, panel.primary.b, 0.35)

                        Text {
                            anchors.centerIn: parent
                            text: "⚙"
                            color: panel.advancedOpen ? panel.primary : panel.mutedColor
                            font.pixelSize: 16
                        }
                        MouseArea {
                            id: settingsMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                panel.advancedOpen = !panel.advancedOpen
                                panel.modelPickerOpen = false
                                if (panel.advancedOpen) Qt.callLater(function() { modelSearch.forceActiveFocus() })
                            }
                        }
                    }

                    Rectangle {
                        id: sendButton
                        width: 42
                        height: 42
                        radius: 14
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        color: panel.busy ? panel.surfaceHigh : (sendMouse.containsMouse ? Qt.lighter(panel.primary, 1.08) : panel.primary)

                        Text {
                            anchors.centerIn: parent
                            text: panel.busy ? "■" : "➜"
                            color: panel.busy ? panel.mutedColor : panel.surface
                            font.pixelSize: 17
                            font.weight: Font.Bold
                        }

                        MouseArea {
                            id: sendMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (panel.busy) panel.cancelPrompt(true)
                                else panel.sendPrompt()
                            }
                        }
                    }
                }

                // Ajustes: proveedor, modelos, API y parámetros viven aquí, no en la vista principal.
                Rectangle {
                    id: settingsPanel
                    visible: panel.advancedOpen
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: topRow.bottom
                    anchors.bottom: parent.bottom
                    anchors.leftMargin: 14
                    anchors.rightMargin: 14
                    anchors.bottomMargin: 14
                    radius: 18
                    color: Qt.rgba(panel.surfaceHigh.r, panel.surfaceHigh.g, panel.surfaceHigh.b, 0.82)
                    border.width: 1
                    border.color: Qt.rgba(1, 1, 1, 0.055)

                    Text {
                        id: settingsTitle
                        anchors.left: parent.left
                        anchors.top: parent.top
                        anchors.leftMargin: 16
                        anchors.topMargin: 13
                        text: "Ajustes de Mock"
                        color: panel.textColor
                        font.pixelSize: 13
                        font.weight: Font.DemiBold
                    }
                    Text {
                        anchors.left: settingsTitle.right
                        anchors.leftMargin: 9
                        anchors.verticalCenter: settingsTitle.verticalCenter
                        text: panel.providerLocal ? "LOCAL" : "CLOUD"
                        color: panel.providerOnline ? panel.primary : panel.errorColor
                        font.pixelSize: 9
                        font.weight: Font.Bold
                    }
                    Text {
                        anchors.right: parent.right
                        anchors.rightMargin: 16
                        anchors.verticalCenter: settingsTitle.verticalCenter
                        text: panel.probeMessage
                        color: panel.mutedColor
                        font.pixelSize: 9
                        elide: Text.ElideRight
                        width: 330
                        horizontalAlignment: Text.AlignRight
                    }

                    Rectangle {
                        height: 1
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: settingsTitle.bottom
                        anchors.topMargin: 11
                        anchors.leftMargin: 14
                        anchors.rightMargin: 14
                        color: Qt.rgba(1, 1, 1, 0.055)
                    }

                    Item {
                        id: leftSettings
                        anchors.left: parent.left
                        anchors.top: settingsTitle.bottom
                        anchors.bottom: parent.bottom
                        anchors.leftMargin: 14
                        anchors.topMargin: 25
                        anchors.bottomMargin: 14
                        width: 330

                        Text {
                            id: modelLabel
                            anchors.left: parent.left
                            anchors.top: parent.top
                            text: "Modelo"
                            color: panel.mutedColor
                            font.pixelSize: 9
                            font.weight: Font.Bold
                        }

                        TextField {
                            id: modelSearch
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: modelLabel.bottom
                            anchors.topMargin: 6
                            height: 40
                            placeholderText: panel.modelCount > 0 ? "Buscar entre " + panel.modelCount + " modelos…" : "ID del modelo…"
                            color: panel.textColor
                            placeholderTextColor: panel.mutedColor
                            font.pixelSize: 10
                            selectByMouse: true
                            leftPadding: 12
                            rightPadding: 12
                            background: Rectangle {
                                radius: 12
                                color: panel.surfaceContainer
                                border.width: modelSearch.activeFocus ? 1 : 0
                                border.color: panel.primary
                            }
                            onAccepted: {
                                if (text.trim() !== "") panel.chooseModel(text.trim())
                            }
                        }

                        Rectangle {
                            id: selectedModel
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: modelSearch.bottom
                            anchors.topMargin: 7
                            height: 32
                            radius: 10
                            color: Qt.rgba(panel.primary.r, panel.primary.g, panel.primary.b, 0.085)
                            Text {
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.leftMargin: 10
                                anchors.rightMargin: 10
                                anchors.verticalCenter: parent.verticalCenter
                                text: panel.modelName !== "" ? panel.modelName : "Modelo automático"
                                color: panel.modelName !== "" ? panel.primary : panel.mutedColor
                                font.pixelSize: 9
                                elide: Text.ElideMiddle
                            }
                        }

                        Rectangle {
                            id: modelListFrame
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: selectedModel.bottom
                            anchors.topMargin: 7
                            anchors.bottom: parent.bottom
                            radius: 12
                            color: panel.surfaceContainer
                            border.width: 1
                            border.color: Qt.rgba(1, 1, 1, 0.045)
                            clip: true

                            Text {
                                visible: panel.modelCount === 0
                                anchors.centerIn: parent
                                width: parent.width - 32
                                text: panel.providerNeedsKey && !panel.providerHasKey
                                    ? "Guarda la API key y pulsa ↻ para cargar los modelos."
                                    : "No hay catálogo disponible. Escribe el ID arriba y pulsa Enter."
                                color: panel.mutedColor
                                font.pixelSize: 10
                                wrapMode: Text.Wrap
                                horizontalAlignment: Text.AlignHCenter
                            }

                            ListView {
                                id: modelList
                                visible: panel.modelCount > 0
                                anchors.fill: parent
                                anchors.margins: 5
                                clip: true
                                spacing: 2
                                model: panel.filteredModels(modelSearch.text)
                                boundsBehavior: Flickable.StopAtBounds

                                delegate: Rectangle {
                                    required property var modelData
                                    width: modelList.width
                                    height: 34
                                    radius: 9
                                    color: modelListMouse.containsMouse
                                        ? panel.surfaceHigh
                                        : (String(modelData) === panel.modelName
                                            ? Qt.rgba(panel.primary.r, panel.primary.g, panel.primary.b, 0.11)
                                            : "transparent")

                                    Rectangle {
                                        width: 6; height: 6; radius: 3
                                        anchors.left: parent.left
                                        anchors.leftMargin: 9
                                        anchors.verticalCenter: parent.verticalCenter
                                        color: String(modelData) === panel.modelName ? panel.primary : panel.outlineColor
                                    }
                                    Text {
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        anchors.leftMargin: 24
                                        anchors.rightMargin: 28
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: String(modelData)
                                        color: String(modelData) === panel.modelName ? panel.primary : panel.textColor
                                        font.pixelSize: 9
                                        elide: Text.ElideMiddle
                                    }
                                    Text {
                                        anchors.right: parent.right
                                        anchors.rightMargin: 10
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: String(modelData) === panel.modelName ? "✓" : ""
                                        color: panel.primary
                                        font.pixelSize: 11
                                    }
                                    MouseArea {
                                        id: modelListMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: panel.chooseModel(String(modelData))
                                    }
                                }
                                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                            }
                        }
                    }

                    Rectangle {
                        width: 1
                        anchors.top: leftSettings.top
                        anchors.bottom: leftSettings.bottom
                        anchors.left: leftSettings.right
                        anchors.leftMargin: 14
                        color: Qt.rgba(1, 1, 1, 0.055)
                    }

                    Item {
                        id: rightSettings
                        anchors.left: leftSettings.right
                        anchors.leftMargin: 29
                        anchors.right: parent.right
                        anchors.rightMargin: 14
                        anchors.top: leftSettings.top
                        anchors.bottom: leftSettings.bottom

                        Text {
                            id: providerSettingsLabel
                            anchors.left: parent.left
                            anchors.top: parent.top
                            text: "Proveedor"
                            color: panel.mutedColor
                            font.pixelSize: 9
                            font.weight: Font.Bold
                        }

                        Rectangle {
                            id: providerSettingsButton
                            anchors.left: parent.left
                            anchors.top: providerSettingsLabel.bottom
                            anchors.topMargin: 6
                            width: 150
                            height: 40
                            radius: 12
                            color: providerSettingsMouse.containsMouse ? panel.surfaceHighest : panel.surfaceContainer
                            Text {
                                anchors.left: parent.left
                                anchors.leftMargin: 12
                                anchors.verticalCenter: parent.verticalCenter
                                text: panel.providerName
                                color: panel.primary
                                font.pixelSize: 10
                                font.weight: Font.DemiBold
                            }
                            Text {
                                anchors.right: parent.right
                                anchors.rightMargin: 11
                                anchors.verticalCenter: parent.verticalCenter
                                text: "▾"
                                color: panel.mutedColor
                                font.pixelSize: 10
                            }
                            MouseArea {
                                id: providerSettingsMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: providerSettingsMenu.open()
                            }
                            Menu {
                                id: providerSettingsMenu
                                y: height + 4
                                Repeater {
                                    model: ["mock", "ollama", "lmstudio", "openai", "openrouter", "anthropic", "gemini", "nvidia", "custom"]
                                    MenuItem {
                                        required property string modelData
                                        text: modelData
                                        onTriggered: panel.selectProvider(modelData)
                                    }
                                }
                            }
                        }

                        Rectangle {
                            anchors.left: providerSettingsButton.right
                            anchors.leftMargin: 8
                            anchors.right: parent.right
                            anchors.top: providerSettingsButton.top
                            height: 40
                            radius: 12
                            color: panel.surfaceContainer
                            Rectangle {
                                width: 7; height: 7; radius: 4
                                anchors.left: parent.left
                                anchors.leftMargin: 11
                                anchors.verticalCenter: parent.verticalCenter
                                color: panel.providerOnline ? panel.primary : panel.errorColor
                            }
                            Text {
                                anchors.left: parent.left
                                anchors.leftMargin: 25
                                anchors.right: refreshSettings.left
                                anchors.rightMargin: 8
                                anchors.verticalCenter: parent.verticalCenter
                                text: (panel.providerOnline ? "Conectado" : "Sin conexión") + " · " + panel.modelCount + " modelos"
                                color: panel.mutedColor
                                font.pixelSize: 9
                                elide: Text.ElideRight
                            }
                            Text {
                                id: refreshSettings
                                anchors.right: parent.right
                                anchors.rightMargin: 12
                                anchors.verticalCenter: parent.verticalCenter
                                text: probeProcess.running || providerProcess.running ? "…" : "↻"
                                color: panel.primary
                                font.pixelSize: 16
                                MouseArea {
                                    anchors.fill: parent
                                    anchors.margins: -7
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: panel.probeCurrent()
                                }
                            }
                        }

                        TextField {
                            id: apiField
                            visible: panel.providerSupportsKey
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: providerSettingsButton.bottom
                            anchors.topMargin: 8
                            height: 40
                            echoMode: panel.showApiKey ? TextInput.Normal : TextInput.Password
                            passwordCharacter: "•"
                            placeholderText: panel.providerHasKey ? "API key guardada ••••" : (panel.providerNeedsKey ? "API key requerida" : "API key opcional")
                            color: panel.textColor
                            placeholderTextColor: panel.providerNeedsKey && !panel.providerHasKey ? panel.errorColor : panel.mutedColor
                            selectByMouse: true
                            font.pixelSize: 10
                            rightPadding: 38
                            background: Rectangle {
                                radius: 12
                                color: panel.surfaceContainer
                                border.width: apiField.activeFocus ? 1 : 0
                                border.color: panel.primary
                            }
                            Text {
                                anchors.right: parent.right
                                anchors.rightMargin: 12
                                anchors.verticalCenter: parent.verticalCenter
                                text: panel.showApiKey ? "◉" : "◎"
                                color: apiEyeMouse.containsMouse ? panel.primary : panel.mutedColor
                                font.pixelSize: 13
                                MouseArea {
                                    id: apiEyeMouse
                                    anchors.fill: parent
                                    anchors.margins: -6
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: panel.showApiKey = !panel.showApiKey
                                }
                            }
                        }

                        TextField {
                            id: baseUrlField
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: panel.providerSupportsKey ? apiField.bottom : providerSettingsButton.bottom
                            anchors.topMargin: 8
                            height: 40
                            placeholderText: "Base URL"
                            color: panel.textColor
                            placeholderTextColor: panel.mutedColor
                            selectByMouse: true
                            font.pixelSize: 10
                            background: Rectangle {
                                radius: 12
                                color: panel.surfaceContainer
                                border.width: baseUrlField.activeFocus ? 1 : 0
                                border.color: panel.primary
                            }
                        }

                        Row {
                            id: tuningRow
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: baseUrlField.bottom
                            anchors.topMargin: 8
                            height: 48
                            spacing: 8

                            Rectangle {
                                width: Math.floor((parent.width - 8) * 0.62)
                                height: parent.height
                                radius: 12
                                color: panel.surfaceContainer
                                Column {
                                    anchors.fill: parent
                                    anchors.margins: 8
                                    spacing: 2
                                    Text {
                                        text: "Temperatura  " + temperatureSlider.value.toFixed(1)
                                        color: panel.mutedColor
                                        font.pixelSize: 8
                                        font.weight: Font.Bold
                                    }
                                    Slider {
                                        id: temperatureSlider
                                        width: parent.width
                                        from: 0
                                        to: 2
                                        stepSize: 0.1
                                        value: 0.7
                                    }
                                }
                            }

                            Rectangle {
                                width: parent.width - Math.floor((parent.width - 8) * 0.62) - 8
                                height: parent.height
                                radius: 12
                                color: panel.surfaceContainer
                                SpinBox {
                                    id: maxTokensSpin
                                    anchors.fill: parent
                                    anchors.margins: 4
                                    from: 64
                                    to: 131072
                                    stepSize: 256
                                    value: 4096
                                    editable: true
                                    font.pixelSize: 9
                                }
                            }
                        }

                        TextArea {
                            id: systemPromptField
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: tuningRow.bottom
                            anchors.bottom: actionsRow.top
                            anchors.topMargin: 8
                            anchors.bottomMargin: 8
                            placeholderText: "Prompt del sistema de Mock"
                            color: panel.textColor
                            placeholderTextColor: panel.mutedColor
                            font.pixelSize: 10
                            wrapMode: TextArea.Wrap
                            selectByMouse: true
                            background: Rectangle {
                                radius: 12
                                color: panel.surfaceContainer
                                border.width: systemPromptField.activeFocus ? 1 : 0
                                border.color: panel.primary
                            }
                        }

                        Row {
                            id: actionsRow
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            height: 36
                            spacing: 8

                            Rectangle {
                                width: 94
                                height: parent.height
                                radius: 11
                                color: saveSettingsMouse.containsMouse ? panel.primary : panel.surfaceHighest
                                Text {
                                    anchors.centerIn: parent
                                    text: configProcess.running ? "guardando…" : "guardar"
                                    color: saveSettingsMouse.containsMouse ? panel.surface : panel.textColor
                                    font.pixelSize: 9
                                    font.weight: Font.DemiBold
                                }
                                MouseArea {
                                    id: saveSettingsMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: panel.persistConfig(false)
                                }
                            }
                            Rectangle {
                                width: 112
                                height: parent.height
                                radius: 11
                                color: panel.surfaceContainer
                                Text {
                                    anchors.centerIn: parent
                                    text: "recargar modelos"
                                    color: reloadSettingsMouse.containsMouse ? panel.primary : panel.mutedColor
                                    font.pixelSize: 9
                                }
                                MouseArea {
                                    id: reloadSettingsMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: panel.probeCurrent()
                                }
                            }
                            Item { width: Math.max(0, parent.width - 214); height: 1 }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: "Esc cierra ajustes"
                                color: panel.mutedColor
                                font.pixelSize: 9
                            }
                        }
                    }
                }

                Rectangle {
                    id: divider
                    visible: !panel.advancedOpen && (panel.hasResponse || panel.hasError)
                    height: 1
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: topRow.bottom
                    anchors.leftMargin: 14
                    anchors.rightMargin: 14
                    color: Qt.rgba(1, 1, 1, 0.055)
                }

                Item {
                    id: responseArea
                    visible: !panel.advancedOpen && (panel.hasResponse || panel.hasError)
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: divider.bottom
                    anchors.bottom: footer.top
                    anchors.leftMargin: 16
                    anchors.rightMargin: 16
                    anchors.topMargin: 12
                    anchors.bottomMargin: 5

                    Flickable {
                        id: responseFlick
                        anchors.fill: parent
                        clip: true
                        contentWidth: width
                        contentHeight: responseColumn.implicitHeight
                        boundsBehavior: Flickable.StopAtBounds

                        Column {
                            id: responseColumn
                            width: responseFlick.width
                            spacing: 8

                            Text {
                                id: responseLive
                                visible: panel.busy
                                width: parent.width
                                height: implicitHeight
                                text: panel.responseText
                                textFormat: Text.PlainText
                                wrapMode: Text.Wrap
                                color: panel.textColor
                                font.pixelSize: 13
                                lineHeight: 1.22
                            }

                            TextEdit {
                                id: responseEditor
                                visible: !panel.busy && panel.responseText.length > 0
                                width: parent.width
                                height: visible ? Math.max(implicitHeight, 24) : 0
                                readOnly: true
                                selectByMouse: true
                                text: panel.responseText
                                textFormat: TextEdit.PlainText
                                wrapMode: TextEdit.Wrap
                                color: panel.textColor
                                selectionColor: panel.primary
                                selectedTextColor: panel.surface
                                font.pixelSize: 13
                            }

                            Text {
                                visible: errorText.text !== ""
                                width: parent.width
                                text: errorText.text
                                color: panel.errorColor
                                wrapMode: Text.Wrap
                                textFormat: Text.PlainText
                                font.pixelSize: 12
                            }
                        }

                        ScrollBar.vertical: ScrollBar { }
                    }
                }

                Item {
                    id: footer
                    visible: !panel.advancedOpen && (panel.hasResponse || panel.hasError)
                    height: 34
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.leftMargin: 16
                    anchors.rightMargin: 16

                    Text {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        text: panel.modelName !== "" ? panel.providerName + " · " + panel.modelName : panel.providerName + " · auto"
                        color: panel.mutedColor
                        font.pixelSize: 10
                        elide: Text.ElideRight
                        width: parent.width - 340
                    }

                    Row {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 14

                        Text {
                            text: panel.busy ? "Mock está escribiendo…" : "Super+Espacio / Esc"
                            color: panel.mutedColor
                            font.pixelSize: 10
                        }
                        Text {
                            visible: panel.responseText.length > 0 && !panel.busy
                            text: "copiar"
                            color: copyMouse.containsMouse ? panel.primary : panel.mutedColor
                            font.pixelSize: 10
                            MouseArea {
                                id: copyMouse
                                anchors.fill: parent
                                anchors.margins: -5
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: panel.copyResponse()
                            }
                        }
                        Text {
                            visible: panel.lastPrompt !== "" && !panel.busy
                            text: "regenerar"
                            color: regenMouse.containsMouse ? panel.primary : panel.mutedColor
                            font.pixelSize: 10
                            MouseArea {
                                id: regenMouse
                                anchors.fill: parent
                                anchors.margins: -5
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: panel.regenerate()
                            }
                        }
                        Text {
                            text: "limpiar"
                            color: clearMouse.containsMouse ? panel.primary : panel.mutedColor
                            font.pixelSize: 10
                            MouseArea {
                                id: clearMouse
                                anchors.fill: parent
                                anchors.margins: -5
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: panel.clearConversation()
                            }
                        }
                    }
                }

                FocusScope {
                    anchors.fill: parent
                    focus: panel.visible
                    Keys.onEscapePressed: {
                        if (panel.advancedOpen) {
                            panel.advancedOpen = false
                            modelSearch.text = ""
                            Qt.callLater(function() { promptField.forceActiveFocus() })
                        } else {
                            promptField.focus = false
                            app.closeIsland()
                        }
                    }
                }
            }

            Text { id: errorText; visible: false }

            Timer {
                id: streamFlushTimer
                interval: 80
                repeat: true
                running: panel.busy || panel.streamPending.length > 0
                onTriggered: panel.flushStream(false)
            }

            Timer {
                id: requestWatchdog
                interval: 5000
                repeat: true
                running: panel.busy
                onTriggered: {
                    if (panel.lastActivityMs > 0 && Date.now() - panel.lastActivityMs > 120000) {
                        panel.cancelPrompt(false)
                        errorText.text = "El proveedor lleva más de 2 minutos sin enviar datos. Puedes reintentar o cambiar de modelo/proveedor."
                        panel.statusLabel = "Sin respuesta"
                    }
                }
            }

            Timer {
                interval: 5000
                running: panel.visible
                repeat: true
                onTriggered: if (!themeProcess.running) themeProcess.running = true
            }

            Process {
                id: themeProcess
                command: ["python3", app.bridge, "theme"]
                running: panel.visible
                stdout: StdioCollector {
                    onStreamFinished: {
                        try {
                            const t = JSON.parse(text)
                            panel.primary = t.primary || panel.primary
                            panel.surface = t.surface || panel.surface
                            panel.surfaceContainer = t.surface_container || panel.surfaceContainer
                            panel.surfaceHigh = t.surface_high || panel.surfaceHigh
                            panel.surfaceHighest = t.surface_highest || panel.surfaceHighest
                            panel.textColor = t.text || panel.textColor
                            panel.mutedColor = t.muted || panel.mutedColor
                            panel.outlineColor = t.outline || panel.outlineColor
                            panel.errorColor = t.error || panel.errorColor
                        } catch (e) {}
                    }
                }
            }

            Process {
                id: statusProcess
                command: ["python3", app.bridge, "status"]
                running: false
                stdout: StdioCollector {
                    onStreamFinished: {
                        try { panel.applyProbe(JSON.parse(text)) }
                        catch (e) { panel.probeMessage = "No pude leer el estado" }
                    }
                }
            }

            Process {
                id: probeProcess
                command: ["python3", app.bridge, "probe", "--provider", panel.providerName]
                running: false
                stdout: StdioCollector {
                    onStreamFinished: {
                        try { panel.applyProbe(JSON.parse(text)) }
                        catch (e) { panel.probeMessage = "No pude comprobar el proveedor" }
                    }
                }
            }

            Process {
                id: providerProcess
                running: false
                stdout: StdioCollector {
                    onStreamFinished: {
                        try { panel.applyProbe(JSON.parse(text)) }
                        catch (e) {}
                    }
                }
            }

            Process {
                id: configProcess
                stdinEnabled: true
                running: false
                property string configPayload: ""
                command: ["python3", app.bridge, "configure", "--stdin"]
                onStarted: {
                    write(configPayload)
                    stdinEnabled = false
                }
                stdout: StdioCollector {
                    onStreamFinished: {
                        try {
                            panel.applyProbe(JSON.parse(text))
                            apiField.text = ""
                        } catch (e) {}
                    }
                }
                onExited: exitCode => {
                    stdinEnabled = true
                    if (exitCode !== 0) {
                        errorText.text = "No pude guardar la configuración"
                        panel.pendingSendAfterConfig = false
                        return
                    }
                    if (panel.pendingSendAfterConfig) {
                        panel.pendingSendAfterConfig = false
                        if (panel.providerNeedsKey && !panel.providerHasKey) {
                            errorText.text = "Falta la API key de " + panel.providerName
                            return
                        }
                        panel.startPrompt()
                    }
                }
            }

            Process {
                id: clearProcess
                command: ["python3", app.bridge, "clear"]
                running: false
            }

            Process {
                id: copyProcess
                stdinEnabled: true
                running: false
                property string payload: ""
                command: ["sh", "-c", "if command -v wl-copy >/dev/null 2>&1; then wl-copy; elif command -v xclip >/dev/null 2>&1; then xclip -selection clipboard; else cat >/tmp/mock-island-clipboard.txt; fi"]
                onStarted: {
                    write(payload)
                    stdinEnabled = false
                }
                onExited: stdinEnabled = true
            }

            Process {
                id: aiProcess
                stdinEnabled: true
                running: false
                command: ["python3", app.bridge, "ask", "--provider", panel.providerName, "--model", panel.modelName]

                onStarted: {
                    panel.lastActivityMs = Date.now()
                    write(panel.pendingPrompt + "\n")
                    stdinEnabled = false
                }

                stdout: SplitParser {
                    splitMarker: "\n"
                    onRead: line => {
                        const s = line.trim()
                        if (!s) return
                        try {
                            const e = JSON.parse(s)
                            panel.lastActivityMs = Date.now()
                            if (e.type === "meta") {
                                panel.statusLabel = "Conectado · " + (e.model || "auto")
                                if (panel.modelName === "" && e.model && e.model !== "auto") panel.modelName = e.model
                            } else if (e.type === "state") {
                                panel.statusLabel = e.state === "reasoning" ? "Razonando…" : "Pensando…"
                            } else if (e.type === "delta") {
                                panel.statusLabel = "Respondiendo…"
                                panel.streamPending += e.text || ""
                            } else if (e.type === "reset") {
                                panel.streamPending = ""
                                panel.responseText = ""
                            } else if (e.type === "error") {
                                errorText.text = e.message || "Error desconocido"
                            }
                        } catch (err) {
                            errorText.text = s
                        }
                    }
                }

                stderr: SplitParser {
                    splitMarker: "\n"
                    onRead: line => {
                        if (line.trim() !== "") console.warn("[Mock]", line)
                    }
                }

                onExited: exitCode => {
                    const wasCancelled = panel.cancelRequested
                    panel.cancelRequested = false
                    panel.flushStream(true)
                    panel.busy = false
                    stdinEnabled = true
                    if (!wasCancelled && exitCode !== 0 && errorText.text === "")
                        errorText.text = "El proveedor terminó con código " + exitCode
                    if (!wasCancelled && exitCode === 0) panel.statusLabel = "Listo"
                    Qt.callLater(function() {
                        responseFlick.contentY = Math.max(0, responseFlick.contentHeight - responseFlick.height)
                    })
                }
            }

            Connections {
                target: app
                function onFocusRequested(screenName) {
                    if (!panel.visible) return
                    Qt.callLater(function() { promptField.forceActiveFocus() })
                }
                function onRefreshRequested(screenName) {
                    if (!panel.visible) return
                    Qt.callLater(function() { panel.refreshStatus() })
                }
            }

            onVisibleChanged: {
                if (visible) {
                    if (!themeProcess.running) themeProcess.running = true
                    refreshStatus()
                    Qt.callLater(function() { promptField.forceActiveFocus() })
                } else {
                    modelPickerOpen = false
                    advancedOpen = false
                }
            }

            function filteredModels(query) {
                const q = String(query || "").trim().toLowerCase()
                if (!q) return providerModels
                return providerModels.filter(function(m) { return String(m).toLowerCase().indexOf(q) !== -1 })
            }

            function chooseModel(name) {
                modelName = String(name || "").trim()
                modelSearch.text = ""
                statusLabel = modelName !== "" ? "Modelo seleccionado" : "Modelo automático"
            }

            function applyProbe(s) {
                providerName = s.provider || providerName
                providerOnline = !!s.online
                providerLocal = !!s.local
                providerHasKey = !!s.has_key
                providerNeedsKey = !!s.requires_key
                providerSupportsKey = !!s.supports_key
                providerModels = s.models || []
                modelCount = providerModels.length
                probeMessage = s.message || ""
                catalogError = s.catalog_error || ""
                modelName = s.resolved_model || s.model || ""
                baseUrlField.text = s.base_url || baseUrlField.text
                if (s.temperature !== undefined) temperatureSlider.value = Number(s.temperature)
                if (s.max_tokens !== undefined) maxTokensSpin.value = Number(s.max_tokens)
                if (s.system_prompt) systemPromptField.text = s.system_prompt
                statusLabel = providerOnline ? "Listo" : "Configura proveedor"
            }

            function refreshStatus() {
                if (!statusProcess.running) statusProcess.running = true
            }

            function probeCurrent() {
                if (!probeProcess.running && !providerProcess.running && !configProcess.running) {
                    probeMessage = "Cargando modelos…"
                    probeProcess.command = ["python3", app.bridge, "probe", "--provider", providerName]
                    probeProcess.running = true
                }
            }

            function selectProvider(name) {
                if (providerProcess.running || configProcess.running) return
                if (busy) cancelPrompt(false)
                providerName = name
                modelName = ""
                providerModels = []
                modelCount = 0
                modelPickerOpen = false
                apiField.text = ""
                responseText = ""
                streamPending = ""
                errorText.text = ""
                statusLabel = "Cambiando proveedor…"
                probeMessage = "Consultando " + name + "…"
                providerProcess.command = ["python3", app.bridge, "provider", name]
                providerProcess.running = true
            }

            function persistConfig(thenSend) {
                if (configProcess.running || busy) return
                pendingSendAfterConfig = thenSend
                configProcess.configPayload = JSON.stringify({
                    provider: providerName,
                    model: modelName,
                    api_key: apiField.text.trim(),
                    base_url: baseUrlField.text.trim(),
                    temperature: temperatureSlider.value,
                    max_tokens: maxTokensSpin.value,
                    system_prompt: systemPromptField.text.trim()
                })
                probeMessage = "Guardando y cargando modelos…"
                configProcess.stdinEnabled = true
                configProcess.running = true
            }

            function sendPrompt() {
                const p = promptField.text.trim()
                if (!p || busy || configProcess.running || providerProcess.running) return
                if (providerNeedsKey && !providerHasKey) {
                    errorText.text = "Configura la API key de " + providerName + " en ⚙ Ajustes"
                    return
                }
                pendingPrompt = p
                lastPrompt = p
                startPrompt()
            }

            function regenerate() {
                if (lastPrompt === "" || busy || configProcess.running || providerProcess.running) return
                pendingPrompt = lastPrompt
                startPrompt()
            }

            function startPrompt() {
                const p = pendingPrompt.trim()
                if (!p || busy) return
                responseText = ""
                streamPending = ""
                errorText.text = ""
                promptField.text = ""
                cancelRequested = false
                busy = true
                lastActivityMs = Date.now()
                statusLabel = "Pensando…"
                aiProcess.stdinEnabled = true
                aiProcess.command = ["python3", app.bridge, "ask", "--provider", providerName, "--model", modelName]
                aiProcess.running = true
            }

            function cancelPrompt(showLabel) {
                cancelRequested = true
                if (aiProcess.running) aiProcess.running = false
                flushStream(true)
                busy = false
                aiProcess.stdinEnabled = true
                if (showLabel !== false) statusLabel = "Cancelado"
            }

            function flushStream(forceAll) {
                if (streamPending.length === 0) return
                const maxBefore = Math.max(0, responseFlick.contentHeight - responseFlick.height)
                const shouldFollow = responseFlick.contentY >= maxBefore - 72
                const count = forceAll ? streamPending.length : Math.min(streamPending.length, 8192)
                const chunk = streamPending.slice(0, count)
                streamPending = streamPending.slice(count)
                responseText += chunk
                if (shouldFollow) {
                    Qt.callLater(function() {
                        responseFlick.contentY = Math.max(0, responseFlick.contentHeight - responseFlick.height)
                    })
                }
            }

            function copyResponse() {
                if (responseText.length === 0 || copyProcess.running) return
                copyProcess.payload = responseText
                copyProcess.stdinEnabled = true
                copyProcess.running = true
                statusLabel = "Copiado"
            }

            function clearConversation() {
                responseText = ""
                streamPending = ""
                errorText.text = ""
                lastPrompt = ""
                clearProcess.running = true
                statusLabel = "Historial limpio"
            }
        }
    }
}
