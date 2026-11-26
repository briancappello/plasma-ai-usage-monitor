import QtQuick
import QtTest
import org.kde.kirigami as Kirigami
import "../../package/contents/ui" as Widget

Item {
    id: root
    width: 180
    height: 46
    property var allProviders: []
    property var allSubscriptionTools: [{ enabled: true, monitor: monitor }, { enabled: true, monitor: secondMonitor }]
    property int connectedCount: 0
    function i18n(text) { return text; }

    QtObject {
        id: plasmoid
        property QtObject configuration: QtObject {
            property string compactDisplayMode: "chart"
            property int chartToolIndex: 0
            property string chartQuotaWindow: "weekly"
            property int warningThreshold: 80
            property int criticalThreshold: 95
        }
    }

    // Claude-like: one weekly window plus a per-model weekly limit.
    QtObject {
        id: monitor
        property bool installed: true
        property bool hasSubscriptionCost: false
        property bool hasSecondaryLimit: false
        property string periodLabel: "Weekly"
        property string secondaryPeriodLabel: ""
        property int usageLimit: 100
        property int secondaryUsageLimit: 0
        property real percentUsed: 45
        property real secondaryPercentUsed: 0
        property int paceLevel: 0
        property int secondaryPaceLevel: -1
        property var scopedLimits: [{ name: "Fable", percent: 12, paceLevel: 0 }]
        property int secondsUntilReset: 6 * 86400 + 2 * 3600
        property int secondarySecondsUntilReset: 0
        property bool limitReached: false
        signal usageUpdated()
    }

    Widget.CompactRepresentation { id: compact; anchors.fill: parent }

    // Codex-like: 5-hour primary window plus weekly, no per-model limits.
    QtObject {
        id: secondMonitor
        property bool installed: true
        property bool hasSubscriptionCost: false
        property bool hasSecondaryLimit: true
        property string periodLabel: "5-hour window"
        property string secondaryPeriodLabel: "Weekly"
        property int usageLimit: 100
        property int secondaryUsageLimit: 100
        property real percentUsed: 23
        property real secondaryPercentUsed: 64
        property int paceLevel: -1
        property int secondaryPaceLevel: 0
        property var scopedLimits: []
        property int secondsUntilReset: 3600
        property int secondarySecondsUntilReset: 86400
        property bool limitReached: false
        signal usageUpdated()
    }

    TestCase {
        name: "CompactSubscriptionChart"
        when: windowShown

        function descendant(item, predicate) {
            if (predicate(item)) return item;
            for (var i = 0; i < item.children.length; ++i) {
                var found = descendant(item.children[i], predicate);
                if (found) return found;
            }
            return null;
        }
        function named(name) { return descendant(compact, function(i) { return i.objectName === name; }); }
        function letterOf(bar) { return descendant(bar, function(i) { return i.objectName === "barLetter"; }); }

        function test_stackedWeeklyAndScopedBars() {
            var quota = named("quotaBar");
            var scoped = named("scopedBar");
            var countdown = descendant(compact, function(i) { return i.formatCountdown !== undefined; });
            verify(quota !== null);
            verify(scoped !== null);
            verify(countdown !== null);

            // Weekly on top, Fable stacked below it, both visible.
            compare(quota.pct, 0.45);
            compare(scoped.pct, 0.12);
            verify(scoped.visible);
            verify(scoped.y > quota.y);
            verify(quota.height > 0 && scoped.height > 0);

            // Three equal rows: weekly bar, Fable bar, countdown.
            var countdownRow = named("countdownRow");
            verify(countdownRow !== null);
            fuzzyCompare(scoped.height, quota.height, 0.5);
            fuzzyCompare(countdownRow.height, quota.height, 0.5);
            verify(countdownRow.y > scoped.y);
            // The countdown sits further below the last bar than the bars sit apart.
            var barGap = scoped.y - (quota.y + quota.height);
            var countdownGap = countdownRow.y - (scoped.y + scoped.height);
            verify(countdownGap > barGap);
            // Rows stay inside the widget, leaving the panel's padding alone.
            verify(quota.mapToItem(compact, 0, 0).y >= 0);
            verify(countdownRow.mapToItem(compact, 0, countdownRow.height).y <= compact.height);
            compare(countdown.formatCountdown(), "6d 2h");
            compare(quota.fillColor, Kirigami.Theme.positiveTextColor);
            compare(scoped.fillColor, Kirigami.Theme.positiveTextColor);

            // Each bar is labelled with its window's initial, sized to the bar
            // and the same width so both tracks line up.
            compare(quota.letter, "W");
            compare(scoped.letter, "F");
            var quotaLetter = letterOf(quota);
            var scopedLetter = letterOf(scoped);
            verify(quotaLetter.visible && scopedLetter.visible);
            verify(quotaLetter.font.pixelSize >= quota.height);
            // Both letters and the countdown share one font size.
            compare(scopedLetter.font.pixelSize, quotaLetter.font.pixelSize);
            compare(named("countdownRow").font.pixelSize, quotaLetter.font.pixelSize);
            compare(quotaLetter.parent.width, scopedLetter.parent.width);
            verify(quotaLetter.parent.width > 0);

            // Weekly color follows pace, not how much of the quota is used.
            monitor.percentUsed = 96;
            compare(quota.pct, 0.96);
            compare(quota.fillColor, Kirigami.Theme.positiveTextColor);
            compare(compact.hasWarning, false);
            compare(compact.hasCritical, false);
            monitor.percentUsed = 20;
            monitor.paceLevel = 1;
            compare(quota.fillColor, Kirigami.Theme.neutralTextColor);
            compare(compact.hasWarning, true);
            compare(compact.hasCritical, false);
            monitor.paceLevel = 2;
            compare(quota.fillColor, Kirigami.Theme.negativeTextColor);
            compare(compact.hasCritical, true);
            monitor.paceLevel = 0;
            monitor.percentUsed = 45;

            // Each bar has its own pace; a critical per-model pace raises the
            // panel badge on its own, even at low usage.
            monitor.scopedLimits = [{ name: "Fable", percent: 12, paceLevel: 2 }];
            compare(scoped.fillColor, Kirigami.Theme.negativeTextColor);
            compare(quota.fillColor, Kirigami.Theme.positiveTextColor);
            compare(compact.hasCritical, true);
            monitor.scopedLimits = [{ name: "Fable", percent: 97, paceLevel: 0 }];
            compare(scoped.fillColor, Kirigami.Theme.positiveTextColor);
            compare(compact.hasCritical, false);

            // The session option cannot resurrect a 5-hour view for Claude.
            plasmoid.configuration.chartQuotaWindow = "session";
            compare(quota.pct, 0.45);
            compare(countdown.formatCountdown(), "6d 2h");
            plasmoid.configuration.chartQuotaWindow = "weekly";

            // No per-model limit: a single bar fills the space.
            monitor.scopedLimits = [];
            verify(!scoped.visible);
            // Without a per-model limit, the bar and countdown split the height.
            tryVerify(function() { return quota.height > root.height / 3; });
            fuzzyCompare(named("countdownRow").height, quota.height, 0.5);

            // Switching tools: Codex shows weekly by default, 5-hour on request.
            for (var index of [1, 0, 1]) {
                plasmoid.configuration.chartToolIndex = index;
                compare(quota.pct, index === 1 ? 0.64 : 0.45);
                compare(countdown.formatCountdown(), index === 1 ? "1d 0h" : "6d 2h");
            }
            plasmoid.configuration.chartQuotaWindow = "session";
            compare(quota.pct, 0.23);
            compare(countdown.formatCountdown(), "1h 00m");
            compare(quota.letter, "5");
            // The 5-hour window isn't paced: it's colored by how much is used.
            compare(quota.paceLevel, -1);
            secondMonitor.percentUsed = 81;
            compare(quota.fillColor, Kirigami.Theme.neutralTextColor);
            compare(compact.hasWarning, true);
            secondMonitor.percentUsed = 23;
            plasmoid.configuration.chartQuotaWindow = "weekly";
        }
    }
}
