import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.components as PlasmaComponents
import org.kde.kirigami as Kirigami
import "Utils.js" as Utils

MouseArea {
    id: compactRoot
    readonly property url brandedIconSource: Qt.resolvedUrl("../icons/logo.png")

    readonly property var providers: root.allProviders ?? []
    readonly property var subscriptionTools: root.allSubscriptionTools ?? []
    readonly property var loofiProvider: {
        for (var i = 0; i < providers.length; i++) {
            if (providers[i] && providers[i].configKey === "loofi")
                return providers[i];
        }
        return null;
    }
    readonly property bool loofiConnected: !!(loofiProvider && loofiProvider.enabled && loofiProvider.backend && loofiProvider.backend.connected)
    readonly property double compactTotalCost: {
        var total = 0;
        for (var i = 0; i < providers.length; i++) {
            var provider = providers[i];
            if (provider && provider.enabled && provider.backend && provider.backend.connected)
                total += provider.backend.cost ?? 0;
        }
        for (var j = 0; j < subscriptionTools.length; j++) {
            var tool = subscriptionTools[j];
            if (tool && tool.enabled && tool.monitor && tool.monitor.hasSubscriptionCost)
                total += tool.monitor.subscriptionCost ?? 0;
        }
        return total;
    }

    Accessible.role: Accessible.Button
    Accessible.name: {
        if (compactRoot.displayMode === "loofi" && compactRoot.loofiConnected) {
            return i18n("Loofi Server: %1, %2, GPU %3 percent, %4 requests in 24 hours",
                        compactRoot.loofiProvider.backend.activeModel || i18n("No model"),
                        compactRoot.loofiProvider.backend.trainingStage || i18n("idle"),
                        Math.round(Math.max(0, compactRoot.loofiProvider.backend.gpuMemoryPct || 0)),
                        compactRoot.formatMetric(compactRoot.loofiProvider.backend.requestCount || 0));
        }
        return i18n("AI Usage Monitor: %1 providers connected", root.connectedCount ?? 0);
    }

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
            if (t && t.enabled && t.monitor
                && (usesSecondaryQuota(t.monitor) ? t.monitor.secondaryPercentUsed : t.monitor.percentUsed) >= 80) return true;
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
            if (t && t.enabled && t.monitor && (t.monitor.limitReached
                || (usesSecondaryQuota(t.monitor) ? t.monitor.secondaryPercentUsed : t.monitor.percentUsed) >= 95)) return true;
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
    Layout.preferredWidth: displayMode === "chart" ? height * 3 : -1

    hoverEnabled: true
    onClicked: plasmoid.activated()

    // Icon mode (default)
    Kirigami.Icon {
        id: mainIcon
        anchors.fill: parent
        source: compactRoot.brandedIconSource
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
        text: "$" + compactRoot.compactTotalCost.toFixed(2)
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        font.bold: true
        font.pointSize: Math.max(Kirigami.Theme.smallFont.pointSize, height * 0.35)
        minimumPointSize: Kirigami.Theme.smallFont.pointSize
        fontSizeMode: Text.Fit
        color: {
            var cost = compactRoot.compactTotalCost;
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
            source: compactRoot.brandedIconSource
            Layout.preferredWidth: Kirigami.Units.iconSizes.small
            Layout.preferredHeight: Kirigami.Units.iconSizes.small
        }

        PlasmaComponents.Label {
            text: (root.connectedCount ?? 0).toString()
            font.bold: true
            Layout.alignment: Qt.AlignVCenter
        }
    }

    // Chart mode: primary quota, or weekly quota for plans without a primary window.
    Item {
        id: chartMode
        anchors.fill: parent
        visible: compactRoot.displayMode === "chart"

        // Resolve which monitor to display from the chartToolIndex config
        // Index order matches allSubscriptionTools: 0=Claude Code, 1=OpenCode, 2=Codex CLI, 3=Copilot
        readonly property var allTools: root.allSubscriptionTools ?? []
        readonly property int toolIdx: Math.min(
            Math.max(0, plasmoid.configuration.chartToolIndex ?? 0),
            allTools.length - 1)
        readonly property var selectedTool: allTools.length > 0 ? allTools[toolIdx] : null
        readonly property var ccMonitor: selectedTool ? selectedTool.monitor : null
        readonly property bool useSecondary: compactRoot.usesSecondaryQuota(ccMonitor)
        readonly property bool ccAvailable: ccMonitor
                                            && selectedTool && selectedTool.enabled
                                            && ccMonitor.installed

        // Live countdown: tick every second while visible
        Timer {
            interval: 1000
            running: chartMode.visible && chartMode.ccAvailable
            repeat: true
            onTriggered: countdownLabel.updateText()
        }

        // Countdown label — anchored to the bottom, matching the Digital Clock's
        // date string row in both size and vertical position
        PlasmaComponents.Label {
            id: countdownLabel
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.leftMargin: Kirigami.Units.smallSpacing
            anchors.rightMargin: Kirigami.Units.smallSpacing
            // Explicit height: one line at the default font size, scaled by DPI.
            // This must be a stable non-zero value so the bar above can anchor to it.
            height: Kirigami.Theme.defaultFont.pixelSize
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            // Use the same unstyled default font the clock's date string uses
            font.pointSize: Kirigami.Theme.defaultFont.pointSize * 0.9
            font.weight: Kirigami.Theme.defaultFont.weight
            text: chartMode.ccAvailable ? formatCountdown() : i18n("–")

            function formatCountdown() {
                var secs = chartMode.useSecondary ? chartMode.ccMonitor.secondarySecondsUntilReset
                                                  : chartMode.ccMonitor.secondsUntilReset;
                if (secs <= 0) return i18n("reset");
                var h = Math.floor(secs / 3600);
                var m = Math.floor((secs % 3600) / 60);
                var s = secs % 60;
                if (h >= 24) return Math.floor(h / 24) + "d " + (h % 24) + "h";
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

        // Usage bar — fills the space above the countdown label
        Item {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.bottom: countdownLabel.top
            anchors.leftMargin: Kirigami.Units.smallSpacing
            anchors.rightMargin: Kirigami.Units.smallSpacing
            anchors.topMargin: 1
            anchors.bottomMargin: 5

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
                    ? Math.min(1.0, (chartMode.useSecondary
                        ? chartMode.ccMonitor.secondaryPercentUsed / 100.0
                        : chartMode.ccMonitor.sessionPercentUsed > 0
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

            // "not available" placeholder
            Rectangle {
                anchors.fill: parent
                radius: height / 2
                color: Qt.alpha(Kirigami.Theme.textColor, 0.08)
                visible: !chartMode.ccAvailable
            }
        }
    }

    // Loofi server mode
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Kirigami.Units.smallSpacing
        visible: compactRoot.displayMode === "loofi"
        spacing: 1

        RowLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing / 2

            Kirigami.Icon {
                source: compactRoot.brandedIconSource
                Layout.preferredWidth: Kirigami.Units.iconSizes.small
                Layout.preferredHeight: Kirigami.Units.iconSizes.small
            }

            PlasmaComponents.Label {
                Layout.fillWidth: true
                text: compactRoot.loofiConnected
                    ? (compactRoot.loofiProvider.backend.activeModel || i18n("No model"))
                    : i18n("Loofi offline")
                font.bold: true
                elide: Text.ElideRight
                font.pointSize: Kirigami.Theme.smallFont.pointSize
            }

            PlasmaComponents.Label {
                visible: compactRoot.loofiConnected
                text: compactRoot.loofiProvider.backend.trainingStage || i18n("idle")
                opacity: 0.7
                font.pointSize: Kirigami.Theme.smallFont.pointSize
                elide: Text.ElideRight
            }
        }

        PlasmaComponents.Label {
            Layout.fillWidth: true
            text: compactRoot.loofiConnected
                ? i18n("GPU %1%  Req %2/24h",
                       Math.round(Math.max(0, compactRoot.loofiProvider.backend.gpuMemoryPct || 0)),
                       compactRoot.formatMetric(compactRoot.loofiProvider.backend.requestCount || 0))
                : i18n("Enable the Loofi provider to show server KPIs.")
            opacity: compactRoot.loofiConnected ? 0.75 : 0.6
            wrapMode: Text.NoWrap
            elide: Text.ElideRight
            font.pointSize: Kirigami.Theme.smallFont.pointSize * 0.92
        }
    }

    // Spinning indicator when loading (all modes)
    PlasmaComponents.BusyIndicator {
        anchors.fill: parent
        visible: compactRoot.anyLoading
        running: visible
    }

    function usesSecondaryQuota(monitor) {
        return !!monitor && monitor.usageLimit <= 0
            && monitor.hasSecondaryLimit && monitor.secondaryUsageLimit > 0;
    }

    function formatMetric(value) {
        if (value >= 1000000)
            return (value / 1000000).toFixed(1) + "M";
        if (value >= 1000)
            return (value / 1000).toFixed(1) + "K";
        return value.toString();
    }
}
