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
        property int usageLimit: 100
        property int secondaryUsageLimit: 0
        property real percentUsed: 45
        property real secondaryPercentUsed: 0
        property var scopedLimits: [{ name: "Fable", percent: 12 }]
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
        property int usageLimit: 100
        property int secondaryUsageLimit: 100
        property real percentUsed: 23
        property real secondaryPercentUsed: 64
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
            compare(countdown.formatCountdown(), "6d 2h");

            // Each bar is coloured by its own percentage.
            monitor.percentUsed = 81;
            compare(quota.fillColor, Kirigami.Theme.neutralTextColor);
            compare(scoped.fillColor, Kirigami.Theme.positiveTextColor);
            compare(compact.hasWarning, true);
            compare(compact.hasCritical, false);

            // A critical per-model limit raises the panel badge on its own.
            monitor.percentUsed = 45;
            monitor.scopedLimits = [{ name: "Fable", percent: 97 }];
            compare(scoped.fillColor, Kirigami.Theme.negativeTextColor);
            compare(compact.hasCritical, true);

            // The session option cannot resurrect a 5-hour view for Claude.
            plasmoid.configuration.chartQuotaWindow = "session";
            compare(quota.pct, 0.45);
            compare(countdown.formatCountdown(), "6d 2h");
            plasmoid.configuration.chartQuotaWindow = "weekly";

            // No per-model limit: a single bar fills the space.
            monitor.scopedLimits = [];
            verify(!scoped.visible);

            // Switching tools: Codex shows weekly by default, 5-hour on request.
            for (var index of [1, 0, 1]) {
                plasmoid.configuration.chartToolIndex = index;
                compare(quota.pct, index === 1 ? 0.64 : 0.45);
                compare(countdown.formatCountdown(), index === 1 ? "1d 0h" : "6d 2h");
            }
            plasmoid.configuration.chartQuotaWindow = "session";
            compare(quota.pct, 0.23);
            compare(countdown.formatCountdown(), "1h 00m");
            plasmoid.configuration.chartQuotaWindow = "weekly";
        }
    }
}
