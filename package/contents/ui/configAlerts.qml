import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM

KCM.SimpleKCM {
    id: alertsPage

    property alias cfg_alertsEnabled: alertsSwitch.checked
    property alias cfg_warningThreshold: warningSlider.value
    property alias cfg_criticalThreshold: criticalSlider.value
    property alias cfg_notifyOnError: errorNotifySwitch.checked
    property alias cfg_notifyOnBudgetWarning: budgetNotifySwitch.checked
    property alias cfg_notifyOnDisconnect: disconnectNotifySwitch.checked
    property alias cfg_notifyOnReconnect: reconnectNotifySwitch.checked
    property alias cfg_notificationCooldownMinutes: cooldownSlider.value
    property int cfg_dndStartHour: plasmoid.configuration.dndStartHour
    property int cfg_dndEndHour: plasmoid.configuration.dndEndHour

    property alias cfg_openaiNotificationsEnabled: openaiNotifySwitch.checked
    property alias cfg_anthropicNotificationsEnabled: anthropicNotifySwitch.checked
    property alias cfg_googleNotificationsEnabled: googleNotifySwitch.checked
    property alias cfg_mistralNotificationsEnabled: mistralNotifySwitch.checked
    property alias cfg_deepseekNotificationsEnabled: deepseekNotifySwitch.checked
    property alias cfg_groqNotificationsEnabled: groqNotifySwitch.checked
    property alias cfg_xaiNotificationsEnabled: xaiNotifySwitch.checked
    property alias cfg_googleveoNotificationsEnabled: googleveoNotifySwitch.checked
    property alias cfg_azureNotificationsEnabled: azureNotifySwitch.checked
    property alias cfg_loofiNotificationsEnabled: loofiNotifySwitch.checked

    readonly property int labelWidth: Kirigami.Units.gridUnit * 12

    ColumnLayout {
        anchors.fill: parent
        spacing: Kirigami.Units.smallSpacing

        // ── Master Toggle ──
        RowLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing
            QQC2.Label { text: i18n("Enable alerts:"); Layout.preferredWidth: alertsPage.labelWidth }
            QQC2.Switch {
                id: alertsSwitch
                checked: plasmoid.configuration.alertsEnabled
            }
        }

        // ── Rate Limit Thresholds ──
        Kirigami.Separator { Layout.fillWidth: true; Layout.topMargin: Kirigami.Units.largeSpacing }
        QQC2.Label { text: i18n("Rate Limit Thresholds"); font.bold: true }

        RowLayout {
            Layout.fillWidth: true
            enabled: alertsSwitch.checked
            spacing: Kirigami.Units.smallSpacing
            QQC2.Label { text: i18n("Warning threshold:"); Layout.preferredWidth: alertsPage.labelWidth; wrapMode: Text.WordWrap }
            ColumnLayout {
                Layout.fillWidth: true; spacing: 2
                QQC2.Slider {
                    id: warningSlider
                    Layout.fillWidth: true
                    from: 50; to: 95; stepSize: 5
                    value: plasmoid.configuration.warningThreshold
                    onValueChanged: { if (value >= criticalSlider.value) value = criticalSlider.value - 5; }
                }
                QQC2.Label { text: i18n("%1% of rate limit used", warningSlider.value); opacity: 0.7; font.pointSize: Kirigami.Theme.smallFont.pointSize }
                QQC2.Label { text: i18n("Shows yellow warning indicator and optional notification"); font.pointSize: Kirigami.Theme.smallFont.pointSize; opacity: 0.5; wrapMode: Text.WordWrap; Layout.fillWidth: true }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            enabled: alertsSwitch.checked
            spacing: Kirigami.Units.smallSpacing
            QQC2.Label { text: i18n("Critical threshold:"); Layout.preferredWidth: alertsPage.labelWidth; wrapMode: Text.WordWrap }
            ColumnLayout {
                Layout.fillWidth: true; spacing: 2
                QQC2.Slider {
                    id: criticalSlider
                    Layout.fillWidth: true
                    from: 60; to: 100; stepSize: 5
                    value: plasmoid.configuration.criticalThreshold
                    onValueChanged: { if (value <= warningSlider.value) value = warningSlider.value + 5; }
                }
                QQC2.Label { text: i18n("%1% of rate limit used", criticalSlider.value); opacity: 0.7; font.pointSize: Kirigami.Theme.smallFont.pointSize }
                QQC2.Label { text: i18n("Shows red critical indicator and urgent notification"); font.pointSize: Kirigami.Theme.smallFont.pointSize; opacity: 0.5; wrapMode: Text.WordWrap; Layout.fillWidth: true }
            }
        }

        // ── Notification Types ──
        Kirigami.Separator { Layout.fillWidth: true; Layout.topMargin: Kirigami.Units.largeSpacing }
        QQC2.Label { text: i18n("Notification Types"); font.bold: true }

        RowLayout {
            Layout.fillWidth: true; spacing: Kirigami.Units.smallSpacing
            QQC2.Label { text: i18n("API errors:"); Layout.preferredWidth: alertsPage.labelWidth }
            QQC2.Switch { id: errorNotifySwitch; enabled: alertsSwitch.checked; checked: plasmoid.configuration.notifyOnError }
        }
        RowLayout {
            Layout.fillWidth: true; spacing: Kirigami.Units.smallSpacing
            QQC2.Label { text: i18n("Budget warnings:"); Layout.preferredWidth: alertsPage.labelWidth }
            QQC2.Switch { id: budgetNotifySwitch; enabled: alertsSwitch.checked; checked: plasmoid.configuration.notifyOnBudgetWarning }
        }
        RowLayout {
            Layout.fillWidth: true; spacing: Kirigami.Units.smallSpacing
            QQC2.Label { text: i18n("Provider disconnected:"); Layout.preferredWidth: alertsPage.labelWidth; wrapMode: Text.WordWrap }
            QQC2.Switch { id: disconnectNotifySwitch; enabled: alertsSwitch.checked; checked: plasmoid.configuration.notifyOnDisconnect }
        }
        RowLayout {
            Layout.fillWidth: true; spacing: Kirigami.Units.smallSpacing
            QQC2.Label { text: i18n("Provider reconnected:"); Layout.preferredWidth: alertsPage.labelWidth; wrapMode: Text.WordWrap }
            QQC2.Switch { id: reconnectNotifySwitch; enabled: alertsSwitch.checked; checked: plasmoid.configuration.notifyOnReconnect }
        }

        // ── Per-Provider Notifications ──
        Kirigami.Separator { Layout.fillWidth: true; Layout.topMargin: Kirigami.Units.largeSpacing }
        QQC2.Label { text: i18n("Per-Provider Notifications"); font.bold: true }

        QQC2.Label {
            Layout.fillWidth: true
            text: i18n("Disable notifications for specific providers. Global types above still apply.")
            font.pointSize: Kirigami.Theme.smallFont.pointSize
            opacity: 0.6; wrapMode: Text.WordWrap
        }

        RowLayout { Layout.fillWidth: true; spacing: Kirigami.Units.smallSpacing; QQC2.Label { text: i18n("OpenAI:"); Layout.preferredWidth: alertsPage.labelWidth } QQC2.Switch { id: openaiNotifySwitch; enabled: alertsSwitch.checked; checked: plasmoid.configuration.openaiNotificationsEnabled } }
        RowLayout { Layout.fillWidth: true; spacing: Kirigami.Units.smallSpacing; QQC2.Label { text: i18n("Anthropic:"); Layout.preferredWidth: alertsPage.labelWidth } QQC2.Switch { id: anthropicNotifySwitch; enabled: alertsSwitch.checked; checked: plasmoid.configuration.anthropicNotificationsEnabled } }
        RowLayout { Layout.fillWidth: true; spacing: Kirigami.Units.smallSpacing; QQC2.Label { text: i18n("Google Gemini:"); Layout.preferredWidth: alertsPage.labelWidth } QQC2.Switch { id: googleNotifySwitch; enabled: alertsSwitch.checked; checked: plasmoid.configuration.googleNotificationsEnabled } }
        RowLayout { Layout.fillWidth: true; spacing: Kirigami.Units.smallSpacing; QQC2.Label { text: i18n("Mistral AI:"); Layout.preferredWidth: alertsPage.labelWidth } QQC2.Switch { id: mistralNotifySwitch; enabled: alertsSwitch.checked; checked: plasmoid.configuration.mistralNotificationsEnabled } }
        RowLayout { Layout.fillWidth: true; spacing: Kirigami.Units.smallSpacing; QQC2.Label { text: i18n("DeepSeek:"); Layout.preferredWidth: alertsPage.labelWidth } QQC2.Switch { id: deepseekNotifySwitch; enabled: alertsSwitch.checked; checked: plasmoid.configuration.deepseekNotificationsEnabled } }
        RowLayout { Layout.fillWidth: true; spacing: Kirigami.Units.smallSpacing; QQC2.Label { text: i18n("Groq:"); Layout.preferredWidth: alertsPage.labelWidth } QQC2.Switch { id: groqNotifySwitch; enabled: alertsSwitch.checked; checked: plasmoid.configuration.groqNotificationsEnabled } }
        RowLayout { Layout.fillWidth: true; spacing: Kirigami.Units.smallSpacing; QQC2.Label { text: i18n("xAI / Grok:"); Layout.preferredWidth: alertsPage.labelWidth } QQC2.Switch { id: xaiNotifySwitch; enabled: alertsSwitch.checked; checked: plasmoid.configuration.xaiNotificationsEnabled } }
        RowLayout { Layout.fillWidth: true; spacing: Kirigami.Units.smallSpacing; QQC2.Label { text: i18n("Google Veo:"); Layout.preferredWidth: alertsPage.labelWidth } QQC2.Switch { id: googleveoNotifySwitch; enabled: alertsSwitch.checked; checked: plasmoid.configuration.googleveoNotificationsEnabled } }

        QQC2.Switch {
            id: azureNotifySwitch
            Kirigami.FormData.label: i18n("Azure OpenAI:")
            enabled: alertsSwitch.checked
            checked: plasmoid.configuration.azureNotificationsEnabled
        }

        QQC2.Switch {
            id: loofiNotifySwitch
            Kirigami.FormData.label: i18n("Loofi Server:")
            enabled: alertsSwitch.checked
            checked: plasmoid.configuration.loofiNotificationsEnabled
        }

        // ── Cooldown & Do Not Disturb ──
        Kirigami.Separator { Layout.fillWidth: true; Layout.topMargin: Kirigami.Units.largeSpacing }
        QQC2.Label { text: i18n("Cooldown & Do Not Disturb"); font.bold: true }

        RowLayout {
            Layout.fillWidth: true
            enabled: alertsSwitch.checked
            spacing: Kirigami.Units.smallSpacing
            QQC2.Label { text: i18n("Notification cooldown:"); Layout.preferredWidth: alertsPage.labelWidth; wrapMode: Text.WordWrap }
            ColumnLayout {
                Layout.fillWidth: true; spacing: 2
                QQC2.Slider { id: cooldownSlider; Layout.fillWidth: true; from: 1; to: 60; stepSize: 1; value: plasmoid.configuration.notificationCooldownMinutes }
                QQC2.Label {
                    Layout.fillWidth: true
                    text: i18np("%1 minute between repeated notifications", "%1 minutes between repeated notifications", cooldownSlider.value)
                    opacity: 0.7; font.pointSize: Kirigami.Theme.smallFont.pointSize; wrapMode: Text.WordWrap
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            enabled: alertsSwitch.checked
            spacing: Kirigami.Units.smallSpacing
            QQC2.Label { text: i18n("Do Not Disturb:"); Layout.preferredWidth: alertsPage.labelWidth }
            QQC2.ComboBox {
                id: dndStartCombo
                model: buildHourModel()
                currentIndex: cfg_dndStartHour >= 0 ? cfg_dndStartHour + 1 : 0
                onCurrentIndexChanged: { cfg_dndStartHour = currentIndex === 0 ? -1 : currentIndex - 1; }
            }
            QQC2.Label { text: i18n("to") }
            QQC2.ComboBox {
                id: dndEndCombo
                enabled: dndStartCombo.currentIndex > 0
                model: buildHourModel()
                currentIndex: cfg_dndEndHour >= 0 ? cfg_dndEndHour + 1 : 0
                onCurrentIndexChanged: { cfg_dndEndHour = currentIndex === 0 ? -1 : currentIndex - 1; }
            }
        }

        QQC2.Label {
            Layout.fillWidth: true
            enabled: alertsSwitch.checked
            text: i18n("Suppress all notifications during this time window. Set start to 'Disabled' to turn off DND.")
            font.pointSize: Kirigami.Theme.smallFont.pointSize
            opacity: 0.5; wrapMode: Text.WordWrap
        }

        // ── Preview ──
        Kirigami.Separator { Layout.fillWidth: true; Layout.topMargin: Kirigami.Units.largeSpacing }
        QQC2.Label { text: i18n("Preview"); font.bold: true }

        RowLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing
            QQC2.Label { text: i18n("Status colors:"); Layout.preferredWidth: alertsPage.labelWidth }
            RowLayout {
                spacing: Kirigami.Units.largeSpacing
                RowLayout { spacing: Kirigami.Units.smallSpacing; Rectangle { width: 12; height: 12; radius: 6; color: Kirigami.Theme.positiveTextColor } QQC2.Label { text: i18n("OK"); font.pointSize: Kirigami.Theme.smallFont.pointSize } }
                RowLayout { spacing: Kirigami.Units.smallSpacing; Rectangle { width: 12; height: 12; radius: 6; color: Kirigami.Theme.neutralTextColor } QQC2.Label { text: i18n("Warning"); font.pointSize: Kirigami.Theme.smallFont.pointSize } }
                RowLayout { spacing: Kirigami.Units.smallSpacing; Rectangle { width: 12; height: 12; radius: 6; color: Kirigami.Theme.negativeTextColor } QQC2.Label { text: i18n("Critical"); font.pointSize: Kirigami.Theme.smallFont.pointSize } }
            }
        }

        Item { Layout.fillHeight: true }
    }

    function buildHourModel() {
        var items = [i18n("Disabled")];
        for (var h = 0; h < 24; h++) {
            items.push(h.toString().padStart(2, '0') + ":00");
        }
        return items;
    }
}
