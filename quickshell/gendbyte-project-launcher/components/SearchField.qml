import QtQuick
import QtQuick.Controls

Item {
  id: root

  property alias text: input.text
  signal queryChanged(string query)
  signal moveUp()
  signal moveDown()
  signal toActions()
  signal activate()
  signal escapePressed()

  implicitHeight: 46

  function focusInput() {
    input.forceActiveFocus()
    input.selectAll()
  }

  Rectangle {
    anchors.fill: parent
    radius: 12
    color: "#181818"
    border.width: input.activeFocus ? 1 : 1
    border.color: input.activeFocus ? "#ff8a3d" : "#363636"

    TextField {
      id: input
      anchors.fill: parent
      anchors.leftMargin: 14
      anchors.rightMargin: 14
      placeholderText: "Search projects..."
      color: "#f2f2f2"
      placeholderTextColor: "#787878"
      selectionColor: "#ff8a3d"
      selectedTextColor: "#101010"
      background: null
      font.family: "monospace"
      font.pixelSize: 15

      onTextEdited: root.queryChanged(text)

      Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Up) {
          root.moveUp()
          event.accepted = true
        } else if (event.key === Qt.Key_Down) {
          root.moveDown()
          event.accepted = true
        } else if (event.key === Qt.Key_Tab || event.key === Qt.Key_Right) {
          root.toActions()
          event.accepted = true
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
          root.activate()
          event.accepted = true
        } else if (event.key === Qt.Key_Escape) {
          root.escapePressed()
          event.accepted = true
        }
      }
    }
  }
}
