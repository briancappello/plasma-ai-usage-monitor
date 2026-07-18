#include "opencodemonitor.h"
#include <QStandardPaths>
#include <QFileInfo>
#include <QProcess>
#include <QDebug>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonArray>
#include <QNetworkAccessManager>
#include <QNetworkRequest>
#include <QNetworkReply>
#include <KLocalizedString>

OpenCodeMonitor::OpenCodeMonitor(QObject *parent)
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
            incrementUsage();
        }
    });

    connect(m_watcher, &QFileSystemWatcher::directoryChanged,
            this, &OpenCodeMonitor::onDirectoryChanged);
    connect(m_watcher, &QFileSystemWatcher::fileChanged,
            this, &OpenCodeMonitor::onFileChanged);
}

QString OpenCodeMonitor::openCodeDataDir() const
{
    // OpenCode stores data in ~/.local/share/opencode/ (XDG_DATA_HOME)
    QString dataHome = QStandardPaths::writableLocation(QStandardPaths::GenericDataLocation);
    if (dataHome.isEmpty()) {
        dataHome = QDir::homePath() + QStringLiteral("/.local/share");
    }
    return dataHome + QStringLiteral("/opencode");
}

QString OpenCodeMonitor::openCodeConfigDir() const
{
    // OpenCode global config in ~/.opencode/
    return QDir::homePath() + QStringLiteral("/.opencode");
}

void OpenCodeMonitor::checkToolInstalled()
{
    bool found = false;

    // Check if 'opencode' binary exists in PATH
    QString opencodePath = QStandardPaths::findExecutable(QStringLiteral("opencode"));
    if (!opencodePath.isEmpty()) {
        found = true;
    }

    // Check for ~/.opencode/bin/opencode (common install location)
    if (!found) {
        QString localBin = openCodeConfigDir() + QStringLiteral("/bin/opencode");
        if (QFileInfo::exists(localBin)) {
            found = true;
        }
    }

    // Also check for ~/.local/share/opencode/ directory (data dir exists = was used)
    if (!found) {
        QDir dataDir(openCodeDataDir());
        if (dataDir.exists()) {
            found = true;
        }
    }

    setInstalled(found);

    if (found && isEnabled()) {
        setupWatcher();
    }
}

void OpenCodeMonitor::setupWatcher()
{
    QString dataDir = openCodeDataDir();
    QDir dir(dataDir);

    if (dir.exists()) {
        m_watcher->addPath(dataDir);

        // Watch the SQLite database file for changes (primary activity indicator)
        QString dbFile = dataDir + QStringLiteral("/opencode.db");
        if (QFileInfo::exists(dbFile)) {
            m_watcher->addPath(dbFile);
        }

        // Watch the WAL file (written on every DB transaction)
        QString walFile = dataDir + QStringLiteral("/opencode.db-wal");
        if (QFileInfo::exists(walFile)) {
            m_watcher->addPath(walFile);
        }
    }

    // Also watch the config dir for auth changes
    QString configDir = openCodeConfigDir();
    if (QDir(configDir).exists()) {
        m_watcher->addPath(configDir);
    }
}

void OpenCodeMonitor::detectActivity()
{
    // Check for recent activity by looking at database modification times
    QString dataDir = openCodeDataDir();
    QDir dir(dataDir);

    if (!dir.exists()) return;

    QDateTime latestMod;

    // Check database file
    QFileInfo dbFile(dataDir + QStringLiteral("/opencode.db-wal"));
    if (dbFile.exists() && dbFile.lastModified() > latestMod) {
        latestMod = dbFile.lastModified();
    }

    // Fallback to main DB file
    QFileInfo mainDb(dataDir + QStringLiteral("/opencode.db"));
    if (mainDb.exists() && mainDb.lastModified() > latestMod) {
        latestMod = mainDb.lastModified();
    }

    // If we see a new modification since last check, schedule a debounced increment
    if (latestMod.isValid() && latestMod > m_lastKnownModification) {
        m_lastKnownModification = latestMod;
        m_pendingIncrement = true;
        if (!m_debounceTimer->isActive()) {
            m_debounceTimer->start();
        }
    }
}

void OpenCodeMonitor::onDirectoryChanged(const QString &path)
{
    Q_UNUSED(path);
    if (!isEnabled()) return;
    detectActivity();
}

void OpenCodeMonitor::onFileChanged(const QString &path)
{
    Q_UNUSED(path);
    if (!isEnabled()) return;

    // Only count database-related file changes as activity
    if (!path.contains(QStringLiteral("opencode.db"))) {
        // Re-add the file to the watcher but don't count as usage
        if (!m_watcher->files().contains(path) && QFileInfo::exists(path)) {
            m_watcher->addPath(path);
        }
        return;
    }

    QFileInfo fi(path);
    if (fi.exists() && fi.lastModified() > m_lastKnownModification) {
        m_lastKnownModification = fi.lastModified();
        m_pendingIncrement = true;
        if (!m_debounceTimer->isActive()) {
            m_debounceTimer->start();
        }
    }

    // Re-add the file to the watcher (QFileSystemWatcher removes files after change)
    if (!m_watcher->files().contains(path) && QFileInfo::exists(path)) {
        m_watcher->addPath(path);
    }
}

// --- Plans (same as Claude.ai subscription tiers) ---

QStringList OpenCodeMonitor::availablePlans() const
{
    return {
        QStringLiteral("Pro"),
        QStringLiteral("Max 5x"),
        QStringLiteral("Max 20x")
    };
}

int OpenCodeMonitor::defaultLimitForPlan(const QString &plan) const
{
    // Shares Claude's percentage-based usage API (no message counts), so the
    // "limit" is a 0–100 percent scale for every plan.
    Q_UNUSED(plan);
    return 100;
}

int OpenCodeMonitor::defaultSecondaryLimitForPlan(const QString &plan) const
{
    // Weekly usage is likewise reported as a 0–100 percent scale.
    Q_UNUSED(plan);
    return 100;
}

double OpenCodeMonitor::subscriptionCost() const
{
    return defaultCostForPlan(planTier());
}

double OpenCodeMonitor::defaultCostForPlan(const QString &plan) const
{
    if (plan == QStringLiteral("Pro")) return 20.0;
    if (plan == QStringLiteral("Max 5x")) return 100.0;
    if (plan == QStringLiteral("Max 20x")) return 200.0;
    return 20.0;
}

// --- Browser Sync (reuses Claude.ai API — same subscription) ---

void OpenCodeMonitor::syncFromBrowser(const QString &cookieHeader, int browserType)
{
    Q_UNUSED(browserType);

    if (isSyncing()) return;
    setSyncing(true);
    setSyncStatus(QStringLiteral("Syncing..."));

    if (cookieHeader.isEmpty()) {
        setSyncing(false);
        setSyncStatus(i18n("Not logged in"));
        const QString message = i18n("Not logged in — open claude.ai in Firefox first");
        Q_EMIT syncDiagnostic(toolName(), QStringLiteral("not_logged_in"), message);
        Q_EMIT syncCompleted(false, message);
        return;
    }

    fetchAccountInfo(cookieHeader);
}

void OpenCodeMonitor::fetchAccountInfo(const QString &cookieHeader)
{
    // Use /api/bootstrap to get account info and organization UUID
    // (same endpoint as Claude Code — shared Claude.ai subscription)
    QUrl url(QStringLiteral("https://claude.ai/api/bootstrap"));

    QNetworkRequest request(url);
    request.setRawHeader("Cookie", cookieHeader.toUtf8());
    request.setRawHeader("Accept", "application/json");
    request.setRawHeader("User-Agent", "Mozilla/5.0 (X11; Linux x86_64; rv:128.0) Gecko/20100101 Firefox/128.0");
    request.setAttribute(QNetworkRequest::Http2AllowedAttribute, false);
    request.setAttribute(QNetworkRequest::CookieLoadControlAttribute, QNetworkRequest::Manual);
    request.setAttribute(QNetworkRequest::CookieSaveControlAttribute, QNetworkRequest::Manual);
    request.setTransferTimeout(30000); // 30 second timeout

    QNetworkReply *reply = networkManager()->get(request);
    connect(reply, &QNetworkReply::finished, this, [this, reply, cookieHeader]() {
        reply->deleteLater();

        if (reply->error() != QNetworkReply::NoError) {
            int httpStatus = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
            qWarning() << "OpenCodeMonitor: Bootstrap fetch failed:" << reply->errorString() << "HTTP" << httpStatus;
            setSyncing(false);
            if (httpStatus == 401 || httpStatus == 403) {
                setSyncStatus(i18n("Session expired"));
                const QString message = i18n("Session expired — please log in to claude.ai in Firefox again");
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
            const QString message = i18n("Unexpected response from Claude.ai");
            Q_EMIT syncDiagnostic(toolName(), QStringLiteral("invalid_response"), message);
            Q_EMIT syncCompleted(false, message);
            return;
        }

        QJsonObject root = doc.object();

        // Extract organization UUID from bootstrap response
        // Structure: { account: { memberships: [ { organization: { uuid: "..." } } ] } }
        QString orgUuid;
        QJsonObject account = root.value(QStringLiteral("account")).toObject();
        if (account.isEmpty()) {
            setSyncing(false);
            setSyncStatus(i18n("Invalid response"));
            const QString message = i18n("API response format may have changed — missing account data");
            Q_EMIT syncDiagnostic(toolName(), QStringLiteral("format_changed"), message);
            Q_EMIT syncCompleted(false, message);
            return;
        }
        QJsonArray memberships = account.value(QStringLiteral("memberships")).toArray();
        QJsonObject org; // Declared in outer scope for plan detection below

        // Pick the membership whose organization owns the Claude subscription
        // (chat / claude_max / claude_pro). A separate API/console org (whose
        // capabilities include "api") returns 403 on /usage — selecting it
        // caused false "session expired" errors.
        auto hasSubscriptionCapability = [](const QJsonObject &organization) {
            const QJsonArray caps = organization.value(QStringLiteral("capabilities")).toArray();
            for (const QJsonValue &c : caps) {
                const QString cap = c.toString();
                if (cap == QStringLiteral("chat")
                    || cap.startsWith(QStringLiteral("claude_"))) {
                    return true;
                }
            }
            return false;
        };

        for (const QJsonValue &m : memberships) {
            const QJsonObject candidate = m.toObject().value(QStringLiteral("organization")).toObject();
            if (hasSubscriptionCapability(candidate)) {
                org = candidate;
                orgUuid = candidate.value(QStringLiteral("uuid")).toString();
                break;
            }
        }

        if (orgUuid.isEmpty() && !memberships.isEmpty()) {
            org = memberships.first().toObject().value(QStringLiteral("organization")).toObject();
            orgUuid = org.value(QStringLiteral("uuid")).toString();
        }

        // Fallback: try top-level uuid
        if (orgUuid.isEmpty()) {
            orgUuid = account.value(QStringLiteral("uuid")).toString();
        }

        if (orgUuid.isEmpty()) {
            setSyncing(false);
            setSyncStatus(i18n("No organization"));
            const QString message = i18n("Could not find your Claude organization");
            Q_EMIT syncDiagnostic(toolName(), QStringLiteral("organization_missing"), message);
            Q_EMIT syncCompleted(false, message);
            return;
        }

        m_orgUuid = orgUuid;

        // Auto-detect plan. Prefer subscription.type; fall back to the org's
        // rate_limit_tier (e.g. "default_claude_max_20x"), present on Claude Max
        // orgs that have no separate subscription object.
        QString planType = org.value(QStringLiteral("subscription")).toObject()
                               .value(QStringLiteral("type")).toString();
        if (planType.isEmpty()) {
            planType = org.value(QStringLiteral("rate_limit_tier")).toString();
        }

        QString detectedPlan;
        if (planType.contains(QStringLiteral("max_20x"), Qt::CaseInsensitive)
            || planType.contains(QStringLiteral("max20x"), Qt::CaseInsensitive)
            || planType == QStringLiteral("scale_max_20x")) {
            detectedPlan = QStringLiteral("Max 20x");
        } else if (planType.contains(QStringLiteral("max_5x"), Qt::CaseInsensitive)
                   || planType.contains(QStringLiteral("max5x"), Qt::CaseInsensitive)
                   || planType == QStringLiteral("scale_max_5x")) {
            detectedPlan = QStringLiteral("Max 5x");
        } else if (planType.contains(QStringLiteral("pro"), Qt::CaseInsensitive)
                   || planType == QStringLiteral("professional")) {
            detectedPlan = QStringLiteral("Pro");
        }

        if (!detectedPlan.isEmpty() && detectedPlan != planTier()) {
            qDebug() << "OpenCodeMonitor: Auto-detected plan:" << detectedPlan << "(raw:" << planType << ")";
            setPlanTier(detectedPlan);
            setUsageLimit(defaultLimitForPlan(detectedPlan));
            setSecondaryUsageLimit(defaultSecondaryLimitForPlan(detectedPlan));
        }

        fetchUsageData(orgUuid, cookieHeader);
    });
}

void OpenCodeMonitor::fetchUsageData(const QString &orgUuid, const QString &cookieHeader)
{
    QUrl url(QStringLiteral("https://claude.ai/api/organizations/%1/usage").arg(orgUuid));

    QNetworkRequest request(url);
    request.setRawHeader("Cookie", cookieHeader.toUtf8());
    request.setRawHeader("Accept", "application/json");
    request.setRawHeader("User-Agent", "Mozilla/5.0 (X11; Linux x86_64; rv:128.0) Gecko/20100101 Firefox/128.0");
    request.setAttribute(QNetworkRequest::Http2AllowedAttribute, false);
    request.setAttribute(QNetworkRequest::CookieLoadControlAttribute, QNetworkRequest::Manual);
    request.setAttribute(QNetworkRequest::CookieSaveControlAttribute, QNetworkRequest::Manual);
    request.setTransferTimeout(30000); // 30 second timeout

    QNetworkReply *reply = networkManager()->get(request);
    connect(reply, &QNetworkReply::finished, this, [this, reply]() {
        reply->deleteLater();

        if (reply->error() != QNetworkReply::NoError) {
            int httpStatus = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
            qWarning() << "OpenCodeMonitor: Usage fetch failed:" << reply->errorString() << "HTTP" << httpStatus;
            setSyncing(false);
            if (httpStatus == 401 || httpStatus == 403) {
                setSyncStatus(i18n("Session expired"));
                const QString message = i18n("Session expired — please log in to claude.ai in Firefox again");
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
        if (!doc.isObject()) {
            setSyncing(false);
            setSyncStatus(i18n("Invalid response"));
            const QString message = i18n("Unexpected response from Claude.ai");
            Q_EMIT syncDiagnostic(toolName(), QStringLiteral("invalid_response"), message);
            Q_EMIT syncCompleted(false, message);
            return;
        }

        QJsonObject root = doc.object();

        // Validate expected fields exist
        if (!root.contains(QStringLiteral("five_hour")) && !root.contains(QStringLiteral("seven_day"))) {
            setSyncing(false);
            setSyncStatus(i18n("Invalid response"));
            const QString message = i18n("API response format may have changed — no usage data found");
            Q_EMIT syncDiagnostic(toolName(), QStringLiteral("format_changed"), message);
            Q_EMIT syncCompleted(false, message);
            return;
        }

        // Claude's usage API (shared subscription) is percentage-based: session
        // and weekly are 0–100 utilization with no message counts. Normalise the
        // count-based UI to that percent scale (limit == 100, count == %).
        //
        // The `limits` array is the authoritative source that drives claude.ai's
        // own UI (kinds: session / weekly_all / weekly_scoped). Prefer it, and
        // fall back to the flat five_hour / seven_day objects.
        double sessionPct = -1.0;
        double weeklyPct = -1.0;
        const QJsonArray limits = root.value(QStringLiteral("limits")).toArray();
        for (const QJsonValue &v : limits) {
            const QJsonObject l = v.toObject();
            const QString kind = l.value(QStringLiteral("kind")).toString();
            const double pct = l.value(QStringLiteral("percent")).toDouble(0.0);
            if (kind == QStringLiteral("session")) {
                sessionPct = pct;
            } else if (kind == QStringLiteral("weekly_all")) {
                weeklyPct = pct;
            }
        }

        // Parse 5-hour session usage
        QJsonObject fiveHour = root.value(QStringLiteral("five_hour")).toObject();
        if (sessionPct < 0.0 && !fiveHour.isEmpty()) {
            sessionPct = fiveHour.value(QStringLiteral("utilization")).toDouble(0.0);
        }
        if (sessionPct >= 0.0) {
            setSessionPercentUsed(sessionPct);
            setHasSessionInfo(true);
            // Count bars run on a 0–100 percent scale (see defaultLimitForPlan).
            setUsageCount(static_cast<int>(qRound(sessionPct)));

            QString resetsAt = fiveHour.value(QStringLiteral("resets_at")).toString();
            if (!resetsAt.isEmpty()) {
                QDateTime resetTime = QDateTime::fromString(resetsAt, Qt::ISODate);
                if (resetTime.isValid()) {
                    // Calculate period start from reset time (reset = start + 5h)
                    setPeriodStart(resetTime.addSecs(-5 * 3600));
                }
            }
        }

        // Parse 7-day (weekly) usage
        QJsonObject sevenDay = root.value(QStringLiteral("seven_day")).toObject();
        if (weeklyPct < 0.0 && !sevenDay.isEmpty()) {
            weeklyPct = sevenDay.value(QStringLiteral("utilization")).toDouble(0.0);
        }
        if (weeklyPct >= 0.0) {
            setSecondaryUsageCount(static_cast<int>(qRound(weeklyPct)));
        }

        // Parse extra_usage (metered credit spending). Real fields:
        //   is_enabled, monthly_limit, used_credits (currency units, not cents).
        QJsonValue extraVal = root.value(QStringLiteral("extra_usage"));
        if (!extraVal.isNull() && extraVal.isObject()) {
            QJsonObject extra = extraVal.toObject();
            const bool enabled = extra.value(QStringLiteral("is_enabled")).toBool(false);
            setHasExtraUsage(enabled);
            if (enabled) {
                setExtraUsageSpent(extra.value(QStringLiteral("used_credits")).toDouble(0.0));
                setExtraUsageLimit(extra.value(QStringLiteral("monthly_limit")).toDouble(0.0));
                QString resetsAt = extra.value(QStringLiteral("resets_at")).toString();
                if (!resetsAt.isEmpty()) {
                    setExtraUsageResetDate(QDateTime::fromString(resetsAt, Qt::ISODate));
                }
            }
        }

        // Sync complete
        setSyncing(false);
        setLastSyncTime(QDateTime::currentDateTimeUtc());
        setSyncStatus(i18n("Synced"));
        Q_EMIT syncCompleted(true, i18n("OpenCode usage data synced successfully"));
        Q_EMIT usageUpdated();
    });
}
