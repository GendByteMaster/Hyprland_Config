import QtQuick
import Quickshell
import Quickshell.Wayland

Item {
  id: root

  property var shell: null
  property var manifest: null
  property bool opened: false
  property bool cardShown: false
  property string mode: "numpad"
  property string button: "LMB"

  function open(payloadJson) {
    var payload = {}
    try { payload = JSON.parse(payloadJson || "{}") || {} } catch (e) {}

    root.mode = payload.mode === "mouse" ? "mouse" : "numpad"
    if (payload.button === "RMB" || payload.button === "MMB")
      root.button = payload.button
    else
      root.button = "LMB"

    root.opened = true
    root.cardShown = false
    hideTimer.stop()
    closeTimer.stop()

    Qt.callLater(function() {
      root.cardShown = true
      hideTimer.restart()
    })
  }

  function close() {
    hideTimer.stop()
    closeTimer.stop()
    root.cardShown = false
    root.opened = false
  }

  function dismiss() {
    if (root.shell && typeof root.shell.hide === "function")
      root.shell.hide((root.manifest && root.manifest.id) || "gendbyte.mouse-hud")
    else
      root.close()
  }

  Timer {
    id: hideTimer
    interval: 1300
    repeat: false
    onTriggered: {
      root.cardShown = false
      closeTimer.restart()
    }
  }

  Timer {
    id: closeTimer
    interval: 180
    repeat: false
    onTriggered: root.dismiss()
  }

  PanelWindow {
    id: hudWindow

    visible: root.opened
    anchors {
      left: true
      right: true
      bottom: true
    }
    implicitHeight: 96
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    focusable: false
    mask: Region { }

    WlrLayershell.namespace: "gendbyte-mouse-hud"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    Rectangle {
      id: card

      anchors.horizontalCenter: parent.horizontalCenter
      anchors.bottom: parent.bottom
      anchors.bottomMargin: root.cardShown ? 24 : 14

      width: contentRow.implicitWidth + 30
      height: 48
      radius: 16
      color: Qt.rgba(0.07, 0.07, 0.08, 0.88)
      border.width: 1
      border.color: Qt.rgba(1, 1, 1, 0.16)
      opacity: root.cardShown ? 1 : 0

      Behavior on opacity {
        NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
      }

      Behavior on anchors.bottomMargin {
        NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
      }

      Row {
        id: contentRow
        anchors.centerIn: parent
        spacing: 12

        Rectangle {
          width: 8
          height: 8
          radius: 4
          anchors.verticalCenter: parent.verticalCenter
          color: root.mode === "mouse" ? "#8bd450" : "#9aa0a6"
        }

        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: root.mode === "mouse" ? "Mouse Mode" : "NumPad"
          color: "#f5f5f7"
          font.pixelSize: 15
          font.weight: Font.DemiBold
          textFormat: Text.PlainText
        }

        Rectangle {
          visible: root.mode === "mouse"
          anchors.verticalCenter: parent.verticalCenter
          width: buttonText.implicitWidth + 16
          height: 28
          radius: 10
          color: Qt.rgba(1, 1, 1, 0.09)
          border.width: 1
          border.color: Qt.rgba(1, 1, 1, 0.12)

          Text {
            id: buttonText
            anchors.centerIn: parent
            text: root.button
            color: "#ffffff"
            font.pixelSize: 12
            font.weight: Font.Bold
            font.letterSpacing: 0.6
            textFormat: Text.PlainText
          }
        }
      }
    }
  }
}
