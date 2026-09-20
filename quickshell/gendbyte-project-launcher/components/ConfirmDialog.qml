import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Item {
  id: root

  property string actionLabel: ""
  property bool opened: false
  property var themePalette: null
  signal confirmed()
  signal cancelled()

  visible: opened
  z: 100
  focus: visible

  onVisibleChanged: {
    if (visible)
      forceActiveFocus()
  }

  Keys.onPressed: function(event) {
    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
      root.confirmed()
      event.accepted = true
    } else if (event.key === Qt.Key_Escape) {
      root.cancelled()
      event.accepted = true
    }
  }

  Rectangle {
    anchors.fill: parent
    color: root.themePalette ? root.themePalette.colorWithAlpha(root.themePalette.background, 0.76) : "#b0000000"

    Rectangle {
      anchors.centerIn: parent
      width: 420
      height: 176
      radius: 14
      color: root.themePalette ? root.themePalette.darkBackground : "#181818"
      border.width: 1
      border.color: root.themePalette ? root.themePalette.accent : "#6b4028"

      ColumnLayout {
        anchors.fill: parent
        anchors.margins: 20
        spacing: 12

        Text {
          Layout.fillWidth: true
          text: "Confirm action"
          color: root.themePalette ? root.themePalette.foreground : "#f2f2f2"
          font.family: "monospace"
          font.pixelSize: 17
          font.bold: true
        }

        Text {
          Layout.fillWidth: true
          text: root.actionLabel
          color: root.themePalette ? root.themePalette.muted : "#bdbdbd"
          wrapMode: Text.Wrap
          font.family: "monospace"
          font.pixelSize: 12
        }

        Item {
          Layout.fillHeight: true
        }

        RowLayout {
          Layout.alignment: Qt.AlignRight
          spacing: 8

          Button {
            text: "Cancel"
            onClicked: root.cancelled()
          }

          Button {
            text: "Run"
            onClicked: root.confirmed()
          }
        }
      }
    }
  }
}
