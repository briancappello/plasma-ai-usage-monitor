#include <QtTest>
#include <QSignalSpy>

#include "subscriptiontoolbackend.h"
#include "resilientnetworkaccessmanager.h"

/**
 * Minimal concrete subclass for testing SubscriptionToolBackend's non-virtual logic.
 */
class TestToolBackend : public SubscriptionToolBackend
{
    Q_OBJECT
public:
    explicit TestToolBackend(QObject *parent = nullptr)
        : SubscriptionToolBackend(parent)
        , m_hasSecondary(false)
    {}

    QString toolName() const override { return QStringLiteral("TestTool"); }
    QString iconName() const override { return QStringLiteral("test-tool-icon"); }
    QString toolColor() const override { return QStringLiteral("#FF0000"); }
    QString periodLabel() const override { return QStringLiteral("5-hour"); }
    void checkToolInstalled() override { setInstalled(true); }
    void detectActivity() override { /* no-op */ }
    QStringList availablePlans() const override { return {QStringLiteral("Free"), QStringLiteral("Pro")}; }
    int defaultLimitForPlan(const QString &plan) const override {
        return plan == QStringLiteral("Pro") ? 300 : 50;
    }

    // Allow tests to enable secondary limit
    void setHasSecondary(bool has) { m_hasSecondary = has; }
    bool hasSecondaryLimit() const override { return m_hasSecondary; }
    QString secondaryPeriodLabel() const override { return QStringLiteral("weekly"); }

    // Expose protected methods
    using SubscriptionToolBackend::setInstalled;
    using SubscriptionToolBackend::setUsageCount;
    using SubscriptionToolBackend::setSecondaryUsageCount;
    using SubscriptionToolBackend::setPeriodStart;
    using SubscriptionToolBackend::setSecondaryPeriodStart;
    using SubscriptionToolBackend::calculatePeriodEnd;
    using SubscriptionToolBackend::checkAndResetPeriod;
    using SubscriptionToolBackend::networkManager;

protected:
    UsagePeriod primaryPeriodType() const override { return FiveHour; }
    UsagePeriod secondaryPeriodType() const override { return Weekly; }

private:
    bool m_hasSecondary;
};

class SubscriptionToolBackendTest : public QObject
{
    Q_OBJECT

private Q_SLOTS:
    void testIncrementUsage();
    void testResetUsage();
    void testPercentUsed();
    void testLimitReached();
    void testLimitReachedSignal();
    void testLimitWarningSignal();
    void testCalculatePeriodEndFiveHour();
    void testCalculatePeriodEndDaily();
    void testCalculatePeriodEndWeekly();
    void testCalculatePeriodEndMonthly();
    void testCalculatePeriodEndInvalidStart();
    void testSecondaryUsageTracking();
    void testCheckAndResetPeriod();
    void testDefaultLimitForPlan();
    void testTimeUntilResetFormat();
    void testUsesResilientNetworkManager();
    void testActiveSecondsBetween();
    void testProjectedPercentAtReset();
    void testPaceLevelFor();
    void testSecondaryPaceProperties();
};

namespace {
QDateTime mountain(int y, int m, int d, int h, int min = 0)
{
    return QDateTime(QDate(y, m, d), QTime(h, min), QTimeZone(QByteArrayLiteral("America/Denver")));
}
constexpr qint64 kHour = 3600;
}

void SubscriptionToolBackendTest::testActiveSecondsBetween()
{
    // A full week counts 16 active hours (06:00–22:00) per day.
    QCOMPARE(SubscriptionToolBackend::activeSecondsBetween(mountain(2026, 1, 12, 0), mountain(2026, 1, 19, 0)),
             7 * 16 * kHour);
    // Still 16 h/day across the DST switch (2026-03-08), since 06:00 and 22:00 are local.
    QCOMPARE(SubscriptionToolBackend::activeSecondsBetween(mountain(2026, 3, 5, 0), mountain(2026, 3, 12, 0)),
             7 * 16 * kHour);
    // Overnight is inactive.
    QCOMPARE(SubscriptionToolBackend::activeSecondsBetween(mountain(2026, 1, 12, 22), mountain(2026, 1, 13, 6)), 0);
    // Partial overlap at both ends: 20:00–22:00 plus 06:00–09:30.
    QCOMPARE(SubscriptionToolBackend::activeSecondsBetween(mountain(2026, 1, 12, 20), mountain(2026, 1, 13, 9, 30)),
             2 * kHour + 3 * kHour + 30 * 60);
    // The zone conversion works for UTC inputs too (13:00Z = 06:00 MST).
    QCOMPARE(SubscriptionToolBackend::activeSecondsBetween(
                 QDateTime(QDate(2026, 1, 12), QTime(13, 0), QTimeZone::utc()),
                 QDateTime(QDate(2026, 1, 12), QTime(14, 0), QTimeZone::utc())),
             kHour);
    QCOMPARE(SubscriptionToolBackend::activeSecondsBetween(mountain(2026, 1, 13, 0), mountain(2026, 1, 12, 0)), 0);
    QCOMPARE(SubscriptionToolBackend::activeSecondsBetween(QDateTime(), mountain(2026, 1, 12, 0)), 0);
}

void SubscriptionToolBackendTest::testProjectedPercentAtReset()
{
    // Window Mon 06:00 → next Mon 06:00: 112 active hours.
    const QDateTime start = mountain(2026, 1, 12, 6);
    const QDateTime end = start.addDays(7);
    // Wed 22:00: three active days (48 h) elapsed.
    const QDateTime wedNight = mountain(2026, 1, 14, 22);
    QCOMPARE(SubscriptionToolBackend::projectedPercentAtReset(30, start, end, wedNight), 30.0 * 112 / 48);

    // Overnight the projection holds steady instead of drifting greener.
    QCOMPARE(SubscriptionToolBackend::projectedPercentAtReset(30, start, end, mountain(2026, 1, 15, 3)),
             30.0 * 112 / 48);

    // Early in the window, elapsed time is floored at 4 active hours.
    QCOMPARE(SubscriptionToolBackend::projectedPercentAtReset(2, start, end, start.addSecs(30 * 60)),
             2.0 * 112 / 4);

    // After the window ends, the projection is just what was used.
    QCOMPARE(SubscriptionToolBackend::projectedPercentAtReset(60, start, end, end.addDays(1)), 60.0);

    QCOMPARE(SubscriptionToolBackend::projectedPercentAtReset(0, start, end, wedNight), 0.0);
    // Unknown window: fall back to the raw percentage.
    QCOMPARE(SubscriptionToolBackend::projectedPercentAtReset(42, QDateTime(), QDateTime(), wedNight), 42.0);
}

void SubscriptionToolBackendTest::testPaceLevelFor()
{
    QCOMPARE(SubscriptionToolBackend::paceLevelFor(0), SubscriptionToolBackend::PaceOk);
    QCOMPARE(SubscriptionToolBackend::paceLevelFor(84.9), SubscriptionToolBackend::PaceOk);
    QCOMPARE(SubscriptionToolBackend::paceLevelFor(85), SubscriptionToolBackend::PaceWarning);
    QCOMPARE(SubscriptionToolBackend::paceLevelFor(99.9), SubscriptionToolBackend::PaceWarning);
    QCOMPARE(SubscriptionToolBackend::paceLevelFor(100), SubscriptionToolBackend::PaceCritical);
    QCOMPARE(SubscriptionToolBackend::paceLevelFor(250), SubscriptionToolBackend::PaceCritical);
}

void SubscriptionToolBackendTest::testSecondaryPaceProperties()
{
    TestToolBackend t;
    t.setHasSecondary(true);
    t.setSecondaryUsageLimit(100);

    // A window that just ended: the projection equals usage.
    t.setSecondaryPeriodStart(QDateTime::currentDateTimeUtc().addDays(-7).addSecs(-60));
    t.setSecondaryUsageCount(90);
    QCOMPARE(t.secondaryProjectedPercent(), 90.0);
    QCOMPARE(t.secondaryPaceLevel(), static_cast<int>(SubscriptionToolBackend::PaceWarning));
    t.setSecondaryUsageCount(100);
    QCOMPARE(t.secondaryPaceLevel(), static_cast<int>(SubscriptionToolBackend::PaceCritical));

    // A burn rate that outruns the window goes red even at low absolute usage.
    t.setSecondaryPeriodStart(QDateTime::currentDateTimeUtc());
    t.setSecondaryUsageCount(30);
    QVERIFY(t.secondaryProjectedPercent() >= 100.0);
    QCOMPARE(t.secondaryPaceLevel(), static_cast<int>(SubscriptionToolBackend::PaceCritical));

    // The 5-hour primary window isn't paced.
    t.setUsageLimit(100);
    QCOMPARE(t.paceLevel(), static_cast<int>(SubscriptionToolBackend::PaceNone));
    QCOMPARE(t.projectedPercent(), t.percentUsed());

    QSignalSpy paceSpy(&t, &SubscriptionToolBackend::paceUpdated);
    Q_EMIT t.usageUpdated();
    QCOMPARE(paceSpy.count(), 1);
}

void SubscriptionToolBackendTest::testUsesResilientNetworkManager()
{
    TestToolBackend t;
    QVERIFY(dynamic_cast<ResilientNetworkAccessManager *>(t.networkManager()) != nullptr);
}

void SubscriptionToolBackendTest::testIncrementUsage()
{
    TestToolBackend t;
    t.setUsageLimit(100);
    t.setPeriodStart(QDateTime::currentDateTimeUtc());

    QSignalSpy usageSpy(&t, &SubscriptionToolBackend::usageUpdated);
    QSignalSpy activitySpy(&t, &SubscriptionToolBackend::activityDetected);

    t.incrementUsage();

    QCOMPARE(t.usageCount(), 1);
    QVERIFY(usageSpy.count() >= 1);
    QCOMPARE(activitySpy.count(), 1);
    QCOMPARE(activitySpy.first().at(0).toString(), QStringLiteral("TestTool"));
    QVERIFY(t.lastActivity().isValid());
}

void SubscriptionToolBackendTest::testResetUsage()
{
    TestToolBackend t;
    t.setPeriodStart(QDateTime::currentDateTimeUtc());
    t.setUsageLimit(100);
    t.incrementUsage();
    t.incrementUsage();
    QCOMPARE(t.usageCount(), 2);

    QSignalSpy usageSpy(&t, &SubscriptionToolBackend::usageUpdated);
    t.resetUsage();

    QCOMPARE(t.usageCount(), 0);
    QVERIFY(t.periodStart().isValid());
    QVERIFY(usageSpy.count() >= 1);
}

void SubscriptionToolBackendTest::testPercentUsed()
{
    TestToolBackend t;

    // Zero limit — should return 0
    QVERIFY(qAbs(t.percentUsed()) < 0.01);

    t.setUsageLimit(100);
    t.setUsageCount(50);
    QVERIFY(qAbs(t.percentUsed() - 50.0) < 0.01);

    t.setUsageCount(100);
    QVERIFY(qAbs(t.percentUsed() - 100.0) < 0.01);
}

void SubscriptionToolBackendTest::testLimitReached()
{
    TestToolBackend t;
    t.setUsageLimit(5);

    QVERIFY(!t.isLimitReached());
    t.setUsageCount(4);
    QVERIFY(!t.isLimitReached());
    t.setUsageCount(5);
    QVERIFY(t.isLimitReached());
    t.setUsageCount(6);
    QVERIFY(t.isLimitReached());
}

void SubscriptionToolBackendTest::testLimitReachedSignal()
{
    TestToolBackend t;
    t.setUsageLimit(3);
    t.setPeriodStart(QDateTime::currentDateTimeUtc());

    QSignalSpy limitSpy(&t, &SubscriptionToolBackend::limitReached);

    t.incrementUsage(); // 1
    t.incrementUsage(); // 2
    QCOMPARE(limitSpy.count(), 0);

    t.incrementUsage(); // 3 — limit reached
    QCOMPARE(limitSpy.count(), 1);
    QCOMPARE(limitSpy.first().at(0).toString(), QStringLiteral("TestTool"));
}

void SubscriptionToolBackendTest::testLimitWarningSignal()
{
    TestToolBackend t;
    t.setUsageLimit(10);
    t.setPeriodStart(QDateTime::currentDateTimeUtc());

    QSignalSpy warningSpy(&t, &SubscriptionToolBackend::limitWarning);

    // Increment to 7 — no warning yet (70%)
    for (int i = 0; i < 7; ++i) t.incrementUsage();
    QCOMPARE(warningSpy.count(), 0);

    // Increment to 8 — 80% triggers warning
    t.incrementUsage();
    QCOMPARE(warningSpy.count(), 1);
    QCOMPARE(warningSpy.first().at(0).toString(), QStringLiteral("TestTool"));
    QCOMPARE(warningSpy.first().at(1).toInt(), 80);
}

void SubscriptionToolBackendTest::testCalculatePeriodEndFiveHour()
{
    TestToolBackend t;
    QDateTime start(QDate(2026, 1, 15), QTime(10, 0, 0), QTimeZone::utc());
    QDateTime end = t.calculatePeriodEnd(SubscriptionToolBackend::FiveHour, start);

    QCOMPARE(end, start.addSecs(5 * 3600));
}

void SubscriptionToolBackendTest::testCalculatePeriodEndDaily()
{
    TestToolBackend t;
    QDateTime start(QDate(2026, 1, 15), QTime(10, 0, 0), QTimeZone::utc());
    QDateTime end = t.calculatePeriodEnd(SubscriptionToolBackend::Daily, start);

    QCOMPARE(end, start.addDays(1));
}

void SubscriptionToolBackendTest::testCalculatePeriodEndWeekly()
{
    TestToolBackend t;
    QDateTime start(QDate(2026, 1, 15), QTime(10, 0, 0), QTimeZone::utc());
    QDateTime end = t.calculatePeriodEnd(SubscriptionToolBackend::Weekly, start);

    QCOMPARE(end, start.addDays(7));
}

void SubscriptionToolBackendTest::testCalculatePeriodEndMonthly()
{
    TestToolBackend t;
    QDateTime start(QDate(2026, 1, 15), QTime(10, 0, 0), QTimeZone::utc());
    QDateTime end = t.calculatePeriodEnd(SubscriptionToolBackend::Monthly, start);

    // Should be 1st of next month at 00:00 UTC
    QDateTime expected(QDate(2026, 2, 1), QTime(0, 0, 0), QTimeZone::utc());
    QCOMPARE(end, expected);
}

void SubscriptionToolBackendTest::testCalculatePeriodEndInvalidStart()
{
    TestToolBackend t;
    QDateTime end = t.calculatePeriodEnd(SubscriptionToolBackend::FiveHour, QDateTime());
    QVERIFY(!end.isValid());
}

void SubscriptionToolBackendTest::testSecondaryUsageTracking()
{
    TestToolBackend t;
    t.setHasSecondary(true);
    t.setSecondaryUsageLimit(100);
    t.setPeriodStart(QDateTime::currentDateTimeUtc());
    t.setSecondaryPeriodStart(QDateTime::currentDateTimeUtc());
    t.setUsageLimit(50);

    // Increment should bump both primary and secondary
    t.incrementUsage();
    QCOMPARE(t.usageCount(), 1);
    QCOMPARE(t.secondaryUsageCount(), 1);

    t.setSecondaryUsageCount(99);
    QVERIFY(!t.isSecondaryLimitReached());
    t.setSecondaryUsageCount(100);
    QVERIFY(t.isSecondaryLimitReached());

    QVERIFY(qAbs(t.secondaryPercentUsed() - 100.0) < 0.01);
}

void SubscriptionToolBackendTest::testCheckAndResetPeriod()
{
    TestToolBackend t;
    // Set period start to 6 hours ago (past the 5-hour window)
    QDateTime oldStart = QDateTime::currentDateTimeUtc().addSecs(-6 * 3600);
    t.setPeriodStart(oldStart);
    t.setUsageLimit(100);
    t.setUsageCount(42);

    QSignalSpy usageSpy(&t, &SubscriptionToolBackend::usageUpdated);
    t.checkAndResetPeriod();

    // Usage should be reset because the period expired
    QCOMPARE(t.usageCount(), 0);
    QVERIFY(usageSpy.count() >= 1);
    // Period start should be updated to now (approximately)
    QVERIFY(t.periodStart().secsTo(QDateTime::currentDateTimeUtc()) < 2);
}

void SubscriptionToolBackendTest::testDefaultLimitForPlan()
{
    TestToolBackend t;
    QCOMPARE(t.defaultLimitForPlan(QStringLiteral("Pro")), 300);
    QCOMPARE(t.defaultLimitForPlan(QStringLiteral("Free")), 50);
}

void SubscriptionToolBackendTest::testTimeUntilResetFormat()
{
    TestToolBackend t;
    // Set period start to now — 5 hours from now
    t.setPeriodStart(QDateTime::currentDateTimeUtc());

    int secs = t.secondsUntilReset();
    // Should be approximately 5 hours (18000 secs) ± a few seconds
    QVERIFY(secs > 17990 && secs <= 18000);

    QString timeStr = t.timeUntilReset();
    // Should contain hours and minutes
    QVERIFY(timeStr.contains(QLatin1Char('h')));
}

QTEST_MAIN(SubscriptionToolBackendTest)
#include "test_subscriptiontoolbackend.moc"
