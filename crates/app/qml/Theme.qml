pragma Singleton
import QtQuick

QtObject {
    // Neutral, media-first dark palette. The video canvas remains visually dominant while
    // controls stay readable without turning the app into a dashboard of cards.
    readonly property color window: "#101214"
    readonly property color toolbar: "#131619"
    readonly property color player: "#020304"
    readonly property color playerControlSurface: "#111418"
    readonly property color surface: "#171a1e"
    readonly property color surfaceHover: "#20242a"
    readonly property color surfacePressed: "#292e35"
    readonly property color surfaceDisabled: "#141619"
    readonly property color border: "#2a2f36"
    readonly property color borderStrong: "#3a414b"
    readonly property color sliderTrack: "#363c44"
    readonly property color text: "#f2f4f6"
    readonly property color textMuted: "#9aa3ae"
    readonly property color textDim: "#737d88"
    readonly property color textDisabled: "#59616b"
    readonly property color accent: "#e3e7eb"
    readonly property color accentText: "#111316"
    readonly property color focusBorder: "#7f8996"
    readonly property color errorSurface: "#29181b"
    readonly property color errorBorder: "#65343b"
    readonly property color errorText: "#ffd9dc"

    readonly property int borderWidth: 1

    readonly property int space1: 4
    readonly property int space2: 8
    readonly property int space3: 12
    readonly property int space4: 16
    readonly property int space5: 24
    readonly property int space6: 32
    readonly property int space7: 40

    readonly property int radiusSmall: 5
    readonly property int radiusMedium: 8
    readonly property int radiusLarge: 12

    readonly property int buttonMinWidth: 72
    readonly property int controlHeight: 32
    readonly property int iconButtonSize: 34
    readonly property int primaryTransportSize: 40
    readonly property int transportHeight: 42
    readonly property int toolbarHeight: 44
    readonly property int timelineHeight: 28
    readonly property int controlBarHeight: 88
    readonly property int sliderHitHeight: 28

    readonly property int initialWindowWidth: 1180
    readonly property int initialWindowHeight: 720
    readonly property int minimumWindowWidth: 720
    readonly property int minimumWindowHeight: 460
    readonly property int volumeSliderWidth: 110
    readonly property int statusTextMaxWidth: 180
    readonly property int timelineTimeWidth: 48
    readonly property int timelineMinSliderWidth: 80
    readonly property int sliderTrackHeight: 3
    readonly property int sliderHandleSize: 10
    readonly property int sliderHandlePressedSize: 14
    readonly property int errorTextMinWidth: 80
    readonly property int inspectorWidth: 320
    readonly property int minimumPlayerWidth: 420
    readonly property int trackButtonMaxWidth: 190
    readonly property int emptyIconSize: 48
    readonly property int dividerHeight: 1

    readonly property int textTiny: 11
    readonly property int textSmall: 12
    readonly property int textBody: 13
    readonly property int textTitle: 14
    readonly property int textEmptyState: 21
    readonly property int textEmptySubhead: 13

    readonly property int motionFast: 80
    readonly property int motionNormal: 140
}
