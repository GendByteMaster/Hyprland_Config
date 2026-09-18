import QtQuick
import QtQuick.Controls

Item {
  id: root

  property var projectsModel: []
  property int currentIndex: -1
  signal selected(int index)

  ListView {
    id: list
    anchors.fill: parent
    clip: true
    spacing: 4
    model: root.projectsModel
    currentIndex: root.currentIndex

    delegate: Rectangle {
      required property int index
      required property var modelData

      width: ListView.view.width
      height: 42
      radius: 9
      color: index === root.currentIndex ? "#2a211c" : (hover.hovered ? "#1d1d1d" : "transparent")
      border.width: index === root.currentIndex ? 1 : 0
      border.color: "#6b4028"

      HoverHandler {
        id: hover
      }

      TapHandler {
        onTapped: root.selected(index)
      }

      Row {
        anchors.fill: parent
        anchors.leftMargin: 12
        anchors.rightMargin: 12
        spacing: 9

        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: modelData.favorite === true ? "★" : " "
          color: "#ff8a3d"
          font.pixelSize: 14
        }

        Column {
          anchors.verticalCenter: parent.verticalCenter
          width: parent.width - 32
          spacing: 1

          Text {
            width: parent.width
            text: modelData.name || modelData.path
            color: "#eeeeee"
            elide: Text.ElideRight
            font.family: "monospace"
            font.pixelSize: 14
          }

          Text {
            width: parent.width
            text: modelData.path || ""
            color: "#777777"
            elide: Text.ElideMiddle
            font.family: "monospace"
            font.pixelSize: 10
          }
        }
      }
    }

    ScrollBar.vertical: ScrollBar {
    }
  }
}
