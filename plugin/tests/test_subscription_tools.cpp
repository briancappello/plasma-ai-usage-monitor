#include <QtTest>

#include <QDir>
#include <QSignalSpy>
#include <QTemporaryDir>

#include "claudecodemonitor.h"
#include "codexclimonitor.h"
#include "copilotmonitor.h"
#include "opencodemonitor.h"

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
    void browserSyncEmptyCookieDiagnostics();
};

void SubscriptionToolsTest::planDefaults()
{
    ClaudeCodeMonitor claude;
    QCOMPARE(claude.defaultLimitForPlan(QStringLiteral("Pro")), 45);
    QCOMPARE(claude.defaultSecondaryLimitForPlan(QStringLiteral("Max 5x")), 1125);
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
    QCOMPARE(opencode.defaultLimitForPlan(QStringLiteral("Pro")), 45);
    QCOMPARE(opencode.defaultSecondaryLimitForPlan(QStringLiteral("Max 5x")), 1125);
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

QTEST_MAIN(SubscriptionToolsTest)
#include "test_subscription_tools.moc"
