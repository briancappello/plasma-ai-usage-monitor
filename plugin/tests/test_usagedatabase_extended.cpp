#include <QtTest>

#include <QTemporaryDir>
#include <QJsonDocument>
#include <QJsonArray>
#include <QJsonObject>
#include <QSqlDatabase>
#include <QSqlQuery>
#include <QStandardPaths>
#include <QUuid>

#include "usagedatabase.h"

namespace {
/**
 * Directly update a snapshot timestamp for test purposes.
 */
bool setSnapshotTimestamp(const QString &provider, double cost, const QString &timestamp)
{
    const QString connName = QStringLiteral("ext_test_%1").arg(QUuid::createUuid().toString(QUuid::WithoutBraces));
    bool ok = false;
    {
        QSqlDatabase db = QSqlDatabase::addDatabase(QStringLiteral("QSQLITE"), connName);
        db.setDatabaseName(
            QStandardPaths::writableLocation(QStandardPaths::GenericDataLocation)
            + QStringLiteral("/plasma-ai-usage-monitor/usage_history.db"));
        if (db.open()) {
            QSqlQuery query(db);
            query.prepare(QStringLiteral(
                "UPDATE usage_snapshots SET timestamp = ? WHERE provider = ? AND ABS(cost - ?) < 0.00001"));
            query.addBindValue(timestamp);
            query.addBindValue(provider);
            query.addBindValue(cost);
            ok = query.exec() && query.numRowsAffected() > 0;
            db.close();
        }
    }
    QSqlDatabase::removeDatabase(connName);
    return ok;
}
} // namespace

class UsageDatabaseExtendedTest : public QObject
{
    Q_OBJECT

private Q_SLOTS:
    void testRetentionDaysClamping();
    void testGetProviders();
    void testGetToolNames();
    void testExportCsv();
    void testExportJson();
    void testGetSummary();
    void testGetDailyCosts();
    void testPruneOldData();
    void testDisabledRecording();
};

void UsageDatabaseExtendedTest::testRetentionDaysClamping()
{
    UsageDatabase db;

    db.setRetentionDays(0);
    QCOMPARE(db.retentionDays(), 1);

    db.setRetentionDays(-10);
    QCOMPARE(db.retentionDays(), 1);

    db.setRetentionDays(500);
    QCOMPARE(db.retentionDays(), 365);

    db.setRetentionDays(90);
    QCOMPARE(db.retentionDays(), 90);
}

void UsageDatabaseExtendedTest::testGetProviders()
{
    QTemporaryDir tmp;
    QVERIFY(tmp.isValid());
    qputenv("XDG_DATA_HOME", tmp.path().toUtf8());

    UsageDatabase db;
    db.init();

    db.recordSnapshot(QStringLiteral("OpenAI"), 100, 50, 10, 1.0, 1.0, 10.0, 100, 90, 1000, 950);
    db.recordSnapshot(QStringLiteral("Anthropic"), 200, 100, 20, 2.0, 2.0, 20.0, 50, 40, 500, 400);

    // Wait past throttle for different provider
    QStringList providers = db.getProviders();
    QVERIFY(providers.contains(QStringLiteral("OpenAI")));
    QVERIFY(providers.contains(QStringLiteral("Anthropic")));
}

void UsageDatabaseExtendedTest::testGetToolNames()
{
    QTemporaryDir tmp;
    QVERIFY(tmp.isValid());
    qputenv("XDG_DATA_HOME", tmp.path().toUtf8());

    UsageDatabase db;
    db.init();

    db.recordToolSnapshot(QStringLiteral("Claude Code"), 10, 45, QStringLiteral("5-hour"), QStringLiteral("Pro"), false);
    db.recordToolSnapshot(QStringLiteral("Copilot"), 5, 300, QStringLiteral("monthly"), QStringLiteral("Pro"), false);

    QStringList tools = db.getToolNames();
    QVERIFY(tools.contains(QStringLiteral("Claude Code")));
    QVERIFY(tools.contains(QStringLiteral("Copilot")));
}

void UsageDatabaseExtendedTest::testExportCsv()
{
    QTemporaryDir tmp;
    QVERIFY(tmp.isValid());
    qputenv("XDG_DATA_HOME", tmp.path().toUtf8());

    UsageDatabase db;
    db.init();

    db.recordSnapshot(QStringLiteral("OpenAI"), 100, 50, 10, 1.5, 1.5, 15.0, 100, 90, 1000, 950);

    const QDateTime from = QDateTime::currentDateTimeUtc().addSecs(-3600);
    const QDateTime to = QDateTime::currentDateTimeUtc().addSecs(3600);

    QString csv = db.exportCsv(QStringLiteral("OpenAI"), from, to);
    QVERIFY(!csv.isEmpty());

    // Check CSV has header row
    QStringList lines = csv.split(QLatin1Char('\n'), Qt::SkipEmptyParts);
    QVERIFY(lines.size() >= 2); // header + at least 1 data row

    // Header should contain expected column names
    QString header = lines.first();
    QVERIFY(header.contains(QStringLiteral("timestamp")));
    QVERIFY(header.contains(QStringLiteral("cost")));
}

void UsageDatabaseExtendedTest::testExportJson()
{
    QTemporaryDir tmp;
    QVERIFY(tmp.isValid());
    qputenv("XDG_DATA_HOME", tmp.path().toUtf8());

    UsageDatabase db;
    db.init();

    db.recordSnapshot(QStringLiteral("OpenAI"), 200, 100, 20, 3.0, 3.0, 30.0, 100, 80, 1000, 800);

    const QDateTime from = QDateTime::currentDateTimeUtc().addSecs(-3600);
    const QDateTime to = QDateTime::currentDateTimeUtc().addSecs(3600);

    QString jsonStr = db.exportJson(QStringLiteral("OpenAI"), from, to);
    QVERIFY(!jsonStr.isEmpty());

    // Parse and validate JSON structure — exportJson wraps data in a root object
    QJsonDocument doc = QJsonDocument::fromJson(jsonStr.toUtf8());
    QVERIFY(doc.isObject());

    QJsonObject root = doc.object();
    QCOMPARE(root.value(QStringLiteral("provider")).toString(), QStringLiteral("OpenAI"));
    QVERIFY(root.contains(QStringLiteral("from")));
    QVERIFY(root.contains(QStringLiteral("to")));
    QVERIFY(root.contains(QStringLiteral("snapshots")));

    QJsonArray arr = root.value(QStringLiteral("snapshots")).toArray();
    QVERIFY(arr.size() >= 1);

    QJsonObject first = arr.first().toObject();
    QVERIFY(first.contains(QStringLiteral("timestamp")));
    QVERIFY(first.contains(QStringLiteral("cost")));
    QVERIFY(qAbs(first.value(QStringLiteral("cost")).toDouble() - 3.0) < 0.01);
}

void UsageDatabaseExtendedTest::testGetSummary()
{
    QTemporaryDir tmp;
    QVERIFY(tmp.isValid());
    qputenv("XDG_DATA_HOME", tmp.path().toUtf8());

    UsageDatabase db;
    db.init();

    db.recordSnapshot(QStringLiteral("TestProv"), 100, 50, 5, 1.0, 1.0, 10.0, 100, 90, 1000, 950);
    // Need to bypass write throttling for second snapshot — use different cost
    db.recordSnapshot(QStringLiteral("TestProv"), 300, 200, 15, 3.0, 3.0, 30.0, 100, 70, 1000, 700);

    const QDateTime from = QDateTime::currentDateTimeUtc().addSecs(-3600);
    const QDateTime to = QDateTime::currentDateTimeUtc().addSecs(3600);

    QVariantMap summary = db.getSummary(QStringLiteral("TestProv"), from, to);
    QVERIFY(!summary.isEmpty());
    QVERIFY(summary.contains(QStringLiteral("snapshotCount")));

    // Should have at least 1 snapshot (throttle may skip the second if same provider within 60s)
    QVERIFY(summary.value(QStringLiteral("snapshotCount")).toInt() >= 1);
}

void UsageDatabaseExtendedTest::testGetDailyCosts()
{
    QTemporaryDir tmp;
    QVERIFY(tmp.isValid());
    qputenv("XDG_DATA_HOME", tmp.path().toUtf8());

    UsageDatabase db;
    db.init();

    db.recordSnapshot(QStringLiteral("DailyCostProv"), 100, 50, 10, 5.0, 5.0, 50.0, 0, 0, 0, 0);

    // Backdate the snapshot to yesterday
    QVERIFY(setSnapshotTimestamp(QStringLiteral("DailyCostProv"), 5.0,
                                  QDateTime::currentDateTimeUtc().addDays(-1).toString(QStringLiteral("yyyy-MM-dd hh:mm:ss"))));

    // Insert another for today (different cost to bypass throttle)
    db.recordSnapshot(QStringLiteral("DailyCostProv"), 200, 100, 20, 8.0, 8.0, 80.0, 0, 0, 0, 0);

    const QDateTime from = QDateTime::currentDateTimeUtc().addDays(-2);
    const QDateTime to = QDateTime::currentDateTimeUtc().addSecs(3600);

    QVariantList dailyCosts = db.getDailyCosts(QStringLiteral("DailyCostProv"), from, to);
    QVERIFY(dailyCosts.size() >= 1);
}

void UsageDatabaseExtendedTest::testPruneOldData()
{
    QTemporaryDir tmp;
    QVERIFY(tmp.isValid());
    qputenv("XDG_DATA_HOME", tmp.path().toUtf8());

    UsageDatabase db;
    db.init();
    db.setRetentionDays(1);

    db.recordSnapshot(QStringLiteral("PruneProv"), 100, 50, 10, 1.0, 1.0, 10.0, 0, 0, 0, 0);

    // Backdate the snapshot to 5 days ago (beyond 1-day retention)
    QVERIFY(setSnapshotTimestamp(QStringLiteral("PruneProv"), 1.0,
                                  QDateTime::currentDateTimeUtc().addDays(-5).toString(QStringLiteral("yyyy-MM-dd hh:mm:ss"))));

    // Insert a recent one (different cost to bypass throttle)
    db.recordSnapshot(QStringLiteral("PruneProv"), 200, 100, 20, 9.0, 9.0, 90.0, 0, 0, 0, 0);

    db.pruneOldData();

    const QDateTime from = QDateTime::currentDateTimeUtc().addDays(-10);
    const QDateTime to = QDateTime::currentDateTimeUtc().addSecs(3600);
    QVariantList snapshots = db.getSnapshots(QStringLiteral("PruneProv"), from, to);

    // Old snapshot should be pruned, recent one kept
    QCOMPARE(snapshots.size(), 1);
    QVERIFY(qAbs(snapshots.first().toMap().value(QStringLiteral("cost")).toDouble() - 9.0) < 0.01);
}

void UsageDatabaseExtendedTest::testDisabledRecording()
{
    QTemporaryDir tmp;
    QVERIFY(tmp.isValid());
    qputenv("XDG_DATA_HOME", tmp.path().toUtf8());

    UsageDatabase db;
    db.init();
    db.setEnabled(false);

    db.recordSnapshot(QStringLiteral("DisabledProv"), 100, 50, 10, 1.0, 1.0, 10.0, 0, 0, 0, 0);

    const QDateTime from = QDateTime::currentDateTimeUtc().addSecs(-3600);
    const QDateTime to = QDateTime::currentDateTimeUtc().addSecs(3600);
    QVariantList snapshots = db.getSnapshots(QStringLiteral("DisabledProv"), from, to);

    QCOMPARE(snapshots.size(), 0);
}

QTEST_MAIN(UsageDatabaseExtendedTest)
#include "test_usagedatabase_extended.moc"
