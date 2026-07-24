import QtQuick
import QtQuick.Controls
import qs.Common
import qs.Widgets
import qs.Modules.Plugins
import Quickshell.Io

// Root plugin component for the alarm, timer, and pomodoro popout UI.
PluginComponent {
    id: root

    // Development helpers used for temporary on-screen debugging.
    property bool debugMode: false
    property string lastLogMessage: ""

    // Shell popout service injected by DankMaterialShell when available.
    property var popoutService: null

    // User-configurable defaults loaded from plugin settings.
    property int defaultMinutes: pluginData.defaultMinutes ?? 25
    property bool showSeconds: pluginData.showSeconds ?? true

    // Core runtime state shared by the timer and alarm flows.
    property string mode: "idle"
    property bool running: false
    property int remainingSeconds: 0

    // Current timer input values shown in the timer form.
    property int timerHours: 0
    property int timerMinutes: defaultMinutes
    property int timerSeconds: 0

    // Current alarm clock target time shown in the alarm form.
    property int alarmHour: 7
    property int alarmMinute: 0

    // Notification and sound options for finished timers and alarms.
    property string alarmCommand: pluginData.alarmCommand ?? "notify-send 'Alarm Timer' 'Time is up!' && canberra-gtk-play -i alarm-clock-elapsed"
    property bool soundEnabled: pluginData.soundEnabled ?? true
    property bool notificationShown: false

    // Tracks which popout tab is currently visible.
    property string currentTab: "alarm"

    // Saved Pomodoro defaults loaded from plugin settings.
    property int pomodoroFocusMinutes: pluginData.pomodoroFocusMinutes ?? 25
    property int pomodoroShortBreakMinutes: pluginData.pomodoroShortBreakMinutes ?? 5
    property int pomodoroLongBreakMinutes: pluginData.pomodoroLongBreakMinutes ?? 20
    property int pomodoroCycleTarget: pluginData.pomodoroCycleTarget ?? 4

    // Current Pomodoro runtime state.
    property string pomodoroMode: "idle"
    property bool pomodoroRunning: false
    property int pomodoroRemainingSeconds: pomodoroFocusMinutes * 60
    property int pomodoroCompletedSessions: 0

    // Controls whether the Pomodoro settings panel is expanded.
    property bool pomodoroSettingsOpen: false

    // Stores the full duration of the active Pomodoro phase for ring progress.
    property int pomodoroTotalSeconds: pomodoroFocusMinutes * 60

    // Converts raw seconds into a user-friendly display string.
    function formatTime(totalSeconds) {
        const s = Math.max(0, totalSeconds);
        const h = Math.floor(s / 3600);
        const m = Math.floor((s % 3600) / 60);
        const sec = s % 60;

        if (h > 0)
            return showSeconds ? `${h}:${String(m).padStart(2, "0")}:${String(sec).padStart(2, "0")}` : `${h}h ${m}m`;

        return showSeconds ? `${m}:${String(sec).padStart(2, "0")}` : `${m}m`;
    }

    // Resets the notification guard so a new alert can be shown later.
    function clearAlertState() {
        notificationShown = false;
    }

    // Returns the display label for the active Pomodoro phase.
    function pomodoroPhaseLabel() {
        if (pomodoroMode === "focus")
            return "Focus";
        if (pomodoroMode === "shortBreak")
            return "Short Break";
        if (pomodoroMode === "longBreak")
            return "Long Break";
        if (pomodoroMode === "paused")
            return "Paused";
        return "Ready";
    }

    // Returns Pomodoro progress as a value between 0 and 1.
    function pomodoroProgress() {
        if (pomodoroTotalSeconds <= 0)
            return 0;
        return Math.max(0, Math.min(1, pomodoroRemainingSeconds / pomodoroTotalSeconds));
    }

    // Applies Pomodoro settings entered by the user and resets the current session.
    function applyPomodoroSettings(focusMinutes, shortBreakMinutes, longBreakMinutes, cycleTarget) {
        pomodoroFocusMinutes = Math.max(1, Number(focusMinutes) || 25);
        pomodoroShortBreakMinutes = Math.max(1, Number(shortBreakMinutes) || 5);
        pomodoroLongBreakMinutes = Math.max(1, Number(longBreakMinutes) || 20);
        pomodoroCycleTarget = Math.max(1, Number(cycleTarget) || 4);
        resetPomodoro();
    }

    // Starts a new Pomodoro focus session using the configured focus length.
    function startPomodoroFocus() {
        clearAlertState();
        pomodoroMode = "focus";
        pomodoroTotalSeconds = pomodoroFocusMinutes * 60;
        pomodoroRemainingSeconds = pomodoroTotalSeconds;
        pomodoroRunning = true;
    }

    // Starts the correct Pomodoro break based on the completed session count.
    function startPomodoroBreak() {
        clearAlertState();

        const shouldUseLongBreak = pomodoroCompletedSessions > 0 && pomodoroCompletedSessions % pomodoroCycleTarget === 0;
        if (shouldUseLongBreak) {
            pomodoroMode = "longBreak";
            pomodoroTotalSeconds = pomodoroLongBreakMinutes * 60;
            pomodoroRemainingSeconds = pomodoroTotalSeconds;
        } else {
            pomodoroMode = "shortBreak";
            pomodoroTotalSeconds = pomodoroShortBreakMinutes * 60;
            pomodoroRemainingSeconds = pomodoroTotalSeconds;
        }

        pomodoroRunning = true;
    }

    // Pauses the current Pomodoro phase without clearing the remaining time.
    function pausePomodoro() {
        if (!pomodoroRunning)
            return;
        pomodoroRunning = false;
        if (pomodoroMode === "focus" || pomodoroMode === "shortBreak" || pomodoroMode === "longBreak")
            pomodoroMode = "paused";
    }

    // Resumes the paused Pomodoro phase based on the remaining time and session cycle.
    function resumePomodoro() {
        if (pomodoroRunning)
            return;

        if (pomodoroMode === "paused") {
            const focusDuration = pomodoroFocusMinutes * 60;
            const shortDuration = pomodoroShortBreakMinutes * 60;
            const longDuration = pomodoroLongBreakMinutes * 60;

            if (pomodoroRemainingSeconds <= focusDuration && pomodoroRemainingSeconds > shortDuration) {
                pomodoroMode = "focus";
                pomodoroTotalSeconds = focusDuration;
            } else if (pomodoroRemainingSeconds === focusDuration) {
                pomodoroMode = "focus";
                pomodoroTotalSeconds = focusDuration;
            } else {
                const shouldUseLongBreak = pomodoroCompletedSessions > 0 && pomodoroCompletedSessions % pomodoroCycleTarget === 0;
                pomodoroMode = shouldUseLongBreak && pomodoroRemainingSeconds <= longDuration ? "longBreak" : "shortBreak";
                pomodoroTotalSeconds = pomodoroMode === "longBreak" ? longDuration : shortDuration;
            }
        } else if (pomodoroMode === "idle") {
            pomodoroMode = "focus";
            pomodoroTotalSeconds = pomodoroFocusMinutes * 60;
            pomodoroRemainingSeconds = pomodoroTotalSeconds;
        }

        pomodoroRunning = true;
    }

    // Moves the Pomodoro workflow to the next phase when one phase finishes.
    function advancePomodoroPhase() {
        if (pomodoroMode === "focus") {
            pomodoroCompletedSessions += 1;
            triggerAlert("Pomodoro", "Focus session finished.");
            startPomodoroBreak();
            return;
        }

        if (pomodoroMode === "shortBreak" || pomodoroMode === "longBreak") {
            triggerAlert("Pomodoro", "Break finished. Back to focus.");
            pomodoroMode = "idle";
            pomodoroRunning = false;
            pomodoroTotalSeconds = pomodoroFocusMinutes * 60;
            pomodoroRemainingSeconds = pomodoroTotalSeconds;
        }
    }

    // Resets the Pomodoro workflow back to the configured default focus state.
    function resetPomodoro() {
        pomodoroMode = "idle";
        pomodoroRunning = false;
        pomodoroCompletedSessions = 0;
        pomodoroTotalSeconds = pomodoroFocusMinutes * 60;
        pomodoroRemainingSeconds = pomodoroTotalSeconds;
        clearAlertState();
    }

    // Skips the current Pomodoro phase and moves to the next logical step.
    function skipPomodoroPhase() {
        if (pomodoroMode === "focus") {
            pomodoroCompletedSessions += 1;
            startPomodoroBreak();
        } else if (pomodoroMode === "shortBreak" || pomodoroMode === "longBreak" || pomodoroMode === "paused") {
            pomodoroMode = "idle";
            pomodoroRunning = false;
            pomodoroTotalSeconds = pomodoroFocusMinutes * 60;
            pomodoroRemainingSeconds = pomodoroTotalSeconds;
        } else {
            startPomodoroFocus();
        }
    }

    // Runs external system commands for notifications and alarm sounds.
    Process {
        id: alertProcess
        running: false
    }

    // Sends a desktop notification and optionally plays an alarm sound.
    function triggerAlert(title, message) {
        if (notificationShown)
            return;
        notificationShown = true;
        lastLogMessage = `${title}: ${message}`;

        const escapedTitle = String(title).replace(/'/g, "'\\''");
        const escapedMessage = String(message).replace(/'/g, "'\\''");

        let command = `notify-send '${escapedTitle}' '${escapedMessage}'`;
        if (soundEnabled) {
            command += " && (canberra-gtk-play -i alarm-clock-elapsed || paplay /usr/share/sounds/freedesktop/stereo/alarm-clock-elapsed.oga || pw-play /usr/share/sounds/freedesktop/stereo/alarm-clock-elapsed.oga)";
        }

        alertProcess.command = ["sh", "-c", command];
        alertProcess.running = true;
    }

    // Starts a countdown timer using the entered hour, minute, and second values.
    function startTimer(hours, minutes, seconds) {
        const h = Number(hours) || 0;
        const m = Number(minutes) || 0;
        const s = Number(seconds) || 0;
        const totalSeconds = (h * 3600) + (m * 60) + s;

        if (totalSeconds <= 0)
            return;
        clearAlertState();
        timerHours = h;
        timerMinutes = m;
        timerSeconds = s;
        remainingSeconds = totalSeconds;
        mode = "timer";
        running = true;
    }

    // Arms a clock-based alarm for the selected hour and minute.
    function setAlarm(hour, minute) {
        alarmHour = Math.max(0, Math.min(23, Number(hour) || 0));
        alarmMinute = Math.max(0, Math.min(59, Number(minute) || 0));
        clearAlertState();
        mode = "alarm";
        running = true;
    }

    // Stops any active timer or alarm and returns the plugin to idle state.
    function stopAll() {
        mode = "idle";
        running = false;
        remainingSeconds = 0;
        clearAlertState();
    }

    // Reusable styled text field used by timer and alarm inputs.
    component ThemedField: TextField {
        id: control
        implicitHeight: 40
        color: Theme.surfaceText
        selectedTextColor: Theme.surface
        selectionColor: Theme.primary
        placeholderTextColor: Qt.rgba(1, 1, 1, 0.45)

        background: Rectangle {
            radius: Theme.cornerRadius
            color: Theme.surfaceContainerHighest
            border.width: control.activeFocus ? 2 : 1
            border.color: control.activeFocus ? Theme.primary : Qt.rgba(1, 1, 1, 0.10)
        }
    }

    // Reusable primary action button for main actions such as Start or Set.
    component ThemedButton: Button {
        id: control
        implicitHeight: 40
        implicitWidth: 72

        contentItem: Text {
            text: control.text
            color: Theme.surface
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            font.pixelSize: Theme.fontSizeMedium
            font.weight: Font.DemiBold
        }

        background: Rectangle {
            radius: Theme.cornerRadius
            color: control.down ? Qt.darker(Theme.primary, 1.15) : Theme.primary
        }
    }

    // Reusable secondary button for quick timer presets and lower-priority actions.
    component SecondaryButton: Button {
        id: control
        implicitHeight: 40
        implicitWidth: 72

        contentItem: Text {
            text: control.text
            color: Theme.surfaceText
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            font.pixelSize: Theme.fontSizeMedium
            font.weight: Font.Medium
        }

        background: Rectangle {
            radius: Theme.cornerRadius
            color: Theme.surfaceContainerHighest
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.10)
        }
    }

    // Main repeating timer loop that updates countdowns and checks alarm time matches.
    Timer {
        interval: 1000
        repeat: true
        running: root.running

        onTriggered: {
            if (root.mode === "timer") {
                if (root.remainingSeconds > 0) {
                    root.remainingSeconds--;
                } else {
                    root.running = false;
                    root.mode = "ringing";
                    root.triggerAlert("Alarm Timer", "Your timer has finished.");
                }
            } else if (root.mode === "alarm") {
                const now = new Date();
                if (now.getHours() === root.alarmHour && now.getMinutes() === root.alarmMinute) {
                    root.running = false;
                    root.mode = "ringing";
                    root.triggerAlert("Alarm Timer", "Your alarm is ringing.");
                }
            }
        }
    }

    // Repeating timer loop dedicated to Pomodoro countdown updates.
    Timer {
        interval: 1000
        repeat: true
        running: root.pomodoroRunning

        onTriggered: {
            if (root.pomodoroRemainingSeconds > 0) {
                root.pomodoroRemainingSeconds--;
            } else {
                root.pomodoroRunning = false;
                root.advancePomodoroPhase();
            }
        }
    }

    // Horizontal bar icon shown when the plugin is placed in a horizontal bar.
    horizontalBarPill: Component {
        Item {
            implicitWidth: Theme.iconSize + 8
            implicitHeight: Theme.iconSize + 8

            DankIcon {
                anchors.centerIn: parent
                name: root.mode === "timer" ? "timer" : "alarm"
                size: Theme.iconSize
                color: root.mode === "ringing" ? Theme.error : Theme.primary
            }
        }
    }

    // Vertical bar icon shown when the plugin is placed in a vertical bar.
    verticalBarPill: Component {
        Item {
            implicitWidth: Theme.iconSize + 8
            implicitHeight: Theme.iconSize + 8

            DankIcon {
                anchors.centerIn: parent
                name: root.mode === "timer" ? "timer" : "alarm"
                size: Theme.iconSize
                color: root.mode === "ringing" ? Theme.error : Theme.primary
            }
        }
    }

    // Defines the default size of the plugin popout window.
    popoutWidth: 420
    popoutHeight: 560

    // Main popout content containing the tab switcher and both tab screens.
    popoutContent: Component {
        PopoutComponent {
            id: alarmPopout

            // Header content changes depending on the currently active tab and mode.
            headerText: "Alarm Clock"
            detailsText: root.currentTab === "pomodoro" ? `${root.pomodoroPhaseLabel()}: ${root.formatTime(root.pomodoroRemainingSeconds)}` : root.mode === "idle" ? "Set a timer or alarm" : root.mode === "timer" ? `Timer: ${root.formatTime(root.remainingSeconds)}` : root.mode === "alarm" ? `Alarm set for ${String(root.alarmHour).padStart(2, "0")}:${String(root.alarmMinute).padStart(2, "0")}` : "Ringing"
            showCloseButton: true

            // Wrapper item that reserves the usable area below the popout header.
            Item {
                width: parent.width
                implicitHeight: root.popoutHeight - alarmPopout.headerHeight - alarmPopout.detailsHeight - Theme.spacingXL

                // Scrollable container for the entire popout body.
                Flickable {
                    anchors.fill: parent
                    clip: true
                    contentWidth: width
                    contentHeight: contentColumn.implicitHeight
                    boundsBehavior: Flickable.StopAtBounds

                    // Main vertical layout for the tab switcher and tab contents.
                    Column {
                        id: contentColumn
                        width: parent.width
                        spacing: Theme.spacingM

                        // Top tab switcher used to move between Alarm/Timer and Pomodoro.
                        StyledRect {
                            width: parent.width
                            implicitHeight: tabRow.implicitHeight + Theme.spacingS * 2
                            radius: Theme.cornerRadius
                            color: Theme.surfaceContainerHigh
                            border.width: 0

                            Row {
                                id: tabRow
                                anchors.fill: parent
                                anchors.margins: Theme.spacingS
                                spacing: Theme.spacingS

                                // Alarm and timer tab button.
                                Button {
                                    id: alarmTabButton
                                    width: (parent.width - Theme.spacingS) / 2
                                    height: 40
                                    text: "Alarm / Timer"
                                    onClicked: root.currentTab = "alarm"

                                    contentItem: Text {
                                        text: alarmTabButton.text
                                        color: root.currentTab === "alarm" ? Theme.surface : Theme.surfaceText
                                        horizontalAlignment: Text.AlignHCenter
                                        verticalAlignment: Text.AlignVCenter
                                        font.pixelSize: Theme.fontSizeMedium
                                        font.weight: Font.DemiBold
                                    }

                                    background: Rectangle {
                                        radius: Theme.cornerRadius
                                        color: root.currentTab === "alarm" ? Theme.primary : Theme.surfaceContainerHighest
                                        border.width: root.currentTab === "alarm" ? 0 : 1
                                        border.color: Qt.rgba(1, 1, 1, 0.10)
                                    }
                                }

                                // Pomodoro tab button.
                                Button {
                                    id: pomodoroTabButton
                                    width: (parent.width - Theme.spacingS) / 2
                                    height: 40
                                    text: "Pomodoro"
                                    onClicked: root.currentTab = "pomodoro"

                                    contentItem: Text {
                                        text: pomodoroTabButton.text
                                        color: root.currentTab === "pomodoro" ? Theme.surface : Theme.surfaceText
                                        horizontalAlignment: Text.AlignHCenter
                                        verticalAlignment: Text.AlignVCenter
                                        font.pixelSize: Theme.fontSizeMedium
                                        font.weight: Font.DemiBold
                                    }

                                    background: Rectangle {
                                        radius: Theme.cornerRadius
                                        color: root.currentTab === "pomodoro" ? Theme.primary : Theme.surfaceContainerHighest
                                        border.width: root.currentTab === "pomodoro" ? 0 : 1
                                        border.color: Qt.rgba(1, 1, 1, 0.10)
                                    }
                                }
                            }
                        }

                        // Alarm and timer tab body.
                        Column {
                            width: parent.width
                            spacing: Theme.spacingM
                            visible: root.currentTab === "alarm"

                            // Current timer or alarm status card shown at the top of the alarm tab.
                            StyledRect {
                                width: parent.width
                                height: 84
                                radius: Theme.cornerRadius
                                color: root.mode === "ringing" ? Theme.primary : Theme.surfaceContainerHighest
                                border.width: 0

                                Column {
                                    anchors.centerIn: parent
                                    spacing: 4

                                    StyledText {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        text: root.mode === "timer" ? "Timer Running" : root.mode === "alarm" ? "Alarm Armed" : root.mode === "ringing" ? "Finished" : "Ready"
                                        font.pixelSize: Theme.fontSizeMedium
                                        font.weight: Font.DemiBold
                                        color: root.mode === "ringing" ? Theme.surface : Theme.surfaceText
                                    }

                                    StyledText {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        text: root.mode === "timer" ? root.formatTime(root.remainingSeconds) : root.mode === "alarm" ? `${String(root.alarmHour).padStart(2, "0")}:${String(root.alarmMinute).padStart(2, "0")}` : `${root.timerHours}h ${root.timerMinutes}m ${root.timerSeconds}s`
                                        font.pixelSize: Theme.fontSizeXLarge
                                        font.weight: Font.Bold
                                        color: root.mode === "ringing" ? Theme.surface : Theme.primary
                                    }
                                }
                            }

                            // Countdown timer controls including manual entry and quick presets.
                            StyledRect {
                                width: parent.width
                                implicitHeight: timerControls.implicitHeight + Theme.spacingM * 2
                                radius: Theme.cornerRadius
                                color: Theme.surfaceContainerHigh
                                border.width: 0

                                Column {
                                    id: timerControls
                                    anchors.fill: parent
                                    anchors.margins: Theme.spacingM
                                    spacing: Theme.spacingS

                                    StyledText {
                                        text: "Countdown Timer"
                                        font.pixelSize: Theme.fontSizeMedium
                                        font.weight: Font.DemiBold
                                        color: Theme.surfaceText
                                    }

                                    Flow {
                                        width: parent.width
                                        spacing: Theme.spacingS

                                        ThemedField {
                                            id: hoursField
                                            width: 78
                                            text: String(root.timerHours)
                                            placeholderText: "HH"
                                        }

                                        ThemedField {
                                            id: minutesField
                                            width: 78
                                            text: String(root.timerMinutes).padStart(2, "0")
                                            placeholderText: "MM"
                                        }

                                        ThemedField {
                                            id: secondsField
                                            width: 78
                                            text: String(root.timerSeconds).padStart(2, "0")
                                            placeholderText: "SS"
                                        }

                                        ThemedButton {
                                            width: 96
                                            text: "Start"
                                            onClicked: root.startTimer(hoursField.text, minutesField.text, secondsField.text)
                                        }
                                    }

                                    Flow {
                                        width: parent.width
                                        spacing: Theme.spacingS

                                        SecondaryButton {
                                            text: "15s"
                                            onClicked: root.startTimer(0, 0, 15)
                                        }
                                        SecondaryButton {
                                            text: "30s"
                                            onClicked: root.startTimer(0, 0, 30)
                                        }
                                        SecondaryButton {
                                            text: "1m"
                                            onClicked: root.startTimer(0, 1, 0)
                                        }
                                        SecondaryButton {
                                            text: "15m"
                                            onClicked: root.startTimer(0, 15, 0)
                                        }
                                        SecondaryButton {
                                            text: "1h"
                                            onClicked: root.startTimer(1, 0, 0)
                                        }
                                    }
                                }
                            }

                            // Alarm clock controls for setting a specific hour and minute.
                            StyledRect {
                                width: parent.width
                                implicitHeight: alarmControls.implicitHeight + Theme.spacingM * 2
                                radius: Theme.cornerRadius
                                color: Theme.surfaceContainerHigh
                                border.width: 0

                                Column {
                                    id: alarmControls
                                    anchors.fill: parent
                                    anchors.margins: Theme.spacingM
                                    spacing: Theme.spacingS

                                    StyledText {
                                        text: "Alarm Time"
                                        font.pixelSize: Theme.fontSizeMedium
                                        font.weight: Font.DemiBold
                                        color: Theme.surfaceText
                                    }

                                    Row {
                                        width: parent.width
                                        spacing: Theme.spacingS

                                        ThemedField {
                                            id: hourField
                                            width: 88
                                            text: String(root.alarmHour).padStart(2, "0")
                                            placeholderText: "HH"
                                        }

                                        ThemedField {
                                            id: minuteField
                                            width: 88
                                            text: String(root.alarmMinute).padStart(2, "0")
                                            placeholderText: "MM"
                                        }

                                        ThemedButton {
                                            width: 84
                                            text: "Set"
                                            onClicked: root.setAlarm(hourField.text, minuteField.text)
                                        }
                                    }
                                }
                            }

                            // Optional debug panel used while developing the plugin.
                            StyledRect {
                                visible: root.debugMode
                                width: parent.width
                                implicitHeight: debugColumn.implicitHeight + Theme.spacingM * 2
                                radius: Theme.cornerRadius
                                color: Theme.surfaceContainerHigh
                                border.width: 1
                                border.color: Qt.rgba(1, 1, 1, 0.10)

                                Column {
                                    id: debugColumn
                                    anchors.fill: parent
                                    anchors.margins: Theme.spacingM
                                    spacing: Theme.spacingXS

                                    StyledText {
                                        text: "Debug"
                                        font.pixelSize: Theme.fontSizeMedium
                                        font.weight: Font.DemiBold
                                        color: Theme.surfaceText
                                    }

                                    StyledText {
                                        text: root.lastLogMessage.length > 0 ? root.lastLogMessage : "No alert has fired yet."
                                        font.pixelSize: Theme.fontSizeSmall
                                        color: Theme.surfaceText
                                        wrapMode: Text.WordWrap
                                        width: parent.width
                                    }

                                    StyledText {
                                        text: `Mode: ${root.mode} | Running: ${root.running} | Remaining: ${root.remainingSeconds}`
                                        font.pixelSize: Theme.fontSizeSmall
                                        color: Theme.surfaceVariantText
                                        wrapMode: Text.WordWrap
                                        width: parent.width
                                    }
                                }
                            }

                            // Button that stops the current timer or alarm and clears active state.
                            Button {
                                id: clearButton
                                width: parent.width
                                height: 42
                                text: "Stop / Clear"
                                onClicked: root.stopAll()

                                contentItem: Text {
                                    text: clearButton.text
                                    color: Theme.surfaceText
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                    font.pixelSize: Theme.fontSizeMedium
                                    font.weight: Font.DemiBold
                                }

                                background: Rectangle {
                                    radius: Theme.cornerRadius
                                    color: Theme.surfaceContainerHighest
                                    border.width: 1
                                    border.color: Qt.rgba(1, 1, 1, 0.10)
                                }
                            }
                        }

                        // Pomodoro tab body with status, settings, and controls.
                        Column {
                            width: parent.width
                            spacing: Theme.spacingM
                            visible: root.currentTab === "pomodoro"

                            // Main Pomodoro status card with a gear button and circular countdown ring.
                            StyledRect {
                                width: parent.width
                                implicitHeight: pomodoroCard.implicitHeight + Theme.spacingM * 2
                                radius: Theme.cornerRadius
                                color: Theme.surfaceContainerHigh
                                border.width: 0

                                Column {
                                    id: pomodoroCard
                                    anchors.fill: parent
                                    anchors.margins: Theme.spacingM
                                    spacing: Theme.spacingM

                                    Row {
                                        width: parent.width
                                        spacing: Theme.spacingS

                                        Column {
                                            width: parent.width - settingsButton.width - Theme.spacingS
                                            spacing: 4

                                            StyledText {
                                                text: "Pomodoro"
                                                font.pixelSize: Theme.fontSizeMedium
                                                font.weight: Font.DemiBold
                                                color: Theme.surfaceText
                                            }

                                            StyledText {
                                                text: `${root.pomodoroPhaseLabel()} • Session ${Math.min(root.pomodoroCompletedSessions + 1, root.pomodoroCycleTarget)} / ${root.pomodoroCycleTarget}`
                                                font.pixelSize: Theme.fontSizeSmall
                                                color: Theme.surfaceVariantText
                                            }
                                        }

                                        Button {
                                            id: settingsButton
                                            width: 40
                                            height: 40
                                            onClicked: root.pomodoroSettingsOpen = !root.pomodoroSettingsOpen

                                            background: Rectangle {
                                                radius: Theme.cornerRadius
                                                color: root.pomodoroSettingsOpen ? Theme.primary : Theme.surfaceContainerHighest
                                                border.width: root.pomodoroSettingsOpen ? 0 : 1
                                                border.color: Qt.rgba(1, 1, 1, 0.10)
                                            }

                                            contentItem: Text {
                                                text: "⚙"
                                                font.pixelSize: 18
                                                font.weight: Font.DemiBold
                                                horizontalAlignment: Text.AlignHCenter
                                                verticalAlignment: Text.AlignVCenter
                                                color: root.pomodoroSettingsOpen ? Theme.surface : Theme.surfaceText
                                            }
                                        }
                                    }

                                    Item {
                                        width: 180
                                        height: 180
                                        anchors.horizontalCenter: parent.horizontalCenter

                                        Canvas {
                                            id: pomodoroRing
                                            anchors.fill: parent
                                            antialiasing: true

                                            onPaint: {
                                                const ctx = getContext("2d");
                                                const centerX = width / 2;
                                                const centerY = height / 2;
                                                const lineWidth = 10;
                                                const radius = (width / 2) - lineWidth;
                                                const startAngle = -Math.PI / 2;
                                                const fullAngle = startAngle + (Math.PI * 2);
                                                const progressAngle = startAngle + (Math.PI * 2 * root.pomodoroProgress());

                                                if (ctx.reset)
                                                    ctx.reset();
                                                else
                                                    ctx.clearRect(0, 0, width, height);

                                                ctx.lineCap = "round";
                                                ctx.lineWidth = lineWidth;

                                                ctx.beginPath();
                                                ctx.arc(centerX, centerY, radius, startAngle, fullAngle, false);
                                                ctx.strokeStyle = Qt.rgba(1, 1, 1, 0.10);
                                                ctx.stroke();

                                                ctx.beginPath();
                                                ctx.arc(centerX, centerY, radius, startAngle, progressAngle, false);
                                                ctx.strokeStyle = Theme.primary;
                                                ctx.stroke();
                                            }

                                            Connections {
                                                target: root

                                                function onPomodoroRemainingSecondsChanged() {
                                                    pomodoroRing.requestPaint();
                                                }

                                                function onPomodoroTotalSecondsChanged() {
                                                    pomodoroRing.requestPaint();
                                                }

                                                function onPomodoroModeChanged() {
                                                    pomodoroRing.requestPaint();
                                                }
                                            }
                                        }

                                        Column {
                                            anchors.centerIn: parent
                                            spacing: 4

                                            StyledText {
                                                anchors.horizontalCenter: parent.horizontalCenter
                                                text: root.pomodoroPhaseLabel()
                                                font.pixelSize: Theme.fontSizeSmall
                                                color: Theme.surfaceVariantText
                                            }

                                            StyledText {
                                                anchors.horizontalCenter: parent.horizontalCenter
                                                text: root.formatTime(root.pomodoroRemainingSeconds)
                                                font.pixelSize: Theme.fontSizeXLarge
                                                font.weight: Font.Bold
                                                color: Theme.primary
                                            }
                                        }
                                    }

                                    Row {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        spacing: Theme.spacingXS

                                        Repeater {
                                            model: root.pomodoroCycleTarget

                                            Rectangle {
                                                width: 10
                                                height: 10
                                                radius: 5
                                                color: index < root.pomodoroCompletedSessions ? Theme.primary : Theme.surfaceContainerHighest
                                                border.width: index < root.pomodoroCompletedSessions ? 0 : 1
                                                border.color: Qt.rgba(1, 1, 1, 0.12)
                                            }
                                        }
                                    }

                                    Flow {
                                        width: parent.width
                                        spacing: Theme.spacingS

                                        ThemedButton {
                                            width: 110
                                            text: root.pomodoroMode === "idle" ? "Start Focus" : root.pomodoroMode === "paused" ? "Resume" : "Restart"
                                            onClicked: {
                                                if (root.pomodoroMode === "paused")
                                                    root.resumePomodoro();
                                                else
                                                    root.startPomodoroFocus();
                                            }
                                        }

                                        SecondaryButton {
                                            width: 90
                                            text: root.pomodoroRunning ? "Pause" : "Break"
                                            onClicked: {
                                                if (root.pomodoroRunning)
                                                    root.pausePomodoro();
                                                else
                                                    root.startPomodoroBreak();
                                            }
                                        }

                                        SecondaryButton {
                                            width: 78
                                            text: "Skip"
                                            onClicked: root.skipPomodoroPhase()
                                        }

                                        SecondaryButton {
                                            width: 78
                                            text: "Reset"
                                            onClicked: root.resetPomodoro()
                                        }
                                    }

                                    // Expandable Pomodoro settings panel used to customize phase durations.
                                    StyledRect {
                                        visible: root.pomodoroSettingsOpen
                                        width: parent.width
                                        implicitHeight: settingsColumn.implicitHeight + Theme.spacingM * 2
                                        radius: Theme.cornerRadius
                                        color: Theme.surfaceContainerHighest
                                        border.width: 1
                                        border.color: Qt.rgba(1, 1, 1, 0.10)

                                        Column {
                                            id: settingsColumn
                                            anchors.fill: parent
                                            anchors.margins: Theme.spacingM
                                            spacing: Theme.spacingS

                                            StyledText {
                                                text: "Pomodoro Settings"
                                                font.pixelSize: Theme.fontSizeMedium
                                                font.weight: Font.DemiBold
                                                color: Theme.surfaceText
                                            }

                                            StyledText {
                                                text: "Change the default focus, break, and cycle values."
                                                font.pixelSize: Theme.fontSizeSmall
                                                color: Theme.surfaceVariantText
                                                wrapMode: Text.WordWrap
                                                width: parent.width
                                            }

                                            Flow {
                                                width: parent.width
                                                spacing: Theme.spacingS

                                                ThemedField {
                                                    id: focusMinutesField
                                                    width: 84
                                                    text: String(root.pomodoroFocusMinutes)
                                                    placeholderText: "Focus"
                                                }

                                                ThemedField {
                                                    id: shortBreakField
                                                    width: 84
                                                    text: String(root.pomodoroShortBreakMinutes)
                                                    placeholderText: "Short"
                                                }

                                                ThemedField {
                                                    id: longBreakField
                                                    width: 84
                                                    text: String(root.pomodoroLongBreakMinutes)
                                                    placeholderText: "Long"
                                                }

                                                ThemedField {
                                                    id: cycleTargetField
                                                    width: 84
                                                    text: String(root.pomodoroCycleTarget)
                                                    placeholderText: "Cycles"
                                                }
                                            }

                                            Flow {
                                                width: parent.width
                                                spacing: Theme.spacingS

                                                ThemedButton {
                                                    width: 92
                                                    text: "Apply"
                                                    onClicked: root.applyPomodoroSettings(focusMinutesField.text, shortBreakField.text, longBreakField.text, cycleTargetField.text)
                                                }

                                                SecondaryButton {
                                                    width: 92
                                                    text: "Defaults"
                                                    onClicked: {
                                                        focusMinutesField.text = String(pluginData.pomodoroFocusMinutes ?? 25);
                                                        shortBreakField.text = String(pluginData.pomodoroShortBreakMinutes ?? 5);
                                                        longBreakField.text = String(pluginData.pomodoroLongBreakMinutes ?? 20);
                                                        cycleTargetField.text = String(pluginData.pomodoroCycleTarget ?? 4);
                                                        root.applyPomodoroSettings(focusMinutesField.text, shortBreakField.text, longBreakField.text, cycleTargetField.text);
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            // Preset summary card showing the currently configured Pomodoro timings.
                            StyledRect {
                                width: parent.width
                                implicitHeight: presetSummary.implicitHeight + Theme.spacingM * 2
                                radius: Theme.cornerRadius
                                color: Theme.surfaceContainerHigh
                                border.width: 0

                                Column {
                                    id: presetSummary
                                    anchors.fill: parent
                                    anchors.margins: Theme.spacingM
                                    spacing: Theme.spacingXS

                                    StyledText {
                                        text: "Current Cycle"
                                        font.pixelSize: Theme.fontSizeMedium
                                        font.weight: Font.DemiBold
                                        color: Theme.surfaceText
                                    }

                                    StyledText {
                                        text: `Focus ${root.pomodoroFocusMinutes}m • Short ${root.pomodoroShortBreakMinutes}m • Long ${root.pomodoroLongBreakMinutes}m • Every ${root.pomodoroCycleTarget} sessions`
                                        font.pixelSize: Theme.fontSizeSmall
                                        color: Theme.surfaceVariantText
                                        wrapMode: Text.WordWrap
                                        width: parent.width
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
