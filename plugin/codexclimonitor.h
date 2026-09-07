#ifndef CODEXCLIMONITOR_H
#define CODEXCLIMONITOR_H

#include "subscriptiontoolbackend.h"
#include <QFileSystemWatcher>
#include <QDir>

/**
 * Monitor for OpenAI Codex CLI usage.
 *
 * Codex CLI uses a 5-hour rolling window for usage limits tied to the
 * ChatGPT subscription plan. Limits vary by plan and task type.
 *
 * No public API exists for checking remaining quota. This monitor:
 * 1. Detects if Codex CLI is installed (checks PATH + ~/.codex/)
 * 2. Watches ~/.codex/ for session activity
 * 3. Self-tracks usage counts in the local database
 * 4. Lets users set their plan tier to auto-fill limits
 * 5. (Optional) Syncs from browser cookies to get real-time data
 *
 * Plans and approximate limits (5-hour window):
 * - Plus ($20/mo):    45–225 local messages, 10–60 cloud tasks
 * - Pro ($200/mo):    300–1500 local messages, 50–400 cloud tasks
 * - Business ($30/user/mo): 45–225 local messages
 *
 * Ranges depend on task complexity. We use the lower bound as default.
 *
 * Browser sync exchanges Firefox session cookies for an in-memory access token,
 * then reads /backend-api/wham/usage. Synced counts use a 0-100 percentage scale,
 * not the approximate message limits above. Local activity cannot increment them.
 * The response provides:
 * - 5-hour usage limit (primary)
 * - Weekly usage limit (secondary)
 * - Code review (tertiary)
 * - Remaining credits
 */
class CodexCliMonitor : public SubscriptionToolBackend
{
    Q_OBJECT

public:
    explicit CodexCliMonitor(QObject *parent = nullptr);

    // Identity
    QString toolName() const override { return QStringLiteral("Codex CLI"); }
    QString iconName() const override { return QStringLiteral("utilities-terminal"); }
    QString toolColor() const override { return QStringLiteral("#10A37F"); }

    // Period labels
    QString periodLabel() const override { return QStringLiteral("5-hour window"); }

    // Plan management
    Q_INVOKABLE QStringList availablePlans() const override;
    Q_INVOKABLE int defaultLimitForPlan(const QString &plan) const override;
    Q_INVOKABLE int defaultSecondaryLimitForPlan(const QString &plan) const override;

    // Tool detection
    Q_INVOKABLE void checkToolInstalled() override;
    Q_INVOKABLE void detectActivity() override;

    // Browser sync
    Q_INVOKABLE void syncFromBrowser(const QString &cookieHeader, int browserType) override;

    // Cost
    double subscriptionCost() const override;
    double defaultCostForPlan(const QString &plan) const override;
    bool hasSubscriptionCost() const override { return true; }

    // Tertiary & credits overrides
    bool hasTertiaryLimit() const override { return m_hasTertiary; }
    QString tertiaryPeriodLabel() const override { return QStringLiteral("Code review"); }
    bool hasCredits() const override { return m_hasCreditsData; }
    bool hasSecondaryLimit() const override { return true; }
    QString secondaryPeriodLabel() const override { return QStringLiteral("Weekly"); }

protected:
    UsagePeriod primaryPeriodType() const override { return FiveHour; }
    UsagePeriod secondaryPeriodType() const override { return Weekly; }

private Q_SLOTS:
    void onDirectoryChanged(const QString &path);

private:
    void setupWatcher();
    QString codexConfigDir() const;
    void fetchUsage(const QString &cookieHeader, const QString &accessToken = QString());

    QFileSystemWatcher *m_watcher;
    QDateTime m_lastKnownModification;
    bool m_hasTertiary = false;
    bool m_hasCreditsData = false;

    // Debounce timer to avoid counting rapid filesystem events as separate messages
    QTimer *m_debounceTimer;
    bool m_pendingIncrement = false;
};

#endif // CODEXCLIMONITOR_H
