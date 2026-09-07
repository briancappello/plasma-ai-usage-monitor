#include "codexclimonitor.h"
#include <QStandardPaths>
#include <QFileInfo>
#include <QDebug>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonArray>
#include <QNetworkAccessManager>
#include <QNetworkRequest>
#include <QNetworkReply>
#include <QTimeZone>
#include <KLocalizedString>
#include <limits>

#include "browsercookieextractor.h"

CodexCliMonitor::CodexCliMonitor(QObject *parent)
    : SubscriptionToolBackend(parent)
    , m_watcher(new QFileSystemWatcher(this))
    , m_debounceTimer(new QTimer(this))
{
    // Debounce: multiple filesystem events within 5 seconds count as one message
    m_debounceTimer->setSingleShot(true);
    m_debounceTimer->setInterval(5000);
    connect(m_debounceTimer, &QTimer::timeout, this, [this]() {
        if (m_pendingIncrement) {
            m_pendingIncrement = false;
            // Filesystem events are not percentage points of the subscription quota.
            if (!lastSyncTime().isValid()) incrementUsage();
        }
    });

    connect(this, &SubscriptionToolBackend::syncEnabledChanged, this, [this]() {
        if (isSyncEnabled()) return;
        for (auto *reply : networkManager()->findChildren<QNetworkReply *>()) reply->abort();
        if (!lastSyncTime().isValid()) return;
        // Start a new local estimate rather than treating percentage points as messages.
        setUsageCount(0);
        setSecondaryUsageCount(0);
        setUsageLimit(defaultLimitForPlan(planTier()));
        setSecondaryUsageLimit(defaultSecondaryLimitForPlan(planTier()));
        setPeriodStart(QDateTime::currentDateTimeUtc());
        setSecondaryPeriodStart(QDateTime::currentDateTimeUtc());
        m_hasTertiary = false;
        m_hasCreditsData = false;
        setLastSyncTime(QDateTime());
        setSyncStatus(i18n("Local estimate"));
        Q_EMIT usageUpdated();
    });

    connect(m_watcher, &QFileSystemWatcher::directoryChanged,
            this, &CodexCliMonitor::onDirectoryChanged);
}

QString CodexCliMonitor::codexConfigDir() const
{
    // Codex CLI stores config in ~/.codex/
    return QDir::homePath() + QStringLiteral("/.codex");
}

void CodexCliMonitor::checkToolInstalled()
{
    bool found = false;

    // Check if 'codex' binary exists in PATH
    QString codexPath = QStandardPaths::findExecutable(QStringLiteral("codex"));
    if (!codexPath.isEmpty()) {
        found = true;
    }

    // Also check for ~/.codex/ directory
    QDir configDir(codexConfigDir());
    if (configDir.exists()) {
        found = true;
    }

    setInstalled(found);

    if (found && isEnabled()) {
        setupWatcher();
    }
}

void CodexCliMonitor::setupWatcher()
{
    QString configDir = codexConfigDir();
    QDir dir(configDir);

    if (dir.exists()) {
        m_watcher->addPath(configDir);

        // Watch subdirectories for session activity
        const auto subdirs = dir.entryInfoList(QDir::Dirs | QDir::NoDotAndDotDot);
        for (const auto &subdir : subdirs) {
            m_watcher->addPath(subdir.absoluteFilePath());
        }
    }
}

void CodexCliMonitor::detectActivity()
{
    QString configDir = codexConfigDir();
    QDir dir(configDir);

    if (!dir.exists()) return;

    QDateTime latestMod;

    // Check all files in the codex directory for recent modifications
    const auto entries = dir.entryInfoList(QDir::Files | QDir::Dirs | QDir::NoDotAndDotDot,
                                            QDir::Time);
    if (!entries.isEmpty()) {
        latestMod = entries.first().lastModified();
    }

    if (latestMod.isValid() && latestMod > m_lastKnownModification) {
        m_lastKnownModification = latestMod;
        m_pendingIncrement = true;
        if (!m_debounceTimer->isActive()) {
            m_debounceTimer->start();
        }
    }
}

void CodexCliMonitor::onDirectoryChanged(const QString &path)
{
    Q_UNUSED(path);
    if (!isEnabled()) return;
    detectActivity();
}

QStringList CodexCliMonitor::availablePlans() const
{
    return {
        QStringLiteral("Plus"),
        QStringLiteral("Pro"),
        QStringLiteral("Business")
    };
}

int CodexCliMonitor::defaultLimitForPlan(const QString &plan) const
{
    // Lower bound of 5-hour window for local messages
    if (plan == QStringLiteral("Plus")) return 45;
    if (plan == QStringLiteral("Pro")) return 300;
    if (plan == QStringLiteral("Business")) return 45;
    return 45;
}

int CodexCliMonitor::defaultSecondaryLimitForPlan(const QString &plan) const
{
    // Weekly usage limits
    if (plan == QStringLiteral("Plus")) return 100;
    if (plan == QStringLiteral("Pro")) return 500;
    if (plan == QStringLiteral("Business")) return 100;
    return 100;
}

double CodexCliMonitor::subscriptionCost() const
{
    return defaultCostForPlan(planTier());
}

double CodexCliMonitor::defaultCostForPlan(const QString &plan) const
{
    if (plan == QStringLiteral("Plus")) return 20.0;
    if (plan == QStringLiteral("Pro")) return 200.0;
    if (plan == QStringLiteral("Business")) return 30.0;
    return 20.0;
}

// --- Browser Sync ---

void CodexCliMonitor::syncFromBrowser(const QString &cookieHeader, int browserType)
{
    if (isSyncing()) return;
    setSyncing(true);
    setSyncStatus(QStringLiteral("Syncing..."));

    if (browserType != BrowserCookieExtractor::Firefox) {
        setSyncing(false);
        setSyncStatus(i18n("Browser unsupported"));
        const QString message = i18n("Browser Sync currently supports Firefox only");
        Q_EMIT syncDiagnostic(toolName(), QStringLiteral("unsupported_browser"), message);
        Q_EMIT syncCompleted(false, message);
        return;
    }

    if (cookieHeader.isEmpty()) {
        setSyncing(false);
        setSyncStatus(i18n("Not logged in"));
        const QString message = i18n("Not logged in — open chatgpt.com in Firefox first");
        Q_EMIT syncDiagnostic(toolName(), QStringLiteral("not_logged_in"), message);
        Q_EMIT syncCompleted(false, message);
        return;
    }

    fetchUsage(cookieHeader);
}

void CodexCliMonitor::fetchUsage(const QString &cookieHeader, const QString &accessToken)
{
    // Browser cookies authenticate the session endpoint; Codex usage needs its bearer token.
    const QString baseUrl = qEnvironmentVariableIsSet("PLASMA_AI_MONITOR_DEMO")
        ? QStringLiteral("http://localhost:8080/chatgpt") : QStringLiteral("https://chatgpt.com");
    const bool fetchingSession = accessToken.isEmpty();
    const QUrl url(baseUrl + (fetchingSession ? QStringLiteral("/api/auth/session")
                                            : QStringLiteral("/backend-api/wham/usage")));

    QNetworkRequest request(url);
    request.setRawHeader("Cookie", cookieHeader.toUtf8());
    if (!fetchingSession) {
        request.setRawHeader("Authorization", "Bearer " + accessToken.toUtf8());
    }
    request.setRawHeader("Accept", "application/json");
    request.setRawHeader("User-Agent", "Mozilla/5.0 (X11; Linux x86_64; rv:128.0) Gecko/20100101 Firefox/128.0");
    // Force HTTP/1.1 — Qt's HTTP/2 implementation triggers 401 on ChatGPT backend API
    request.setAttribute(QNetworkRequest::Http2AllowedAttribute, false);
    request.setAttribute(QNetworkRequest::CookieLoadControlAttribute, QNetworkRequest::Manual);
    request.setAttribute(QNetworkRequest::CookieSaveControlAttribute, QNetworkRequest::Manual);
    request.setAttribute(QNetworkRequest::RedirectPolicyAttribute, QNetworkRequest::ManualRedirectPolicy);
    request.setTransferTimeout(30000); // 30 second timeout

    QNetworkReply *reply = networkManager()->get(request);
    connect(reply, &QNetworkReply::finished, this, [this, reply, cookieHeader, fetchingSession]() {
        reply->deleteLater();

        if (reply->error() != QNetworkReply::NoError) {
            int httpStatus = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
            qWarning() << "CodexCliMonitor: Sync request failed: HTTP" << httpStatus;
            setSyncing(false);
            if (httpStatus == 401 || httpStatus == 403) {
                setSyncStatus(i18n("Session expired"));
                const QString message = i18n("Session expired — please log in to chatgpt.com in Firefox again");
                Q_EMIT syncDiagnostic(toolName(), QStringLiteral("session_expired"), message);
                Q_EMIT syncCompleted(false, message);
            } else {
                setSyncStatus(i18n("Sync failed"));
                const QString message = reply->errorString();
                Q_EMIT syncDiagnostic(toolName(), QStringLiteral("network_error"), message);
                Q_EMIT syncCompleted(false, message);
            }
            return;
        }

        QByteArray data = reply->readAll();
        QJsonDocument doc = QJsonDocument::fromJson(data);
        if (doc.isNull() || !doc.isObject()) {
            setSyncing(false);
            setSyncStatus(i18n("Invalid response"));
            const QString message = i18n("Unexpected response from ChatGPT");
            Q_EMIT syncDiagnostic(toolName(), QStringLiteral("invalid_response"), message);
            Q_EMIT syncCompleted(false, message);
            return;
        }

        QJsonObject root = doc.object();

        if (fetchingSession) {
            const QString token = root.value(QStringLiteral("accessToken")).toString();
            if (token.isEmpty() || token.contains(QLatin1Char('\r')) || token.contains(QLatin1Char('\n'))) {
                setSyncing(false);
                setSyncStatus(i18n("Session expired"));
                const QString message = i18n("Sign in to chatgpt.com in Firefox again");
                Q_EMIT syncDiagnostic(toolName(), QStringLiteral("session_expired"), message);
                Q_EMIT syncCompleted(false, message);
                return;
            }
            fetchUsage(cookieHeader, token);
            return;
        }

        const QJsonObject rateLimit = root.value(QStringLiteral("rate_limit")).toObject();
        QJsonValue primaryValue = rateLimit.value(QStringLiteral("primary_window"));
        QJsonValue weeklyValue = rateLimit.value(QStringLiteral("secondary_window"));
        // Some plans return only a weekly quota in primary_window.
        if (primaryValue.toObject().value(QStringLiteral("limit_window_seconds")).toInt() == 7 * 24 * 3600) {
            std::swap(primaryValue, weeklyValue);
        }
        const QJsonObject primary = primaryValue.toObject();
        const QJsonObject weekly = weeklyValue.toObject();
        const auto validWindow = [](const QJsonObject &window) {
            const QJsonValue used = window.value(QStringLiteral("used_percent"));
            return used.isDouble() && used.toDouble() >= 0 && used.toDouble() <= 100
                && window.value(QStringLiteral("reset_at")).toInteger() > 0;
        };
        // Do not overwrite the last snapshot or claim success for an unrelated payload.
        const bool hasPrimary = validWindow(primary);
        const bool hasWeekly = validWindow(weekly);
        if ((!hasPrimary && !hasWeekly)
            || (!primaryValue.isNull() && !primaryValue.isUndefined() && !hasPrimary)
            || (!weeklyValue.isNull() && !weeklyValue.isUndefined() && !hasWeekly)) {
            setSyncing(false);
            setSyncStatus(i18n("Invalid response"));
            const QString message = i18n("No valid Codex usage data found");
            Q_EMIT syncDiagnostic(toolName(), QStringLiteral("format_changed"), message);
            Q_EMIT syncCompleted(false, message);
            return;
        }

        // Disable the local-limit QML binding before changing limits or the detected plan.
        setLastSyncTime(QDateTime::currentDateTimeUtc());
        setUsageLimit(hasPrimary ? 100 : 0);
        setSecondaryUsageLimit(hasWeekly ? 100 : 0);
        setUsageCount(qRound(primary.value(QStringLiteral("used_percent")).toDouble()));
        setSecondaryUsageCount(qRound(weekly.value(QStringLiteral("used_percent")).toDouble()));
        setPeriodStart(hasPrimary ? QDateTime::fromSecsSinceEpoch(primary.value(QStringLiteral("reset_at")).toInteger(), QTimeZone::utc()).addSecs(-5 * 3600) : QDateTime());
        setSecondaryPeriodStart(hasWeekly ? QDateTime::fromSecsSinceEpoch(weekly.value(QStringLiteral("reset_at")).toInteger(), QTimeZone::utc()).addDays(-7) : QDateTime());

        const QJsonObject review = root.value(QStringLiteral("code_review_rate_limit")).toObject()
            .value(QStringLiteral("primary_window")).toObject();
        m_hasTertiary = validWindow(review);
        setTertiaryPercentRemaining(m_hasTertiary ? 100 - review.value(QStringLiteral("used_percent")).toDouble() : 0);
        setTertiaryResetDate(m_hasTertiary
            ? QDateTime::fromSecsSinceEpoch(review.value(QStringLiteral("reset_at")).toInteger(), QTimeZone::utc()) : QDateTime());

        const QJsonObject credits = root.value(QStringLiteral("credits")).toObject();
        bool validBalance = false;
        const double balance = credits.value(QStringLiteral("balance")).toVariant().toDouble(&validBalance);
        m_hasCreditsData = validBalance && balance >= 0 && balance <= std::numeric_limits<int>::max()
            && !credits.value(QStringLiteral("unlimited")).toBool();
        setRemainingCredits(m_hasCreditsData ? static_cast<int>(balance) : 0);

        const QString plan = root.value(QStringLiteral("plan_type")).toString();
        if (plan == QStringLiteral("pro")) {
            setPlanTier(QStringLiteral("Pro"));
        } else if (plan == QStringLiteral("plus")) {
            setPlanTier(QStringLiteral("Plus"));
        } else if (plan == QStringLiteral("business") || plan == QStringLiteral("team")) {
            setPlanTier(QStringLiteral("Business"));
        }

        // Sync complete
        setSyncing(false);
        setSyncStatus(i18n("Synced"));
        Q_EMIT syncCompleted(true, i18n("Codex usage data synced successfully"));
        Q_EMIT usageUpdated();
    });
}
