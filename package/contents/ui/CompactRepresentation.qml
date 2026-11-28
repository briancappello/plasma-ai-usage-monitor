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
            if (t && t.enabled && t.monitor && quotaLevel(t.monitor) >= 1) return true;
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
            if (t && t.enabled && t.monitor && (t.monitor.limitReached || quotaLevel(t.monitor) >= 2)) return true;
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

    // Chart mode: the tool's weekly quota (or Codex's 5-hour window, per the
    // chartQuotaWindow setting), with any per-model weekly quota stacked below.
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

        // First per-model weekly limit (e.g. Claude's "Fable"), if the tool has one
        readonly property var scopedLimit: {
            var limits = ccAvailable ? (ccMonitor.scopedLimits ?? []) : [];
            return limits.length > 0 ? limits[0] : null;
        }

        // Equal-height rows: the main quota bar, the per-model weekly bar (if
        // any) and the countdown.
        readonly property int topEdgeMargin: 1
        readonly property int bottomEdgeMargin: 0
        readonly property int rowSpacing: 2
        // Extra space between the last bar and the countdown.
        readonly property int countdownGap: 3
        readonly property int rowCount: scopedLimit !== null ? 3 : 2
        // Whole pixels: the layout snaps rows to pixel positions, so fractional
        // heights would push the last row past the bottom edge.
        readonly property int rowHeight: Math.max(1, Math.floor(
            (height - topEdgeMargin - bottomEdgeMargin - (rowCount - 1) * rowSpacing - countdownGap) / rowCount))
        // One font size for every row (bar letters and countdown): a capital
        // letter's inked height fills the row.
        readonly property int rowFontPixelSize: Math.max(1, Math.round(rowHeight / letterMetrics.capRatio))

        ColumnLayout {
            anchors.fill: parent
            anchors.leftMargin: Kirigami.Units.smallSpacing
            anchors.rightMargin: Kirigami.Units.smallSpacing
            anchors.topMargin: chartMode.topEdgeMargin
            anchors.bottomMargin: chartMode.bottomEdgeMargin
            spacing: chartMode.rowSpacing

            UsageBar {
                objectName: "quotaBar"
                Layout.fillWidth: true
                Layout.preferredHeight: chartMode.rowHeight
                pct: chartMode.ccAvailable
                    ? (chartMode.useSecondary ? chartMode.ccMonitor.secondaryPercentUsed
                                              : chartMode.ccMonitor.percentUsed) / 100.0
                    : 0.0
                paceLevel: chartMode.ccAvailable ? compactRoot.quotaPaceLevel(chartMode.ccMonitor) : -1
                label: chartMode.ccMonitor
                    ? (chartMode.useSecondary ? chartMode.ccMonitor.secondaryPeriodLabel
                                              : chartMode.ccMonitor.periodLabel) ?? ""
                    : ""
            }

            UsageBar {
                objectName: "scopedBar"
                Layout.fillWidth: true
                Layout.preferredHeight: chartMode.rowHeight
                visible: chartMode.scopedLimit !== null
                pct: chartMode.scopedLimit ? (chartMode.scopedLimit.percent ?? 0) / 100.0 : 0.0
                paceLevel: chartMode.scopedLimit ? (chartMode.scopedLimit.paceLevel ?? -1) : -1
                label: chartMode.scopedLimit ? (chartMode.scopedLimit.name ?? "") : ""
            }

            // Countdown label — the last row, same height and font size as the
            // bars' letters above it.
            PlasmaComponents.Label {
                id: countdownLabel
                objectName: "countdownRow"
                Layout.fillWidth: true
                Layout.topMargin: chartMode.countdownGap
                Layout.preferredHeight: chartMode.rowHeight
                Layout.maximumHeight: chartMode.rowHeight
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                font.family: Kirigami.Theme.defaultFont.family
                font.pixelSize: chartMode.rowFontPixelSize
                font.weight: Kirigami.Theme.defaultFont.weight
                // Shrink rather than clip when "run-out / reset" is wider than the panel.
                fontSizeMode: Text.HorizontalFit
                minimumPixelSize: 6
                textFormat: Text.StyledText
                text: chartMode.ccAvailable ? countdownMarkup() : i18n("–")
                // Within budget, the reset countdown is green; when the quota will
                // run out first, only the run-out time takes the bar's color.
                color: chartMode.ccAvailable && compactRoot.quotaPaceLevel(chartMode.ccMonitor) >= 0
                       && secondsUntilOut() < 0
                    ? Kirigami.Theme.positiveTextColor
                    : Kirigami.Theme.textColor

                // -1 when the quota lasts until its reset (or isn't paced).
                function secondsUntilOut() {
                    return (chartMode.useSecondary ? chartMode.ccMonitor.secondarySecondsUntilExhausted
                                                   : chartMode.ccMonitor.secondsUntilExhausted) ?? -1;
                }

                function formatDuration(secs) {
                    var h = Math.floor(secs / 3600);
                    var m = Math.floor((secs % 3600) / 60);
                    var s = secs % 60;
                    if (h >= 24) return Math.floor(h / 24) + "d " + (h % 24) + "h";
                    if (h > 0)
                        return h + "h " + (m < 10 ? "0" : "") + m + "m";
                    return (m < 10 ? "0" : "") + m + "m " + (s < 10 ? "0" : "") + s + "s";
                }

                function formatReset() {
                    var secs = chartMode.useSecondary ? chartMode.ccMonitor.secondarySecondsUntilReset
                                                      : chartMode.ccMonitor.secondsUntilReset;
                    return secs <= 0 ? i18n("reset") : formatDuration(secs);
                }

                function formatRunOut() {
                    var out = secondsUntilOut();
                    if (out < 0) return "";
                    return out === 0 ? i18n("out") : formatDuration(out);
                }

                // Plain text: "2d 20h", or "1d 1h / 2d 20h" when it runs out first.
                function formatCountdown() {
                    var runOut = formatRunOut();
                    return runOut ? runOut + " / " + formatReset() : formatReset();
                }

                function countdownMarkup() {
                    var runOut = formatRunOut();
                    if (!runOut) return formatReset();
                    var barColor = Utils.paceColor(compactRoot.quotaPaceLevel(chartMode.ccMonitor), Kirigami.Theme);
                    return "<font color=\"" + readableOnPanel(barColor) + "\">" + runOut + "</font> / " + formatReset();
                }

                // Thin glyphs blend into a dark panel and read darker than the solid
                // bar, so on dark themes the bar color is brightened for text.
                function readableOnPanel(c) {
                    return Kirigami.ColorUtils.brightnessForColor(Kirigami.Theme.textColor) === Kirigami.ColorUtils.Light
                        ? Qt.lighter(c, 1.35) : c;
                }

                function updateText() {
                    text = chartMode.ccAvailable ? countdownMarkup() : i18n("–");
                }

                Connections {
                    target: chartMode.ccMonitor ?? null
                    function onUsageUpdated() { countdownLabel.updateText(); }
                }
            }
        }
    }

    // Inked size of a capital "W" as a fraction of the font's pixel size, so a
    // bar's letter can be sized to exactly the bar's height.
    FontMetrics {
        id: letterMetrics
        font.family: Kirigami.Theme.defaultFont.family
        font.weight: Font.DemiBold
        font.pixelSize: 100
        readonly property rect wBounds: tightBoundingRect("W")
        readonly property real capRatio: Math.max(0.1, wBounds.height / 100)
        readonly property real widthRatio: wBounds.width / 100
    }

    // A quota bar with the first letter of its window's name to its left
    // (W = weekly, F = Fable, …), scaled to the bar's height.
    component UsageBar: Item {
        id: bar
        property double pct: 0.0
        // Weekly quotas are colored by pace; -1 falls back to how much is used.
        property int paceLevel: -1
        property string label: ""
        readonly property string letter: label.length > 0 ? label.charAt(0).toUpperCase() : ""
        readonly property double fill: Math.max(0.0, Math.min(1.0, pct))
        readonly property color fillColor: {
            if (paceLevel >= 0)
                return Utils.paceColor(paceLevel, Kirigami.Theme);
            var p = pct * 100;
            if (p >= plasmoid.configuration.criticalThreshold)
                return Kirigami.Theme.negativeTextColor;
            if (p >= plasmoid.configuration.warningThreshold)
                return Kirigami.Theme.neutralTextColor;
            return Kirigami.Theme.positiveTextColor;
        }

        // Fixed to the inked width of a "W" (the widest letter) so stacked
        // bars line up.
        Item {
            id: letterBox
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            visible: bar.letter.length > 0
            width: visible ? Math.ceil(letterLabel.font.pixelSize * letterMetrics.widthRatio) : 0

            Text {
                id: letterLabel
                objectName: "barLetter"
                anchors.centerIn: parent
                text: bar.letter
                color: Kirigami.Theme.textColor
                font.family: Kirigami.Theme.defaultFont.family
                font.weight: Font.DemiBold
                font.pixelSize: chartMode.rowFontPixelSize
            }
        }

        Item {
            id: track
            anchors.left: letterBox.right
            anchors.leftMargin: letterBox.visible ? Math.max(2, Math.round(letterLabel.font.pixelSize * 0.25)) : 0
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.bottom: parent.bottom

            // Track background
            Rectangle {
                anchors.fill: parent
                radius: height / 2
                color: Qt.alpha(Kirigami.Theme.textColor, 0.12)
            }

            // Filled portion
            Rectangle {
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: parent.width * bar.fill
                radius: height / 2
                color: bar.fillColor
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

    // Weekly is preferred by default; tools without a weekly limit fall back
    // to their primary window, and tools without a primary window use weekly.
    function usesSecondaryQuota(monitor) {
        if (!monitor || !monitor.hasSecondaryLimit || monitor.secondaryUsageLimit <= 0)
            return false;
        return plasmoid.configuration.chartQuotaWindow !== "session" || monitor.usageLimit <= 0;
    }

    // Pace level (-1 = not paced) of the panel's quota window: secondary or primary.
    function quotaPaceLevel(monitor) {
        return (usesSecondaryQuota(monitor) ? monitor.secondaryPaceLevel : monitor.paceLevel) ?? -1;
    }

    // 0 ok, 1 warning, 2 critical: the worst of the panel's quota and any
    // per-model weekly quota. Weekly quotas are judged by pace (projected
    // usage at reset); other windows by how much of them is used.
    function quotaLevel(monitor) {
        var level = quotaPaceLevel(monitor);
        if (level < 0) {
            var pct = usesSecondaryQuota(monitor) ? monitor.secondaryPercentUsed : monitor.percentUsed;
            level = pct >= 95 ? 2 : pct >= 80 ? 1 : 0;
        }
        var scoped = monitor.scopedLimits ?? [];
        for (var i = 0; i < scoped.length; i++)
            level = Math.max(level, scoped[i].paceLevel ?? 0);
        return level;
    }

    function formatMetric(value) {
        if (value >= 1000000)
            return (value / 1000000).toFixed(1) + "M";
        if (value >= 1000)
            return (value / 1000).toFixed(1) + "K";
        return value.toString();
    }
}
