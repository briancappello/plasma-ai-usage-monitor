#ifndef RESILIENTNETWORKACCESSMANAGER_H
#define RESILIENTNETWORKACCESSMANAGER_H

#include <QNetworkAccessManager>
#include <QNetworkRequest>

/**
 * QNetworkAccessManager that limits how long idle HTTP connections stay cached.
 *
 * Qt pins a cached connection to the address family (IPv4 or IPv6) that won its
 * first Happy Eyeballs race, and keeps it for 120 s after each use. A widget
 * that polls more often than that never lets the entry expire, so after a
 * network change (e.g. a laptop moving to a network without IPv6 routing)
 * every request fails with "Network unreachable" until plasmashell restarts.
 * A short expiry makes each poll start a fresh lookup and race.
 */
class ResilientNetworkAccessManager : public QNetworkAccessManager
{
public:
    static constexpr int DefaultIdleExpirySeconds = 30;

    explicit ResilientNetworkAccessManager(QObject *parent = nullptr,
                                           int idleExpirySeconds = DefaultIdleExpirySeconds)
        : QNetworkAccessManager(parent)
        , m_idleExpirySeconds(idleExpirySeconds)
    {
    }

    int idleExpirySeconds() const { return m_idleExpirySeconds; }

protected:
    QNetworkReply *createRequest(Operation op, const QNetworkRequest &originalReq,
                                 QIODevice *outgoingData = nullptr) override
    {
        QNetworkRequest request(originalReq);
        if (!request.attribute(QNetworkRequest::ConnectionCacheExpiryTimeoutSecondsAttribute).isValid()) {
            request.setAttribute(QNetworkRequest::ConnectionCacheExpiryTimeoutSecondsAttribute,
                                 m_idleExpirySeconds);
        }
        return QNetworkAccessManager::createRequest(op, request, outgoingData);
    }

private:
    int m_idleExpirySeconds;
};

#endif // RESILIENTNETWORKACCESSMANAGER_H
