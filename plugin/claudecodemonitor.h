#ifndef CLAUDECODEMONITOR_H
#define CLAUDECODEMONITOR_H

#include "subscriptiontoolbackend.h"
#include <QFileSystemWatcher>
#include <QDir>

/**
 * Monitor for Claude Code CLI usage.
 *
 * Claude Code (Anthropic) uses rolling time windows:
 * - Primary: 5-hour session window
 * - Secondary: Weekly rolling window (separate Opus/non-Opus limits)
 *
 * v2.3: Added browser-sync support via Claude.ai internal APIs.
 * When enabled, extracts session cookies from Firefox to call:
 * - GET /api/account → get organization UUID
 * - GET /api/organizations/{uuid}/usage → session %, weekly limits
 * - GET /api/organizations/{uuid}/settings/billing → extra usage spend
 *
 * Plans and approximate limits (messages vary by complexity):
 * - Pro ($20/mo):    ~45 messages/5h session, ~225/week
 * - Max 5x ($100/mo): ~225 messages/5h session, ~1125/week
 * - Ultra ($200/mo, formerly Max 20x): no 5h cap for verified accounts, weekly limit only
 */
class ClaudeCodeMonitor : public SubscriptionToolBackend
{
    Q_OBJECT

public:
    explicit ClaudeCodeMonitor(QObject *parent = nullptr);

    // Identity
    QString toolName() const override { return QStringLiteral("Claude Code"); }
    QString iconName() const override { return QStringLiteral("utilities-terminal"); }
    QString toolColor() const override { return QStringLiteral("#D4A574"); }

    // Period labels
    QString periodLabel() const override { return QStringLiteral("5-hour session"); }
    QString secondaryPeriodLabel() const override { return QStringLiteral("Weekly"); }
    bool hasSecondaryLimit() const override { return true; }

    // Subscription cost
    bool hasSubscriptionCost() const override { return true; }
    double subscriptionCost() const override;

    // Plan management
    Q_INVOKABLE QStringList availablePlans() const override;
    Q_INVOKABLE int defaultLimitForPlan(const QString &plan) const override;
    Q_INVOKABLE int defaultSecondaryLimitForPlan(const QString &plan) const override;
    Q_INVOKABLE double defaultCostForPlan(const QString &plan) const override;

    // Tool detection
    Q_INVOKABLE void checkToolInstalled() override;
    Q_INVOKABLE void detectActivity() override;

    // Browser sync
    Q_INVOKABLE void syncFromBrowser(const QString &cookieHeader, int browserType) override;

protected:
    UsagePeriod primaryPeriodType() const override { return FiveHour; }
    UsagePeriod secondaryPeriodType() const override { return Weekly; }

private Q_SLOTS:
    void onDirectoryChanged(const QString &path);
    void onFileChanged(const QString &path);

private:
    void setupWatcher();
    QString claudeConfigDir() const;
    void fetchAccountInfo(const QString &cookieHeader);
    void fetchUsageData(const QString &orgUuid, const QString &cookieHeader);

    QFileSystemWatcher *m_watcher;
    QDateTime m_lastKnownModification;
    QString m_orgUuid;

    // Debounce timer to avoid counting rapid filesystem events as separate messages
    QTimer *m_debounceTimer;
    bool m_pendingIncrement = false;
};

#endif // CLAUDECODEMONITOR_H
