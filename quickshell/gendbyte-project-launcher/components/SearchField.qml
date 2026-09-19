import QtQuick
import QtQuick.Controls

Item {
  id: root

  property alias text: input.text
  property var palette: null
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
    color: palette ? palette.darkBackground : "#181818"
    border.width: input.activeFocus ? 1 : 1
    border.color: palette ? (input.activeFocus ? palette.accent : palette.border) : (input.activeFocus ? "#ff8a3d" : "#363636")

    TextField {
      id: input
      anchors.fill: parent
      anchors.leftMargin: 14
      anchors.rightMargin: 14
      placeholderText: "Search projects..."
      color: palette ? palette.foreground : "#f2f2f2"
      placeholderTextColor: palette ? palette.muted : "#787878"
      selectionColor: palette ? palette.accent : "#ff8a3d"
      selectedTextColor: palette ? palette.background : "#101010"
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
