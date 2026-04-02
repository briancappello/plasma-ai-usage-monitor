#ifndef OPENCODEMONITOR_H
#define OPENCODEMONITOR_H

#include "subscriptiontoolbackend.h"
#include <QFileSystemWatcher>
#include <QDir>

/**
 * Monitor for OpenCode CLI usage with Anthropic (Claude) provider.
 *
 * OpenCode is a third-party AI coding assistant that supports multiple
 * providers including Anthropic. When authenticated to Claude via OpenCode,
 * the same Claude.ai subscription limits apply:
 * - Primary: 5-hour session window
 * - Secondary: Weekly rolling window
 *
 * Browser sync reuses the Claude.ai internal APIs (identical to
 * ClaudeCodeMonitor) since both tools consume the same subscription.
 *
 * Detection paths:
 * - Binary: 'opencode' in PATH, or ~/.opencode/bin/opencode
 * - Data dir: ~/.local/share/opencode/
 * - Auth file: ~/.local/share/opencode/auth.json (checks for "anthropic" key)
 *
 * Activity tracking watches the OpenCode SQLite database at
 * ~/.local/share/opencode/opencode.db for changes.
 *
 * Plans mirror Claude.ai subscription tiers:
 * - Pro ($20/mo):     ~45 messages/5h session, ~225/week
 * - Max 5x ($100/mo): ~225 messages/5h session, ~1125/week
 * - Max 20x ($200/mo): ~900 messages/5h session, ~4500/week
 */
class OpenCodeMonitor : public SubscriptionToolBackend
{
    Q_OBJECT

public:
    explicit OpenCodeMonitor(QObject *parent = nullptr);

    // Identity
    QString toolName() const override { return QStringLiteral("OpenCode"); }
    QString iconName() const override { return QStringLiteral("utilities-terminal"); }
    QString toolColor() const override { return QStringLiteral("#7C5CFC"); }

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

    // Browser sync (reuses Claude.ai API)
    Q_INVOKABLE void syncFromBrowser(const QString &cookieHeader, int browserType) override;

protected:
    UsagePeriod primaryPeriodType() const override { return FiveHour; }
    UsagePeriod secondaryPeriodType() const override { return Weekly; }

private Q_SLOTS:
    void onDirectoryChanged(const QString &path);
    void onFileChanged(const QString &path);

private:
    void setupWatcher();
    QString openCodeDataDir() const;
    QString openCodeConfigDir() const;
    void fetchAccountInfo(const QString &cookieHeader);
    void fetchUsageData(const QString &orgUuid, const QString &cookieHeader);

    QFileSystemWatcher *m_watcher;
    QDateTime m_lastKnownModification;
    QString m_orgUuid;

    // Debounce timer to avoid counting rapid filesystem events as separate messages
    QTimer *m_debounceTimer;
    bool m_pendingIncrement = false;
};

#endif // OPENCODEMONITOR_H
