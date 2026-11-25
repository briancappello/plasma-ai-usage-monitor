#ifndef CLAUDECODEMONITOR_H
#define CLAUDECODEMONITOR_H

#include "subscriptiontoolbackend.h"
#include <QFileSystemWatcher>
#include <QDir>

/**
 * Monitor for Claude Code CLI usage.
 *
 * Claude subscriptions have a single weekly rolling quota (all models), plus
 * optional per-model weekly quotas (e.g. "Fable") exposed as scopedLimits.
 * There is no 5-hour session window.
 *
 * Browser sync extracts session cookies from Firefox to call Claude.ai's
 * internal APIs:
 * - GET /api/bootstrap → organization UUID and plan
 * - GET /api/organizations/{uuid}/usage → weekly %, per-model weekly %, extra usage
 *
 * Plans: Pro ($20/mo), Max 5x ($100/mo), Ultra ($200/mo, formerly Max 20x).
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
    QString periodLabel() const override { return QStringLiteral("Weekly"); }

    // Subscription cost
    bool hasSubscriptionCost() const override { return true; }
    double subscriptionCost() const override;

    // Plan management
    Q_INVOKABLE QStringList availablePlans() const override;
    Q_INVOKABLE int defaultLimitForPlan(const QString &plan) const override;
    Q_INVOKABLE double defaultCostForPlan(const QString &plan) const override;

    // Tool detection
    Q_INVOKABLE void checkToolInstalled() override;
    Q_INVOKABLE void detectActivity() override;

    // Browser sync
    Q_INVOKABLE void syncFromBrowser(const QString &cookieHeader, int browserType) override;

protected:
    UsagePeriod primaryPeriodType() const override { return Weekly; }

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
