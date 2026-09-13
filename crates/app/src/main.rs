#![cfg_attr(all(windows, not(debug_assertions)), windows_subsystem = "windows")]

mod player_controller;

use cxx_qt_lib::{QGuiApplication, QQmlApplicationEngine, QUrl};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;

fn main() -> std::process::ExitCode {
    let mut app = QGuiApplication::new();
    let Some(mut app_ref) = app.as_mut() else {
        eprintln!("Aperture could not create the Qt GUI application.");
        return std::process::ExitCode::FAILURE;
    };

    app_ref
        .as_mut()
        .set_organization_name(&"Aperture Project".into());
    app_ref.as_mut().set_application_name(&"Aperture".into());
    app_ref
        .as_mut()
        .set_application_version(&env!("CARGO_PKG_VERSION").into());

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

    // Preserve Qt's event-loop exit code instead of flattening every failure to 1. Smoke.qml
    // uses codes 20..28 to identify the exact failed probe stage, which must survive the Rust
    // process boundary so packaged release builds remain diagnosable without console logging.
    let qt_exit_code = app_ref.exec();
    if qt_exit_code == 0 {
        std::process::ExitCode::SUCCESS
    } else {
        let portable_code = if (1..=255).contains(&qt_exit_code) {
            qt_exit_code as u8
        } else {
            1
        };
        std::process::ExitCode::from(portable_code)
    }
}
