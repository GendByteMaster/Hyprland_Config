import QtQuick
import QtQuick.Layouts

Rectangle {
  id: root

  property var workspacesModel: []
  property int selectedIndex: -1
  property int activeWorkspaceId: -1

  signal selected(int index)
  signal activated(int index)

  implicitWidth: Math.max(220, workspaceRow.implicitWidth + 28)
  implicitHeight: 86
  radius: 16
  color: "#e5131313"
  border.width: 1
  border.color: "#303030"

  Row {
    id: workspaceRow
    anchors.centerIn: parent
    spacing: 10

    Repeater {
      model: root.workspacesModel

      Rectangle {
        required property int index
        required property var modelData

        width: modelData.add ? 112 : 124
        height: 58
        radius: 11
        color: {
          if (index === root.selectedIndex)
            return "#2a211b"
          if (Number(modelData.id) === root.activeWorkspaceId)
            return "#211b18"
          return tileMouse.containsMouse ? "#1d1d1d" : "#171717"
        }
        border.width: index === root.selectedIndex ? 2 : 1
        border.color: index === root.selectedIndex
          ? "#ff8a3d"
          : (Number(modelData.id) === root.activeWorkspaceId ? "#72482f" : "#343434")

        Behavior on color {
          ColorAnimation { duration: 80 }
        }

        Column {
          anchors.centerIn: parent
          spacing: 5

          Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: modelData.add ? "+" : String(modelData.name || modelData.id)
            color: index === root.selectedIndex ? "#ff9a58" : "#d7d7d7"
            font.family: "monospace"
            font.pixelSize: modelData.add ? 22 : 12
            font.bold: true
          }

          Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: modelData.add
              ? "New workspace"
              : String(modelData.count || 0) + ((modelData.count || 0) === 1 ? " window" : " windows")
            color: "#777777"
            font.family: "monospace"
            font.pixelSize: 8
          }
        }

        MouseArea {
          id: tileMouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor

          onEntered: root.selected(index)
          onClicked: root.activated(index)
        }
      }
    }
  }
}
