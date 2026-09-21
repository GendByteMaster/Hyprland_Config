import QtQuick
import QtQuick.Controls

Item {
  id: root

  property var actionsModel: []
  property int currentIndex: -1
  property var themePalette: null
  property bool active: false
  signal selected(int index)
  signal activated(int index)
  signal back()
  signal escapePressed()

  function focusList() {
    list.forceActiveFocus()
  }

  ListView {
    id: list
    anchors.fill: parent
    clip: true
    spacing: 4
    model: root.actionsModel
    currentIndex: root.currentIndex
    focus: false

    Keys.onPressed: function(event) {
      if (event.key === Qt.Key_Up) {
        if (root.actionsModel.length > 0)
          root.selected(Math.max(0, root.currentIndex - 1))
        event.accepted = true
      } else if (event.key === Qt.Key_Down) {
        if (root.actionsModel.length > 0)
          root.selected(Math.min(root.actionsModel.length - 1, root.currentIndex + 1))
        event.accepted = true
      } else if (event.key === Qt.Key_Left) {
        root.back()
        event.accepted = true
      } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
        if (root.currentIndex >= 0)
          root.activated(root.currentIndex)
        event.accepted = true
      } else if (event.key === Qt.Key_Escape) {
        root.escapePressed()
        event.accepted = true
      }
    }

    delegate: Rectangle {
      required property int index
      required property var modelData

      width: ListView.view.width
      height: modelData.reason ? 50 : 40
      radius: 9
      opacity: modelData.enabled === false ? 0.48 : 1.0
      color: index === root.currentIndex
        ? (root.themePalette
            ? (root.active ? root.themePalette.selection : root.themePalette.lighterBackground)
            : (root.active ? "#2a211c" : "#1d1d1d"))
        : (hover.hovered ? (root.themePalette ? root.themePalette.lighterBackground : "#1d1d1d") : "transparent")
      border.width: index === root.currentIndex && root.active ? 1 : 0
      border.color: root.themePalette ? root.themePalette.accent : "#6b4028"

      HoverHandler {
        id: hover
      }

      TapHandler {
        onTapped: {
          root.selected(index)
          if (modelData.enabled !== false)
            root.activated(index)
        }
      }

      Column {
        anchors.fill: parent
        anchors.leftMargin: 12
        anchors.rightMargin: 10
        anchors.topMargin: 7
        spacing: 2

        Text {
          width: parent.width
          text: (modelData.confirm === true ? "⚠ " : "") + (modelData.label || modelData.id)
          color: root.themePalette
            ? (modelData.enabled === false ? root.themePalette.muted : root.themePalette.foreground)
            : (modelData.enabled === false ? "#929292" : "#eeeeee")
          elide: Text.ElideRight
          font.family: "monospace"
          font.pixelSize: 13
        }

        Text {
          width: parent.width
          visible: modelData.reason !== undefined && modelData.reason !== null && modelData.reason !== ""
          text: modelData.reason || ""
          color: root.themePalette ? root.themePalette.muted : "#8a8a8a"
          elide: Text.ElideRight
          font.family: "monospace"
          font.pixelSize: 9
        }
      }
    }

    ScrollBar.vertical: ScrollBar {
    }
  }
}
