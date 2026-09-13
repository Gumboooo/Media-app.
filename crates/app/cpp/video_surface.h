#pragma once

#include <QEvent>
#include <QObject>
#include <QWindow>
#include <QtQml/qqmlregistration.h>

// A deliberately tiny native child window. libVLC renders directly to this platform window,
// while Qt Quick WindowContainer handles geometry and embedding. No decoded frame copies pass
// through QML.
// Qt 6.8's QML registration creates a derived wrapper for this type.
class VideoSurface : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    Q_PROPERTY(QWindow* window READ window CONSTANT)
    Q_PROPERTY(qulonglong nativeHandle READ nativeHandle NOTIFY nativeHandleChanged)

public:
    explicit VideoSurface(QObject* parent = nullptr);
    ~VideoSurface() override;

    QWindow* window() const noexcept { return m_window; }
    qulonglong nativeHandle() const noexcept;

signals:
    void nativeHandleChanged();

protected:
    bool eventFilter(QObject* watched, QEvent* event) override;

private:
    QWindow* m_window = nullptr;
};
