#include <QtTest>
#include <QHostInfo>
#include <QNetworkReply>
#include <QTcpServer>
#include <QTcpSocket>

#include "resilientnetworkaccessmanager.h"

namespace {

// Minimal keep-alive HTTP server: answers every request with "ok".
class TinyHttpServer : public QTcpServer
{
public:
    using QTcpServer::QTcpServer;

    bool start(const QHostAddress &address, quint16 port)
    {
        connect(this, &QTcpServer::newConnection, this, [this]() {
            while (QTcpSocket *socket = nextPendingConnection()) {
                socket->setParent(this);
                connect(socket, &QTcpSocket::readyRead, socket, [socket]() {
                    if (socket->readAll().contains("\r\n\r\n")) {
                        socket->write("HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\nok");
                    }
                });
            }
        });
        return listen(address, port);
    }
};

QNetworkReply::NetworkError get(QNetworkAccessManager &nam, quint16 port)
{
    QNetworkReply *reply = nam.get(QNetworkRequest(QUrl(QStringLiteral("http://localhost:%1/").arg(port))));
    QSignalSpy finished(reply, &QNetworkReply::finished);
    if (!finished.wait(10000)) {
        reply->abort();
    }
    const auto error = reply->error();
    reply->deleteLater();
    return error;
}

bool localhostHasBothFamilies()
{
    bool v4 = false;
    bool v6 = false;
    for (const QHostAddress &a : QHostInfo::fromName(QStringLiteral("localhost")).addresses()) {
        v4 |= a.protocol() == QAbstractSocket::IPv4Protocol;
        v6 |= a.protocol() == QAbstractSocket::IPv6Protocol;
    }
    return v4 && v6;
}

} // namespace

class ResilientNetworkAccessManagerTest : public QObject
{
    Q_OBJECT

private:
    // Pins the manager's cached connection to IPv6, then moves the server to
    // IPv4 only (simulating a network without IPv6 routing) and returns the
    // result of the next request once the short idle expiry has elapsed.
    QNetworkReply::NetworkError requestAfterFamilySwitch(QNetworkAccessManager &nam)
    {
        auto server6 = std::make_unique<TinyHttpServer>();
        if (!server6->start(QHostAddress::LocalHostIPv6, 0)) {
            qWarning() << "cannot listen on ::1";
            return QNetworkReply::UnknownNetworkError;
        }
        const quint16 port = server6->serverPort();

        if (get(nam, port) != QNetworkReply::NoError) {
            return QNetworkReply::UnknownNetworkError;
        }

        server6.reset();
        TinyHttpServer server4;
        if (!server4.start(QHostAddress::LocalHost, port)) {
            qWarning() << "cannot listen on 127.0.0.1";
            return QNetworkReply::UnknownNetworkError;
        }

        QTest::qWait(2500);
        return get(nam, port);
    }

private Q_SLOTS:
    void initTestCase()
    {
        if (!localhostHasBothFamilies()) {
            QSKIP("localhost must resolve to both 127.0.0.1 and ::1");
        }
    }

    void plainManagerStaysPinnedToFirstFamily()
    {
        // Documents the Qt behaviour the wrapper works around.
        QNetworkAccessManager nam;
        QCOMPARE(requestAfterFamilySwitch(nam), QNetworkReply::ConnectionRefusedError);
    }

    void resilientManagerRecoversAfterNetworkChange()
    {
        ResilientNetworkAccessManager nam(nullptr, 1);
        QCOMPARE(requestAfterFamilySwitch(nam), QNetworkReply::NoError);
    }
};

QTEST_MAIN(ResilientNetworkAccessManagerTest)
#include "test_resilientnetworkaccessmanager.moc"
