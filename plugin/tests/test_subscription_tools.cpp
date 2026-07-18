#include <QtTest>

#include <QDir>
#include <QFile>
#include <QSignalSpy>
#include <QTcpServer>
#include <QTcpSocket>
#include <QTemporaryDir>

#include "claudecodemonitor.h"
#include "codexclimonitor.h"
#include "copilotmonitor.h"
#include "opencodemonitor.h"

// Minimal HTTP mock that serves Claude bootstrap + usage responses on
// 127.0.0.1:8080 (the address the PLASMA_AI_MONITOR_DEMO override targets).
// Replies are keyed off the request path substring.
class MockClaudeServer : public QObject
{
    Q_OBJECT
public:
    explicit MockClaudeServer(QObject *parent = nullptr) : QObject(parent)
    {
        connect(&m_server, &QTcpServer::newConnection, this, &MockClaudeServer::onConnection);
    }

    bool listen() { return m_server.listen(QHostAddress::LocalHost, 8080); }

private Q_SLOTS:
    void onConnection()
    {
        QTcpSocket *sock = m_server.nextPendingConnection();
        connect(sock, &QTcpSocket::readyRead, this, [this, sock]() {
            const QByteArray req = sock->readAll();
            const QByteArray firstLine = req.left(req.indexOf('\r'));

            QByteArray body;
            int status = 200;
            if (firstLine.contains("/bootstrap")) {
                // Two memberships: an API/console org FIRST (whose /usage 403s),
                // then the Claude Max subscription org. The monitor must pick the
                // latter by capability and read its plan from rate_limit_tier.
                body = R"({"account":{"uuid":"acct","memberships":[)"
                       R"({"organization":{"uuid":"org_api","capabilities":["api","api_individual"]}},)"
                       R"({"organization":{"uuid":"org_max","capabilities":["chat","claude_max"],)"
                       R"("rate_limit_tier":"default_claude_max_20x"}}]}})";
            } else if (firstLine.contains("/org_api/usage")) {
                // Selecting the API org must never happen; if it does, 403.
                status = 403;
                body = R"({"type":"error","error":{"type":"permission_error"}})";
            } else if (firstLine.contains("/usage")) {
                // Real-shaped percentage response (see claudecodemonitor.cpp).
                body = R"({"five_hour":{"utilization":4.0,"resets_at":"2099-01-01T00:00:00Z"},)"
                       R"("seven_day":{"utilization":3.0,"resets_at":"2099-01-07T00:00:00Z"},)"
                       R"("extra_usage":{"is_enabled":false,"monthly_limit":0,"used_credits":0.0},)"
                       R"("limits":[{"kind":"session","group":"session","percent":4,"is_active":true},)"
                       R"({"kind":"weekly_all","group":"weekly","percent":3,"is_active":false},)"
                       R"({"kind":"weekly_scoped","group":"weekly","percent":1,)"
                       R"("scope":{"model":{"display_name":"Fable"}},"is_active":false}]})";
            } else {
                status = 404;
                body = R"({"error":"not found"})";
            }

            const char *reason = status == 200 ? "OK" : (status == 403 ? "Forbidden" : "Not Found");
            QByteArray resp = "HTTP/1.1 " + QByteArray::number(status) + " " + reason
                + "\r\nContent-Type: application/json\r\nContent-Length: "
                + QByteArray::number(body.size()) + "\r\nConnection: close\r\n\r\n" + body;
            sock->write(resp);
            sock->flush();
            sock->disconnectFromHost();
        });
        connect(sock, &QTcpSocket::disconnected, sock, &QObject::deleteLater);
    }

private:
    QTcpServer m_server;
};

class EnvVarGuard
{
public:
    explicit EnvVarGuard(const char *name)
        : m_name(name)
        , m_oldValue(qgetenv(name))
        , m_hadValue(!m_oldValue.isNull())
    {
    }

    ~EnvVarGuard()
    {
        if (m_hadValue) {
            qputenv(m_name.constData(), m_oldValue);
        } else {
            qunsetenv(m_name.constData());
        }
    }

private:
    QByteArray m_name;
    QByteArray m_oldValue;
    bool m_hadValue = false;
};

class SubscriptionToolsTest : public QObject
{
    Q_OBJECT

private Q_SLOTS:
    void planDefaults();
    void openCodePlanDefaults();
    void installDetectionWithTemporaryHome();
    void usageIncrementAndReset();
    void copilotDetectActivityIncrementsUsage();
    void browserSyncEmptyCookieDiagnostics();
    void browserSyncUnsupportedBrowserDiagnostics();
    void claudeSyncParsesPercentageUsage();
};

void SubscriptionToolsTest::planDefaults()
{
    ClaudeCodeMonitor claude;
    // Claude's usage API is percentage-based: every plan's limit is the 0–100
    // percent scale (the backend normalises utilization to the real plan).
    QCOMPARE(claude.defaultLimitForPlan(QStringLiteral("Pro")), 100);
    QCOMPARE(claude.defaultLimitForPlan(QStringLiteral("Max 20x")), 100);
    QCOMPARE(claude.defaultSecondaryLimitForPlan(QStringLiteral("Max 5x")), 100);
    QCOMPARE(claude.defaultCostForPlan(QStringLiteral("Max 20x")), 200.0);

    CodexCliMonitor codex;
    QCOMPARE(codex.defaultLimitForPlan(QStringLiteral("Plus")), 45);
    QCOMPARE(codex.defaultSecondaryLimitForPlan(QStringLiteral("Pro")), 500);
    QCOMPARE(codex.defaultCostForPlan(QStringLiteral("Pro")), 200.0);

    CopilotMonitor copilot;
    QCOMPARE(copilot.defaultLimitForPlan(QStringLiteral("Free")), 50);
    QCOMPARE(copilot.defaultLimitForPlan(QStringLiteral("Pro+")), 1500);
    QCOMPARE(copilot.defaultCostForPlan(QStringLiteral("Business")), 19.0);
}

void SubscriptionToolsTest::openCodePlanDefaults()
{
    OpenCodeMonitor opencode;
    // Shares Claude's percentage-based usage API → 0–100 percent scale.
    QCOMPARE(opencode.defaultLimitForPlan(QStringLiteral("Pro")), 100);
    QCOMPARE(opencode.defaultSecondaryLimitForPlan(QStringLiteral("Max 5x")), 100);
    QCOMPARE(opencode.defaultCostForPlan(QStringLiteral("Max 20x")), 200.0);
    QCOMPARE(opencode.toolName(), QStringLiteral("OpenCode"));
    QVERIFY(opencode.hasSecondaryLimit());
    QVERIFY(opencode.hasSubscriptionCost());
}

void SubscriptionToolsTest::installDetectionWithTemporaryHome()
{
    QTemporaryDir tempHome;
    QVERIFY(tempHome.isValid());

    EnvVarGuard homeGuard("HOME");
    EnvVarGuard pathGuard("PATH");

    qputenv("HOME", tempHome.path().toUtf8());
    qputenv("PATH", QByteArray());

    ClaudeCodeMonitor claude;
    CodexCliMonitor codex;
    CopilotMonitor copilot;
    OpenCodeMonitor opencode;

    claude.checkToolInstalled();
    codex.checkToolInstalled();
    copilot.checkToolInstalled();
    opencode.checkToolInstalled();

    QVERIFY(!claude.isInstalled());
    QVERIFY(!codex.isInstalled());
    QVERIFY(!copilot.isInstalled());
    QVERIFY(!opencode.isInstalled());

    QVERIFY(QDir().mkpath(tempHome.path() + QStringLiteral("/.claude")));
    QVERIFY(QDir().mkpath(tempHome.path() + QStringLiteral("/.codex")));
    QVERIFY(QDir().mkpath(tempHome.path() + QStringLiteral("/.vscode/extensions/github.copilot-test")));
    QVERIFY(QDir().mkpath(tempHome.path() + QStringLiteral("/.local/share/opencode")));

    claude.checkToolInstalled();
    codex.checkToolInstalled();
    copilot.checkToolInstalled();
    opencode.checkToolInstalled();

    QVERIFY(claude.isInstalled());
    QVERIFY(codex.isInstalled());
    QVERIFY(copilot.isInstalled());
    QVERIFY(opencode.isInstalled());
}

void SubscriptionToolsTest::usageIncrementAndReset()
{
    CodexCliMonitor codex;
    codex.setUsageLimit(2);

    codex.incrementUsage();
    codex.incrementUsage();

    QCOMPARE(codex.usageCount(), 2);
    QVERIFY(codex.isLimitReached());

    codex.resetUsage();
    QCOMPARE(codex.usageCount(), 0);
    QVERIFY(!codex.isLimitReached());
}

void SubscriptionToolsTest::copilotDetectActivityIncrementsUsage()
{
    QTemporaryDir tempHome;
    QVERIFY(tempHome.isValid());

    EnvVarGuard homeGuard("HOME");
    qputenv("HOME", tempHome.path().toUtf8());

    const QString stateDir = tempHome.path() + QStringLiteral("/.config/Code/User/globalStorage/github.copilot-chat");
    QVERIFY(QDir().mkpath(stateDir));
    const QString stateFilePath = stateDir + QStringLiteral("/state.json");

    QFile stateFile(stateFilePath);
    QVERIFY(stateFile.open(QIODevice::WriteOnly | QIODevice::Text));
    stateFile.write("{\"status\":\"idle\"}\n");
    stateFile.close();

    CopilotMonitor copilot;
    copilot.setUsageLimit(10);

    QSignalSpy activitySpy(&copilot, &SubscriptionToolBackend::activityDetected);
    QSignalSpy usageSpy(&copilot, &SubscriptionToolBackend::usageUpdated);

    // Baseline only — first pass should not increment usage.
    copilot.detectActivity();
    QCOMPARE(copilot.usageCount(), 0);

    QTest::qWait(1100);
    QVERIFY(stateFile.open(QIODevice::WriteOnly | QIODevice::Text | QIODevice::Truncate));
    stateFile.write("{\"status\":\"active\"}\n");
    stateFile.close();

    copilot.detectActivity();

    QCOMPARE(copilot.usageCount(), 1);
    QCOMPARE(activitySpy.count(), 1);
    QVERIFY(usageSpy.count() >= 1);
}

void SubscriptionToolsTest::browserSyncEmptyCookieDiagnostics()
{
    ClaudeCodeMonitor claude;
    QSignalSpy claudeCompletedSpy(&claude, &SubscriptionToolBackend::syncCompleted);
    QSignalSpy claudeDiagnosticSpy(&claude, &SubscriptionToolBackend::syncDiagnostic);

    claude.syncFromBrowser(QString(), 0);

    QCOMPARE(claudeCompletedSpy.count(), 1);
    QCOMPARE(claudeDiagnosticSpy.count(), 1);
    QCOMPARE(claude.syncStatus(), QStringLiteral("Not logged in"));

    const QList<QVariant> claudeCompletionArgs = claudeCompletedSpy.takeFirst();
    QCOMPARE(claudeCompletionArgs.at(0).toBool(), false);
    QVERIFY(claudeCompletionArgs.at(1).toString().contains(QStringLiteral("Not logged in"), Qt::CaseInsensitive));

    const QList<QVariant> claudeDiagnosticArgs = claudeDiagnosticSpy.takeFirst();
    QCOMPARE(claudeDiagnosticArgs.at(0).toString(), QStringLiteral("Claude Code"));
    QCOMPARE(claudeDiagnosticArgs.at(1).toString(), QStringLiteral("not_logged_in"));

    CodexCliMonitor codex;
    QSignalSpy codexCompletedSpy(&codex, &SubscriptionToolBackend::syncCompleted);
    QSignalSpy codexDiagnosticSpy(&codex, &SubscriptionToolBackend::syncDiagnostic);

    codex.syncFromBrowser(QString(), 0);

    QCOMPARE(codexCompletedSpy.count(), 1);
    QCOMPARE(codexDiagnosticSpy.count(), 1);
    QCOMPARE(codex.syncStatus(), QStringLiteral("Not logged in"));

    const QList<QVariant> codexCompletionArgs = codexCompletedSpy.takeFirst();
    QCOMPARE(codexCompletionArgs.at(0).toBool(), false);
    QVERIFY(codexCompletionArgs.at(1).toString().contains(QStringLiteral("Not logged in"), Qt::CaseInsensitive));

    const QList<QVariant> codexDiagnosticArgs = codexDiagnosticSpy.takeFirst();
    QCOMPARE(codexDiagnosticArgs.at(0).toString(), QStringLiteral("Codex CLI"));
    QCOMPARE(codexDiagnosticArgs.at(1).toString(), QStringLiteral("not_logged_in"));

    OpenCodeMonitor opencode;
    QSignalSpy opencodeCompletedSpy(&opencode, &SubscriptionToolBackend::syncCompleted);
    QSignalSpy opencodeDiagnosticSpy(&opencode, &SubscriptionToolBackend::syncDiagnostic);

    opencode.syncFromBrowser(QString(), 0);

    QCOMPARE(opencodeCompletedSpy.count(), 1);
    QCOMPARE(opencodeDiagnosticSpy.count(), 1);
    QCOMPARE(opencode.syncStatus(), QStringLiteral("Not logged in"));

    const QList<QVariant> opencodeCompletionArgs = opencodeCompletedSpy.takeFirst();
    QCOMPARE(opencodeCompletionArgs.at(0).toBool(), false);
    QVERIFY(opencodeCompletionArgs.at(1).toString().contains(QStringLiteral("Not logged in"), Qt::CaseInsensitive));

    const QList<QVariant> opencodeDiagnosticArgs = opencodeDiagnosticSpy.takeFirst();
    QCOMPARE(opencodeDiagnosticArgs.at(0).toString(), QStringLiteral("OpenCode"));
    QCOMPARE(opencodeDiagnosticArgs.at(1).toString(), QStringLiteral("not_logged_in"));
}

void SubscriptionToolsTest::browserSyncUnsupportedBrowserDiagnostics()
{
    ClaudeCodeMonitor claude;
    QSignalSpy claudeCompletedSpy(&claude, &SubscriptionToolBackend::syncCompleted);
    QSignalSpy claudeDiagnosticSpy(&claude, &SubscriptionToolBackend::syncDiagnostic);

    claude.syncFromBrowser(QStringLiteral("sessionKey=test"), 1);

    QCOMPARE(claudeCompletedSpy.count(), 1);
    QCOMPARE(claudeDiagnosticSpy.count(), 1);
    QCOMPARE(claude.syncStatus(), QStringLiteral("Browser unsupported"));

    const QList<QVariant> claudeCompletionArgs = claudeCompletedSpy.takeFirst();
    QCOMPARE(claudeCompletionArgs.at(0).toBool(), false);
    QVERIFY(claudeCompletionArgs.at(1).toString().contains(QStringLiteral("Firefox"), Qt::CaseInsensitive));

    const QList<QVariant> claudeDiagnosticArgs = claudeDiagnosticSpy.takeFirst();
    QCOMPARE(claudeDiagnosticArgs.at(0).toString(), QStringLiteral("Claude Code"));
    QCOMPARE(claudeDiagnosticArgs.at(1).toString(), QStringLiteral("unsupported_browser"));

    CodexCliMonitor codex;
    QSignalSpy codexCompletedSpy(&codex, &SubscriptionToolBackend::syncCompleted);
    QSignalSpy codexDiagnosticSpy(&codex, &SubscriptionToolBackend::syncDiagnostic);

    codex.syncFromBrowser(QStringLiteral("__Secure-next-auth.session-token=test"), 1);

    QCOMPARE(codexCompletedSpy.count(), 1);
    QCOMPARE(codexDiagnosticSpy.count(), 1);
    QCOMPARE(codex.syncStatus(), QStringLiteral("Browser unsupported"));

    const QList<QVariant> codexCompletionArgs = codexCompletedSpy.takeFirst();
    QCOMPARE(codexCompletionArgs.at(0).toBool(), false);
    QVERIFY(codexCompletionArgs.at(1).toString().contains(QStringLiteral("Firefox"), Qt::CaseInsensitive));

    const QList<QVariant> codexDiagnosticArgs = codexDiagnosticSpy.takeFirst();
    QCOMPARE(codexDiagnosticArgs.at(0).toString(), QStringLiteral("Codex CLI"));
    QCOMPARE(codexDiagnosticArgs.at(1).toString(), QStringLiteral("unsupported_browser"));
}

// Regression: Claude's usage API is percentage-based (session 4%, weekly 3%,
// no message counts) and reports extra_usage via is_enabled/used_credits.
// The monitor must surface those percents on a 0–100 scale and must NOT invent
// message counts or show a disabled extra-usage row.
void SubscriptionToolsTest::claudeSyncParsesPercentageUsage()
{
    MockClaudeServer server;
    QVERIFY2(server.listen(), "port 8080 must be free for this test");

    EnvVarGuard demoGuard("PLASMA_AI_MONITOR_DEMO");
    qputenv("PLASMA_AI_MONITOR_DEMO", "1");

    ClaudeCodeMonitor claude;
    QSignalSpy completedSpy(&claude, &SubscriptionToolBackend::syncCompleted);

    // browserType 0 = Firefox (only supported); any non-empty cookie header.
    claude.syncFromBrowser(QStringLiteral("sessionKey=test"), 0);

    QVERIFY(completedSpy.wait(15000));
    QCOMPARE(completedSpy.count(), 1);
    QCOMPARE(completedSpy.takeFirst().at(0).toBool(), true);

    // Plan auto-detected from bootstrap subscription.type == "max_20x".
    QCOMPARE(claude.planTier(), QStringLiteral("Max 20x"));

    // Percentage-native: limits are the 0–100 scale, counts equal the percent.
    QCOMPARE(claude.usageLimit(), 100);
    QCOMPARE(claude.secondaryUsageLimit(), 100);
    QCOMPARE(qRound(claude.sessionPercentUsed()), 4);
    QCOMPARE(claude.usageCount(), 4);          // session 4%, NOT 4% of 900
    QCOMPARE(claude.secondaryUsageCount(), 3); // weekly_all 3%, NOT 3% of 4500

    // extra_usage is disabled in the payload → no metered row.
    QCOMPARE(claude.hasExtraUsage(), false);
}

QTEST_MAIN(SubscriptionToolsTest)
#include "test_subscription_tools.moc"
