import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland

Rectangle {
  id: root

  required property var toplevel
  property bool selected: false
  property bool capturing: true
  property var palette: null

  signal selectionRequested()
  signal activated()

  readonly property var waylandToplevel: toplevel ? toplevel.wayland : null
  readonly property string title: toplevel
    ? String(toplevel.title || (waylandToplevel ? waylandToplevel.appId : "") || "Window")
    : "Window"
  readonly property string appId: waylandToplevel
    ? String(waylandToplevel.appId || "")
    : ""
  readonly property string monitorName: {
    var workspace = toplevel ? toplevel.workspace : null
    var monitor = workspace ? workspace.monitor : null
    return monitor ? String(monitor.name || "") : ""
  }
  readonly property var desktopEntry: appId !== ""
    ? DesktopEntries.heuristicLookup(appId)
    : null
  readonly property string iconSource: {
    var name = desktopEntry && desktopEntry.icon ? desktopEntry.icon : appId
    if (!name)
      return Quickshell.iconPath("application-x-executable", true)
    var resolved = Quickshell.iconPath(name, true)
    return resolved || Quickshell.iconPath("application-x-executable", true)
  }

  radius: 14
  color: selected && palette ? palette.selection : (palette ? palette.darkBackground : "#151515")
  border.width: selected ? 2 : 1
  border.color: selected && palette ? palette.accent : (palette ? palette.border : "#383838")
  clip: true

  Behavior on border.color {
    ColorAnimation { duration: 90 }
  }

  ScreencopyView {
    id: capture
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.bottom: titleBar.top
    captureSource: root.capturing ? root.waylandToplevel : null
    live: root.capturing && root.visible
    paintCursor: false
    visible: hasContent
  }

  Image {
    anchors.centerIn: capture
    visible: !capture.hasContent
    source: root.iconSource
    width: Math.min(parent.width, parent.height) * 0.28
    height: width
    fillMode: Image.PreserveAspectFit
    asynchronous: true
    smooth: true
    opacity: 0.72
  }

  Rectangle {
    id: titleBar
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    height: 40
    color: palette ? palette.colorWithAlpha(palette.background, 0.92) : "#e9141414"

    RowLayout {
      anchors.fill: parent
      anchors.leftMargin: 12
      anchors.rightMargin: 12
      spacing: 8

      Image {
        Layout.preferredWidth: 18
        Layout.preferredHeight: 18
        source: root.iconSource
        fillMode: Image.PreserveAspectFit
        asynchronous: true
        visible: source !== ""
      }

      Text {
        Layout.fillWidth: true
        text: root.title
        color: root.palette ? root.palette.foreground : (root.selected ? "#ffffff" : "#c4c4c4")
        elide: Text.ElideRight
        textFormat: Text.PlainText
        font.family: "monospace"
        font.pixelSize: 11
      }

      Rectangle {
        visible: root.monitorName !== ""
        Layout.preferredWidth: monitorLabel.implicitWidth + 14
        Layout.preferredHeight: 22
        radius: 7
        color: root.palette ? root.palette.lighterBackground : "#202020"
        border.width: 1
        border.color: root.palette ? (root.selected ? root.palette.accent : root.palette.border) : (root.selected ? "#70472e" : "#343434")

        Text {
          id: monitorLabel
          anchors.centerIn: parent
          text: root.monitorName
          color: root.palette ? (root.selected ? root.palette.accent : root.palette.muted) : (root.selected ? "#ff9a58" : "#858585")
          font.family: "monospace"
          font.pixelSize: 8
        }
      }
    }
  }

  HoverHandler {
    onHoveredChanged: {
      if (hovered)
        root.selectionRequested()
    }
  }

  TapHandler {
    acceptedButtons: Qt.LeftButton
    onTapped: root.activated()
  }
}
