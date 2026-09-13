pragma Singleton
import QtQuick

QtObject {
    readonly property color window: "#111214"
    readonly property color player: "#050506"
    readonly property color surface: "#191b1f"
    readonly property color surfaceHover: "#22252a"
    readonly property color border: "#30343a"
    readonly property color text: "#f2f3f5"
    readonly property color textMuted: "#a9afb8"
    readonly property color accent: "#e9edf3"
    readonly property color accentText: "#111214"
    readonly property color errorSurface: "#2b181a"
    readonly property color errorBorder: "#603035"
    readonly property color errorText: "#ffd7da"

    readonly property int borderWidth: 1

    readonly property int space1: 4
    readonly property int space2: 8
    readonly property int space3: 12
    readonly property int space4: 16
    readonly property int space5: 24
    readonly property int space6: 32

    readonly property int radiusSmall: 5
    readonly property int radiusMedium: 8
    readonly property int radiusLarge: 12

    readonly property int controlHeight: 34
    readonly property int transportHeight: 38
    readonly property int toolbarHeight: 46
    readonly property int timelineHeight: 30

    readonly property int initialWindowWidth: 1100
    readonly property int initialWindowHeight: 700
    readonly property int minimumWindowWidth: 680
    readonly property int minimumWindowHeight: 420
    readonly property int volumeSliderWidth: 120
    readonly property int statusTextMaxWidth: 220
    readonly property int timelineTimeWidth: 46
    readonly property int timelineMinSliderWidth: 80
    readonly property int sliderTrackHeight: 3
    readonly property int sliderHandleSize: 10
    readonly property int sliderHandlePressedSize: 14
    readonly property int errorTextMinWidth: 80
    readonly property int inspectorWidth: 300
    readonly property int minimumPlayerWidth: 360
    readonly property int trackButtonMaxWidth: 190

    readonly property int textSmall: 12
    readonly property int textBody: 13
    readonly property int textTitle: 15
    readonly property int textEmptyState: 22

    readonly property int motionFast: 90
    readonly property int motionNormal: 150
}
