//@ pragma UseQApplication
//@ pragma AppId dev.mock.island
//@ pragma ShellId mock-island

import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io

ShellRoot {
    id: app

    readonly property string projectDir: Quickshell.env("MOCK_ISLAND_DIR") !== ""
        ? Quickshell.env("MOCK_ISLAND_DIR")
        : Quickshell.env("HOME") + "/Projects/mock-island"
    readonly property string bridge: projectDir + "/backend/ai_bridge.py"
    readonly property string agentRuntime: projectDir + "/backend/agent_runtime.py"
    readonly property string voiceBridge: projectDir + "/backend/voice_bridge.py"

    property bool shown: false
    property string targetScreen: ""
    signal focusRequested(string screenName)
    signal refreshRequested(string screenName)
    signal voiceToggleRequested(string screenName)

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

        function voiceToggle(screenName: string): string {
            if (!app.shown) app.openOn(screenName)
            app.voiceToggleRequested(screenName || app.targetScreen)
            return "VOICE_TOGGLE"
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
            property bool completionPulse: false
            property bool edgeHover: false
            property int mascotPokes: 0
            property bool mascotAnnoyed: false
            property bool mascotDizzy: false
            property bool mascotHearts: false
            property bool pendingSendAfterConfig: false
            property bool pendingSendAfterContext: false
            property bool contextNeedsClipboard: false
            property string pendingPrompt: ""
            property string lastPrompt: ""
            property string streamPending: ""
            property string responseText: ""
            property bool advancedOpen: false
            property bool modelPickerOpen: false
            property bool showApiKey: false
            property bool attachWindowContext: false
            property bool attachClipboardContext: false
            property bool agentEnabled: true
            property bool agentExecuting: false
            property bool agentAwaitingApproval: false
            property string agentPlanJson: ""
            property string agentPlanActionsText: ""
            property bool voiceRecording: false
            property bool voiceSpeaking: false
            property bool voiceTtsEnabled: false
            property bool voiceAutoSend: true
            property bool voiceReady: false
            property string voiceMessage: ""
            property bool dropHover: false
            property var desktopContext: ({})
            property string attachedFilePath: ""
            property string attachedFileName: ""
            property string attachedFileText: ""
            property bool attachedFileTruncated: false
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
            readonly property bool hasContent: hasResponse || hasError || agentAwaitingApproval
            property double lastActivityMs: 0
            readonly property bool pulseMode: !app.shown && (busy || completionPulse)
            readonly property bool hiddenIdle: !app.shown && !busy && !completionPulse
            readonly property bool peekMode: hiddenIdle && edgeHover
            property real baseWindowHeight: advancedOpen ? 500 : (agentAwaitingApproval ? 230 : (hasResponse ? 430 : (hasError ? 182 : 96)))
            property real windowHeight: hiddenIdle ? (peekMode ? 36 : 5) : (pulseMode ? 36 : baseWindowHeight)
            readonly property string mockMood: errorText.text !== "" ? "error" : (voiceRecording ? "listening" : (voiceSpeaking ? "speaking" : (agentExecuting ? "acting" : (busy ? "thinking" : (!providerOnline ? "offline" : (hasResponse ? "happy" : "idle"))))))
            readonly property string focusedAppLabel: {
                const n = desktopContext && desktopContext.desktop ? desktopContext.desktop : null
                if (!n) return "ventana"
                return n.app_id || n.title || "ventana"
            }
            readonly property string workspaceLabel: {
                const n = desktopContext && desktopContext.desktop ? desktopContext.desktop : null
                if (!n || !n.workspace) return ""
                return "WS " + n.workspace
            }
            readonly property string mediaLabel: {
                const m = desktopContext && desktopContext.media ? desktopContext.media : null
                if (!m || !m.available || !m.title) return ""
                return (m.status === "Playing" ? "▶ " : "Ⅱ ") + (m.artist ? m.artist + " · " : "") + m.title
            }

            property color primary: "#9fc9ff"
            property color secondary: "#b9c7dc"
            property color tertiary: "#b9c9ff"
            property color surface: "#11161c"
            property color surfaceContainer: "#171d24"
            property color surfaceHigh: "#1f2731"
            property color surfaceHighest: "#27313d"
            property color textColor: "#edf3fb"
            property color mutedColor: "#a9b4c0"
            property color outlineColor: "#51606f"
            property color errorColor: "#ffb4ab"

            // Keep a tiny input strip alive when idle so Mock can peek on hover.
            visible: (app.targetScreen === "" || screen.name === app.targetScreen)
            color: "transparent"
            implicitHeight: windowHeight + 16

            // PanelWindow keeps the surface portable across Wayland/X11.
            // Quickshell maps these generic properties to layer-shell when available.
            aboveWindows: true
            exclusiveZone: 0
            focusable: app.shown && visible

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
                width: panel.hiddenIdle
                    ? (panel.peekMode ? Math.min(190, panel.width - 40) : Math.min(72, panel.width - 40))
                    : (panel.pulseMode ? Math.min(240, panel.width - 40) : Math.min(760, panel.width - 40))
                height: panel.windowHeight
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 8
                radius: panel.hiddenIdle ? (panel.peekMode ? 18 : 3) : (panel.pulseMode ? 18 : 22)
                color: panel.surfaceContainer
                border.width: 1
                border.color: Qt.rgba(panel.primary.r, panel.primary.g, panel.primary.b, 0.30)
                clip: true

                opacity: panel.hiddenIdle && !panel.peekMode ? 0.0 : 1
                scale: panel.hiddenIdle && !panel.peekMode ? 0.98 : 1
                Behavior on opacity { NumberAnimation { duration: 130 } }
                Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutBack } }
                Behavior on width { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }
                Behavior on height { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                Behavior on radius { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

                Rectangle {
                    anchors.fill: parent
                    radius: parent.radius
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: Qt.rgba(panel.primary.r, panel.primary.g, panel.primary.b, 0.065) }
                        GradientStop { position: 0.32; color: "transparent" }
                    }
                    z: -1
                }

                // Pulse: cuando la UI se cierra durante una tarea, Mock queda como un indicador mínimo del shell.
                Item {
                    id: pulseRow
                    visible: panel.pulseMode || panel.peekMode
                    anchors.fill: parent

                    Rectangle {
                        id: pulseCore
                        width: 30
                        height: 26
                        radius: 11
                        anchors.left: parent.left
                        anchors.leftMargin: 7
                        anchors.verticalCenter: parent.verticalCenter
                        border.width: 1
                        border.color: Qt.rgba(1, 1, 1, 0.10)
                        gradient: Gradient {
                            GradientStop { position: 0.0; color: Qt.rgba(panel.primary.r, panel.primary.g, panel.primary.b, 0.70) }
                            GradientStop { position: 1.0; color: panel.surfaceHighest }
                        }
                        Rectangle { width: 3; height: 4; radius: 2; x: 8; y: 11; color: panel.surface }
                        Rectangle { width: 3; height: 4; radius: 2; x: 19; y: 11; color: panel.surface }

                        SequentialAnimation on scale {
                            running: panel.busy
                            loops: Animation.Infinite
                            NumberAnimation { to: 1.08; duration: 430; easing.type: Easing.InOutSine }
                            NumberAnimation { to: 1.0; duration: 430; easing.type: Easing.InOutSine }
                        }
                    }

                    Column {
                        anchors.left: pulseCore.right
                        anchors.leftMargin: 9
                        anchors.right: pulseHint.left
                        anchors.rightMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: -1
                        Text {
                            width: parent.width
                            text: panel.peekMode ? "Mock está aquí" : (panel.busy ? "Mock está trabajando" : "Respuesta lista")
                            color: panel.textColor
                            font.pixelSize: 11
                            font.weight: Font.DemiBold
                            elide: Text.ElideRight
                        }
                        Text {
                            width: parent.width
                            text: panel.peekMode ? "clic para abrir · hola 👋" : (panel.busy ? panel.statusLabel : "clic para volver")
                            color: panel.busy ? panel.primary : panel.tertiary
                            font.pixelSize: 9
                            elide: Text.ElideRight
                        }
                    }

                    Text {
                        id: pulseHint
                        anchors.right: parent.right
                        anchors.rightMargin: 12
                        anchors.verticalCenter: parent.verticalCenter
                        text: "↗"
                        color: panel.mutedColor
                        font.pixelSize: 15
                    }

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: app.openOn(screen.name)
                    }
                }

                Timer {
                    id: edgeCollapseTimer
                    interval: 320
                    repeat: false
                    onTriggered: panel.edgeHover = false
                }

                MouseArea {
                    id: edgeHotspot
                    anchors.fill: parent
                    visible: panel.hiddenIdle
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onEntered: {
                        edgeCollapseTimer.stop()
                        panel.edgeHover = true
                    }
                    onExited: edgeCollapseTimer.restart()
                    onClicked: app.openOn(screen.name)
                }

                // Mock Core v13: una presencia mínima y suave. Las manos solo aparecen
                // como reacción; el estado normal es una cápsula viva, no una cara de avatar.
                Item {
                    id: topRow
                    visible: !panel.pulseMode && !panel.hiddenIdle
                    height: visible ? 62 : 0
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12

                    Item {
                        id: mascot
                        property bool blinking: false
                        property real lookX: 0
                        width: 54
                        height: 46
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        transformOrigin: Item.Center
                        rotation: panel.mascotDizzy ? 7 : (panel.mascotAnnoyed ? -3 : 0)

                        Rectangle {
                            width: 50
                            height: 40
                            radius: 18
                            anchors.centerIn: parent
                            color: Qt.rgba(panel.primary.r, panel.primary.g, panel.primary.b, panel.busy ? 0.12 : 0.055)
                            border.width: 1
                            border.color: panel.mockMood === "error"
                                ? Qt.rgba(panel.errorColor.r, panel.errorColor.g, panel.errorColor.b, 0.34)
                                : Qt.rgba(panel.primary.r, panel.primary.g, panel.primary.b, 0.12)
                        }

                        Rectangle {
                            id: body
                            width: 42
                            height: 34
                            radius: 15
                            anchors.centerIn: parent
                            border.width: 1
                            border.color: Qt.rgba(1, 1, 1, 0.10)
                            gradient: Gradient {
                                GradientStop {
                                    position: 0.0
                                    color: panel.voiceRecording
                                        ? Qt.rgba(panel.tertiary.r, panel.tertiary.g, panel.tertiary.b, 0.72)
                                        : Qt.rgba(panel.primary.r, panel.primary.g, panel.primary.b, 0.72)
                                }
                                GradientStop {
                                    position: 1.0
                                    color: Qt.rgba(panel.surfaceHighest.r, panel.surfaceHighest.g, panel.surfaceHighest.b, 0.96)
                                }
                            }

                            Rectangle {
                                width: 25
                                height: 11
                                radius: 6
                                anchors.horizontalCenter: parent.horizontalCenter
                                anchors.top: parent.top
                                anchors.topMargin: 4
                                color: Qt.rgba(1, 1, 1, 0.075)
                            }

                            Rectangle {
                                visible: !panel.mascotDizzy
                                width: 4
                                height: mascot.blinking ? 1 : 5
                                radius: 2
                                x: 11 + mascot.lookX
                                y: mascot.blinking ? 17 : 14
                                color: panel.surface
                                Behavior on height { NumberAnimation { duration: 70 } }
                                Behavior on x { NumberAnimation { duration: 80 } }
                            }
                            Rectangle {
                                visible: !panel.mascotDizzy
                                width: 4
                                height: mascot.blinking ? 1 : 5
                                radius: 2
                                x: 27 + mascot.lookX
                                y: mascot.blinking ? 17 : 14
                                color: panel.surface
                                Behavior on height { NumberAnimation { duration: 70 } }
                                Behavior on x { NumberAnimation { duration: 80 } }
                            }

                            Text {
                                visible: panel.mascotDizzy
                                text: "×  ×"
                                anchors.centerIn: parent
                                anchors.verticalCenterOffset: -1
                                color: panel.surface
                                font.pixelSize: 12
                                font.weight: Font.Bold
                            }

                            Rectangle {
                                width: panel.mascotAnnoyed ? 8 : (panel.mockMood === "happy" ? 10 : 6)
                                height: 1
                                radius: 1
                                anchors.horizontalCenter: parent.horizontalCenter
                                anchors.bottom: parent.bottom
                                anchors.bottomMargin: 7
                                color: panel.mockMood === "error" ? panel.errorColor : Qt.rgba(panel.surface.r, panel.surface.g, panel.surface.b, 0.68)
                                rotation: panel.mascotAnnoyed ? 7 : 0
                                Behavior on width { NumberAnimation { duration: 120 } }
                            }
                        }

                        // Manos reactivas: ocultas en idle para mantener la silueta limpia.
                        Rectangle {
                            visible: mascotMouse.containsMouse || panel.dropHover || panel.mockMood === "happy"
                            width: 6; height: 6; radius: 3
                            x: panel.dropHover ? 0 : 3
                            y: panel.dropHover ? 5 : 30
                            color: panel.secondary
                            opacity: 0.88
                            Behavior on x { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                            Behavior on y { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                        }
                        Rectangle {
                            id: reactiveHand
                            property real wave: 0
                            visible: mascotMouse.containsMouse || panel.dropHover || panel.mockMood === "happy"
                            width: 6; height: 6; radius: 3
                            x: panel.dropHover ? 48 : 45
                            y: (panel.dropHover ? 5 : 30) + wave
                            color: panel.tertiary
                            opacity: 0.88
                            SequentialAnimation on wave {
                                running: mascotMouse.containsMouse && !panel.dropHover && !panel.mascotDizzy
                                loops: Animation.Infinite
                                NumberAnimation { to: -7; duration: 150; easing.type: Easing.OutCubic }
                                NumberAnimation { to: 0; duration: 190; easing.type: Easing.InOutSine }
                                PauseAnimation { duration: 720 }
                            }
                        }

                        Rectangle {
                            width: 7
                            height: 7
                            radius: 4
                            x: 43
                            y: 1
                            color: panel.mockMood === "error" ? panel.errorColor
                                : (panel.voiceRecording ? panel.tertiary : (panel.busy ? panel.primary : (panel.agentEnabled ? panel.primary : panel.outlineColor)))
                            border.width: 2
                            border.color: panel.surfaceContainer
                            SequentialAnimation on scale {
                                running: panel.busy
                                loops: Animation.Infinite
                                NumberAnimation { to: 1.34; duration: 400; easing.type: Easing.InOutSine }
                                NumberAnimation { to: 1.0; duration: 400; easing.type: Easing.InOutSine }
                            }
                        }

                        Text {
                            visible: panel.mascotHearts && !panel.busy
                            text: "♥"
                            x: 42
                            y: -8
                            color: panel.tertiary
                            font.pixelSize: 10
                        }

                        SequentialAnimation on scale {
                            running: panel.visible
                            loops: Animation.Infinite
                            NumberAnimation { to: panel.busy ? 1.045 : 1.012; duration: panel.busy ? 420 : 1650; easing.type: Easing.InOutSine }
                            NumberAnimation { to: 1.0; duration: panel.busy ? 420 : 1650; easing.type: Easing.InOutSine }
                        }
                        Behavior on rotation { NumberAnimation { duration: 150; easing.type: Easing.OutBack } }

                        SequentialAnimation on lookX {
                            running: panel.visible && !mascotMouse.containsMouse && !panel.busy
                            loops: Animation.Infinite
                            PauseAnimation { duration: 1600 }
                            NumberAnimation { to: 1.3; duration: 180; easing.type: Easing.OutCubic }
                            PauseAnimation { duration: 650 }
                            NumberAnimation { to: -1.1; duration: 220; easing.type: Easing.OutCubic }
                            PauseAnimation { duration: 900 }
                            NumberAnimation { to: 0; duration: 180; easing.type: Easing.OutCubic }
                        }

                        Timer {
                            id: blinkTimer
                            running: panel.visible
                            repeat: true
                            interval: 2400
                            onTriggered: {
                                mascot.blinking = true
                                blinkReset.restart()
                                interval = 1800 + Math.floor(Math.random() * 2800)
                            }
                        }
                        Timer { id: blinkReset; interval: 105; repeat: false; onTriggered: mascot.blinking = false }
                        Timer { id: pokeResetTimer; interval: 900; repeat: false; onTriggered: panel.mascotPokes = 0 }
                        Timer { id: annoyedResetTimer; interval: 720; repeat: false; onTriggered: panel.mascotAnnoyed = false }
                        Timer { id: dizzyResetTimer; interval: 2400; repeat: false; onTriggered: panel.mascotDizzy = false }
                        Timer {
                            id: heartTimer
                            interval: 1600
                            repeat: false
                            onTriggered: if (mascotMouse.containsMouse && !panel.busy) panel.mascotHearts = true
                        }

                        MouseArea {
                            id: mascotMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onEntered: heartTimer.restart()
                            onPositionChanged: mouse => mascot.lookX = Math.max(-1.5, Math.min(1.5, (mouse.x - width / 2) / 11))
                            onExited: {
                                mascot.lookX = 0
                                heartTimer.stop()
                                panel.mascotHearts = false
                            }
                            onClicked: {
                                panel.mascotPokes += 1
                                pokeResetTimer.restart()
                                panel.mascotHearts = false
                                if (panel.mascotPokes >= 3) {
                                    panel.mascotPokes = 0
                                    panel.mascotAnnoyed = false
                                    panel.mascotDizzy = true
                                    dizzyResetTimer.restart()
                                } else {
                                    panel.mascotAnnoyed = true
                                    annoyedResetTimer.restart()
                                }
                                panel.refreshDesktopContext(panel.attachClipboardContext)
                                Qt.callLater(function() { promptField.forceActiveFocus() })
                            }
                        }
                    }

                    Column {
                        id: identity
                        anchors.left: mascot.right
                        anchors.leftMargin: 7
                        anchors.verticalCenter: parent.verticalCenter
                        width: 88
                        spacing: 0
                        Text {
                            text: "Mock"
                            color: panel.textColor
                            font.pixelSize: 13
                            font.weight: Font.DemiBold
                        }
                        Row {
                            spacing: 4
                            Rectangle {
                                width: 5; height: 5; radius: 3
                                anchors.verticalCenter: parent.verticalCenter
                                color: panel.busy ? panel.primary : (panel.agentEnabled ? panel.tertiary : panel.outlineColor)
                            }
                            Text {
                                text: panel.busy ? panel.statusLabel : (panel.agentEnabled ? "Agente listo" : "Chat")
                                color: panel.busy ? panel.primary : panel.mutedColor
                                font.pixelSize: 9
                                elide: Text.ElideRight
                                width: 74
                            }
                        }
                    }

                    Rectangle {
                        id: providerChip
                        anchors.left: identity.right
                        anchors.leftMargin: 6
                        anchors.verticalCenter: parent.verticalCenter
                        width: Math.max(68, Math.min(92, providerText.implicitWidth + 22))
                        height: 30
                        radius: 15
                        color: providerMouse.containsMouse ? panel.surfaceHighest : panel.surfaceHigh
                        border.width: 1
                        border.color: Qt.rgba(1, 1, 1, 0.065)
                        Text {
                            id: providerText
                            anchors.centerIn: parent
                            text: panel.providerName.toUpperCase()
                            color: panel.primary
                            font.pixelSize: 9
                            font.weight: Font.DemiBold
                            elide: Text.ElideRight
                        }
                        MouseArea {
                            id: providerMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                panel.advancedOpen = true
                                Qt.callLater(function() { modelSearch.forceActiveFocus() })
                            }
                        }
                    }

                    TextField {
                        id: promptField
                        anchors.left: providerChip.right
                        anchors.leftMargin: 7
                        anchors.right: advancedButton.left
                        anchors.rightMargin: 7
                        anchors.verticalCenter: parent.verticalCenter
                        height: 40
                        placeholderText: panel.agentEnabled ? "Pídele algo a Mock…" : "Pregunta a Mock…"
                        color: panel.textColor
                        placeholderTextColor: panel.mutedColor
                        font.pixelSize: 12
                        selectByMouse: true
                        leftPadding: 14
                        rightPadding: 14
                        background: Rectangle {
                            radius: 20
                            color: panel.surfaceHigh
                            border.width: 1
                            border.color: promptField.activeFocus
                                ? Qt.rgba(panel.primary.r, panel.primary.g, panel.primary.b, 0.78)
                                : Qt.rgba(1, 1, 1, 0.065)
                        }
                        onAccepted: panel.sendPrompt()
                    }

                    Rectangle {
                        id: advancedButton
                        width: 34
                        height: 34
                        radius: 17
                        anchors.right: micButton.left
                        anchors.rightMargin: 6
                        anchors.verticalCenter: parent.verticalCenter
                        color: panel.advancedOpen || settingsMouse.containsMouse ? panel.surfaceHighest : "transparent"
                        Text {
                            anchors.centerIn: parent
                            text: "⚙"
                            color: panel.advancedOpen ? panel.primary : panel.mutedColor
                            font.pixelSize: 14
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
                        id: micButton
                        width: 34
                        height: 34
                        radius: 17
                        anchors.right: sendButton.left
                        anchors.rightMargin: 6
                        anchors.verticalCenter: parent.verticalCenter
                        color: panel.voiceRecording
                            ? Qt.rgba(panel.tertiary.r, panel.tertiary.g, panel.tertiary.b, 0.20)
                            : (micMouse.containsMouse ? panel.surfaceHighest : "transparent")
                        border.width: panel.voiceRecording ? 1 : 0
                        border.color: panel.tertiary
                        Text {
                            anchors.centerIn: parent
                            text: panel.voiceRecording ? "■" : "MIC"
                            color: panel.voiceRecording ? panel.tertiary : panel.mutedColor
                            font.pixelSize: panel.voiceRecording ? 11 : 7
                            font.weight: Font.Bold
                        }
                        MouseArea {
                            id: micMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: panel.toggleVoice()
                        }
                    }

                    Rectangle {
                        id: sendButton
                        width: 38
                        height: 38
                        radius: 19
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        color: panel.busy ? panel.surfaceHighest : (sendMouse.containsMouse ? Qt.lighter(panel.primary, 1.06) : panel.primary)
                        Text {
                            anchors.centerIn: parent
                            text: panel.busy ? "■" : "↑"
                            color: panel.busy ? panel.mutedColor : panel.surface
                            font.pixelSize: panel.busy ? 10 : 19
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

                // Context Rail: contexto explícito y portable; nada sensible se adjunta sin activarlo.
                Rectangle {
                    id: contextRail
                    visible: !panel.advancedOpen && !panel.pulseMode
                    height: visible ? 28 : 0
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: topRow.bottom
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    radius: 10
                    color: "transparent"
                    border.width: 0

                    Row {
                        anchors.left: parent.left
                        anchors.leftMargin: 7
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 6

                        Text {
                            visible: false
                            text: "CTX"
                        }

                        Rectangle {
                            id: agentChip
                            width: 62
                            height: 22
                            radius: 11
                            color: panel.agentEnabled
                                ? Qt.rgba(panel.primary.r, panel.primary.g, panel.primary.b, 0.18)
                                : (agentChipMouse.containsMouse ? panel.surfaceHighest : panel.surfaceContainer)
                            border.width: 1
                            border.color: panel.agentEnabled
                                ? Qt.rgba(panel.primary.r, panel.primary.g, panel.primary.b, 0.55)
                                : Qt.rgba(1, 1, 1, 0.05)
                            Text {
                                anchors.centerIn: parent
                                text: panel.agentEnabled ? "AGENT ✓" : "CHAT"
                                color: panel.agentEnabled ? panel.primary : panel.mutedColor
                                font.pixelSize: 8
                                font.weight: Font.Bold
                            }
                            MouseArea {
                                id: agentChipMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    panel.agentEnabled = !panel.agentEnabled
                                    panel.persistPreferences()
                                    panel.statusLabel = panel.agentEnabled ? "Agente activo" : "Chat activo"
                                }
                            }
                        }

                        Rectangle {
                            id: ttsChip
                            width: 46
                            height: 22
                            radius: 11
                            color: panel.voiceTtsEnabled
                                ? Qt.rgba(panel.tertiary.r, panel.tertiary.g, panel.tertiary.b, 0.16)
                                : (ttsChipMouse.containsMouse ? panel.surfaceHighest : panel.surfaceContainer)
                            border.width: 1
                            border.color: panel.voiceTtsEnabled
                                ? Qt.rgba(panel.tertiary.r, panel.tertiary.g, panel.tertiary.b, 0.48)
                                : Qt.rgba(1, 1, 1, 0.05)
                            Text {
                                anchors.centerIn: parent
                                text: panel.voiceTtsEnabled ? "TTS ✓" : "TTS"
                                color: panel.voiceTtsEnabled ? panel.tertiary : panel.mutedColor
                                font.pixelSize: 8
                                font.weight: Font.Bold
                            }
                            MouseArea {
                                id: ttsChipMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    panel.voiceTtsEnabled = !panel.voiceTtsEnabled
                                    panel.persistPreferences()
                                    panel.statusLabel = panel.voiceTtsEnabled ? "Voz de salida activa" : "Voz de salida desactivada"
                                }
                            }
                        }

                        Rectangle {
                            id: windowContextChip
                            width: 112
                            height: 22
                            radius: 11
                            color: panel.attachWindowContext
                                ? Qt.rgba(panel.primary.r, panel.primary.g, panel.primary.b, 0.16)
                                : (windowContextMouse.containsMouse ? panel.surfaceHighest : panel.surfaceContainer)
                            border.width: 1
                            border.color: panel.attachWindowContext
                                ? Qt.rgba(panel.primary.r, panel.primary.g, panel.primary.b, 0.48)
                                : Qt.rgba(1, 1, 1, 0.05)

                            Text {
                                anchors.fill: parent
                                anchors.leftMargin: 8
                                anchors.rightMargin: 8
                                verticalAlignment: Text.AlignVCenter
                                text: (panel.attachWindowContext ? "WIN ✓ · " : "WIN · ") + panel.focusedAppLabel
                                color: panel.attachWindowContext ? panel.primary : panel.mutedColor
                                font.pixelSize: 9
                                elide: Text.ElideRight
                            }
                            MouseArea {
                                id: windowContextMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    panel.attachWindowContext = !panel.attachWindowContext
                                    panel.refreshDesktopContext(panel.attachClipboardContext)
                                }
                            }
                        }

                        Rectangle {
                            id: clipboardContextChip
                            width: 64
                            height: 22
                            radius: 11
                            color: panel.attachClipboardContext
                                ? Qt.rgba(panel.tertiary.r, panel.tertiary.g, panel.tertiary.b, 0.16)
                                : (clipboardContextMouse.containsMouse ? panel.surfaceHighest : panel.surfaceContainer)
                            border.width: 1
                            border.color: panel.attachClipboardContext
                                ? Qt.rgba(panel.tertiary.r, panel.tertiary.g, panel.tertiary.b, 0.48)
                                : Qt.rgba(1, 1, 1, 0.05)

                            Text {
                                anchors.centerIn: parent
                                text: panel.attachClipboardContext ? "CLIP ✓" : "CLIP"
                                color: panel.attachClipboardContext ? panel.tertiary : panel.mutedColor
                                font.pixelSize: 9
                                font.weight: Font.DemiBold
                            }
                            MouseArea {
                                id: clipboardContextMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    panel.attachClipboardContext = !panel.attachClipboardContext
                                    panel.refreshDesktopContext(panel.attachClipboardContext)
                                }
                            }
                        }

                        Rectangle {
                            id: fileContextChip
                            visible: panel.attachedFileName !== ""
                            width: 150
                            height: 22
                            radius: 11
                            color: panel.attachedFileName !== ""
                                ? Qt.rgba(panel.secondary.r, panel.secondary.g, panel.secondary.b, 0.14)
                                : (fileContextMouse.containsMouse ? panel.surfaceHighest : panel.surfaceContainer)
                            border.width: 1
                            border.color: panel.attachedFileName !== ""
                                ? Qt.rgba(panel.secondary.r, panel.secondary.g, panel.secondary.b, 0.42)
                                : Qt.rgba(1, 1, 1, 0.05)

                            Text {
                                anchors.fill: parent
                                anchors.leftMargin: 8
                                anchors.rightMargin: 8
                                verticalAlignment: Text.AlignVCenter
                                text: panel.attachedFileName !== "" ? "FILE ✓ · " + panel.attachedFileName : "FILE · drop"
                                color: panel.attachedFileName !== "" ? panel.secondary : panel.mutedColor
                                font.pixelSize: 9
                                elide: Text.ElideMiddle
                            }
                            MouseArea {
                                id: fileContextMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (panel.attachedFileName !== "") panel.clearAttachedFile()
                                    else panel.statusLabel = "Arrastra un archivo sobre Mock"
                                }
                            }
                            Behavior on width { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                        }
                    }

                    Row {
                        anchors.right: parent.right
                        anchors.rightMargin: 9
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 10

                        Text {
                            visible: panel.workspaceLabel !== ""
                            text: panel.workspaceLabel
                            color: panel.outlineColor
                            font.pixelSize: 8
                        }
                        Text {
                            visible: panel.mediaLabel !== ""
                            width: Math.min(220, implicitWidth)
                            text: panel.mediaLabel
                            color: panel.mutedColor
                            font.pixelSize: 8
                            elide: Text.ElideRight
                        }
                    }
                }

                // Ajustes: proveedor, modelos, API y parámetros viven aquí, no en la vista principal.
                Rectangle {
                    id: settingsPanel
                    visible: panel.advancedOpen && !panel.pulseMode
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

                Item {
                    id: agentApprovalArea
                    visible: !panel.pulseMode && !panel.advancedOpen && panel.agentAwaitingApproval
                    height: visible ? 94 : 0
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: contextRail.bottom
                    anchors.leftMargin: 14
                    anchors.rightMargin: 14
                    anchors.topMargin: visible ? 7 : 0

                    Rectangle {
                        anchors.fill: parent
                        radius: 15
                        color: Qt.rgba(panel.tertiary.r, panel.tertiary.g, panel.tertiary.b, 0.08)
                        border.width: 1
                        border.color: Qt.rgba(panel.tertiary.r, panel.tertiary.g, panel.tertiary.b, 0.28)
                    }

                    Column {
                        anchors.left: parent.left
                        anchors.leftMargin: 12
                        anchors.right: approvalButtons.left
                        anchors.rightMargin: 12
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 3
                        Text {
                            width: parent.width
                            text: "Mock quiere actuar en tu PC"
                            color: panel.textColor
                            font.pixelSize: 11
                            font.weight: Font.DemiBold
                        }
                        Text {
                            width: parent.width
                            text: panel.agentPlanActionsText
                            color: panel.mutedColor
                            font.pixelSize: 9
                            wrapMode: Text.Wrap
                            maximumLineCount: 3
                            elide: Text.ElideRight
                        }
                    }

                    Row {
                        id: approvalButtons
                        anchors.right: parent.right
                        anchors.rightMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 7

                        Rectangle {
                            width: 72; height: 30; radius: 10
                            color: rejectAgentMouse.containsMouse ? panel.surfaceHighest : panel.surfaceHigh
                            Text { anchors.centerIn: parent; text: "Cancelar"; color: panel.mutedColor; font.pixelSize: 9 }
                            MouseArea {
                                id: rejectAgentMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: panel.rejectAgentPlan()
                            }
                        }
                        Rectangle {
                            width: 78; height: 30; radius: 10
                            color: approveAgentMouse.containsMouse ? Qt.lighter(panel.primary, 1.08) : panel.primary
                            Text { anchors.centerIn: parent; text: "Ejecutar"; color: panel.surface; font.pixelSize: 9; font.weight: Font.Bold }
                            MouseArea {
                                id: approveAgentMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: panel.executeAgentPlan(true)
                            }
                        }
                    }
                }

                Rectangle {
                    id: divider
                    visible: !panel.pulseMode && !panel.advancedOpen && panel.hasContent
                    height: 1
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: panel.agentAwaitingApproval ? agentApprovalArea.bottom : contextRail.bottom
                    anchors.leftMargin: 14
                    anchors.rightMargin: 14
                    color: Qt.rgba(1, 1, 1, 0.055)
                }

                Item {
                    id: responseArea
                    visible: !panel.pulseMode && !panel.advancedOpen && (panel.hasResponse || panel.hasError)
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
                                textFormat: TextEdit.MarkdownText
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
                    visible: !panel.pulseMode && !panel.advancedOpen && panel.hasContent
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

                DropArea {
                    id: fileDropArea
                    visible: app.shown && !panel.advancedOpen && !panel.pulseMode
                    anchors.fill: parent
                    z: 40
                    onEntered: drag => panel.dropHover = true
                    onExited: panel.dropHover = false
                    onDropped: drop => {
                        panel.dropHover = false
                        if (drop.urls && drop.urls.length > 0) panel.attachFile(String(drop.urls[0]))
                    }
                }

                Rectangle {
                    visible: panel.dropHover
                    anchors.fill: parent
                    anchors.margins: 7
                    radius: Math.max(12, islandCard.radius - 5)
                    color: Qt.rgba(panel.primary.r, panel.primary.g, panel.primary.b, 0.14)
                    border.width: 2
                    border.color: Qt.rgba(panel.primary.r, panel.primary.g, panel.primary.b, 0.68)
                    z: 41

                    Column {
                        anchors.centerIn: parent
                        spacing: 4
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: "Adjuntar a Mock"
                            color: panel.textColor
                            font.pixelSize: 14
                            font.weight: Font.DemiBold
                        }
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: "suelta un archivo de texto · máximo 8 MiB"
                            color: panel.mutedColor
                            font.pixelSize: 10
                        }
                    }
                }

                FocusScope {
                    anchors.fill: parent
                    focus: app.shown && panel.visible
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
                id: completionPulseTimer
                interval: 5200
                repeat: false
                onTriggered: panel.completionPulse = false
            }

            Timer {
                id: contextRefreshTimer
                interval: 2600
                repeat: true
                running: app.shown && panel.visible && !panel.advancedOpen
                onTriggered: panel.refreshDesktopContext(panel.attachClipboardContext)
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
                            panel.secondary = t.secondary || panel.secondary
                            panel.tertiary = t.tertiary || panel.tertiary
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
                id: contextProcess
                running: false
                command: ["python3", app.bridge, "context"]
                stdout: StdioCollector {
                    onStreamFinished: {
                        try { panel.desktopContext = JSON.parse(text) }
                        catch (e) {}

                        if (panel.pendingSendAfterContext && !panel.contextNeedsClipboard) {
                            panel.pendingSendAfterContext = false
                            panel.lastPrompt = panel.pendingPrompt
                            panel.startPrompt()
                        }
                    }
                }
                onExited: {
                    if (panel.contextNeedsClipboard) {
                        panel.contextNeedsClipboard = false
                        Qt.callLater(function() {
                            contextProcess.command = ["python3", app.bridge, "context", "--clipboard"]
                            contextProcess.running = true
                        })
                    }
                }
            }

            Process {
                id: fileContextProcess
                running: false
                property string requestedPath: ""
                command: ["python3", app.bridge, "file-context", requestedPath]
                stdout: StdioCollector {
                    onStreamFinished: {
                        try {
                            const f = JSON.parse(text)
                            if (!f.ok) {
                                errorText.text = f.error || "No pude adjuntar el archivo"
                                panel.statusLabel = "Archivo rechazado"
                                return
                            }
                            panel.attachedFilePath = f.path || ""
                            panel.attachedFileName = f.name || "archivo"
                            panel.attachedFileText = f.text || ""
                            panel.attachedFileTruncated = !!f.truncated
                            errorText.text = ""
                            panel.statusLabel = panel.attachedFileTruncated ? "Archivo adjunto · recortado" : "Archivo adjunto"
                        } catch (e) {
                            errorText.text = "No pude leer el archivo adjunto"
                        }
                    }
                }
            }

            Process {
                id: notifyProcess
                running: false
                command: ["sh", "-c", "command -v notify-send >/dev/null 2>&1 && notify-send --app-name='Mock Island' 'Mock' 'Respuesta lista' || true"]
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
                id: preferencesProcess
                stdinEnabled: true
                running: false
                property string payload: ""
                command: ["python3", app.bridge, "preferences"]
                onStarted: {
                    write(payload)
                    stdinEnabled = false
                }
                onExited: stdinEnabled = true
            }

            Process {
                id: voiceStatusProcess
                running: false
                command: ["python3", app.voiceBridge, "status"]
                stdout: StdioCollector {
                    onStreamFinished: {
                        try {
                            const v = JSON.parse(text)
                            panel.voiceReady = !!(v.pw_record && v.whisper_cli && v.whisper_model_ready)
                            panel.voiceMessage = panel.voiceReady ? "Voz lista" : (v.setup_hint || "mock-island voice-setup")
                            if (v.recording !== undefined) panel.voiceRecording = !!v.recording
                        } catch (e) {}
                    }
                }
            }

            Process {
                id: voiceStartProcess
                running: false
                command: ["python3", app.voiceBridge, "record-start"]
                stdout: StdioCollector {
                    onStreamFinished: {
                        try {
                            const v = JSON.parse(text)
                            if (!v.ok) {
                                panel.voiceRecording = false
                                errorText.text = v.error || "No pude iniciar el micrófono"
                                panel.statusLabel = "Voz no disponible"
                                return
                            }
                            panel.voiceRecording = true
                            panel.statusLabel = "Escuchando… pulsa MIC para terminar"
                            errorText.text = ""
                        } catch (e) {
                            panel.voiceRecording = false
                            errorText.text = "No pude iniciar la captura de voz"
                        }
                    }
                }
            }

            Process {
                id: voiceStopProcess
                running: false
                command: ["python3", app.voiceBridge, "record-stop"]
                stdout: StdioCollector {
                    onStreamFinished: {
                        panel.voiceRecording = false
                        try {
                            const v = JSON.parse(text)
                            if (!v.ok) {
                                errorText.text = v.error || "No pude transcribir la voz"
                                panel.statusLabel = "No entendí"
                                return
                            }
                            promptField.text = v.text || ""
                            panel.statusLabel = "Voz transcrita"
                            errorText.text = ""
                            if (panel.voiceAutoSend && promptField.text.trim() !== "") {
                                Qt.callLater(function() { panel.sendPrompt() })
                            } else {
                                Qt.callLater(function() { promptField.forceActiveFocus() })
                            }
                        } catch (e) {
                            errorText.text = "No pude leer la transcripción"
                        }
                    }
                }
            }

            Process {
                id: voiceSpeakProcess
                stdinEnabled: true
                running: false
                property string payload: ""
                command: ["python3", app.voiceBridge, "speak", "--stdin"]
                onStarted: {
                    panel.voiceSpeaking = true
                    write(payload)
                    stdinEnabled = false
                }
                stdout: StdioCollector {
                    onStreamFinished: {
                        try {
                            const v = JSON.parse(text)
                            if (!v.ok) console.warn("[Mock voice]", v.error || "TTS falló")
                        } catch (e) {}
                    }
                }
                onExited: {
                    stdinEnabled = true
                    panel.voiceSpeaking = false
                }
            }

            Process {
                id: agentPlanProcess
                stdinEnabled: true
                running: false
                property string payload: ""
                command: ["python3", app.agentRuntime, "plan", "--provider", panel.providerName, "--model", panel.modelName, "--stdin"]
                onStarted: {
                    panel.agentExecuting = true
                    write(payload)
                    stdinEnabled = false
                }
                stdout: StdioCollector {
                    onStreamFinished: {
                        try {
                            const plan = JSON.parse(text)
                            if (!plan.ok) {
                                panel.busy = false
                                panel.agentExecuting = false
                                errorText.text = plan.error || "No pude crear el plan"
                                panel.statusLabel = "Agente detenido"
                                return
                            }
                            if (plan.mode !== "agent" || !plan.actions || plan.actions.length === 0) {
                                panel.agentExecuting = false
                                panel.startChatPrompt()
                                return
                            }
                            panel.agentPlanJson = JSON.stringify(plan)
                            const labels = []
                            for (let i = 0; i < plan.actions.length; ++i) {
                                const a = plan.actions[i]
                                labels.push("• " + (a.display || a.label || a.tool) + (a.requires_confirmation ? "  · requiere permiso" : ""))
                            }
                            panel.agentPlanActionsText = labels.join("\n")
                            panel.busy = false
                            panel.agentExecuting = false
                            if (plan.needs_confirmation) {
                                panel.agentAwaitingApproval = true
                                panel.statusLabel = "Esperando aprobación"
                            } else {
                                panel.executeAgentPlan(false)
                            }
                        } catch (e) {
                            panel.busy = false
                            panel.agentExecuting = false
                            errorText.text = "El agente devolvió un plan inválido"
                        }
                    }
                }
                onExited: exitCode => {
                    stdinEnabled = true
                    if (exitCode !== 0 && panel.busy) {
                        panel.busy = false
                        panel.agentExecuting = false
                    }
                }
            }

            Process {
                id: agentExecuteProcess
                stdinEnabled: true
                running: false
                property string payload: ""
                onStarted: {
                    panel.agentExecuting = true
                    write(payload)
                    stdinEnabled = false
                }
                stdout: StdioCollector {
                    onStreamFinished: {
                        try {
                            const result = JSON.parse(text)
                            panel.responseText = result.summary || (result.error || "Acción finalizada")
                            if (!result.ok && result.error) errorText.text = result.error
                            panel.statusLabel = result.ok ? "Acción completada" : "Acción con incidencias"
                        } catch (e) {
                            errorText.text = "No pude leer el resultado del agente"
                        }
                    }
                }
                onExited: exitCode => {
                    stdinEnabled = true
                    panel.busy = false
                    panel.agentExecuting = false
                    panel.agentAwaitingApproval = false
                    panel.agentPlanJson = ""
                    panel.agentPlanActionsText = ""
                    if (exitCode !== 0 && errorText.text === "") errorText.text = "El runtime del agente terminó con error"
                    if (panel.voiceTtsEnabled && panel.responseText.length > 0) panel.speakResponse()
                    if (!app.shown) {
                        panel.completionPulse = true
                        completionPulseTimer.restart()
                        if (!notifyProcess.running) notifyProcess.running = true
                    }
                }
            }

            Process {
                id: aiProcess
                stdinEnabled: true
                running: false
                command: ["python3", app.bridge, "ask", "--provider", panel.providerName, "--model", panel.modelName]

                onStarted: {
                    panel.lastActivityMs = Date.now()
                    write(panel.composedPrompt() + "\n")
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
                    if (!wasCancelled && exitCode === 0) {
                        panel.statusLabel = "Listo"
                        if (panel.voiceTtsEnabled && panel.responseText.length > 0) panel.speakResponse()
                    }
                    if (!wasCancelled && !app.shown) {
                        panel.completionPulse = true
                        completionPulseTimer.restart()
                        if (!notifyProcess.running) notifyProcess.running = true
                    }
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
                function onVoiceToggleRequested(screenName) {
                    if (!panel.visible) return
                    if (screenName && panel.screen && panel.screen.name !== screenName) return
                    Qt.callLater(function() { panel.toggleVoice() })
                }
            }

            onVisibleChanged: {
                if (visible) {
                    if (!themeProcess.running) themeProcess.running = true
                    if (app.shown) {
                        refreshStatus()
                        if (!voiceStatusProcess.running) voiceStatusProcess.running = true
                        refreshDesktopContext(attachClipboardContext)
                        Qt.callLater(function() { promptField.forceActiveFocus() })
                    }
                } else {
                    modelPickerOpen = false
                    advancedOpen = false
                    dropHover = false
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
                if (s.agent) {
                    agentEnabled = !!s.agent.enabled
                }
                if (s.voice) {
                    voiceTtsEnabled = !!s.voice.tts_enabled
                    voiceAutoSend = s.voice.auto_send === undefined ? true : !!s.voice.auto_send
                }
                statusLabel = providerOnline ? "Listo" : "Configura proveedor"
            }

            function refreshStatus() {
                if (!statusProcess.running) statusProcess.running = true
                if (!voiceStatusProcess.running) voiceStatusProcess.running = true
            }

            function refreshDesktopContext(includeClipboard) {
                if (contextProcess.running) {
                    if (includeClipboard) contextNeedsClipboard = true
                    return
                }
                contextProcess.command = includeClipboard
                    ? ["python3", app.bridge, "context", "--clipboard"]
                    : ["python3", app.bridge, "context"]
                contextProcess.running = true
            }

            function attachFile(path) {
                if (!path || fileContextProcess.running) return
                fileContextProcess.requestedPath = path
                fileContextProcess.command = ["python3", app.bridge, "file-context", path]
                fileContextProcess.running = true
                statusLabel = "Leyendo archivo…"
            }

            function clearAttachedFile() {
                attachedFilePath = ""
                attachedFileName = ""
                attachedFileText = ""
                attachedFileTruncated = false
                statusLabel = "Archivo removido"
            }

            function composedPrompt() {
                const blocks = []
                const n = desktopContext && desktopContext.desktop ? desktopContext.desktop : null
                const c = desktopContext && desktopContext.clipboard ? desktopContext.clipboard : null

                if (attachWindowContext && n && n.available) {
                    const lines = []
                    if (n.app_id) lines.push("Aplicación: " + n.app_id)
                    if (n.title) lines.push("Ventana: " + n.title)
                    if (n.workspace) lines.push("Workspace: " + n.workspace)
                    if (n.output) lines.push("Monitor: " + n.output)
                    if (lines.length > 0) blocks.push("[Ventana activa]\n" + lines.join("\n"))
                }

                if (attachClipboardContext && c && c.available && c.text) {
                    blocks.push("[Portapapeles]\n" + c.text + (c.truncated ? "\n[contenido recortado]" : ""))
                }

                if (attachedFileText !== "") {
                    blocks.push("[Archivo: " + attachedFileName + "]\nRuta: " + attachedFilePath + "\n" + attachedFileText + (attachedFileTruncated ? "\n[contenido recortado]" : ""))
                }

                const request = pendingPrompt.trim()
                if (blocks.length === 0) return request
                return "Contexto de escritorio adjuntado explícitamente por el usuario:\n\n" + blocks.join("\n\n") + "\n\n[Solicitud]\n" + request
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
                    system_prompt: systemPromptField.text.trim(),
                    agent_enabled: agentEnabled,
                    voice_tts_enabled: voiceTtsEnabled,
                    voice_auto_send: voiceAutoSend
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

                const clipboardReady = desktopContext && desktopContext.clipboard
                    && desktopContext.clipboard.available
                    && desktopContext.clipboard.text
                if (attachClipboardContext && !clipboardReady) {
                    pendingSendAfterContext = true
                    statusLabel = "Leyendo portapapeles…"
                    if (contextProcess.running) contextNeedsClipboard = true
                    else refreshDesktopContext(true)
                    return
                }

                startPrompt()
            }

            function regenerate() {
                if (lastPrompt === "" || busy || configProcess.running || providerProcess.running) return
                pendingPrompt = lastPrompt
                if (attachClipboardContext) {
                    pendingSendAfterContext = true
                    statusLabel = "Actualizando portapapeles…"
                    if (contextProcess.running) contextNeedsClipboard = true
                    else refreshDesktopContext(true)
                    return
                }
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
                completionPulse = false
                agentAwaitingApproval = false
                agentPlanJson = ""
                agentPlanActionsText = ""
                busy = true
                lastActivityMs = Date.now()
                if (agentEnabled) startAgentPlan()
                else startChatPrompt()
            }

            function startChatPrompt() {
                if (!busy) busy = true
                agentExecuting = false
                statusLabel = "Pensando…"
                aiProcess.stdinEnabled = true
                aiProcess.command = ["python3", app.bridge, "ask", "--provider", providerName, "--model", modelName]
                aiProcess.running = true
            }

            function startAgentPlan() {
                statusLabel = "Planificando acción…"
                agentExecuting = true
                agentPlanProcess.payload = composedPrompt()
                agentPlanProcess.stdinEnabled = true
                agentPlanProcess.command = ["python3", app.agentRuntime, "plan", "--provider", providerName, "--model", modelName, "--stdin"]
                agentPlanProcess.running = true
            }

            function executeAgentPlan(approved) {
                if (agentPlanJson === "" || agentExecuteProcess.running) return
                agentAwaitingApproval = false
                busy = true
                agentExecuting = true
                responseText = ""
                errorText.text = ""
                statusLabel = "Actuando…"
                agentExecuteProcess.payload = agentPlanJson
                const cmd = ["python3", app.agentRuntime, "execute", "--provider", providerName, "--model", modelName, "--stdin"]
                if (approved) cmd.push("--approved")
                agentExecuteProcess.command = cmd
                agentExecuteProcess.stdinEnabled = true
                agentExecuteProcess.running = true
            }

            function rejectAgentPlan() {
                agentAwaitingApproval = false
                agentPlanJson = ""
                agentPlanActionsText = ""
                busy = false
                agentExecuting = false
                responseText = "Acción cancelada. No hice cambios en tu PC."
                statusLabel = "Cancelado"
            }

            function persistPreferences() {
                if (preferencesProcess.running) return
                preferencesProcess.payload = JSON.stringify({
                    agent_enabled: agentEnabled,
                    voice_tts_enabled: voiceTtsEnabled,
                    voice_auto_send: voiceAutoSend
                })
                preferencesProcess.stdinEnabled = true
                preferencesProcess.running = true
            }

            function toggleVoice() {
                if (voiceStartProcess.running || voiceStopProcess.running) return
                if (voiceRecording) {
                    statusLabel = "Transcribiendo…"
                    voiceStopProcess.running = true
                } else {
                    statusLabel = "Activando micrófono…"
                    voiceStartProcess.running = true
                }
            }

            function speakResponse() {
                if (!voiceTtsEnabled || responseText.length === 0 || voiceSpeakProcess.running) return
                voiceSpeakProcess.payload = responseText
                voiceSpeakProcess.stdinEnabled = true
                voiceSpeakProcess.running = true
            }

            function cancelPrompt(showLabel) {
                cancelRequested = true
                if (aiProcess.running) aiProcess.running = false
                if (agentPlanProcess.running) agentPlanProcess.running = false
                if (agentExecuteProcess.running) agentExecuteProcess.running = false
                flushStream(true)
                busy = false
                agentExecuting = false
                aiProcess.stdinEnabled = true
                agentPlanProcess.stdinEnabled = true
                agentExecuteProcess.stdinEnabled = true
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
                completionPulse = false
                agentAwaitingApproval = false
                agentPlanJson = ""
                agentPlanActionsText = ""
                clearProcess.running = true
                statusLabel = "Historial limpio"
            }
        }
    }
}
