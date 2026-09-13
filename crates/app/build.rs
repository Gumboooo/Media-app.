use cxx_qt_build::{CppFile, CxxQtBuilder, QmlFile, QmlModule};

fn main() {
    let qml = QmlModule::new("org.aperture.player")
        .version(1, 0)
        .qml_file("qml/Main.qml")
        .qml_file("qml/Smoke.qml")
        .qml_file("qml/PlayerActions.qml")
        .qml_file(QmlFile::from("qml/Theme.qml").singleton(true))
        .qml_file(QmlFile::from("qml/Format.qml").singleton(true))
        .qml_files([
            "qml/components/AppButton.qml",
            "qml/components/AppSlider.qml",
            "qml/components/IconGlyph.qml",
            "qml/components/IconButton.qml",
            "qml/components/ControlBar.qml",
            "qml/components/PlayerTimeline.qml",
            "qml/components/InfoField.qml",
            "qml/components/MediaInfoPanel.qml",
        ]);

    CxxQtBuilder::new_qml_module(qml)
        .qt_module("Quick")
        .qt_module("QuickControls2")
        .qt_module("QuickDialogs2")
        .qt_module("QuickLayouts")
        .files(["src/player_controller.rs"])
        // Header gets moc/qmltyperegistrar; implementation gets compiled as normal C++.
        .cpp_file(CppFile::from("cpp/video_surface.h"))
        .cpp_file(CppFile::from("cpp/video_surface.cpp"))
        .build();
}
