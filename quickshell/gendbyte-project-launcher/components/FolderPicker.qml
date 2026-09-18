import QtQuick
import QtQuick.Layouts

Item {
  id: root

  property bool opened: false
  property string currentPath: ""
  property string parentPath: ""
  property var entries: []
  property int currentIndex: -1
  property string errorText: ""
  property bool loading: false

  signal browseRequested(string path)
  signal accepted(string path)
  signal cancelled()

  visible: opened
  enabled: opened
  focus: opened
  z: 100

  function openAt(path) {
    opened = true
    currentPath = ""
    parentPath = ""
    entries = []
    currentIndex = -1
    errorText = ""
    loading = true
    forceActiveFocus()
    browseRequested(path || "")
  }

  function closePicker() {
    opened = false
    loading = false
    errorText = ""
  }

  function updateDirectory(path, parent, nextEntries) {
    currentPath = String(path || "")
    parentPath = String(parent || "")
    entries = Array.isArray(nextEntries) ? nextEntries : []
    currentIndex = entries.length > 0 ? 0 : -1
    errorText = ""
    loading = false
    forceActiveFocus()
  }

  function fail(message) {
    errorText = String(message || "Unable to open folder")
    loading = false
    forceActiveFocus()
  }

  function browse(path) {
    if (loading || !path)
      return
    loading = true
    errorText = ""
    browseRequested(path)
  }

  function openSelected() {
    if (currentIndex < 0 || currentIndex >= entries.length)
      return
    browse(entries[currentIndex].path)
  }

  function moveSelection(delta) {
    if (entries.length === 0)
      return
    currentIndex = Math.max(0, Math.min(entries.length - 1, currentIndex + delta))
    folderList.positionViewAtIndex(currentIndex, ListView.Contain)
  }

  Keys.onPressed: function(event) {
    if (event.key === Qt.Key_Escape) {
      root.cancelled()
      event.accepted = true
    } else if (event.key === Qt.Key_Backspace || event.key === Qt.Key_Left) {
      if (root.parentPath !== "")
        root.browse(root.parentPath)
      event.accepted = true
    } else if (event.key === Qt.Key_Up) {
      root.moveSelection(-1)
      event.accepted = true
    } else if (event.key === Qt.Key_Down) {
      root.moveSelection(1)
      event.accepted = true
    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Right) {
      root.openSelected()
      event.accepted = true
    }
  }

  Rectangle {
    anchors.fill: parent
    color: "#dc090909"

    MouseArea {
      anchors.fill: parent
      onClicked: root.forceActiveFocus()
    }
  }

  Rectangle {
    anchors.centerIn: parent
    width: Math.min(parent.width - 48, 620)
    height: Math.min(parent.height - 48, 410)
    radius: 16
    color: "#151515"
    border.width: 1
    border.color: "#4a3a30"

    ColumnLayout {
      anchors.fill: parent
      anchors.margins: 16
      spacing: 10

      RowLayout {
        Layout.fillWidth: true
        Layout.preferredHeight: 32
        spacing: 8

        Text {
          text: "Select project folder"
          color: "#f0f0f0"
          font.family: "monospace"
          font.pixelSize: 13
          font.bold: true
        }

        Item { Layout.fillWidth: true }

        Rectangle {
          Layout.preferredWidth: 30
          Layout.preferredHeight: 30
          radius: 8
          color: closeMouse.containsMouse ? "#292929" : "#1c1c1c"
          border.width: 1
          border.color: "#363636"

          Text {
            anchors.centerIn: parent
            text: "×"
            color: "#bdbdbd"
            font.pixelSize: 16
          }

          MouseArea {
            id: closeMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.cancelled()
          }
        }
      }

      Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: 38
        radius: 9
        color: "#1a1a1a"
        border.width: 1
        border.color: "#303030"

        RowLayout {
          anchors.fill: parent
          anchors.leftMargin: 8
          anchors.rightMargin: 10
          spacing: 8

          Rectangle {
            Layout.preferredWidth: 30
            Layout.preferredHeight: 26
            radius: 7
            color: upMouse.containsMouse && root.parentPath !== "" ? "#29231f" : "#202020"
            opacity: root.parentPath !== "" ? 1.0 : 0.4

            Text {
              anchors.centerIn: parent
              text: "‹"
              color: root.parentPath !== "" ? "#ff8a3d" : "#777777"
              font.pixelSize: 20
            }

            MouseArea {
              id: upMouse
              anchors.fill: parent
              enabled: root.parentPath !== "" && !root.loading
              hoverEnabled: true
              cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
              onClicked: root.browse(root.parentPath)
            }
          }

          Text {
            Layout.fillWidth: true
            text: root.currentPath === "" ? "Loading…" : root.currentPath
            color: root.currentPath === "" ? "#6f6f6f" : "#bdbdbd"
            elide: Text.ElideMiddle
            font.family: "monospace"
            font.pixelSize: 10
          }
        }
      }

      Rectangle {
        Layout.fillWidth: true
        Layout.fillHeight: true
        radius: 10
        color: "#111111"
        border.width: 1
        border.color: "#292929"

        ListView {
          id: folderList
          anchors.fill: parent
          anchors.margins: 6
          clip: true
          visible: !root.loading && root.entries.length > 0
          model: root.entries
          spacing: 3
          currentIndex: root.currentIndex

          delegate: Rectangle {
            required property int index
            required property var modelData

            width: folderList.width
            height: 38
            radius: 8
            color: index === root.currentIndex
              ? "#2a211b"
              : (rowMouse.containsMouse ? "#1c1c1c" : "transparent")
            border.width: index === root.currentIndex ? 1 : 0
            border.color: "#70472e"

            Row {
              anchors.fill: parent
              anchors.leftMargin: 10
              anchors.rightMargin: 10
              spacing: 10

              Item {
                width: 22
                height: parent.height

                Item {
                  anchors.centerIn: parent
                  width: 20
                  height: 16

                  Rectangle {
                    x: 2
                    y: 1
                    width: 9
                    height: 5
                    radius: 2
                    color: "#30241c"
                    border.width: 1
                    border.color: "#ff8a3d"
                  }

                  Rectangle {
                    x: 0
                    y: 5
                    width: 20
                    height: 11
                    radius: 3
                    color: "#241d18"
                    border.width: 1
                    border.color: "#ff8a3d"
                  }
                }
              }

              Text {
                width: parent.width - 42
                height: parent.height
                text: modelData.name
                color: index === root.currentIndex ? "#f0f0f0" : "#b7b7b7"
                verticalAlignment: Text.AlignVCenter
                elide: Text.ElideRight
                font.family: "monospace"
                font.pixelSize: 11
              }
            }

            MouseArea {
              id: rowMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: {
                root.currentIndex = index
                root.forceActiveFocus()
              }
              onDoubleClicked: {
                root.currentIndex = index
                root.browse(modelData.path)
              }
            }
          }
        }

        Text {
          anchors.centerIn: parent
          visible: root.loading
          text: "Loading folders…"
          color: "#777777"
          font.family: "monospace"
          font.pixelSize: 11
        }

        Column {
          anchors.centerIn: parent
          visible: !root.loading && root.entries.length === 0
          spacing: 6

          Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "No subfolders"
            color: "#a8a8a8"
            font.family: "monospace"
            font.pixelSize: 11
            font.bold: true
          }

          Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "You can still use this folder as a project root."
            color: "#626262"
            font.family: "monospace"
            font.pixelSize: 9
          }
        }
      }

      RowLayout {
        Layout.fillWidth: true
        Layout.preferredHeight: 40
        spacing: 10

        ColumnLayout {
          Layout.fillWidth: true
          spacing: 2

          Text {
            Layout.fillWidth: true
            visible: root.errorText !== ""
            text: root.errorText
            color: "#e57373"
            elide: Text.ElideRight
            font.family: "monospace"
            font.pixelSize: 9
          }

          Text {
            Layout.fillWidth: true
            visible: root.errorText === ""
            text: "↑↓ select   Enter open   Backspace/← up"
            color: "#626262"
            font.family: "monospace"
            font.pixelSize: 9
          }
        }

        Rectangle {
          Layout.preferredWidth: 78
          Layout.preferredHeight: 34
          radius: 9
          color: cancelMouse.containsMouse ? "#262626" : "#1c1c1c"
          border.width: 1
          border.color: "#383838"

          Text {
            anchors.centerIn: parent
            text: "Cancel"
            color: "#bdbdbd"
            font.family: "monospace"
            font.pixelSize: 10
          }

          MouseArea {
            id: cancelMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.cancelled()
          }
        }

        Rectangle {
          Layout.preferredWidth: 148
          Layout.preferredHeight: 34
          radius: 9
          color: useMouse.containsMouse && root.currentPath !== "" && !root.loading
            ? "#ff9857" : "#ff8a3d"
          opacity: root.currentPath !== "" && !root.loading ? 1.0 : 0.45

          Text {
            anchors.centerIn: parent
            text: "Use this folder"
            color: "#151515"
            font.family: "monospace"
            font.pixelSize: 10
            font.bold: true
          }

          MouseArea {
            id: useMouse
            anchors.fill: parent
            enabled: root.currentPath !== "" && !root.loading
            hoverEnabled: true
            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: root.accepted(root.currentPath)
          }
        }
      }
    }
  }
}
