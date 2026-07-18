import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM
import com.github.loofi.aiusagemonitor 1.0

KCM.SimpleKCM {
    id: subscriptionsPage

    // ── Browser Sync ──
    property alias cfg_browserSyncEnabled: browserSyncSwitch.checked
    property alias cfg_browserSyncBrowser: browserSyncBrowserCombo.currentIndex
    property alias cfg_browserSyncInterval: browserSyncIntervalSpin.value
    property string cfg_browserSyncProfile: plasmoid.configuration.browserSyncProfile || ""

    // ── Claude Code ──
    property alias cfg_claudeCodeEnabled: claudeCodeSwitch.checked
    property alias cfg_claudeCodePlan: claudeCodePlanCombo.currentIndex
    property alias cfg_claudeCodeCustomLimit: claudeCodeLimitSpin.value
    property alias cfg_claudeCodeNotifications: claudeCodeNotifySwitch.checked

    // ── OpenCode ──
    property alias cfg_openCodeEnabled: openCodeSwitch.checked
    property alias cfg_openCodePlan: openCodePlanCombo.currentIndex
    property alias cfg_openCodeCustomLimit: openCodeLimitSpin.value
    property alias cfg_openCodeNotifications: openCodeNotifySwitch.checked

    // ── Codex CLI ──
    property alias cfg_codexEnabled: codexSwitch.checked
    property alias cfg_codexPlan: codexPlanCombo.currentIndex
    property alias cfg_codexCustomLimit: codexLimitSpin.value
    property alias cfg_codexNotifications: codexNotifySwitch.checked

    // ── GitHub Copilot ──
    property alias cfg_copilotEnabled: copilotSwitch.checked
    property alias cfg_copilotPlan: copilotPlanCombo.currentIndex
    property alias cfg_copilotCustomLimit: copilotLimitSpin.value
    property alias cfg_copilotNotifications: copilotNotifySwitch.checked
    property alias cfg_copilotOrgName: copilotOrgField.text

    // Track key dirtiness for Copilot PAT
    property bool copilotTokenDirty: false

    function normalizedSyncCode(code) {
        if (code === "not_found") return "cookies_not_found";
        if (code === "expired") return "session_missing_or_expired";
        return code;
    }

    function syncStatusColor(code) {
        var normalized = normalizedSyncCode(code);
        if (normalized === "connected") return Kirigami.Theme.positiveTextColor;
        if (normalized === "session_missing_or_expired") return Kirigami.Theme.neutralTextColor;
        return Kirigami.Theme.negativeTextColor;
    }

    function syncGuidance(code, serviceLabel) {
        var normalized = normalizedSyncCode(code);
        if (normalized === "connected") return i18n("%1 session looks valid in Firefox.", serviceLabel);
        if (normalized === "profile_missing") return i18n("Install Firefox or choose Firefox for Browser Sync.");
        if (normalized === "cookie_db_missing") return i18n("Open Firefox once, sign in to %1, then retry so the cookie database exists.", serviceLabel);
        if (normalized === "cookies_not_found") return i18n("Open %1 in Firefox and sign in at least once.", serviceLabel);
        if (normalized === "session_missing_or_expired") return i18n("Log in to %1 again in Firefox, then retry.", serviceLabel);
        if (normalized === "unsupported_browser") return i18n("Only Firefox is supported currently.");
        return i18n("Check your browser session and retry.");
    }

    function reloadFirefoxProfiles() {
        var profiles = syncDetector.firefoxProfiles();
        var entries = [i18n("Auto (Default Profile)")];
        for (var i = 0; i < profiles.length; i++) {
            entries.push(profiles[i]);
        }
        firefoxProfileCombo.model = entries;

        if (!cfg_browserSyncProfile || cfg_browserSyncProfile.length === 0) {
            firefoxProfileCombo.currentIndex = 0;
            syncDetector.selectedFirefoxProfile = "";
            return;
        }

        var idx = entries.indexOf(cfg_browserSyncProfile);
        if (idx >= 0) {
            firefoxProfileCombo.currentIndex = idx;
            syncDetector.selectedFirefoxProfile = cfg_browserSyncProfile;
        } else {
            // Persisted profile no longer exists; fall back safely.
            firefoxProfileCombo.currentIndex = 0;
            cfg_browserSyncProfile = "";
            syncDetector.selectedFirefoxProfile = "";
        }
    }

    // ── Temporary monitors for detection ──
    ClaudeCodeMonitor {
        id: claudeDetector
        Component.onCompleted: checkToolInstalled()
    }

    OpenCodeMonitor {
        id: openCodeDetector
        Component.onCompleted: checkToolInstalled()
    }

    CodexCliMonitor {
        id: codexDetector
        Component.onCompleted: checkToolInstalled()
    }

    CopilotMonitor {
        id: copilotDetector
        Component.onCompleted: checkToolInstalled()
    }

    // ── KWallet Integration for Copilot token ──
    SecretsManager {
        id: secrets

        onWalletOpenChanged: {
            if (walletOpen) {
                loadCopilotToken();
            }
        }

        onKeyStored: function(provider) {
            console.log("Key stored for", provider);
        }

        onError: function(message) {
            console.warn("SecretsManager error:", message);
        }
    }

    function loadCopilotToken() {
        if (secrets.hasKey("copilot_github")) {
            copilotTokenField.text = "********";
            copilotTokenDirty = false;
        } else {
            copilotTokenField.text = "";
        }
    }

    function saveCopilotToken() {
        if (copilotTokenDirty && copilotTokenField.text.length > 0 && copilotTokenField.text !== "********") {
            secrets.storeKey("copilot_github", copilotTokenField.text);
        } else if (copilotTokenDirty && copilotTokenField.text.length === 0) {
            secrets.removeKey("copilot_github");
        }
    }

    Component.onCompleted: {
        if (secrets.walletOpen) {
            loadCopilotToken();
        }
        reloadFirefoxProfiles();
    }

    Component.onDestruction: {
        saveCopilotToken();
    }

    // Reusable label width so all rows align
    readonly property int labelWidth: Kirigami.Units.gridUnit * 10

    ColumnLayout {
        anchors.fill: parent
        spacing: Kirigami.Units.smallSpacing

        // ── Description ──
        QQC2.Label {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            text: i18n("Track usage limits for AI coding tools with fixed subscription quotas. "
                     + "These tools don't expose public APIs for quota checking, so usage is "
                     + "tracked locally via filesystem monitoring and manual counting.")
            font.pointSize: Kirigami.Theme.smallFont.pointSize
            opacity: 0.7
        }

        // ══════════════════════════════════════════════
        // ── Claude Code ──
        // ══════════════════════════════════════════════

        Kirigami.Separator {
            Layout.fillWidth: true
            Layout.topMargin: Kirigami.Units.largeSpacing
        }
        QQC2.Label {
            text: i18n("Claude Code")
            font.bold: true
        }

        // Enable row
        RowLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing
            QQC2.Label {
                text: i18n("Enable:")
                Layout.preferredWidth: subscriptionsPage.labelWidth
            }
            QQC2.Switch {
                id: claudeCodeSwitch
                checked: plasmoid.configuration.claudeCodeEnabled
            }
            QQC2.Label {
                Layout.fillWidth: true
                elide: Text.ElideRight
                text: claudeDetector.installed
                    ? "✓ " + i18n("Detected")
                    : "✗ " + i18n("Not found")
                color: claudeDetector.installed
                    ? Kirigami.Theme.positiveTextColor
                    : Kirigami.Theme.disabledTextColor
                font.pointSize: Kirigami.Theme.smallFont.pointSize
            }
        }

        // Plan row
        RowLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing
            QQC2.Label {
                text: i18n("Plan:")
                Layout.preferredWidth: subscriptionsPage.labelWidth
            }
            QQC2.ComboBox {
                id: claudeCodePlanCombo
                enabled: claudeCodeSwitch.checked
                Layout.fillWidth: true
                model: claudeDetector.availablePlans()
                currentIndex: plasmoid.configuration.claudeCodePlan
                onCurrentIndexChanged: {
                    var plans = claudeDetector.availablePlans();
                    if (currentIndex >= 0 && currentIndex < plans.length) {
                        var def = claudeDetector.defaultLimitForPlan(plans[currentIndex]);
                        if (claudeCodeLimitSpin.value === 0 || !claudeCodeLimitOverride.checked) {
                            claudeCodeLimitSpin.value = def;
                        }
                    }
                }
            }
        }

        // Usage limit row
        RowLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing
            QQC2.Label {
                text: i18n("Usage limit (per 5h):")
                Layout.preferredWidth: subscriptionsPage.labelWidth
                wrapMode: Text.WordWrap
            }
            QQC2.SpinBox {
                id: claudeCodeLimitSpin
                enabled: claudeCodeSwitch.checked
                from: 0; to: 99999
                value: plasmoid.configuration.claudeCodeCustomLimit
                editable: true
                Component.onCompleted: {
                    if (value === 0) {
                        var plans = claudeDetector.availablePlans();
                        var idx = claudeCodePlanCombo.currentIndex;
                        if (idx >= 0 && idx < plans.length) {
                            value = claudeDetector.defaultLimitForPlan(plans[idx]);
                        }
                    }
                }
            }
            QQC2.CheckBox {
                id: claudeCodeLimitOverride
                text: i18n("Custom")
                font.pointSize: Kirigami.Theme.smallFont.pointSize
            }
        }

        QQC2.Label {
            visible: claudeCodeSwitch.checked
            Layout.fillWidth: true
            text: i18n("Claude Code also has a weekly rolling limit. The secondary limit "
                     + "is automatically calculated from the plan tier.")
            font.pointSize: Kirigami.Theme.smallFont.pointSize
            opacity: 0.6
            wrapMode: Text.WordWrap
        }

        // Notifications row
        RowLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing
            QQC2.Label {
                text: i18n("Notifications:")
                Layout.preferredWidth: subscriptionsPage.labelWidth
            }
            QQC2.Switch {
                id: claudeCodeNotifySwitch
                enabled: claudeCodeSwitch.checked
                checked: plasmoid.configuration.claudeCodeNotifications
            }
        }

        // ══════════════════════════════════════════════
        // ── OpenCode ──
        // ══════════════════════════════════════════════

        Kirigami.Separator {
            Layout.fillWidth: true
            Layout.topMargin: Kirigami.Units.largeSpacing
        }
        QQC2.Label {
            text: i18n("OpenCode")
            font.bold: true
        }

        // Enable row
        RowLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing
            QQC2.Label {
                text: i18n("Enable:")
                Layout.preferredWidth: subscriptionsPage.labelWidth
            }
            QQC2.Switch {
                id: openCodeSwitch
                checked: plasmoid.configuration.openCodeEnabled
            }
            QQC2.Label {
                Layout.fillWidth: true
                elide: Text.ElideRight
                text: openCodeDetector.installed
                    ? "✓ " + i18n("Detected")
                    : "✗ " + i18n("Not found")
                color: openCodeDetector.installed
                    ? Kirigami.Theme.positiveTextColor
                    : Kirigami.Theme.disabledTextColor
                font.pointSize: Kirigami.Theme.smallFont.pointSize
            }
        }

        // Plan row
        RowLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing
            QQC2.Label {
                text: i18n("Plan:")
                Layout.preferredWidth: subscriptionsPage.labelWidth
            }
            QQC2.ComboBox {
                id: openCodePlanCombo
                enabled: openCodeSwitch.checked
                Layout.fillWidth: true
                model: openCodeDetector.availablePlans()
                currentIndex: plasmoid.configuration.openCodePlan
                onCurrentIndexChanged: {
                    var plans = openCodeDetector.availablePlans();
                    if (currentIndex >= 0 && currentIndex < plans.length) {
                        var def = openCodeDetector.defaultLimitForPlan(plans[currentIndex]);
                        if (openCodeLimitSpin.value === 0 || !openCodeLimitOverride.checked) {
                            openCodeLimitSpin.value = def;
                        }
                    }
                }
            }
        }

        // Usage limit row
        RowLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing
            QQC2.Label {
                text: i18n("Usage limit (per 5h):")
                Layout.preferredWidth: subscriptionsPage.labelWidth
                wrapMode: Text.WordWrap
            }
            QQC2.SpinBox {
                id: openCodeLimitSpin
                enabled: openCodeSwitch.checked
                from: 0; to: 99999
                value: plasmoid.configuration.openCodeCustomLimit
                editable: true
                Component.onCompleted: {
                    if (value === 0) {
                        var plans = openCodeDetector.availablePlans();
                        var idx = openCodePlanCombo.currentIndex;
                        if (idx >= 0 && idx < plans.length) {
                            value = openCodeDetector.defaultLimitForPlan(plans[idx]);
                        }
                    }
                }
            }
            QQC2.CheckBox {
                id: openCodeLimitOverride
                text: i18n("Custom")
                font.pointSize: Kirigami.Theme.smallFont.pointSize
            }
        }

        QQC2.Label {
            visible: openCodeSwitch.checked
            Layout.fillWidth: true
            text: i18n("OpenCode shares the Claude.ai subscription. Usage limits are "
                     + "the same as Claude Code when using the Anthropic provider.")
            font.pointSize: Kirigami.Theme.smallFont.pointSize
            opacity: 0.6
            wrapMode: Text.WordWrap
        }

        // Notifications row
        RowLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing
            QQC2.Label {
                text: i18n("Notifications:")
                Layout.preferredWidth: subscriptionsPage.labelWidth
            }
            QQC2.Switch {
                id: openCodeNotifySwitch
                enabled: openCodeSwitch.checked
                checked: plasmoid.configuration.openCodeNotifications
            }
        }

        // ══════════════════════════════════════════════
        // ── Codex CLI ──
        // ══════════════════════════════════════════════

        Kirigami.Separator {
            Layout.fillWidth: true
            Layout.topMargin: Kirigami.Units.largeSpacing
        }
        QQC2.Label {
            text: i18n("Codex CLI")
            font.bold: true
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing
            QQC2.Label {
                text: i18n("Enable:")
                Layout.preferredWidth: subscriptionsPage.labelWidth
            }
            QQC2.Switch {
                id: codexSwitch
                checked: plasmoid.configuration.codexEnabled
            }
            QQC2.Label {
                Layout.fillWidth: true
                elide: Text.ElideRight
                text: codexDetector.installed
                    ? "✓ " + i18n("Detected")
                    : "✗ " + i18n("Not found")
                color: codexDetector.installed
                    ? Kirigami.Theme.positiveTextColor
                    : Kirigami.Theme.disabledTextColor
                font.pointSize: Kirigami.Theme.smallFont.pointSize
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing
            QQC2.Label {
                text: i18n("Plan:")
                Layout.preferredWidth: subscriptionsPage.labelWidth
            }
            QQC2.ComboBox {
                id: codexPlanCombo
                enabled: codexSwitch.checked
                Layout.fillWidth: true
                model: codexDetector.availablePlans()
                currentIndex: plasmoid.configuration.codexPlan
                onCurrentIndexChanged: {
                    var plans = codexDetector.availablePlans();
                    if (currentIndex >= 0 && currentIndex < plans.length) {
                        var def = codexDetector.defaultLimitForPlan(plans[currentIndex]);
                        if (codexLimitSpin.value === 0 || !codexLimitOverride.checked) {
                            codexLimitSpin.value = def;
                        }
                    }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing
            QQC2.Label {
                text: i18n("Usage limit (per 5h):")
                Layout.preferredWidth: subscriptionsPage.labelWidth
                wrapMode: Text.WordWrap
            }
            QQC2.SpinBox {
                id: codexLimitSpin
                enabled: codexSwitch.checked
                from: 0; to: 99999
                value: plasmoid.configuration.codexCustomLimit
                editable: true
                Component.onCompleted: {
                    if (value === 0) {
                        var plans = codexDetector.availablePlans();
                        var idx = codexPlanCombo.currentIndex;
                        if (idx >= 0 && idx < plans.length) {
                            value = codexDetector.defaultLimitForPlan(plans[idx]);
                        }
                    }
                }
            }
            QQC2.CheckBox {
                id: codexLimitOverride
                text: i18n("Custom")
                font.pointSize: Kirigami.Theme.smallFont.pointSize
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing
            QQC2.Label {
                text: i18n("Notifications:")
                Layout.preferredWidth: subscriptionsPage.labelWidth
            }
            QQC2.Switch {
                id: codexNotifySwitch
                enabled: codexSwitch.checked
                checked: plasmoid.configuration.codexNotifications
            }
        }

        // ══════════════════════════════════════════════
        // ── GitHub Copilot ──
        // ══════════════════════════════════════════════

        Kirigami.Separator {
            Layout.fillWidth: true
            Layout.topMargin: Kirigami.Units.largeSpacing
        }
        QQC2.Label {
            text: i18n("GitHub Copilot")
            font.bold: true
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing
            QQC2.Label {
                text: i18n("Enable:")
                Layout.preferredWidth: subscriptionsPage.labelWidth
            }
            QQC2.Switch {
                id: copilotSwitch
                checked: plasmoid.configuration.copilotEnabled
            }
            QQC2.Label {
                Layout.fillWidth: true
                elide: Text.ElideRight
                text: copilotDetector.installed
                    ? "✓ " + i18n("Detected")
                    : "✗ " + i18n("Not found")
                color: copilotDetector.installed
                    ? Kirigami.Theme.positiveTextColor
                    : Kirigami.Theme.disabledTextColor
                font.pointSize: Kirigami.Theme.smallFont.pointSize
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing
            QQC2.Label {
                text: i18n("Plan:")
                Layout.preferredWidth: subscriptionsPage.labelWidth
            }
            QQC2.ComboBox {
                id: copilotPlanCombo
                enabled: copilotSwitch.checked
                Layout.fillWidth: true
                model: copilotDetector.availablePlans()
                currentIndex: plasmoid.configuration.copilotPlan
                onCurrentIndexChanged: {
                    var plans = copilotDetector.availablePlans();
                    if (currentIndex >= 0 && currentIndex < plans.length) {
                        var def = copilotDetector.defaultLimitForPlan(plans[currentIndex]);
                        if (copilotLimitSpin.value === 0 || !copilotLimitOverride.checked) {
                            copilotLimitSpin.value = def;
                        }
                    }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing
            QQC2.Label {
                text: i18n("Premium requests (monthly):")
                Layout.preferredWidth: subscriptionsPage.labelWidth
                wrapMode: Text.WordWrap
            }
            QQC2.SpinBox {
                id: copilotLimitSpin
                enabled: copilotSwitch.checked
                from: 0; to: 99999
                value: plasmoid.configuration.copilotCustomLimit
                editable: true
                Component.onCompleted: {
                    if (value === 0) {
                        var plans = copilotDetector.availablePlans();
                        var idx = copilotPlanCombo.currentIndex;
                        if (idx >= 0 && idx < plans.length) {
                            value = copilotDetector.defaultLimitForPlan(plans[idx]);
                        }
                    }
                }
            }
            QQC2.CheckBox {
                id: copilotLimitOverride
                text: i18n("Custom")
                font.pointSize: Kirigami.Theme.smallFont.pointSize
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing
            QQC2.Label {
                text: i18n("Notifications:")
                Layout.preferredWidth: subscriptionsPage.labelWidth
            }
            QQC2.Switch {
                id: copilotNotifySwitch
                enabled: copilotSwitch.checked
                checked: plasmoid.configuration.copilotNotifications
            }
        }

        // ── Optional GitHub API integration ──
        Kirigami.Separator {
            visible: copilotSwitch.checked
            Layout.fillWidth: true
            Layout.topMargin: Kirigami.Units.largeSpacing
        }
        QQC2.Label {
            visible: copilotSwitch.checked
            text: i18n("GitHub API (Optional)")
            font.bold: true
        }

        QQC2.Label {
            visible: copilotSwitch.checked
            Layout.fillWidth: true
            text: i18n("Provide a GitHub Personal Access Token to fetch organization-level "
                     + "Copilot seat metrics. Requires 'manage_billing:copilot' scope.")
            font.pointSize: Kirigami.Theme.smallFont.pointSize
            opacity: 0.6
            wrapMode: Text.WordWrap
        }

        RowLayout {
            visible: copilotSwitch.checked
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing
            QQC2.Label {
                text: i18n("GitHub Token:")
                Layout.preferredWidth: subscriptionsPage.labelWidth
            }
            QQC2.TextField {
                id: copilotTokenField
                enabled: copilotSwitch.checked
                echoMode: copilotTokenVisible.checked ? TextInput.Normal : TextInput.Password
                placeholderText: i18n("ghp_...")
                Layout.fillWidth: true
                onTextEdited: subscriptionsPage.copilotTokenDirty = true
            }
            QQC2.ToolButton {
                id: copilotTokenVisible
                checkable: true; checked: false
                icon.name: checked ? "password-show-off" : "password-show-on"
                display: QQC2.AbstractButton.IconOnly
                QQC2.ToolTip.text: checked ? i18n("Hide token") : i18n("Show token")
                QQC2.ToolTip.visible: hovered
            }
            QQC2.ToolButton {
                icon.name: "edit-clear"
                enabled: copilotTokenField.text.length > 0
                display: QQC2.AbstractButton.IconOnly
                QQC2.ToolTip.text: i18n("Clear token"); QQC2.ToolTip.visible: hovered
                onClicked: { copilotTokenField.text = ""; subscriptionsPage.copilotTokenDirty = true; }
            }
        }

        RowLayout {
            visible: copilotSwitch.checked
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing
            QQC2.Label {
                text: i18n("Organization:")
                Layout.preferredWidth: subscriptionsPage.labelWidth
            }
            QQC2.TextField {
                id: copilotOrgField
                enabled: copilotSwitch.checked
                text: plasmoid.configuration.copilotOrgName
                placeholderText: i18n("my-org-name")
                Layout.fillWidth: true
            }
        }

        // ══════════════════════════════════════════════
        // ── Browser Sync (Experimental) ──
        // ══════════════════════════════════════════════

        Kirigami.Separator {
            Layout.fillWidth: true
            Layout.topMargin: Kirigami.Units.largeSpacing
        }
        QQC2.Label {
            text: i18n("Browser Sync (Experimental)")
            font.bold: true
        }

        QQC2.Label {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            text: i18n("Sync real-time usage data by reading session cookies from your browser. "
                     + "This reads cookies from your browser's cookie database (read-only) to "
                     + "fetch usage data from Claude.ai and ChatGPT. Firefox only for now.")
            font.pointSize: Kirigami.Theme.smallFont.pointSize
            opacity: 0.7
        }

        Rectangle {
            Layout.fillWidth: true
            height: disclaimerLabel.implicitHeight + Kirigami.Units.smallSpacing * 2
            radius: Kirigami.Units.cornerRadius
            color: Qt.alpha(Kirigami.Theme.neutralTextColor, 0.08)
            border.width: 1
            border.color: Qt.alpha(Kirigami.Theme.neutralTextColor, 0.2)

            QQC2.Label {
                id: disclaimerLabel
                anchors {
                    fill: parent
                    margins: Kirigami.Units.smallSpacing
                }
                wrapMode: Text.WordWrap
                text: i18n("⚠ This feature uses internal, undocumented APIs. It may stop working "
                         + "if services change their API. Your cookie data never leaves your "
                         + "machine — all requests go directly to the official services.")
                font.pointSize: Kirigami.Theme.smallFont.pointSize
                color: Kirigami.Theme.neutralTextColor
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing
            QQC2.Label {
                text: i18n("Enable sync:")
                Layout.preferredWidth: subscriptionsPage.labelWidth
            }
            QQC2.Switch {
                id: browserSyncSwitch
                checked: plasmoid.configuration.browserSyncEnabled
            }
            QQC2.Label {
                Layout.fillWidth: true
                elide: Text.ElideRight
                text: syncDetector.hasFirefoxProfile
                    ? "✓ " + i18n("Firefox profile found")
                    : "✗ " + i18n("No Firefox profile")
                color: syncDetector.hasFirefoxProfile
                    ? Kirigami.Theme.positiveTextColor
                    : Kirigami.Theme.disabledTextColor
                font.pointSize: Kirigami.Theme.smallFont.pointSize
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing
            QQC2.Label {
                text: i18n("Browser:")
                Layout.preferredWidth: subscriptionsPage.labelWidth
            }
            QQC2.ComboBox {
                id: browserSyncBrowserCombo
                enabled: browserSyncSwitch.checked
                Layout.fillWidth: true
                model: [i18n("Firefox (supported)")]
                currentIndex: 0
                Component.onCompleted: {
                    if (plasmoid.configuration.browserSyncBrowser !== 0) {
                        cfg_browserSyncBrowser = 0;
                    }
                }
            }
        }

        QQC2.Label {
            visible: browserSyncSwitch.checked
            Layout.fillWidth: true
            text: i18n("Browser Sync currently supports Firefox only. Chrome/Chromium are not available in this release.")
            font.pointSize: Kirigami.Theme.smallFont.pointSize
            opacity: 0.65
            wrapMode: Text.WordWrap
        }

        RowLayout {
            Layout.fillWidth: true
            visible: browserSyncSwitch.checked && browserSyncBrowserCombo.currentIndex === 0
            enabled: browserSyncSwitch.checked && browserSyncBrowserCombo.currentIndex === 0
            spacing: Kirigami.Units.smallSpacing
            QQC2.Label {
                text: i18n("Firefox profile:")
                Layout.preferredWidth: subscriptionsPage.labelWidth
            }
            QQC2.ComboBox {
                id: firefoxProfileCombo
                Layout.fillWidth: true
                model: [i18n("Auto (Default Profile)")]
                onActivated: {
                    if (currentIndex <= 0) {
                        cfg_browserSyncProfile = "";
                        syncDetector.selectedFirefoxProfile = "";
                    } else {
                        cfg_browserSyncProfile = currentText;
                        syncDetector.selectedFirefoxProfile = currentText;
                    }
                }
            }
            QQC2.ToolButton {
                icon.name: "view-refresh"
                display: QQC2.AbstractButton.IconOnly
                QQC2.ToolTip.text: i18n("Reload Firefox profiles")
                QQC2.ToolTip.visible: hovered
                onClicked: reloadFirefoxProfiles()
            }
        }

        RowLayout {
            Layout.fillWidth: true
            enabled: browserSyncSwitch.checked
            spacing: Kirigami.Units.smallSpacing
            QQC2.Label {
                text: i18n("Sync interval:")
                Layout.preferredWidth: subscriptionsPage.labelWidth
            }
            QQC2.SpinBox {
                id: browserSyncIntervalSpin
                from: 60; to: 3600; stepSize: 60
                value: plasmoid.configuration.browserSyncInterval
                editable: true
                textFromValue: function(value, locale) {
                    return Math.floor(value / 60) + " min";
                }
                valueFromText: function(text, locale) {
                    return parseInt(text) * 60;
                }
            }
            QQC2.Label {
                text: i18n("(minimum 60 seconds)")
                font.pointSize: Kirigami.Theme.smallFont.pointSize
                opacity: 0.5
                elide: Text.ElideRight
                Layout.fillWidth: true
            }
        }

        // Connection test
        RowLayout {
            visible: browserSyncSwitch.checked
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing
            QQC2.Label {
                text: i18n("Connection test:")
                Layout.preferredWidth: subscriptionsPage.labelWidth
            }
            QQC2.Button {
                text: i18n("Test Claude.ai")
                icon.name: "network-connect"
                onClicked: {
                    var result = subscriptionsPage.normalizedSyncCode(syncDetector.testConnection("claude"));
                    claudeTestLabel.text = syncDetector.connectionMessage("claude", result);
                    claudeTestLabel.color = subscriptionsPage.syncStatusColor(result);
                    claudeTestLabel.visible = true;
                    claudeGuidanceLabel.text = subscriptionsPage.syncGuidance(result, "claude.ai");
                    claudeGuidanceLabel.visible = true;
                }
            }
            QQC2.Label {
                id: claudeTestLabel
                visible: false
                font.pointSize: Kirigami.Theme.smallFont.pointSize
                Layout.fillWidth: true
                elide: Text.ElideRight
            }
        }

        QQC2.Label {
            id: claudeGuidanceLabel
            visible: false
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            font.pointSize: Kirigami.Theme.smallFont.pointSize
            opacity: 0.75
        }

        RowLayout {
            visible: browserSyncSwitch.checked
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing
            Item { Layout.preferredWidth: subscriptionsPage.labelWidth }
            QQC2.Button {
                text: i18n("Test ChatGPT")
                icon.name: "network-connect"
                onClicked: {
                    var result = subscriptionsPage.normalizedSyncCode(syncDetector.testConnection("chatgpt"));
                    chatgptTestLabel.text = syncDetector.connectionMessage("chatgpt", result);
                    chatgptTestLabel.color = subscriptionsPage.syncStatusColor(result);
                    chatgptTestLabel.visible = true;
                    chatgptGuidanceLabel.text = subscriptionsPage.syncGuidance(result, "chatgpt.com");
                    chatgptGuidanceLabel.visible = true;
                }
            }
            QQC2.Label {
                id: chatgptTestLabel
                visible: false
                font.pointSize: Kirigami.Theme.smallFont.pointSize
                Layout.fillWidth: true
                elide: Text.ElideRight
            }
        }

        QQC2.Label {
            id: chatgptGuidanceLabel
            visible: false
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            font.pointSize: Kirigami.Theme.smallFont.pointSize
            opacity: 0.75
        }

        Item { Layout.fillHeight: true }

    }  // ColumnLayout

    // ── BrowserCookieExtractor for config page ──
    BrowserCookieExtractor {
        id: syncDetector
        selectedFirefoxProfile: subscriptionsPage.cfg_browserSyncProfile
    }
}
