import QtQuick

/*
 * Decides whether an alert reaches the user.
 *
 * Nearly every signal this widget reacts to is level-triggered: a provider that
 * keeps failing re-emits errorChanged on every refresh, and a rate-limit warning
 * re-fires on every poll while usage stays above the threshold. Gating those by
 * elapsed time alone turns a single problem into an endless stream of reminders.
 *
 * So this gate latches instead. An event is delivered once, then stays silent
 * until the caller reports that the condition is gone (clear/clearPrefix) or
 * until the alert's signature changes into a genuinely different message.
 * The cooldown remains only as an anti-flap floor for conditions that clear and
 * re-trigger in quick succession.
 */
QtObject {
    id: gate

    // Minimum time between two alerts for the same key, even across a clear.
    property int cooldownMinutes: 0
    // Quiet hours, as [start, end) in local hours. Negative disables.
    property int dndStartHour: -1
    property int dndEndHour: -1

    // Injectable clock (milliseconds since epoch) so tests stay deterministic.
    property var clock: function() { return Date.now(); }

    // Event key -> signature of the alert already delivered for this occurrence.
    property var activeEvents: ({})
    // Event key -> timestamp of the last delivered alert.
    property var lastFiredAt: ({})

    function isQuietHour(timestamp) {
        if (gate.dndStartHour < 0 || gate.dndEndHour < 0) return false;
        var hour = new Date(timestamp).getHours();
        if (gate.dndStartHour < gate.dndEndHour) {
            return hour >= gate.dndStartHour && hour < gate.dndEndHour;
        }
        // Overnight window, e.g. 22:00 - 07:00.
        return hour >= gate.dndStartHour || hour < gate.dndEndHour;
    }

    /*
     * Returns true at most once per occurrence of a condition.
     *
     * signature distinguishes a genuinely new alert for the same key (a
     * different error message, say) from a repeat of the one already sent.
     * Omit it for conditions that are simply on or off.
     */
    function canNotify(eventKey, signature) {
        var sig = (signature === undefined || signature === null) ? "on" : String(signature);
        if (gate.activeEvents[eventKey] === sig) return false;

        var now = gate.clock();
        // Returning without latching means a condition that starts during quiet
        // hours is still announced once, as soon as they end.
        if (gate.isQuietHour(now)) return false;

        if (now - (gate.lastFiredAt[eventKey] || 0) < gate.cooldownMinutes * 60 * 1000) return false;

        gate.activeEvents[eventKey] = sig;
        gate.lastFiredAt[eventKey] = now;
        return true;
    }

    // Re-arms one event so its next occurrence is announced again.
    function clear(eventKey) {
        delete gate.activeEvents[eventKey];
    }

    // Re-arms every event whose key starts with prefix.
    function clearPrefix(prefix) {
        var keys = Object.keys(gate.activeEvents);
        for (var i = 0; i < keys.length; i++) {
            if (keys[i].indexOf(prefix) === 0) delete gate.activeEvents[keys[i]];
        }
    }

    /*
     * Pure time-based throttle for bookkeeping that must keep sampling while a
     * condition persists, such as writing rate-limit history. Returns true while
     * the previous stamp is still fresh, and stamps the key otherwise.
     */
    function withinCooldown(key) {
        var now = gate.clock();
        if (now - (gate.lastFiredAt[key] || 0) < gate.cooldownMinutes * 60 * 1000) return true;
        gate.lastFiredAt[key] = now;
        return false;
    }
}
