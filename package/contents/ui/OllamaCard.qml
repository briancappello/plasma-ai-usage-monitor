import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.extras as PlasmaExtras
import org.kde.kirigami as Kirigami

// Compact card for the local Ollama server. Unlike API providers, Ollama has
// no cost/usage/token accounting — it exposes loaded models and their RAM/VRAM
// footprint (OllamaProvider: activeModels[{name,size,sizeVram}], totalMemory,
// vramMemory). Kept deliberately small; the standard ProviderCard doesn't fit
// because it requires providerName/providerIcon/modelData and shows cost bars.
ColumnLayout {
    id: card

    required property var backend
    required property string providerColor

    readonly property bool connected: backend?.connected ?? false
    readonly property var models: backend?.activeModels ?? []

    spacing: 0

    function formatBytes(bytes) {
        if (!bytes || bytes <= 0) return "0 B";
        if (bytes >= 1073741824) return (bytes / 1073741824).toFixed(1) + " GB";
        if (bytes >= 1048576) return (bytes / 1048576).toFixed(0) + " MB";
        if (bytes >= 1024) return (bytes / 1024).toFixed(0) + " KB";
        return bytes + " B";
    }

    Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: content.implicitHeight + Kirigami.Units.largeSpacing * 2
        radius: Kirigami.Units.cornerRadius
        color: Qt.darker(Kirigami.Theme.backgroundColor, 1.05)
        border.width: 1
        border.color: {
            if (card.backend?.error) return Qt.alpha(Kirigami.Theme.negativeTextColor, 0.3);
            if (card.connected) return Qt.alpha(card.providerColor, 0.28);
            return Qt.alpha(Kirigami.Theme.textColor, 0.1);
        }

        Accessible.role: Accessible.Grouping
        Accessible.name: {
            var status = card.backend?.error ? i18n("error")
                       : (card.connected ? i18n("connected") : i18n("disconnected"));
            return i18n("Ollama, %1", status);
        }

        // Accent stripe
        Rectangle {
            anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
            width: 3
            radius: Kirigami.Units.cornerRadius
            color: card.connected ? card.providerColor : "transparent"
            opacity: card.connected ? 0.6 : 0
        }

        clip: true

        ColumnLayout {
            id: content
            anchors { fill: parent; margins: Kirigami.Units.largeSpacing }
            spacing: Kirigami.Units.smallSpacing

            // Header
            RowLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing

                Kirigami.Icon {
                    source: card.backend?.iconName ?? "computer"
                    Layout.preferredWidth: Kirigami.Units.iconSizes.small
                    Layout.preferredHeight: Kirigami.Units.iconSizes.small
                }
                PlasmaExtras.Heading {
                    level: 4
                    text: card.backend?.name ?? i18n("Ollama")
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                }
                PlasmaComponents.Label {
                    text: card.backend?.error
                        ? "✗ " + i18n("Offline")
                        : (card.connected ? "✓ " + i18n("Online") : i18n("…"))
                    color: card.backend?.error
                        ? Kirigami.Theme.negativeTextColor
                        : (card.connected ? Kirigami.Theme.positiveTextColor : Kirigami.Theme.disabledTextColor)
                    font.pointSize: Kirigami.Theme.smallFont.pointSize
                }
            }

            // Error line
            PlasmaComponents.Label {
                visible: (card.backend?.error ?? "") !== ""
                Layout.fillWidth: true
                text: card.backend?.error ?? ""
                color: Kirigami.Theme.negativeTextColor
                font.pointSize: Kirigami.Theme.smallFont.pointSize
                wrapMode: Text.WordWrap
            }

            // Memory summary
            RowLayout {
                Layout.fillWidth: true
                visible: card.connected
                PlasmaComponents.Label {
                    text: i18n("VRAM: %1 / %2",
                               card.formatBytes(card.backend?.vramMemory ?? 0),
                               card.formatBytes(card.backend?.totalMemory ?? 0))
                    font.pointSize: Kirigami.Theme.smallFont.pointSize
                    opacity: 0.8
                }
                Item { Layout.fillWidth: true }
                PlasmaComponents.Label {
                    text: i18np("%1 model loaded", "%1 models loaded", card.models.length)
                    font.pointSize: Kirigami.Theme.smallFont.pointSize
                    opacity: 0.7
                }
            }

            // Loaded models
            Repeater {
                model: card.connected ? card.models : []
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing
                    PlasmaComponents.Label {
                        Layout.fillWidth: true
                        text: modelData.name ?? ""
                        elide: Text.ElideRight
                        font.pointSize: Kirigami.Theme.smallFont.pointSize
                    }
                    PlasmaComponents.Label {
                        text: card.formatBytes(modelData.sizeVram ?? 0)
                        font.pointSize: Kirigami.Theme.smallFont.pointSize
                        opacity: 0.7
                    }
                }
            }

            // Empty state
            PlasmaComponents.Label {
                visible: card.connected && card.models.length === 0
                Layout.fillWidth: true
                text: i18n("No models currently loaded")
                font.pointSize: Kirigami.Theme.smallFont.pointSize
                opacity: 0.6
                wrapMode: Text.WordWrap
            }
        }
    }
}
