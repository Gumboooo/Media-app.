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
    if (m_nativeHandle == 0 && m_window->handle()) {
        m_nativeHandle = static_cast<qulonglong>(m_window->winId());
    }
}

VideoSurface::~VideoSurface()
{
    if (m_window) {
        m_window->removeEventFilter(this);
        delete m_window;
    }
}

bool VideoSurface::eventFilter(QObject* watched, QEvent* event)
{
    if (watched == m_window && event->type() == QEvent::PlatformSurface) {
        auto* surfaceEvent = static_cast<QPlatformSurfaceEvent*>(event);
        switch (surfaceEvent->surfaceEventType()) {
        case QPlatformSurfaceEvent::SurfaceAboutToBeDestroyed:
            if (m_nativeHandle != 0) {
                // Publish invalidation before Qt destroys the platform surface. The player can
                // detach libVLC from the old HWND/native view instead of leaving it with a stale
                // handle until a replacement surface eventually appears.
                m_nativeHandle = 0;
                emit nativeHandleChanged();
            }
            break;
        case QPlatformSurfaceEvent::SurfaceCreated: {
            const auto handle = static_cast<qulonglong>(m_window->winId());
            if (m_nativeHandle != handle) {
                m_nativeHandle = handle;
                emit nativeHandleChanged();
            }
            break;
        }
        default:
            break;
        }
    }
    return QObject::eventFilter(watched, event);
}
