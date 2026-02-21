import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.components as PlasmaComponents
import org.kde.kirigami as Kirigami
import "Utils.js" as Utils

MouseArea {
    id: compactRoot

    readonly property var providers: root.allProviders ?? []

    Accessible.role: Accessible.Button
    Accessible.name: i18n("AI Usage Monitor: %1 providers connected", root.connectedCount ?? 0)

    readonly property bool hasWarning: {
        for (var i = 0; i < providers.length; i++) {
            var p = providers[i];
            if (p && p.enabled && p.backend && p.backend.connected && p.backend.rateLimitRequests > 0) {
                var usedPercent = ((p.backend.rateLimitRequests - p.backend.rateLimitRequestsRemaining) / p.backend.rateLimitRequests) * 100;
                if (usedPercent >= plasmoid.configuration.warningThreshold) return true;
            }
        }
        // Also check subscription tools
        var tools = root.allSubscriptionTools ?? [];
        for (var j = 0; j < tools.length; j++) {
            var t = tools[j];
            if (t && t.enabled && t.monitor && t.monitor.percentUsed >= 80) return true;
        }
        return false;
    }
    readonly property bool hasCritical: {
        for (var i = 0; i < providers.length; i++) {
            var p = providers[i];
            if (p && p.enabled && p.backend && p.backend.connected && p.backend.rateLimitRequests > 0) {
                var usedPercent = ((p.backend.rateLimitRequests - p.backend.rateLimitRequestsRemaining) / p.backend.rateLimitRequests) * 100;
                if (usedPercent >= plasmoid.configuration.criticalThreshold) return true;
            }
        }
        // Also check subscription tools
        var tools = root.allSubscriptionTools ?? [];
        for (var j = 0; j < tools.length; j++) {
            var t = tools[j];
            if (t && t.enabled && t.monitor && (t.monitor.limitReached || t.monitor.percentUsed >= 95)) return true;
        }
        return false;
    }
    readonly property bool anyConnected: {
        for (var i = 0; i < providers.length; i++) {
            if (providers[i] && providers[i].enabled && providers[i].backend && providers[i].backend.connected)
                return true;
        }
        return false;
    }
    readonly property bool anyLoading: {
        for (var i = 0; i < providers.length; i++) {
            if (providers[i] && providers[i].enabled && providers[i].backend && providers[i].backend.loading)
                return true;
        }
        return false;
    }

    readonly property string displayMode: plasmoid.configuration.compactDisplayMode

    // In chart mode the widget requests twice its height as width
    Layout.preferredWidth: displayMode === "chart" ? height * 2 : -1

    hoverEnabled: true
    onClicked: plasmoid.activated()

    // Icon mode (default)
    Kirigami.Icon {
        id: mainIcon
        anchors.fill: parent
        source: Qt.resolvedUrl("../icons/logo.png")
        active: compactRoot.containsMouse
        visible: compactRoot.displayMode === "icon"

        // Overlay badge for status indication
        Rectangle {
            id: statusBadge
            visible: compactRoot.anyConnected
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            width: Kirigami.Units.smallSpacing * 3
            height: width
            radius: width / 2
            color: {
                if (compactRoot.hasCritical) return Kirigami.Theme.negativeTextColor;
                if (compactRoot.hasWarning) return Kirigami.Theme.neutralTextColor;
                return Kirigami.Theme.positiveTextColor;
            }
            border.width: 1
            border.color: Kirigami.Theme.backgroundColor

            Behavior on color {
                ColorAnimation { duration: 300 }
            }
        }
    }

    // Cost mode
    PlasmaComponents.Label {
        id: costLabel
        anchors.fill: parent
        visible: compactRoot.displayMode === "cost"
        text: "$" + (root.totalCost ?? 0).toFixed(2)
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        font.bold: true
        font.pointSize: Math.max(Kirigami.Theme.smallFont.pointSize, height * 0.35)
        minimumPointSize: Kirigami.Theme.smallFont.pointSize
        fontSizeMode: Text.Fit
        color: {
            var cost = root.totalCost ?? 0;
            if (cost > 10) return Kirigami.Theme.negativeTextColor;
            if (cost > 5) return Kirigami.Theme.neutralTextColor;
            return Kirigami.Theme.textColor;
        }
    }

    // Count mode
    RowLayout {
        anchors.fill: parent
        visible: compactRoot.displayMode === "count"
        spacing: Kirigami.Units.smallSpacing / 2

        Kirigami.Icon {
            source: Qt.resolvedUrl("../icons/logo.png")
            Layout.preferredWidth: Kirigami.Units.iconSizes.small
            Layout.preferredHeight: Kirigami.Units.iconSizes.small
        }

        PlasmaComponents.Label {
            text: (root.connectedCount ?? 0).toString()
            font.bold: true
            Layout.alignment: Qt.AlignVCenter
        }
    }

    // Chart mode — Claude Code session usage bar + reset countdown
    Item {
        id: chartMode
        anchors.fill: parent
        visible: compactRoot.displayMode === "chart"

        readonly property var ccMonitor: root.claudeCode
        readonly property bool ccAvailable: ccMonitor
                                            && plasmoid.configuration.claudeCodeEnabled
                                            && ccMonitor.installed

        // Live countdown: tick every second while visible
        Timer {
            interval: 1000
            running: chartMode.visible && chartMode.ccAvailable
            repeat: true
            onTriggered: countdownLabel.updateText()
        }

        ColumnLayout {
            anchors {
                fill: parent
                leftMargin: Kirigami.Units.smallSpacing
                rightMargin: Kirigami.Units.smallSpacing
                topMargin: Math.round(Kirigami.Units.smallSpacing * 0.5)
            }
            spacing: Math.round(Kirigami.Units.smallSpacing * 0.5)

            // Usage bar
            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true

                // Track background
                Rectangle {
                    anchors.fill: parent
                    radius: height / 2
                    color: Qt.alpha(Kirigami.Theme.textColor, 0.12)
                }

                // Filled portion
                Rectangle {
                    id: usageFill
                    readonly property double pct: chartMode.ccAvailable
                        ? Math.min(1.0, (chartMode.ccMonitor.sessionPercentUsed > 0
                            ? chartMode.ccMonitor.sessionPercentUsed / 100.0
                            : chartMode.ccMonitor.percentUsed / 100.0))
                        : 0.0
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    width: parent.width * pct
                    radius: height / 2
                    color: {
                        var p = pct * 100;
                        if (p >= plasmoid.configuration.criticalThreshold)
                            return Kirigami.Theme.negativeTextColor;
                        if (p >= plasmoid.configuration.warningThreshold)
                            return Kirigami.Theme.neutralTextColor;
                        return Kirigami.Theme.positiveTextColor;
                    }
                    Behavior on width { NumberAnimation { duration: 300; easing.type: Easing.InOutQuad } }
                    Behavior on color { ColorAnimation { duration: 300 } }
                }

                // "not available" placeholder bar
                Rectangle {
                    anchors.fill: parent
                    radius: height / 2
                    color: Qt.alpha(Kirigami.Theme.textColor, 0.08)
                    visible: !chartMode.ccAvailable
                }
            }

            // Countdown label
            PlasmaComponents.Label {
                id: countdownLabel
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                font.pointSize: Kirigami.Theme.smallFont.pointSize
                minimumPointSize: 5
                fontSizeMode: Text.HorizontalFit
                opacity: 0.75
                text: chartMode.ccAvailable ? formatCountdown() : i18n("–")

                function formatCountdown() {
                    var secs = chartMode.ccMonitor.secondsUntilReset;
                    if (secs <= 0) return i18n("reset");
                    var h = Math.floor(secs / 3600);
                    var m = Math.floor((secs % 3600) / 60);
                    var s = secs % 60;
                    if (h > 0)
                        return h + "h " + (m < 10 ? "0" : "") + m + "m";
                    return (m < 10 ? "0" : "") + m + "m " + (s < 10 ? "0" : "") + s + "s";
                }

                function updateText() {
                    text = chartMode.ccAvailable ? formatCountdown() : i18n("–");
                }

                Connections {
                    target: chartMode.ccMonitor ?? null
                    function onUsageUpdated() { countdownLabel.updateText(); }
                }
            }
        }
    }

    // Spinning indicator when loading (all modes)
    PlasmaComponents.BusyIndicator {
        anchors.fill: parent
        visible: compactRoot.anyLoading
        running: visible
    }
}
