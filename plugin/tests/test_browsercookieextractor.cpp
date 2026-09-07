#include "browsercookieextractor.h"

#include <QCoreApplication>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QElapsedTimer>
#include <QSqlDatabase>
#include <QSqlQuery>
#include <QTemporaryDir>
#include <QTest>

class TestBrowserCookieExtractor : public QObject
{
    Q_OBJECT

private Q_SLOTS:
    void initTestCase()
    {
        const QString profile = QDir::homePath() + QStringLiteral("/.mozilla/firefox/test.default-release");
        QVERIFY(QDir().mkpath(profile));
        m_path = profile + QStringLiteral("/cookies.sqlite");
        m_writer = QSqlDatabase::addDatabase(QStringLiteral("QSQLITE"), QStringLiteral("synthetic_writer"));
        m_writer.setDatabaseName(m_path);
        QVERIFY(m_writer.open());
        QSqlQuery query(m_writer);
        QVERIFY(query.exec(QStringLiteral("CREATE TABLE moz_cookies (host TEXT, name TEXT, value TEXT, expiry INTEGER)")));
    }

    void init()
    {
        QSqlQuery query(m_writer);
        QVERIFY(query.exec(QStringLiteral("DELETE FROM moz_cookies")));
    }

    void sessionDetection_data()
    {
        QTest::addColumn<QStringList>("names");
        QTest::addColumn<QString>("value");
        QTest::addColumn<QString>("expected");
        const QString token = QStringLiteral("__Secure-next-auth.session-token");
        QTest::newRow("unchunked") << QStringList{token} << QStringLiteral("synthetic") << QStringLiteral("connected");
        QTest::newRow("chunked") << QStringList{token + ".0", token + ".1"} << QStringLiteral("synthetic") << QStringLiteral("connected");
        QTest::newRow("callback-only") << QStringList{QStringLiteral("__Secure-next-auth.callback-url")}
                                     << QStringLiteral("https://chatgpt.com") << QStringLiteral("session_missing_or_expired");
        QTest::newRow("empty-token") << QStringList{token} << QString() << QStringLiteral("session_missing_or_expired");
        QTest::newRow("missing-first-chunk") << QStringList{token + ".1"} << QStringLiteral("synthetic") << QStringLiteral("session_missing_or_expired");
        QTest::newRow("unrelated-suffix") << QStringList{token + ".other"} << QStringLiteral("synthetic") << QStringLiteral("session_missing_or_expired");
    }

    void sessionDetection()
    {
        QFETCH(QStringList, names);
        QFETCH(QString, value);
        QFETCH(QString, expected);
        for (const QString &name : names) {
            QSqlQuery query(m_writer);
            query.prepare(QStringLiteral("INSERT INTO moz_cookies VALUES ('.chatgpt.com', ?, ?, 0)"));
            query.addBindValue(name);
            query.addBindValue(value);
            QVERIFY(query.exec());
        }
        QSqlQuery query(m_writer);
        QVERIFY(query.exec(QStringLiteral("INSERT INTO moz_cookies SELECT '.claude.ai', name, value, expiry FROM moz_cookies")));
        BrowserCookieExtractor extractor;
        QCOMPARE(extractor.testConnection(QStringLiteral("chatgpt")), expected);
        QCOMPARE(extractor.testConnection(QStringLiteral("codex")), expected);
        QCOMPARE(extractor.testConnection(QStringLiteral("claude")), expected);
        for (const QString &name : names) {
            QVERIFY(extractor.getCookieHeader(QStringLiteral("chatgpt.com")).contains(name + '=' + value));
        }
    }

    void readsFreshWalCookies()
    {
        QSqlQuery query(m_writer);
        QVERIFY(query.exec(QStringLiteral("PRAGMA locking_mode=EXCLUSIVE")));
        query.finish();
        QVERIFY(query.exec(QStringLiteral("PRAGMA journal_mode=WAL")));
        QVERIFY(query.next());
        QCOMPARE(query.value(0).toString(), QStringLiteral("wal"));
        query.finish();
        QVERIFY(query.exec(QStringLiteral("PRAGMA wal_autocheckpoint=0")));
        QVERIFY(query.exec(QStringLiteral("PRAGMA wal_checkpoint(TRUNCATE)")));
        query.finish();
        QVERIFY(query.exec(QStringLiteral("INSERT INTO moz_cookies VALUES "
                                         "('.chatgpt.com', '__Secure-next-auth.session-token.0', 'fresh-zero', 0),"
                                         "('chatgpt.com', '__Secure-next-auth.session-token.1', 'fresh-one', 0),"
                                         "('.chatgpt.com', 'expired', 'excluded', 1),"
                                         "('other.example', 'unrelated', 'excluded', 0)")));
        QVERIFY(QFileInfo(m_path + QStringLiteral("-wal")).size() > 0);
        QFile database(m_path);
        QFile wal(m_path + QStringLiteral("-wal"));
        QVERIFY(database.open(QIODevice::ReadOnly));
        QVERIFY(wal.open(QIODevice::ReadOnly));
        const QByteArray databaseBefore = database.readAll();
        const QByteArray walBefore = wal.readAll();
        const auto permissionsBefore = database.permissions();

        BrowserCookieExtractor extractor;
        QElapsedTimer elapsed;
        elapsed.start();
        QCOMPARE(extractor.getCookie(QStringLiteral("chatgpt.com"), QStringLiteral("__Secure-next-auth.session-token.0")),
                 QStringLiteral("fresh-zero"));
        QVERIFY2(elapsed.elapsed() < 1000, "Firefox's exclusive lock must not block the UI thread");
        QCOMPARE(extractor.getCookieHeader(QStringLiteral("chatgpt.com")),
                 QStringLiteral("__Secure-next-auth.session-token.0=fresh-zero; __Secure-next-auth.session-token.1=fresh-one"));
        QCOMPARE(extractor.testConnection(QStringLiteral("chatgpt")), QStringLiteral("connected"));
        QVERIFY(m_writer.isOpen());
        QVERIFY(database.seek(0));
        QVERIFY(wal.seek(0));
        QCOMPARE(database.readAll(), databaseBefore);
        QCOMPARE(wal.readAll(), walBefore);
        QCOMPARE(database.permissions(), permissionsBefore);
    }

    void cleanupTestCase()
    {
        m_writer.close();
        m_writer = QSqlDatabase();
        QSqlDatabase::removeDatabase(QStringLiteral("synthetic_writer"));
    }

private:
    QSqlDatabase m_writer;
    QString m_path;
};

int main(int argc, char **argv)
{
    QTemporaryDir home;
    if (!home.isValid() || !qputenv("HOME", home.path().toUtf8())) {
        return 1;
    }
    QCoreApplication app(argc, argv);
    if (QDir::homePath() != home.path()) {
        return 1;
    }
    TestBrowserCookieExtractor test;
    return QTest::qExec(&test, argc, argv);
}

#include "test_browsercookieextractor.moc"
