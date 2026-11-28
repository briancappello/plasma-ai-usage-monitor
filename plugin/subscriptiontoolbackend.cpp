#include "subscriptiontoolbackend.h"
#include <QDate>
#include <QDebug>
#include <QJsonArray>
#include <QTimeZone>
#include "resilientnetworkaccessmanager.h"

#include <algorithm>
#include <cmath>

namespace {
// Pace model: nearly all usage happens 06:00–22:00 Mountain time, every day.
constexpr int kActiveStartHour = 6;
constexpr int kActiveEndHour = 22;
// Floor on elapsed active time, so a few percent in the first minutes of a
// window doesn't extrapolate to an alarming rate.
constexpr qint64 kMinActiveElapsedSecs = 4 * 3600;
constexpr double kPaceWarningPercent = 85.0;
constexpr double kPaceCriticalPercent = 100.0;

const QTimeZone &paceTimeZone()
{
    static const QTimeZone tz = [] {
        const QTimeZone mountain(QByteArrayLiteral("America/Denver"));
        return mountain.isValid() ? mountain : QTimeZone::systemTimeZone();
    }();
    return tz;
}

QString formatDuration(qint64 secs)
{
    if (secs <= 0) return QStringLiteral("now");

    const qint64 hours = secs / 3600;
    const qint64 mins = (secs % 3600) / 60;

    if (hours > 24) {
        return QStringLiteral("%1d %2h").arg(hours / 24).arg(hours % 24);
    }
    if (hours > 0) {
        return QStringLiteral("%1h %2m").arg(hours).arg(mins);
    }
    return QStringLiteral("%1m").arg(mins);
}

// The wall-clock instant reached after `activeSecs` of active time from `from`.
QDateTime addActiveSeconds(const QDateTime &from, qint64 activeSecs)
{
    const QTimeZone &tz = paceTimeZone();
    qint64 remaining = activeSecs;
    QDate day = from.toTimeZone(tz).date();
    // A week window never needs more than a few days; the bound guards the loop.
    for (int i = 0; i < 366; ++i, day = day.addDays(1)) {
        const QDateTime activeStart = std::max(from, QDateTime(day, QTime(kActiveStartHour, 0), tz));
        const QDateTime activeEnd = QDateTime(day, QTime(kActiveEndHour, 0), tz);
        if (activeStart >= activeEnd) continue;
        const qint64 available = activeStart.secsTo(activeEnd);
        if (remaining <= available) return activeStart.addSecs(remaining);
        remaining -= available;
    }
    return QDateTime();
}
} // namespace

SubscriptionToolBackend::SubscriptionToolBackend(QObject *parent)
    : QObject(parent)
    , m_resetCheckTimer(new QTimer(this))
{
    // Check for period resets every 60 seconds
    m_resetCheckTimer->setInterval(60 * 1000);
    connect(m_resetCheckTimer, &QTimer::timeout, this, &SubscriptionToolBackend::checkAndResetPeriod);
    connect(m_resetCheckTimer, &QTimer::timeout, this, &SubscriptionToolBackend::paceUpdated);
    connect(this, &SubscriptionToolBackend::usageUpdated, this, &SubscriptionToolBackend::paceUpdated);
}

SubscriptionToolBackend::~SubscriptionToolBackend() = default;

// --- State ---

bool SubscriptionToolBackend::isEnabled() const { return m_enabled; }
void SubscriptionToolBackend::setEnabled(bool enabled)
{
    if (m_enabled != enabled) {
        m_enabled = enabled;
        if (enabled) {
            checkToolInstalled();
            if (m_periodStart.isNull()) {
                m_periodStart = QDateTime::currentDateTimeUtc();
                m_secondaryPeriodStart = QDateTime::currentDateTimeUtc();
            }
            m_resetCheckTimer->start();
        } else {
            m_resetCheckTimer->stop();
        }
        Q_EMIT enabledChanged();
    }
}

bool SubscriptionToolBackend::isInstalled() const { return m_installed; }
void SubscriptionToolBackend::setInstalled(bool installed)
{
    if (m_installed != installed) {
        m_installed = installed;
        Q_EMIT installedChanged();
    }
}

QString SubscriptionToolBackend::planTier() const { return m_planTier; }
void SubscriptionToolBackend::setPlanTier(const QString &tier)
{
    if (m_planTier != tier) {
        m_planTier = tier;
        Q_EMIT planTierChanged();
    }
}

// --- Usage ---

int SubscriptionToolBackend::usageCount() const { return m_usageCount; }
void SubscriptionToolBackend::setUsageCount(int count)
{
    m_usageCount = count;
}

int SubscriptionToolBackend::usageLimit() const { return m_usageLimit; }
void SubscriptionToolBackend::setUsageLimit(int limit)
{
    if (m_usageLimit != limit) {
        m_usageLimit = limit;
        Q_EMIT usageLimitChanged();
    }
}

double SubscriptionToolBackend::percentUsed() const
{
    if (m_usageLimit <= 0) return 0.0;
    return (static_cast<double>(m_usageCount) / m_usageLimit) * 100.0;
}

bool SubscriptionToolBackend::isLimitReached() const
{
    return m_usageLimit > 0 && m_usageCount >= m_usageLimit;
}

// --- Secondary Window ---

int SubscriptionToolBackend::secondaryUsageCount() const { return m_secondaryUsageCount; }
void SubscriptionToolBackend::setSecondaryUsageCount(int count)
{
    m_secondaryUsageCount = count;
}

int SubscriptionToolBackend::secondaryUsageLimit() const { return m_secondaryUsageLimit; }
void SubscriptionToolBackend::setSecondaryUsageLimit(int limit)
{
    if (m_secondaryUsageLimit != limit) {
        m_secondaryUsageLimit = limit;
        Q_EMIT usageLimitChanged();
    }
}

double SubscriptionToolBackend::secondaryPercentUsed() const
{
    if (m_secondaryUsageLimit <= 0) return 0.0;
    return (static_cast<double>(m_secondaryUsageCount) / m_secondaryUsageLimit) * 100.0;
}

bool SubscriptionToolBackend::isSecondaryLimitReached() const
{
    return m_secondaryUsageLimit > 0 && m_secondaryUsageCount >= m_secondaryUsageLimit;
}

QString SubscriptionToolBackend::secondaryPeriodLabel() const { return QString(); }
bool SubscriptionToolBackend::hasSecondaryLimit() const { return false; }
SubscriptionToolBackend::UsagePeriod SubscriptionToolBackend::secondaryPeriodType() const { return Weekly; }
int SubscriptionToolBackend::defaultSecondaryLimitForPlan(const QString &) const { return 0; }

// --- Time ---

QDateTime SubscriptionToolBackend::periodStart() const { return m_periodStart; }
void SubscriptionToolBackend::setPeriodStart(const QDateTime &start) { m_periodStart = start; }
void SubscriptionToolBackend::setSecondaryPeriodStart(const QDateTime &start) { m_secondaryPeriodStart = start; }

QDateTime SubscriptionToolBackend::periodEnd() const
{
    return calculatePeriodEnd(primaryPeriodType(), m_periodStart);
}

int SubscriptionToolBackend::secondsUntilReset() const
{
    QDateTime end = periodEnd();
    if (!end.isValid()) return 0;
    qint64 secs = QDateTime::currentDateTimeUtc().secsTo(end);
    return secs > 0 ? static_cast<int>(secs) : 0;
}

QString SubscriptionToolBackend::timeUntilReset() const
{
    return formatDuration(secondsUntilReset());
}

QDateTime SubscriptionToolBackend::lastActivity() const { return m_lastActivity; }
void SubscriptionToolBackend::setLastActivity(const QDateTime &time) { m_lastActivity = time; }

// --- Actions ---

void SubscriptionToolBackend::incrementUsage()
{
    checkAndResetPeriod();

    m_usageCount++;
    m_secondaryUsageCount++;
    m_lastActivity = QDateTime::currentDateTimeUtc();

    checkLimitWarnings();
    Q_EMIT usageUpdated();
    Q_EMIT activityDetected(toolName());
}

void SubscriptionToolBackend::recordActivity()
{
    m_lastActivity = QDateTime::currentDateTimeUtc();
    Q_EMIT usageUpdated();
    Q_EMIT activityDetected(toolName());
}

void SubscriptionToolBackend::resetUsage()
{
    m_usageCount = 0;
    m_periodStart = QDateTime::currentDateTimeUtc();
    Q_EMIT usageUpdated();
}

// --- Period Management ---

QDateTime SubscriptionToolBackend::calculatePeriodEnd(UsagePeriod period, const QDateTime &start) const
{
    if (!start.isValid()) return QDateTime();

    switch (period) {
    case FiveHour:
        return start.addSecs(5 * 3600);
    case Daily:
        return start.addDays(1);
    case Weekly:
        return start.addDays(7);
    case Monthly: {
        // Reset on 1st of next month at 00:00 UTC
        QDate d = start.date();
        QDate firstOfNext = d.addMonths(1);
        firstOfNext = QDate(firstOfNext.year(), firstOfNext.month(), 1);
        return QDateTime(firstOfNext, QTime(0, 0), QTimeZone::utc());
    }
    }
    return QDateTime();
}

void SubscriptionToolBackend::checkAndResetPeriod()
{
    QDateTime now = QDateTime::currentDateTimeUtc();

    // Check primary period
    QDateTime end = calculatePeriodEnd(primaryPeriodType(), m_periodStart);
    if (end.isValid() && now >= end) {
        m_usageCount = 0;
        m_periodStart = now;
        Q_EMIT usageUpdated();
    }

    // Check secondary period
    if (hasSecondaryLimit()) {
        QDateTime secEnd = calculatePeriodEnd(secondaryPeriodType(), m_secondaryPeriodStart);
        if (secEnd.isValid() && now >= secEnd) {
            m_secondaryUsageCount = 0;
            m_secondaryPeriodStart = now;
            Q_EMIT usageUpdated();
        }
    }
}

// --- Warning Checks ---

void SubscriptionToolBackend::checkLimitWarnings()
{
    if (m_usageLimit <= 0) return;

    double pct = percentUsed();

    if (m_usageCount >= m_usageLimit) {
        Q_EMIT limitReached(toolName());
    } else if (pct >= 80.0) {
        Q_EMIT limitWarning(toolName(), static_cast<int>(pct));
    }

    // Check secondary limit too
    if (hasSecondaryLimit() && m_secondaryUsageLimit > 0) {
        if (m_secondaryUsageCount >= m_secondaryUsageLimit) {
            Q_EMIT limitReached(toolName());
        }
    }
}

// --- Secondary Time ---

QDateTime SubscriptionToolBackend::secondaryPeriodEnd() const
{
    if (!hasSecondaryLimit()) return QDateTime();
    return calculatePeriodEnd(secondaryPeriodType(), m_secondaryPeriodStart);
}

int SubscriptionToolBackend::secondarySecondsUntilReset() const
{
    QDateTime end = secondaryPeriodEnd();
    if (!end.isValid()) return 0;
    qint64 secs = QDateTime::currentDateTimeUtc().secsTo(end);
    return secs > 0 ? static_cast<int>(secs) : 0;
}

QString SubscriptionToolBackend::secondaryTimeUntilReset() const
{
    return formatDuration(secondarySecondsUntilReset());
}

// --- Pace ---

qint64 SubscriptionToolBackend::activeSecondsBetween(const QDateTime &from, const QDateTime &to)
{
    if (!from.isValid() || !to.isValid() || to <= from) return 0;

    const QTimeZone &tz = paceTimeZone();
    const QDate lastDay = to.toTimeZone(tz).date();
    qint64 total = 0;
    for (QDate day = from.toTimeZone(tz).date(); day <= lastDay; day = day.addDays(1)) {
        const QDateTime activeStart = std::max(from, QDateTime(day, QTime(kActiveStartHour, 0), tz));
        const QDateTime activeEnd = std::min(to, QDateTime(day, QTime(kActiveEndHour, 0), tz));
        if (activeStart < activeEnd) total += activeStart.secsTo(activeEnd);
    }
    return total;
}

double SubscriptionToolBackend::projectedPercentAtReset(double usedPercent, const QDateTime &windowStart,
                                                        const QDateTime &windowEnd, const QDateTime &now)
{
    if (usedPercent <= 0.0) return 0.0;
    const qint64 total = activeSecondsBetween(windowStart, windowEnd);
    if (total <= 0) return usedPercent;
    const qint64 elapsed = std::max(activeSecondsBetween(windowStart, std::min(now, windowEnd)),
                                    std::min(kMinActiveElapsedSecs, total));
    return usedPercent * static_cast<double>(total) / static_cast<double>(elapsed);
}

qint64 SubscriptionToolBackend::secondsUntilExhausted(double usedPercent, const QDateTime &windowStart,
                                                      const QDateTime &windowEnd, const QDateTime &now)
{
    if (usedPercent >= 100.0) return 0;
    if (usedPercent <= 0.0 || now >= windowEnd) return -1;
    const qint64 total = activeSecondsBetween(windowStart, windowEnd);
    if (total <= 0) return -1;
    const qint64 elapsed = std::max(activeSecondsBetween(windowStart, now),
                                    std::min(kMinActiveElapsedSecs, total));
    // Active seconds left at the current burn rate before usage reaches 100%.
    const double needed = (100.0 - usedPercent) * static_cast<double>(elapsed) / usedPercent;
    if (needed >= static_cast<double>(activeSecondsBetween(now, windowEnd))) return -1;
    const QDateTime runsOut = addActiveSeconds(now, static_cast<qint64>(std::ceil(needed)));
    if (!runsOut.isValid() || runsOut >= windowEnd) return -1;
    return now.secsTo(runsOut);
}

QString SubscriptionToolBackend::timeUntilExhaustedText(qint64 secs)
{
    return secs < 0 ? QString() : formatDuration(secs);
}

SubscriptionToolBackend::PaceLevel SubscriptionToolBackend::paceLevelFor(double projectedPercent)
{
    if (projectedPercent >= kPaceCriticalPercent) return PaceCritical;
    if (projectedPercent >= kPaceWarningPercent) return PaceWarning;
    return PaceOk;
}

double SubscriptionToolBackend::projectedPercent() const
{
    if (primaryPeriodType() != Weekly || m_usageLimit <= 0) return percentUsed();
    return projectedPercentAtReset(percentUsed(), m_periodStart, periodEnd(), QDateTime::currentDateTimeUtc());
}

int SubscriptionToolBackend::paceLevel() const
{
    if (primaryPeriodType() != Weekly) return PaceNone;
    return paceLevelFor(projectedPercent());
}

double SubscriptionToolBackend::secondaryProjectedPercent() const
{
    if (!hasSecondaryLimit() || m_secondaryUsageLimit <= 0) return 0.0;
    if (secondaryPeriodType() != Weekly) return secondaryPercentUsed();
    return projectedPercentAtReset(secondaryPercentUsed(), m_secondaryPeriodStart, secondaryPeriodEnd(),
                                   QDateTime::currentDateTimeUtc());
}

int SubscriptionToolBackend::secondaryPaceLevel() const
{
    if (!hasSecondaryLimit() || secondaryPeriodType() != Weekly) return PaceNone;
    return paceLevelFor(secondaryProjectedPercent());
}

int SubscriptionToolBackend::secondsUntilExhausted() const
{
    if (primaryPeriodType() != Weekly || m_usageLimit <= 0) return -1;
    return static_cast<int>(secondsUntilExhausted(percentUsed(), m_periodStart, periodEnd(),
                                                  QDateTime::currentDateTimeUtc()));
}

int SubscriptionToolBackend::secondarySecondsUntilExhausted() const
{
    if (!hasSecondaryLimit() || m_secondaryUsageLimit <= 0 || secondaryPeriodType() != Weekly) return -1;
    return static_cast<int>(secondsUntilExhausted(secondaryPercentUsed(), m_secondaryPeriodStart,
                                                  secondaryPeriodEnd(), QDateTime::currentDateTimeUtc()));
}

QString SubscriptionToolBackend::timeUntilExhausted() const
{
    return timeUntilExhaustedText(secondsUntilExhausted());
}

QString SubscriptionToolBackend::secondaryTimeUntilExhausted() const
{
    return timeUntilExhaustedText(secondarySecondsUntilExhausted());
}

// --- Claude.ai usage ---

bool SubscriptionToolBackend::applyClaudeUsage(const QJsonObject &root)
{
    // Claude's usage API is percentage-based: the weekly quota is reported as
    // 0–100 utilization, with no message counts. The count-based UI is
    // normalised to that percent scale (limit == 100, count == %).
    //
    // The `limits` array drives claude.ai's own UI (kinds: weekly_all /
    // weekly_scoped). Prefer it, and fall back to the flat seven_day object.
    // Subscriptions no longer have a 5-hour session window, so any `session`
    // or `five_hour` data is ignored.
    double weeklyPct = -1.0;
    QString weeklyResetsAt;
    QVariantList scoped;
    const QJsonArray limits = root.value(QStringLiteral("limits")).toArray();
    for (const QJsonValue &v : limits) {
        const QJsonObject l = v.toObject();
        const QString kind = l.value(QStringLiteral("kind")).toString();
        const double pct = l.value(QStringLiteral("percent")).toDouble(0.0);
        if (kind == QStringLiteral("weekly_all")) {
            weeklyPct = pct;
            weeklyResetsAt = l.value(QStringLiteral("resets_at")).toString();
        } else if (kind == QStringLiteral("weekly_scoped")) {
            const QString modelName = l.value(QStringLiteral("scope")).toObject()
                                       .value(QStringLiteral("model")).toObject()
                                       .value(QStringLiteral("display_name")).toString();
            if (!modelName.isEmpty()) {
                scoped.append(QVariantMap{
                    {QStringLiteral("name"), modelName},
                    {QStringLiteral("percent"), static_cast<int>(qRound(pct))},
                    {QStringLiteral("resetsAt"), l.value(QStringLiteral("resets_at")).toString()},
                });
            }
        }
    }

    const QJsonObject sevenDay = root.value(QStringLiteral("seven_day")).toObject();
    if (weeklyPct < 0.0 && !sevenDay.isEmpty()) {
        weeklyPct = sevenDay.value(QStringLiteral("utilization")).toDouble(0.0);
    }
    if (weeklyPct < 0.0 && scoped.isEmpty()) {
        return false;
    }

    setScopedLimits(scoped);

    if (weeklyPct >= 0.0) {
        setUsageCount(static_cast<int>(qRound(weeklyPct)));

        // Anchor the weekly reset to the API value. periodEnd is computed as
        // periodStart + 7 days, so back it out from the real reset time.
        const QString sevenDayResetsAt = sevenDay.value(QStringLiteral("resets_at")).toString();
        if (!sevenDayResetsAt.isEmpty()) {
            weeklyResetsAt = sevenDayResetsAt;
        }
        const QDateTime weeklyReset = QDateTime::fromString(weeklyResetsAt, Qt::ISODate);
        if (weeklyReset.isValid()) {
            setPeriodStart(weeklyReset.addDays(-7));
        }
    }

    // extra_usage (metered credit spending). Real fields:
    //   is_enabled, monthly_limit, used_credits (currency units, not cents).
    const QJsonValue extraVal = root.value(QStringLiteral("extra_usage"));
    if (extraVal.isObject()) {
        const QJsonObject extra = extraVal.toObject();
        const bool enabled = extra.value(QStringLiteral("is_enabled")).toBool(false);
        setHasExtraUsage(enabled);
        if (enabled) {
            setExtraUsageSpent(extra.value(QStringLiteral("used_credits")).toDouble(0.0));
            setExtraUsageLimit(extra.value(QStringLiteral("monthly_limit")).toDouble(0.0));
            const QString resetsAt = extra.value(QStringLiteral("resets_at")).toString();
            if (!resetsAt.isEmpty()) {
                setExtraUsageResetDate(QDateTime::fromString(resetsAt, Qt::ISODate));
            }
        }
    }
    return true;
}

// --- Extra / Metered Usage ---

bool SubscriptionToolBackend::hasExtraUsage() const { return m_hasExtraUsage; }
double SubscriptionToolBackend::extraUsageSpent() const { return m_extraUsageSpent; }
double SubscriptionToolBackend::extraUsageLimit() const { return m_extraUsageLimit; }
double SubscriptionToolBackend::extraUsagePercent() const
{
    if (m_extraUsageLimit <= 0.0) return 0.0;
    return (m_extraUsageSpent / m_extraUsageLimit) * 100.0;
}
QDateTime SubscriptionToolBackend::extraUsageResetDate() const { return m_extraUsageResetDate; }
QString SubscriptionToolBackend::currencySymbol() const { return m_currencySymbol; }

void SubscriptionToolBackend::setExtraUsageSpent(double spent) { m_extraUsageSpent = spent; }
void SubscriptionToolBackend::setExtraUsageLimit(double limit) { m_extraUsageLimit = limit; }
void SubscriptionToolBackend::setExtraUsageResetDate(const QDateTime &date) { m_extraUsageResetDate = date; }
void SubscriptionToolBackend::setCurrencySymbol(const QString &symbol) { m_currencySymbol = symbol; }
void SubscriptionToolBackend::setHasExtraUsage(bool has) { m_hasExtraUsage = has; }

// --- Subscription Cost ---

double SubscriptionToolBackend::subscriptionCost() const { return m_subscriptionCost; }
bool SubscriptionToolBackend::hasSubscriptionCost() const { return false; }
void SubscriptionToolBackend::setSubscriptionCostValue(double cost) { m_subscriptionCost = cost; }
double SubscriptionToolBackend::defaultCostForPlan(const QString &) const { return 0.0; }

// --- Tertiary Usage ---

bool SubscriptionToolBackend::hasTertiaryLimit() const { return false; }
QString SubscriptionToolBackend::tertiaryPeriodLabel() const { return QString(); }
double SubscriptionToolBackend::tertiaryPercentRemaining() const { return m_tertiaryPercentRemaining; }
QDateTime SubscriptionToolBackend::tertiaryResetDate() const { return m_tertiaryResetDate; }
void SubscriptionToolBackend::setTertiaryPercentRemaining(double pct) { m_tertiaryPercentRemaining = pct; }
void SubscriptionToolBackend::setTertiaryResetDate(const QDateTime &date) { m_tertiaryResetDate = date; }

// --- Credits ---

bool SubscriptionToolBackend::hasCredits() const { return false; }
int SubscriptionToolBackend::remainingCredits() const { return m_remainingCredits; }
void SubscriptionToolBackend::setRemainingCredits(int credits) { m_remainingCredits = credits; }

QVariantList SubscriptionToolBackend::scopedLimits() const
{
    // Scoped limits are weekly windows ending at resetsAt.
    const QDateTime now = QDateTime::currentDateTimeUtc();
    QVariantList withPace;
    withPace.reserve(m_scopedLimits.size());
    for (const QVariant &entry : m_scopedLimits) {
        QVariantMap limit = entry.toMap();
        const double percent = limit.value(QStringLiteral("percent")).toDouble();
        const QDateTime resetsAt = QDateTime::fromString(limit.value(QStringLiteral("resetsAt")).toString(), Qt::ISODate);
        const double projected = resetsAt.isValid()
            ? projectedPercentAtReset(percent, resetsAt.addDays(-7), resetsAt, now)
            : percent;
        const qint64 exhausted = resetsAt.isValid()
            ? secondsUntilExhausted(percent, resetsAt.addDays(-7), resetsAt, now)
            : -1;
        limit.insert(QStringLiteral("projectedPercent"), projected);
        limit.insert(QStringLiteral("timeUntilExhausted"), timeUntilExhaustedText(exhausted));
        limit.insert(QStringLiteral("paceLevel"), static_cast<int>(paceLevelFor(projected)));
        withPace.append(limit);
    }
    return withPace;
}
void SubscriptionToolBackend::setScopedLimits(const QVariantList &limits) { m_scopedLimits = limits; }

// --- Browser Sync ---

bool SubscriptionToolBackend::isSyncEnabled() const { return m_syncEnabled; }
void SubscriptionToolBackend::setSyncEnabled(bool enabled)
{
    if (m_syncEnabled != enabled) {
        m_syncEnabled = enabled;
        Q_EMIT syncEnabledChanged();
    }
}

QString SubscriptionToolBackend::syncStatus() const { return m_syncStatus; }
QDateTime SubscriptionToolBackend::lastSyncTime() const { return m_lastSyncTime; }
bool SubscriptionToolBackend::isSyncing() const { return m_syncing; }

void SubscriptionToolBackend::setSyncing(bool syncing)
{
    if (m_syncing != syncing) {
        m_syncing = syncing;
        Q_EMIT syncStatusChanged();
    }
}

void SubscriptionToolBackend::setSyncStatus(const QString &status)
{
    if (m_syncStatus != status) {
        m_syncStatus = status;
        Q_EMIT syncStatusChanged();
    }
}

void SubscriptionToolBackend::setLastSyncTime(const QDateTime &time)
{
    m_lastSyncTime = time;
    Q_EMIT syncStatusChanged();
}

void SubscriptionToolBackend::syncFromBrowser(const QString &cookieHeader, int browserType)
{
    Q_UNUSED(cookieHeader);
    Q_UNUSED(browserType);
    // Default implementation — subclasses override for actual sync
    setSyncStatus(QStringLiteral("Not supported"));
    const QString message = QStringLiteral("Sync not implemented for this tool");
    Q_EMIT syncDiagnostic(toolName(), QStringLiteral("not_supported"), message);
    Q_EMIT syncCompleted(false, message);
}

QNetworkAccessManager *SubscriptionToolBackend::networkManager()
{
    if (m_networkManager == nullptr) {
        m_networkManager = new ResilientNetworkAccessManager(this);
    }
    return m_networkManager;
}
