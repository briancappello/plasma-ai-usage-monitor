import QtQuick
import QtTest

Item {
    id: root
    width: 640
    height: 900
    function i18n(text) { return text; }
    function i18np(singular, plural, count) { return count === 1 ? singular : plural; }

    QtObject {
        id: plasmoid
        property var metaData: ({ version: "test" })
        property var configuration: ({
            chartToolIndex: 0, chartQuotaWindow: "weekly", compactDisplayMode: "chart", refreshInterval: 300,
            openaiRefreshInterval: 0, anthropicRefreshInterval: 0, googleRefreshInterval: 0,
            mistralRefreshInterval: 0, deepseekRefreshInterval: 0, groqRefreshInterval: 0,
            xaiRefreshInterval: 0, googleveoRefreshInterval: 0, loofiRefreshInterval: 0
        })
    }

    TestCase {
        name: "GeneralSettingsApplyWorkflow"
        when: windowShown
        function test_chartSelectionIsStaged() {
            var component = Qt.createComponent("../../package/contents/ui/configGeneral.qml");
            compare(component.status, Component.Ready, component.errorString());
            var page = component.createObject(root);
            verify(page !== null);
            compare(page.cfg_chartToolIndex, 0);
            page.cfg_chartToolIndex = 2;
            compare(plasmoid.configuration.chartToolIndex, 0);
            page.destroy(); // Cancel: discard the page's pending values.
            wait(0);

            page = component.createObject(root);
            compare(page.cfg_chartToolIndex, 0);
            page.cfg_chartToolIndex = 1;
            compare(page.cfg_chartQuotaWindow, "weekly");
            page.cfg_chartQuotaWindow = "session";
            // Plasma's Apply/OK handler copies cfg_* values into configuration.
            Object.keys(plasmoid.configuration).forEach(key => {
                const cfgKey = "cfg_" + key;
                if (cfgKey in page) plasmoid.configuration[key] = page[cfgKey];
            });
            compare(plasmoid.configuration.chartToolIndex, 1);
            compare(plasmoid.configuration.chartQuotaWindow, "session");
            page.destroy();
            wait(0);
            page = component.createObject(root);
            compare(page.cfg_chartToolIndex, 1);
            compare(page.cfg_chartQuotaWindow, "session");
            page.destroy();
        }
    }
}
