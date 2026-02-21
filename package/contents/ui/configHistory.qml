import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM
import com.github.loofi.aiusagemonitor 1.0

KCM.SimpleKCM {
    id: historyPage

    property alias cfg_historyEnabled: historySwitch.checked
    property alias cfg_historyRetentionDays: retentionSlider.value

    readonly property int labelWidth: Kirigami.Units.gridUnit * 12

    UsageDatabase {
        id: historyDb
        enabled: plasmoid.configuration.historyEnabled
        retentionDays: plasmoid.configuration.historyRetentionDays
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: Kirigami.Units.smallSpacing

        // Master toggle
        RowLayout {
            Layout.fillWidth: true; spacing: Kirigami.Units.smallSpacing
            QQC2.Label { text: i18n("Enable history:"); Layout.preferredWidth: historyPage.labelWidth }
            QQC2.Switch { id: historySwitch; checked: plasmoid.configuration.historyEnabled }
        }

        QQC2.Label {
            Layout.fillWidth: true
            text: i18n("When enabled, usage data is periodically saved to a local SQLite database for trend analysis and charts.")
            font.pointSize: Kirigami.Theme.smallFont.pointSize
            opacity: 0.6; wrapMode: Text.WordWrap
        }

        // ── Data Retention ──
        Kirigami.Separator { Layout.fillWidth: true; Layout.topMargin: Kirigami.Units.largeSpacing }
        QQC2.Label { text: i18n("Data Retention"); font.bold: true }

        RowLayout {
            Layout.fillWidth: true
            enabled: historySwitch.checked
            spacing: Kirigami.Units.smallSpacing
            QQC2.Label { text: i18n("Keep data for:"); Layout.preferredWidth: historyPage.labelWidth }
            ColumnLayout {
                Layout.fillWidth: true; spacing: 2
                QQC2.Slider {
                    id: retentionSlider
                    Layout.fillWidth: true
                    from: 7; to: 365; stepSize: 1
                    value: plasmoid.configuration.historyRetentionDays
                }
                QQC2.Label {
                    font.pointSize: Kirigami.Theme.smallFont.pointSize
                    opacity: 0.7
                    text: {
                        var days = retentionSlider.value;
                        if (days >= 365) return i18n("1 year");
                        if (days >= 30) {
                            var months = Math.floor(days / 30);
                            var remainder = days % 30;
                            if (remainder > 0)
                                return i18np("%1 month", "%1 months", months) + " " + i18np("%1 day", "%1 days", remainder);
                            return i18np("%1 month", "%1 months", months);
                        }
                        return i18np("%1 day", "%1 days", days);
                    }
                }
            }
        }

        QQC2.Label {
            Layout.fillWidth: true
            enabled: historySwitch.checked
            text: i18n("Data older than this will be automatically pruned daily.")
            font.pointSize: Kirigami.Theme.smallFont.pointSize
            opacity: 0.5; wrapMode: Text.WordWrap
        }

        // ── Storage ──
        Kirigami.Separator { Layout.fillWidth: true; Layout.topMargin: Kirigami.Units.largeSpacing }
        QQC2.Label { text: i18n("Storage"); font.bold: true }

        RowLayout {
            Layout.fillWidth: true; spacing: Kirigami.Units.smallSpacing
            QQC2.Label { text: i18n("Database size:"); Layout.preferredWidth: historyPage.labelWidth }
            QQC2.Label { text: formatBytes(historyDb.databaseSize()) }
        }

        RowLayout {
            Layout.fillWidth: true; spacing: Kirigami.Units.smallSpacing
            QQC2.Label { text: i18n("Providers tracked:"); Layout.preferredWidth: historyPage.labelWidth; wrapMode: Text.WordWrap }
            QQC2.Label {
                Layout.fillWidth: true
                text: {
                    var providers = historyDb.getProviders();
                    return providers.length > 0 ? providers.join(", ") : i18n("None");
                }
                wrapMode: Text.WordWrap
            }
        }

        RowLayout {
            Layout.fillWidth: true; spacing: Kirigami.Units.smallSpacing
            QQC2.Label { text: i18n("Maintenance:"); Layout.preferredWidth: historyPage.labelWidth }
            QQC2.Button {
                text: i18n("Prune Old Data Now")
                icon.name: "edit-clear-history"
                enabled: historySwitch.checked
                onClicked: {
                    historyDb.pruneOldData();
                    dbSizeRefreshTimer.restart();
                }
            }
        }

        Timer {
            id: dbSizeRefreshTimer
            interval: 500; repeat: false
            onTriggered: historyPage.forceActiveFocus()
        }

        Item { Layout.fillHeight: true }
    }

    function formatBytes(bytes) {
        if (bytes < 1024) return bytes + " B";
        if (bytes < 1024 * 1024) return (bytes / 1024).toFixed(1) + " KB";
        return (bytes / (1024 * 1024)).toFixed(1) + " MB";
    }
}
