import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import "components" as Components

Item {
  id: root

  property bool opened: false
  property string viewMode: "overview"
  property int selectedIndex: -1
  property int selectedWorkspaceIndex: -1
  property string navigationZone: "windows"
  property var targetScreen: null

  readonly property int focusedWorkspaceId: Hyprland.focusedWorkspace
    ? Number(Hyprland.focusedWorkspace.id)
    : -1

  readonly property var workspaceEntries: {
    var values = Hyprland.workspaces ? Hyprland.workspaces.values : []
    var entries = []
    var maxId = 0

    for (var i = 0; i < values.length; ++i) {
      var workspace = values[i]
      if (!workspace)
        continue

      var id = Number(workspace.id)
      if (!Number.isFinite(id) || id <= 0)
        continue

      maxId = Math.max(maxId, id)
      var count = workspace.toplevels && workspace.toplevels.values
        ? workspace.toplevels.values.length
        : 0
      entries.push({
        id: id,
        name: String(workspace.name || id),
        count: count,
        add: false
      })
    }

    entries.sort(function(left, right) { return left.id - right.id })

    var nextId = Math.max(1, maxId + 1)
    entries.push({
      id: nextId,
      name: String(nextId),
      count: 0,
      add: true
    })

    return entries
  }

  readonly property var switcherWindows: {
    var values = Hyprland.toplevels ? Hyprland.toplevels.values : []
    var result = []

    for (var i = 0; i < values.length; ++i) {
      var toplevel = values[i]
      if (!toplevel)
        continue

      var address = root.normalizedAddress(toplevel)
      if (address === "")
        continue

      var workspace = toplevel.workspace
      if (!workspace || !workspace.active)
        continue

      var ipc = toplevel.lastIpcObject
      if (ipc && (ipc.mapped === false || ipc.hidden === true))
        continue

      result.push(toplevel)
    }

    result.sort(function(left, right) {
      var leftIpc = left ? left.lastIpcObject : null
      var rightIpc = right ? right.lastIpcObject : null
      var leftOrder = leftIpc ? Number(leftIpc.focusHistoryID) : Number.POSITIVE_INFINITY
      var rightOrder = rightIpc ? Number(rightIpc.focusHistoryID) : Number.POSITIVE_INFINITY

      if (!Number.isFinite(leftOrder))
        leftOrder = Number.POSITIVE_INFINITY
      if (!Number.isFinite(rightOrder))
        rightOrder = Number.POSITIVE_INFINITY

      if (leftOrder !== rightOrder)
        return leftOrder - rightOrder

      return root.normalizedAddress(left).localeCompare(root.normalizedAddress(right))
    })

    return result
  }

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

  readonly property var windowModel: viewMode === "switcher"
    ? switcherWindows
    : visibleWindows

  function normalizedAddress(toplevel) {
    var value = String(toplevel && toplevel.address ? toplevel.address : "").trim().toLowerCase()
    if (value.indexOf("0x") === 0)
      value = value.substring(2)

    if (!/^[0-9a-f]{1,16}$/.test(value))
      return ""

    return "0x" + value
  }

  function focusedScreen() {
    var screens = Quickshell.screens || []
    var monitor = Hyprland.focusedMonitor

    if (monitor) {
      for (var i = 0; i < screens.length; ++i) {
        if (screens[i] && String(screens[i].name) === String(monitor.name))
          return screens[i]
      }
    }

    return screens.length > 0 ? screens[0] : null
  }

  function activeWorkspaceIndex() {
    for (var i = 0; i < workspaceEntries.length; ++i) {
      if (!workspaceEntries[i].add && Number(workspaceEntries[i].id) === focusedWorkspaceId)
        return i
    }
    return workspaceEntries.length > 0 ? 0 : -1
  }

  function selectedWindow() {
    if (selectedIndex < 0 || selectedIndex >= windowModel.length)
      return null
    return windowModel[selectedIndex]
  }

  function reconcileSelection() {
    if (windowModel.length === 0) {
      selectedIndex = -1
      return
    }

    if (selectedIndex < 0)
      selectedIndex = 0
    if (selectedIndex >= windowModel.length)
      selectedIndex = windowModel.length - 1
  }

  function refreshHyprlandState() {
    Hyprland.refreshMonitors()
    Hyprland.refreshWorkspaces()
    Hyprland.refreshToplevels()
  }

  function showOverview() {
    viewMode = "overview"
    refreshHyprlandState()
    targetScreen = focusedScreen()
    selectedIndex = visibleWindows.length > 0 ? 0 : -1
    selectedWorkspaceIndex = activeWorkspaceIndex()
    navigationZone = visibleWindows.length > 0 ? "windows" : "workspaces"
    opened = true
  }

  function showTaskSwitcher() {
    viewMode = "switcher"
    refreshHyprlandState()
    targetScreen = focusedScreen()
    selectedIndex = switcherWindows.length > 0 ? 0 : -1
    selectedWorkspaceIndex = -1
    navigationZone = "windows"
    opened = true
  }

  function hideOverview() {
    opened = false
    selectedIndex = -1
    selectedWorkspaceIndex = -1
    navigationZone = "windows"
    targetScreen = null
  }

  function toggleOverview() {
    if (opened && viewMode === "overview")
      hideOverview()
    else
      showOverview()
  }

  function toggleTaskSwitcher() {
    if (opened && viewMode === "switcher")
      hideOverview()
    else
      showTaskSwitcher()
  }

  function activateWindow(toplevel) {
    var address = normalizedAddress(toplevel)
    if (address === "")
      return

    hideOverview()
    Hyprland.dispatch('hl.dsp.focus({ window = "address:' + address + '" })')
  }

  function activateWorkspace(index) {
    if (index < 0 || index >= workspaceEntries.length)
      return

    var entry = workspaceEntries[index]
    var id = Number(entry.id)
    if (!Number.isFinite(id) || id <= 0)
      return

    hideOverview()
    Hyprland.dispatch('hl.dsp.focus({ workspace = "' + id + '" })')
  }

  function selectWorkspace(index) {
    if (index < 0 || index >= workspaceEntries.length)
      return
    selectedWorkspaceIndex = index
    navigationZone = "workspaces"
  }

  function moveWorkspaceSelection(delta) {
    if (workspaceEntries.length === 0)
      return
    var current = selectedWorkspaceIndex
    if (current < 0)
      current = activeWorkspaceIndex()
    selectedWorkspaceIndex = Math.max(0, Math.min(workspaceEntries.length - 1, current + delta))
  }

  onWindowModelChanged: reconcileSelection()

  Variants {
    model: Quickshell.screens

    PanelWindow {
      id: surface

      required property var modelData
      screen: modelData

      readonly property bool targetSurface: root.targetScreen !== null
        && screen !== null
        && String(screen.name) === String(root.targetScreen.name)
      readonly property int windowCount: Math.max(1, root.windowModel.length)
      readonly property real gridReserve: {
        if (root.viewMode === "switcher")
          return 48
        if (windowCount <= 1)
          return 58
        if (windowCount === 2)
          return 72
        if (windowCount <= 4)
          return 92
        return 112
      }
      readonly property real gridAvailableHeight: Math.max(170, content.height - gridReserve)
      readonly property int columns: {
        if (windowCount <= 1)
          return 1
        if (windowCount === 2)
          return 2
        return Math.max(1, Math.min(windowCount,
          Math.ceil(Math.sqrt(windowCount * content.width / Math.max(1, gridAvailableHeight)))))
      }
      readonly property int rows: Math.max(1, Math.ceil(windowCount / columns))
      readonly property real widthLimitedPreview: (
        content.width - Math.max(0, columns - 1) * 16
      ) / columns
      readonly property real heightLimitedPreview: (
        gridAvailableHeight - Math.max(0, rows - 1) * 16
      ) / rows / 0.62
      readonly property real previewCap: {
        if (windowCount <= 1)
          return 900
        if (windowCount === 2)
          return 760
        if (windowCount <= 4)
          return 640
        if (windowCount <= 6)
          return 540
        return 460
      }
      readonly property real previewWidth: Math.max(180,
        Math.min(previewCap, widthLimitedPreview, heightLimitedPreview))
      readonly property real previewHeight: previewWidth * 0.62

      visible: root.opened && targetSurface
      color: "transparent"
      exclusionMode: ExclusionMode.Ignore

      WlrLayershell.namespace: "gendbyte-workspace-overview"
      WlrLayershell.layer: WlrLayer.Overlay
      focusable: targetSurface
      WlrLayershell.keyboardFocus: targetSurface
        ? WlrKeyboardFocus.OnDemand
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
        anchors.margins: 28

        Text {
          id: heading
          anchors.left: parent.left
          anchors.top: parent.top
          text: root.viewMode === "switcher"
            ? "Windows"
            : "Workspace " + (root.focusedWorkspaceId > 0 ? root.focusedWorkspaceId : "")
          color: "#eeeeee"
          font.family: "monospace"
          font.pixelSize: 18
          font.bold: true
        }

        Text {
          anchors.left: heading.right
          anchors.leftMargin: 14
          anchors.baseline: heading.baseline
          text: root.windowModel.length + (root.windowModel.length === 1 ? " window" : " windows")
          color: "#777777"
          font.family: "monospace"
          font.pixelSize: 10
        }

        Grid {
          id: grid
          anchors.horizontalCenter: parent.horizontalCenter
          anchors.verticalCenter: parent.verticalCenter
          anchors.verticalCenterOffset: root.viewMode === "overview"
            ? (surface.windowCount <= 2 ? -28 : -44)
            : -12
          columns: surface.columns
          spacing: 16

          Repeater {
            model: root.windowModel

            Components.WindowPreview {
              required property int index
              required property var modelData

              width: surface.previewWidth
              height: surface.previewHeight
              toplevel: modelData
              selected: index === root.selectedIndex
              capturing: surface.visible

              onSelectionRequested: root.selectedIndex = index
              onActivated: root.activateWindow(modelData)
            }
          }
        }

        Rectangle {
          anchors.centerIn: parent
          visible: root.windowModel.length === 0
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
              text: root.viewMode === "switcher"
                ? "No windows on active monitor workspaces"
                : "No windows on this workspace"
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

        Components.WorkspaceStrip {
          id: workspaceStrip
          anchors.horizontalCenter: parent.horizontalCenter
          anchors.bottom: parent.bottom
          width: Math.min(parent.width, implicitWidth)
          height: implicitHeight
          visible: root.viewMode === "overview"
          workspacesModel: root.workspaceEntries
          selectedIndex: root.navigationZone === "workspaces" ? root.selectedWorkspaceIndex : -1
          activeWorkspaceId: root.focusedWorkspaceId

          onSelected: function(index) {
            root.selectWorkspace(index)
          }
          onActivated: function(index) {
            root.activateWorkspace(index)
          }
        }

        Text {
          anchors.right: parent.right
          anchors.bottom: root.viewMode === "overview" ? workspaceStrip.top : parent.bottom
          anchors.bottomMargin: root.viewMode === "overview" ? 10 : 0
          text: root.viewMode === "switcher"
            ? "←→↑↓ select   Enter focus   Esc close"
            : (root.navigationZone === "workspaces"
              ? "←→ workspace   Enter switch/create   Tab windows   Esc close"
              : "←→↑↓ windows   Enter focus   Tab workspaces   Esc close")
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

          if (event.key === Qt.Key_Tab && root.viewMode === "overview") {
            if (root.navigationZone === "windows") {
              root.navigationZone = "workspaces"
              if (root.selectedWorkspaceIndex < 0)
                root.selectedWorkspaceIndex = root.activeWorkspaceIndex()
            } else {
              root.navigationZone = root.visibleWindows.length > 0 ? "windows" : "workspaces"
            }
            event.accepted = true
            return
          }

          if (root.viewMode === "overview"
              && event.key >= Qt.Key_1 && event.key <= Qt.Key_9) {
            var workspaceId = event.key - Qt.Key_0
            for (var directIndex = 0; directIndex < root.workspaceEntries.length; ++directIndex) {
              if (!root.workspaceEntries[directIndex].add
                  && Number(root.workspaceEntries[directIndex].id) === workspaceId) {
                root.activateWorkspace(directIndex)
                event.accepted = true
                return
              }
            }
          }

          if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            if (root.viewMode === "overview" && root.navigationZone === "workspaces") {
              root.activateWorkspace(root.selectedWorkspaceIndex)
            } else {
              var current = root.selectedWindow()
              if (current)
                root.activateWindow(current)
            }
            event.accepted = true
            return
          }

          if (root.viewMode === "overview" && root.navigationZone === "workspaces") {
            if (event.key === Qt.Key_Left)
              root.moveWorkspaceSelection(-1)
            else if (event.key === Qt.Key_Right)
              root.moveWorkspaceSelection(1)
            else
              return
            event.accepted = true
            return
          }

          var count = root.windowModel.length
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
