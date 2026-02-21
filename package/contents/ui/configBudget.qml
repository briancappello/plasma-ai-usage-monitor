import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM

KCM.SimpleKCM {
    id: budgetPage

    property int cfg_openaiDailyBudget
    property int cfg_openaiMonthlyBudget
    property int cfg_anthropicDailyBudget
    property int cfg_anthropicMonthlyBudget
    property int cfg_googleDailyBudget
    property int cfg_googleMonthlyBudget
    property int cfg_mistralDailyBudget
    property int cfg_mistralMonthlyBudget
    property int cfg_deepseekDailyBudget
    property int cfg_deepseekMonthlyBudget
    property int cfg_groqDailyBudget
    property int cfg_groqMonthlyBudget
    property int cfg_xaiDailyBudget
    property int cfg_xaiMonthlyBudget
    property alias cfg_budgetWarningPercent: warningPercentSlider.value

    readonly property var providerBudgets: [
        { name: "OpenAI",        dailyKey: "openaiDailyBudget",    monthlyKey: "openaiMonthlyBudget"    },
        { name: "Anthropic",     dailyKey: "anthropicDailyBudget", monthlyKey: "anthropicMonthlyBudget" },
        { name: "Google Gemini", dailyKey: "googleDailyBudget",    monthlyKey: "googleMonthlyBudget"    },
        { name: "Mistral AI",    dailyKey: "mistralDailyBudget",   monthlyKey: "mistralMonthlyBudget"   },
        { name: "DeepSeek",      dailyKey: "deepseekDailyBudget",  monthlyKey: "deepseekMonthlyBudget"  },
        { name: "Groq",          dailyKey: "groqDailyBudget",      monthlyKey: "groqMonthlyBudget"      },
        { name: "xAI / Grok",    dailyKey: "xaiDailyBudget",       monthlyKey: "xaiMonthlyBudget"       },
        { name: "Google Veo",    dailyKey: "googleveoDailyBudget", monthlyKey: "googleveoMonthlyBudget" }
    ]

    readonly property int labelWidth: Kirigami.Units.gridUnit * 12

    function centsToText(value) { return "$" + (value / 100).toFixed(2); }
    function textToCents(text) {
        var val = parseFloat(text.replace("$", ""));
        return isNaN(val) ? 0 : Math.round(val * 100);
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: Kirigami.Units.smallSpacing

        QQC2.Label {
            Layout.fillWidth: true
            text: i18n("Set daily and monthly budget limits per provider. Set to $0.00 to disable budget tracking for that provider.")
            font.pointSize: Kirigami.Theme.smallFont.pointSize
            opacity: 0.6; wrapMode: Text.WordWrap
        }

        // ── Warning Threshold ──
        Kirigami.Separator { Layout.fillWidth: true; Layout.topMargin: Kirigami.Units.largeSpacing }
        QQC2.Label { text: i18n("Warning Threshold"); font.bold: true }

        RowLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing
            QQC2.Label { text: i18n("Warn at:"); Layout.preferredWidth: budgetPage.labelWidth }
            ColumnLayout {
                Layout.fillWidth: true; spacing: 2
                QQC2.Slider {
                    id: warningPercentSlider
                    Layout.fillWidth: true
                    from: 50; to: 100; stepSize: 5
                    QQC2.ToolTip.text: i18n("Trigger a desktop notification when spending reaches this percentage of the budget")
                    QQC2.ToolTip.visible: hovered
                    QQC2.ToolTip.delay: 500
                }
                QQC2.Label { text: i18n("%1% of budget", warningPercentSlider.value); opacity: 0.7; font.pointSize: Kirigami.Theme.smallFont.pointSize }
            }
        }

        // ── Per-provider budgets ──
        Repeater {
            model: budgetPage.providerBudgets

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing

                Kirigami.Separator { Layout.fillWidth: true; Layout.topMargin: Kirigami.Units.largeSpacing }
                QQC2.Label { text: modelData.name; font.bold: true }

                RowLayout {
                    Layout.fillWidth: true; spacing: Kirigami.Units.smallSpacing
                    QQC2.Label { text: i18n("Daily budget ($):"); Layout.preferredWidth: budgetPage.labelWidth; wrapMode: Text.WordWrap }
                    QQC2.SpinBox {
                        id: dailyField
                        from: 0; to: 100000; stepSize: 100
                        value: budgetPage["cfg_" + modelData.dailyKey]
                        textFromValue: function(value, locale) { return budgetPage.centsToText(value); }
                        valueFromText: function(text, locale) { return budgetPage.textToCents(text); }
                        onValueModified: { budgetPage["cfg_" + modelData.dailyKey] = value; }
                        Component.onCompleted: { value = budgetPage["cfg_" + modelData.dailyKey]; }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true; spacing: Kirigami.Units.smallSpacing
                    QQC2.Label { text: i18n("Monthly budget ($):"); Layout.preferredWidth: budgetPage.labelWidth; wrapMode: Text.WordWrap }
                    QQC2.SpinBox {
                        id: monthlyField
                        from: 0; to: 1000000; stepSize: 500
                        value: budgetPage["cfg_" + modelData.monthlyKey]
                        textFromValue: function(value, locale) { return budgetPage.centsToText(value); }
                        valueFromText: function(text, locale) { return budgetPage.textToCents(text); }
                        onValueModified: { budgetPage["cfg_" + modelData.monthlyKey] = value; }
                        Component.onCompleted: { value = budgetPage["cfg_" + modelData.monthlyKey]; }
                    }
                }
            }
        }

        Item { Layout.fillHeight: true }
    }
}
