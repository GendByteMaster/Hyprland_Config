import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import "components" as Components

Item {
  id: root

  property bool opened: false
  property int selectedIndex: -1

  readonly property int focusedWorkspaceId: Hyprland.focusedWorkspace
    ? Number(Hyprland.focusedWorkspace.id)
    : -1

  readonly property var visibleWindows: {
    var focused = Hyprland.focusedWorkspace
    var values = focused && focused.toplevels
      ? focused.toplevels.values
      : (Hyprland.toplevels ? Hyprland.toplevels.values : [])
    var result = []

    for (var i = 0; i < values.length; ++i) {
      var toplevel = values[i]
      if (!toplevel)
        continue

      var address = root.normalizedAddress(toplevel)
      if (address === "")
        continue

      if (!(focused && focused.toplevels)) {
        var workspace = toplevel.workspace
        if (!workspace || Number(workspace.id) !== root.focusedWorkspaceId)
          continue
      }

      result.push(toplevel)
    }

    return result
  }

  function normalizedAddress(toplevel) {
    var value = String(toplevel && toplevel.address ? toplevel.address : "").trim().toLowerCase()
    if (value.indexOf("0x") === 0)
      value = value.substring(2)

    if (!/^[0-9a-f]{1,16}$/.test(value))
      return ""

    return "0x" + value
  }

  function selectedWindow() {
    if (selectedIndex < 0 || selectedIndex >= visibleWindows.length)
      return null
    return visibleWindows[selectedIndex]
  }

  function reconcileSelection() {
    if (visibleWindows.length === 0) {
      selectedIndex = -1
      return
    }

    if (selectedIndex < 0)
      selectedIndex = 0
    if (selectedIndex >= visibleWindows.length)
      selectedIndex = visibleWindows.length - 1
  }

  function showOverview() {
    Hyprland.refreshMonitors()
    Hyprland.refreshWorkspaces()
    Hyprland.refreshToplevels()
    selectedIndex = 0
    opened = true
  }

  function hideOverview() {
    opened = false
    selectedIndex = -1
  }

  function toggleOverview() {
    if (opened)
      hideOverview()
    else
      showOverview()
  }

  function activateWindow(toplevel) {
    var address = normalizedAddress(toplevel)
    if (address === "")
      return

    hideOverview()
    Hyprland.dispatch('hl.dsp.focus({ window = "address:' + address + '" })')
  }

  onVisibleWindowsChanged: reconcileSelection()

  Variants {
    model: Quickshell.screens

    PanelWindow {
      id: surface

      required property var modelData
      screen: modelData

      readonly property var hyprMonitor: Hyprland.monitorFor(screen)
      readonly property bool focusedSurface: Hyprland.focusedMonitor !== null
        && hyprMonitor !== null
        && Hyprland.focusedMonitor.id === hyprMonitor.id
      readonly property int columns: Math.max(1,
        Math.ceil(Math.sqrt(Math.max(1, root.visibleWindows.length) * width / Math.max(1, height))))
      readonly property real previewWidth: Math.max(220,
        Math.min(520, (content.width - Math.max(0, columns - 1) * 16) / columns))
      readonly property real previewHeight: previewWidth * 0.62

      visible: root.opened && focusedSurface
      color: "transparent"
      exclusionMode: ExclusionMode.Ignore

      WlrLayershell.namespace: "gendbyte-workspace-overview"
      WlrLayershell.layer: WlrLayer.Overlay
      WlrLayershell.keyboardFocus: focusedSurface
        ? WlrKeyboardFocus.Exclusive
        : WlrKeyboardFocus.None

      anchors {
        top: true
        bottom: true
        left: true
        right: true
      }

      onVisibleChanged: {
        if (visible)
          Qt.callLater(function() { keys.forceActiveFocus() })
      }

      Rectangle {
        anchors.fill: parent
        color: "#df0b0b0b"
      }

      MouseArea {
        anchors.fill: parent
        onClicked: root.hideOverview()
      }

      Item {
        id: content
        anchors.fill: parent
        anchors.margins: 42

        Text {
          id: heading
          anchors.left: parent.left
          anchors.top: parent.top
          text: "Workspace " + (root.focusedWorkspaceId > 0 ? root.focusedWorkspaceId : "")
          color: "#eeeeee"
          font.family: "monospace"
          font.pixelSize: 18
          font.bold: true
        }

        Text {
          anchors.left: heading.right
          anchors.leftMargin: 14
          anchors.baseline: heading.baseline
          text: root.visibleWindows.length + (root.visibleWindows.length === 1 ? " window" : " windows")
          color: "#777777"
          font.family: "monospace"
          font.pixelSize: 10
        }

        Grid {
          id: grid
          anchors.centerIn: parent
          columns: surface.columns
          spacing: 16

          Repeater {
            model: root.visibleWindows

            Components.WindowPreview {
              required property int index
              required property var modelData

              width: surface.previewWidth
              height: surface.previewHeight
              toplevel: modelData
              selected: index === root.selectedIndex
              capturing: surface.visible

              onActivated: root.activateWindow(modelData)
            }
          }
        }

        Rectangle {
          anchors.centerIn: parent
          visible: root.visibleWindows.length === 0
          width: 320
          height: 130
          radius: 14
          color: "#151515"
          border.width: 1
          border.color: "#303030"

          Column {
            anchors.centerIn: parent
            spacing: 8

            Text {
              anchors.horizontalCenter: parent.horizontalCenter
              text: "No windows on this workspace"
              color: "#d8d8d8"
              font.family: "monospace"
              font.pixelSize: 12
              font.bold: true
            }

            Text {
              anchors.horizontalCenter: parent.horizontalCenter
              text: "Esc closes the overview"
              color: "#666666"
              font.family: "monospace"
              font.pixelSize: 9
            }
          }
        }

        Text {
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          text: "←→↑↓ navigate   Enter focus   Esc close"
          color: "#686868"
          font.family: "monospace"
          font.pixelSize: 9
        }
      }

      Item {
        id: keys
        anchors.fill: parent
        focus: surface.visible

        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function(event) {
          if (!root.opened)
            return

          if (event.key === Qt.Key_Escape) {
            root.hideOverview()
            event.accepted = true
            return
          }

          if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            var current = root.selectedWindow()
            if (current)
              root.activateWindow(current)
            event.accepted = true
            return
          }

          var count = root.visibleWindows.length
          if (count === 0)
            return

          var columns = Math.max(1, surface.columns)
          var next = root.selectedIndex < 0 ? 0 : root.selectedIndex

          if (event.key === Qt.Key_Left)
            next = Math.max(0, next - 1)
          else if (event.key === Qt.Key_Right)
            next = Math.min(count - 1, next + 1)
          else if (event.key === Qt.Key_Up)
            next = Math.max(0, next - columns)
          else if (event.key === Qt.Key_Down)
            next = Math.min(count - 1, next + columns)
          else
            return

          root.selectedIndex = next
          event.accepted = true
        }
      }
    }
  }
}
