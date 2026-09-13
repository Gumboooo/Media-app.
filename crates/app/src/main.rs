mod player_controller;

use cxx_qt_lib::{QCoreApplication, QGuiApplication, QQmlApplicationEngine, QUrl};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;

fn main() -> std::process::ExitCode {
    let mut app = QGuiApplication::new();

    QCoreApplication::set_organization_name(&"Aperture Project".into());
    QCoreApplication::set_application_name(&"Aperture".into());
    QCoreApplication::set_application_version(&env!("CARGO_PKG_VERSION").into());

    let smoke = std::env::args().any(|arg| arg == "--smoke-test");
    let root_url = QUrl::from(if smoke {
        "qrc:/qt/qml/org/aperture/player/qml/Smoke.qml"
    } else {
        "qrc:/qt/qml/org/aperture/player/qml/Main.qml"
    });
    let load_failed = Arc::new(AtomicBool::new(false));
    let mut engine = QQmlApplicationEngine::new();

    if let Some(mut engine) = engine.as_mut() {
        let failed = Arc::clone(&load_failed);
        let _failure_connection = engine.as_mut().on_object_creation_failed(move |_, _| {
            failed.store(true, Ordering::Release);
        });
        engine.load(&root_url);
    } else {
        eprintln!("Aperture could not create the QML application engine.");
        return std::process::ExitCode::FAILURE;
    }

    if load_failed.load(Ordering::Acquire) {
        eprintln!("Aperture could not load its root QML interface.");
        return std::process::ExitCode::FAILURE;
    }

    if let Some(app) = app.as_mut() {
        app.exec();
    }
    std::process::ExitCode::SUCCESS
}
