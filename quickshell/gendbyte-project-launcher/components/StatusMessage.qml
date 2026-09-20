import QtQuick

Item {
  id: root

  property string message: ""
  property bool error: false
  property var themePalette: null

  implicitHeight: message === "" ? 0 : 24
  visible: message !== ""

  Text {
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    text: root.message
    color: root.error ? "#ff7a7a" : (root.themePalette ? root.themePalette.muted : "#8e8e8e")
    elide: Text.ElideRight
    font.family: "monospace"
    font.pixelSize: 10
  }
}
