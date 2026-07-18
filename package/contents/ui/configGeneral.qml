import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM
import com.github.loofi.aiusagemonitor 1.0

KCM.SimpleKCM {
    id: generalPage

    property alias cfg_refreshInterval: refreshSlider.value
    property string cfg_compactDisplayMode: plasmoid.configuration.compactDisplayMode
    property alias cfg_chartToolIndex: chartToolCombo.currentIndex

    property alias cfg_openaiRefreshInterval: openaiRefreshSlider.value
    property alias cfg_anthropicRefreshInterval: anthropicRefreshSlider.value
    property alias cfg_googleRefreshInterval: googleRefreshSlider.value
    property alias cfg_mistralRefreshInterval: mistralRefreshSlider.value
    property alias cfg_deepseekRefreshInterval: deepseekRefreshSlider.value
    property alias cfg_groqRefreshInterval: groqRefreshSlider.value
    property alias cfg_xaiRefreshInterval: xaiRefreshSlider.value
    property alias cfg_googleveoRefreshInterval: googleveoRefreshSlider.value
    property alias cfg_loofiRefreshInterval: loofiRefreshSlider.value

    readonly property int labelWidth: Kirigami.Units.gridUnit * 12

    ColumnLayout {
        anchors.fill: parent
        spacing: Kirigami.Units.smallSpacing

        // ── Global Refresh Interval ──
        Kirigami.Separator { Layout.fillWidth: true }
        QQC2.Label { text: i18n("Refresh"); font.bold: true }

        RowLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing
            QQC2.Label {
                text: i18n("Default refresh interval:")
                Layout.preferredWidth: generalPage.labelWidth
                wrapMode: Text.WordWrap
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2
                QQC2.Slider {
                    id: refreshSlider
                    Layout.fillWidth: true
                    from: 60; to: 1800; stepSize: 60
                    value: plasmoid.configuration.refreshInterval
                    QQC2.ToolTip.text: i18n("How often to poll provider APIs for updated data (60s–30min)")
                    QQC2.ToolTip.visible: hovered
                    QQC2.ToolTip.delay: 500
                }
                QQC2.Label {
                    text: formatInterval(refreshSlider.value)
                    opacity: 0.7
                    font.pointSize: Kirigami.Theme.smallFont.pointSize
                }
            }
        }

        // ── Panel Display ──
        Kirigami.Separator { Layout.fillWidth: true; Layout.topMargin: Kirigami.Units.largeSpacing }
        QQC2.Label { text: i18n("Panel Display"); font.bold: true }

        RowLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing
            QQC2.Label {
                text: i18n("Show in panel:")
                Layout.preferredWidth: generalPage.labelWidth
            }
            QQC2.ComboBox {
                id: compactModeCombo
                Layout.fillWidth: true
                model: [i18n("Icon only"), i18n("Total cost"), i18n("Active providers count"), i18n("Subscription chart"), i18n("Loofi server KPIs")]
                QQC2.ToolTip.text: i18n("Choose what to display next to the icon in the system panel")
                QQC2.ToolTip.visible: hovered
                QQC2.ToolTip.delay: 500
                currentIndex: {
                    switch (generalPage.cfg_compactDisplayMode) {
                        case "cost": return 1;
                        case "count": return 2;
                        case "chart": return 3;
                        case "loofi": return 4;
                        default: return 0;
                    }
                }
                onCurrentIndexChanged: {
                    switch (currentIndex) {
                        case 1: generalPage.cfg_compactDisplayMode = "cost"; break;
                        case 2: generalPage.cfg_compactDisplayMode = "count"; break;
                        case 3: generalPage.cfg_compactDisplayMode = "chart"; break;
                        case 4: generalPage.cfg_compactDisplayMode = "loofi"; break;
                        default: generalPage.cfg_compactDisplayMode = "icon"; break;
                    }
                }
            }
        }

        // Chart tool selector (visible when chart mode is selected)
        RowLayout {
            visible: generalPage.cfg_compactDisplayMode === "chart"
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing
            QQC2.Label {
                text: i18n("Chart tool:")
                Layout.preferredWidth: generalPage.labelWidth
            }
            QQC2.ComboBox {
                id: chartToolCombo
                Layout.fillWidth: true
                model: [i18n("Claude Code"), i18n("OpenCode"), i18n("Codex CLI"), i18n("GitHub Copilot")]
                currentIndex: plasmoid.configuration.chartToolIndex
                onCurrentIndexChanged: plasmoid.configuration.chartToolIndex = currentIndex
                QQC2.ToolTip.text: i18n("Which subscription tool to display in the panel chart")
                QQC2.ToolTip.visible: hovered
                QQC2.ToolTip.delay: 500
            }
        }

        // ── Per-Provider Refresh Intervals ──
        Kirigami.Separator { Layout.fillWidth: true; Layout.topMargin: Kirigami.Units.largeSpacing }
        QQC2.Label { text: i18n("Per-Provider Refresh Intervals"); font.bold: true }

        QQC2.Label {
            Layout.fillWidth: true
            text: i18n("Set to 0 to use the default interval above. Otherwise, each provider refreshes on its own schedule.")
            font.pointSize: Kirigami.Theme.smallFont.pointSize
            opacity: 0.6
            wrapMode: Text.WordWrap
        }

        // Helper component for each provider slider row
        component ProviderSliderRow: RowLayout {
            property string labelText: ""
            property alias sliderItem: sliderLoader.item
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing
            QQC2.Label {
                text: labelText
                Layout.preferredWidth: generalPage.labelWidth
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2
                Loader { id: sliderLoader }
                QQC2.Label {
                    text: sliderLoader.item
                        ? (sliderLoader.item.value === 0 ? i18n("Use default") : formatInterval(sliderLoader.item.value))
                        : ""
                    font.pointSize: Kirigami.Theme.smallFont.pointSize
                    opacity: 0.7
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing
            QQC2.Label { text: i18n("OpenAI:"); Layout.preferredWidth: generalPage.labelWidth }
            ColumnLayout {
                Layout.fillWidth: true; spacing: 2
                QQC2.Slider { id: openaiRefreshSlider; Layout.fillWidth: true; from: 0; to: 1800; stepSize: 60; value: plasmoid.configuration.openaiRefreshInterval }
                QQC2.Label { text: openaiRefreshSlider.value === 0 ? i18n("Use default") : formatInterval(openaiRefreshSlider.value); font.pointSize: Kirigami.Theme.smallFont.pointSize; opacity: 0.7 }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing
            QQC2.Label { text: i18n("Anthropic:"); Layout.preferredWidth: generalPage.labelWidth }
            ColumnLayout {
                Layout.fillWidth: true; spacing: 2
                QQC2.Slider { id: anthropicRefreshSlider; Layout.fillWidth: true; from: 0; to: 1800; stepSize: 60; value: plasmoid.configuration.anthropicRefreshInterval }
                QQC2.Label { text: anthropicRefreshSlider.value === 0 ? i18n("Use default") : formatInterval(anthropicRefreshSlider.value); font.pointSize: Kirigami.Theme.smallFont.pointSize; opacity: 0.7 }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing
            QQC2.Label { text: i18n("Google Gemini:"); Layout.preferredWidth: generalPage.labelWidth }
            ColumnLayout {
                Layout.fillWidth: true; spacing: 2
                QQC2.Slider { id: googleRefreshSlider; Layout.fillWidth: true; from: 0; to: 1800; stepSize: 60; value: plasmoid.configuration.googleRefreshInterval }
                QQC2.Label { text: googleRefreshSlider.value === 0 ? i18n("Use default") : formatInterval(googleRefreshSlider.value); font.pointSize: Kirigami.Theme.smallFont.pointSize; opacity: 0.7 }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing
            QQC2.Label { text: i18n("Mistral AI:"); Layout.preferredWidth: generalPage.labelWidth }
            ColumnLayout {
                Layout.fillWidth: true; spacing: 2
                QQC2.Slider { id: mistralRefreshSlider; Layout.fillWidth: true; from: 0; to: 1800; stepSize: 60; value: plasmoid.configuration.mistralRefreshInterval }
                QQC2.Label { text: mistralRefreshSlider.value === 0 ? i18n("Use default") : formatInterval(mistralRefreshSlider.value); font.pointSize: Kirigami.Theme.smallFont.pointSize; opacity: 0.7 }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing
            QQC2.Label { text: i18n("DeepSeek:"); Layout.preferredWidth: generalPage.labelWidth }
            ColumnLayout {
                Layout.fillWidth: true; spacing: 2
                QQC2.Slider { id: deepseekRefreshSlider; Layout.fillWidth: true; from: 0; to: 1800; stepSize: 60; value: plasmoid.configuration.deepseekRefreshInterval }
                QQC2.Label { text: deepseekRefreshSlider.value === 0 ? i18n("Use default") : formatInterval(deepseekRefreshSlider.value); font.pointSize: Kirigami.Theme.smallFont.pointSize; opacity: 0.7 }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing
            QQC2.Label { text: i18n("Groq:"); Layout.preferredWidth: generalPage.labelWidth }
            ColumnLayout {
                Layout.fillWidth: true; spacing: 2
                QQC2.Slider { id: groqRefreshSlider; Layout.fillWidth: true; from: 0; to: 1800; stepSize: 60; value: plasmoid.configuration.groqRefreshInterval }
                QQC2.Label { text: groqRefreshSlider.value === 0 ? i18n("Use default") : formatInterval(groqRefreshSlider.value); font.pointSize: Kirigami.Theme.smallFont.pointSize; opacity: 0.7 }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing
            QQC2.Label { text: i18n("xAI / Grok:"); Layout.preferredWidth: generalPage.labelWidth }
            ColumnLayout {
                Layout.fillWidth: true; spacing: 2
                QQC2.Slider { id: xaiRefreshSlider; Layout.fillWidth: true; from: 0; to: 1800; stepSize: 60; value: plasmoid.configuration.xaiRefreshInterval }
                QQC2.Label { text: xaiRefreshSlider.value === 0 ? i18n("Use default") : formatInterval(xaiRefreshSlider.value); font.pointSize: Kirigami.Theme.smallFont.pointSize; opacity: 0.7 }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing
            QQC2.Label { text: i18n("Google Veo:"); Layout.preferredWidth: generalPage.labelWidth }
            ColumnLayout {
                Layout.fillWidth: true; spacing: 2
                QQC2.Slider { id: googleveoRefreshSlider; Layout.fillWidth: true; from: 0; to: 1800; stepSize: 60; value: plasmoid.configuration.googleveoRefreshInterval }
                QQC2.Label { text: googleveoRefreshSlider.value === 0 ? i18n("Use default") : formatInterval(googleveoRefreshSlider.value); font.pointSize: Kirigami.Theme.smallFont.pointSize; opacity: 0.7 }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing
            QQC2.Label { text: i18n("Loofi Server:"); Layout.preferredWidth: generalPage.labelWidth }
            ColumnLayout {
                Layout.fillWidth: true; spacing: 2
                QQC2.Slider { id: loofiRefreshSlider; Layout.fillWidth: true; from: 0; to: 1800; stepSize: 60; value: plasmoid.configuration.loofiRefreshInterval }
                QQC2.Label { text: loofiRefreshSlider.value === 0 ? i18n("Use default") : formatInterval(loofiRefreshSlider.value); font.pointSize: Kirigami.Theme.smallFont.pointSize; opacity: 0.7 }
            }
        }

        // ── About ──
        Kirigami.Separator { Layout.fillWidth: true; Layout.topMargin: Kirigami.Units.largeSpacing }
        QQC2.Label { text: i18n("About"); font.bold: true }

        RowLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing
            QQC2.Label { text: i18n("Icon:"); Layout.preferredWidth: generalPage.labelWidth }
            Kirigami.Icon {
                source: Qt.resolvedUrl("../icons/logo.png")
                Layout.preferredWidth: Kirigami.Units.iconSizes.smallMedium
                Layout.preferredHeight: Kirigami.Units.iconSizes.smallMedium
            }
            QQC2.Label {
                text: i18n("AI Usage Monitor")
                opacity: 0.8
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing
            QQC2.Label { text: i18n("Version:"); Layout.preferredWidth: generalPage.labelWidth }
            QQC2.Label {
                text: (plasmoid.metaData && plasmoid.metaData.version)
                      ? plasmoid.metaData.version
                      : AppInfo.version
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing
            QQC2.Label { text: i18n("Description:"); Layout.preferredWidth: generalPage.labelWidth }
            QQC2.Label {
                Layout.fillWidth: true
                text: i18n("Monitor AI API token usage, rate limits, costs, and budgets across multiple providers")
                wrapMode: Text.WordWrap
            }
        }

        Item { Layout.fillHeight: true }
    }

    function formatInterval(secs) {
        if (secs >= 60) {
            var mins = Math.floor(secs / 60);
            return i18np("%1 minute", "%1 minutes", mins);
        }
        return i18np("%1 second", "%1 seconds", secs);
    }
}
