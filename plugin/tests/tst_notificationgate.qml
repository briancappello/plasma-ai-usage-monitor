import QtQuick
import QtTest

/*
 * Regression cover for the alert-spam bug: a persistent condition used to be
 * re-announced every notificationCooldownMinutes, forever. The gate must latch
 * each event and only re-arm it once the condition clears.
 */
Item {
    id: root

    property real fakeNow: 0

    TestCase {
        id: testCase
        name: "NotificationGate"
        when: windowShown

        function makeGate(cooldownMinutes) {
            var component = Qt.createComponent("../../package/contents/ui/NotificationGate.qml");
            compare(component.status, Component.Ready, component.errorString());
            var gate = component.createObject(root, {
                cooldownMinutes: cooldownMinutes === undefined ? 15 : cooldownMinutes
            });
            verify(gate !== null);
            gate.clock = function() { return root.fakeNow; };
            return gate;
        }

        function advanceMinutes(minutes) {
            root.fakeNow += minutes * 60 * 1000;
        }

        function init() {
            root.fakeNow = 12 * 60 * 60 * 1000; // Midday, outside any quiet hours.
        }

        // The actual bug: OpenAI keeps reporting the same failure on every poll.
        function test_persistentConditionAlertsOnlyOnce() {
            var gate = makeGate(15);
            verify(gate.canNotify("error_OpenAI", "session expired"));

            for (var i = 0; i < 20; i++) {
                advanceMinutes(60);
                verify(!gate.canNotify("error_OpenAI", "session expired"),
                    "repeat alert leaked after " + (i + 1) + " hours");
            }
            gate.destroy();
        }

        // Recovering and failing again is a new occurrence, not a reminder.
        function test_clearReArmsTheEvent() {
            var gate = makeGate(15);
            verify(gate.canNotify("error_OpenAI", "session expired"));
            gate.clear("error_OpenAI");
            advanceMinutes(30);
            verify(gate.canNotify("error_OpenAI", "session expired"));
            gate.destroy();
        }

        // The cooldown still caps a flapping condition.
        function test_cooldownLimitsFlapping() {
            var gate = makeGate(15);
            verify(gate.canNotify("error_OpenAI", "down"));
            gate.clear("error_OpenAI");
            advanceMinutes(5);
            verify(!gate.canNotify("error_OpenAI", "down"));
            advanceMinutes(11);
            verify(gate.canNotify("error_OpenAI", "down"));
            gate.destroy();
        }

        // A different failure must still get through.
        function test_newSignatureAlerts() {
            var gate = makeGate(0);
            verify(gate.canNotify("error_OpenAI", "session expired"));
            verify(!gate.canNotify("error_OpenAI", "session expired"));
            verify(gate.canNotify("error_OpenAI", "quota exhausted"));
            gate.destroy();
        }

        function test_clearPrefixReArmsMatchingEventsOnly() {
            var gate = makeGate(0);
            verify(gate.canNotify("tool_sync_Codex CLI_session_expired"));
            verify(gate.canNotify("tool_sync_Codex CLI_network_error"));
            verify(gate.canNotify("tool_sync_Claude Code_session_expired"));

            gate.clearPrefix("tool_sync_Codex CLI_");
            verify(gate.canNotify("tool_sync_Codex CLI_session_expired"));
            verify(gate.canNotify("tool_sync_Codex CLI_network_error"));
            verify(!gate.canNotify("tool_sync_Claude Code_session_expired"));
            gate.destroy();
        }

        // Quiet hours must defer the alert, never swallow it.
        function test_quietHoursDeferRatherThanDrop() {
            var gate = makeGate(0);
            gate.dndStartHour = 22;
            gate.dndEndHour = 7;

            root.fakeNow = new Date(2026, 0, 1, 23, 0, 0).getTime();
            verify(!gate.canNotify("error_OpenAI", "down"));

            root.fakeNow = new Date(2026, 0, 2, 9, 0, 0).getTime();
            verify(gate.canNotify("error_OpenAI", "down"));
            gate.destroy();
        }

        // History sampling stays time-based so the record keeps its cadence.
        function test_withinCooldownKeepsSampling() {
            var gate = makeGate(15);
            verify(!gate.withinCooldown("quotarecord_OpenAI"));
            advanceMinutes(5);
            verify(gate.withinCooldown("quotarecord_OpenAI"));
            advanceMinutes(11);
            verify(!gate.withinCooldown("quotarecord_OpenAI"));
            gate.destroy();
        }
    }
}
