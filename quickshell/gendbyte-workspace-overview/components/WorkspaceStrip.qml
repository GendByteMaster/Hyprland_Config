import QtQuick
import QtQuick.Layouts

Rectangle {
  id: root

  property var workspacesModel: []
  property int selectedIndex: -1
  property int activeWorkspaceId: -1
  property var themePalette: null

  signal selected(int index)
  signal activated(int index)

  implicitWidth: Math.max(220, workspaceRow.implicitWidth + 28)
  implicitHeight: 86
  radius: 16
  color: root.themePalette ? root.themePalette.colorWithAlpha(root.themePalette.background, 0.92) : "#e5131313"
  border.width: 1
  border.color: root.themePalette ? root.themePalette.border : "#303030"

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
            return root.themePalette ? root.themePalette.selection : "#2a211b"
          if (Number(modelData.id) === root.activeWorkspaceId)
            return root.themePalette ? root.themePalette.lighterBackground : "#211b18"
          return tileMouse.containsMouse
            ? (root.themePalette ? root.themePalette.lighterBackground : "#1d1d1d")
            : (root.themePalette ? root.themePalette.darkBackground : "#171717")
        }
        border.width: index === root.selectedIndex ? 2 : 1
        border.color: index === root.selectedIndex
          ? (root.themePalette ? root.themePalette.accent : "#ff8a3d")
          : (Number(modelData.id) === root.activeWorkspaceId
            ? (root.themePalette ? root.themePalette.accent : "#72482f")
            : (root.themePalette ? root.themePalette.border : "#343434"))

        Behavior on color {
          ColorAnimation { duration: 80 }
        }

        Column {
          anchors.centerIn: parent
          spacing: 5

          Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: modelData.add ? "+" : String(modelData.name || modelData.id)
            color: palette ? (index === root.selectedIndex ? palette.accent : palette.foreground) : (index === root.selectedIndex ? "#ff9a58" : "#d7d7d7")
            font.family: "monospace"
            font.pixelSize: modelData.add ? 22 : 12
            font.bold: true
          }

          Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: modelData.add
              ? "New workspace"
              : String(modelData.count || 0) + ((modelData.count || 0) === 1 ? " window" : " windows")
            color: root.themePalette ? root.themePalette.muted : "#777777"
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
