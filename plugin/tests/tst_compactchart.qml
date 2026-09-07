import QtQuick
import QtTest
import "../../package/contents/ui" as Widget

Item {
    id: root
    width: 180
    height: 46
    property var allProviders: []
    property var allSubscriptionTools: [{ enabled: true, monitor: monitor }]
    property int connectedCount: 0
    function i18n(text) { return text; }

    QtObject {
        id: plasmoid
        property QtObject configuration: QtObject {
            property string compactDisplayMode: "chart"
            property int chartToolIndex: 0
            property int warningThreshold: 80
            property int criticalThreshold: 95
        }
    }

    QtObject {
        id: monitor
        property bool installed: true
        property bool hasSubscriptionCost: false
        property bool hasSecondaryLimit: true
        property int usageLimit: 0
        property int secondaryUsageLimit: 100
        property real sessionPercentUsed: 0
        property real percentUsed: 0
        property real secondaryPercentUsed: 45
        property int secondsUntilReset: 0
        property int secondarySecondsUntilReset: 6 * 86400 + 2 * 3600
        property bool limitReached: false
        signal usageUpdated()
    }

    Widget.CompactRepresentation { id: compact; anchors.fill: parent }

    TestCase {
        name: "CompactSubscriptionChart"
        when: windowShown

        // Locate the existing chart objects by their exposed QML properties.
        function descendant(item, property) {
            if (item[property] !== undefined) return item;
            for (var i = 0; i < item.children.length; ++i) {
                var found = descendant(item.children[i], property);
                if (found) return found;
            }
            return null;
        }

        function test_quotaSelection() {
            var fill = descendant(compact, "pct");
            var countdown = descendant(compact, "formatCountdown");
            verify(fill !== null);
            verify(countdown !== null);
            compare(fill.pct, 0.45);
            compare(countdown.formatCountdown(), "6d 2h");
            monitor.secondaryPercentUsed = 81;
            compare(fill.pct, 0.81);
            compare(compact.hasWarning, true);
            monitor.secondaryPercentUsed = 96;
            compare(compact.hasCritical, true);

            // Claude still displays its primary session, not its higher weekly quota.
            monitor.usageLimit = 100;
            monitor.sessionPercentUsed = 15;
            monitor.percentUsed = 15;
            monitor.secondsUntilReset = 2 * 3600 + 3 * 60;
            compare(fill.pct, 0.15);
            compare(compact.hasWarning, false);
            compare(compact.hasCritical, false);
            compare(countdown.formatCountdown(), "2h 03m");
            monitor.sessionPercentUsed = 0;
            monitor.percentUsed = 0;
            compare(fill.pct, 0);
        }
    }
}
