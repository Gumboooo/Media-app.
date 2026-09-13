#include "video_surface.h"

#include <QPlatformSurfaceEvent>
#include <QtQml/QQmlEngine>

VideoSurface::VideoSurface(QObject* parent)
    : QObject(parent)
    , m_window(new QWindow())
{
    // QML observes this pointer but does not own it. Make that explicit so WindowContainer's
    // JavaScript-vs-C++ ownership branch cannot ever race our VideoSurface destructor.
    QQmlEngine::setObjectOwnership(m_window, QQmlEngine::CppOwnership);

    m_window->setFlags(Qt::FramelessWindowHint);
    m_window->installEventFilter(this);

    // Force initial native surface creation. WindowContainer may later recreate that platform
    // surface (for example after resource release), which eventFilter reports to QML so libVLC
    // can be rebound to the new handle.
    m_window->create();
}

VideoSurface::~VideoSurface()
{
    if (m_window) {
        m_window->removeEventFilter(this);
        delete m_window;
    }
}

qulonglong VideoSurface::nativeHandle() const noexcept
{
    return m_window ? static_cast<qulonglong>(m_window->winId()) : 0;
}

bool VideoSurface::eventFilter(QObject* watched, QEvent* event)
{
    if (watched == m_window && event->type() == QEvent::PlatformSurface) {
        auto* surfaceEvent = static_cast<QPlatformSurfaceEvent*>(event);
        if (surfaceEvent->surfaceEventType() == QPlatformSurfaceEvent::SurfaceCreated) {
            emit nativeHandleChanged();
        }
    }
    return QObject::eventFilter(watched, event);
}
