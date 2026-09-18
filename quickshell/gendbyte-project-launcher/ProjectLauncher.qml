import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "components" as Components

FloatingWindow {
  id: root

  visible: false
  title: "GendByte Project Launcher"
  implicitWidth: 860
  implicitHeight: 520
  minimumSize: Qt.size(680, 420)
  color: "transparent"
  surfaceFormat.opaque: false

  property var projects: []
  property var actions: []
  property int selectedProjectIndex: -1
  property int selectedActionIndex: -1
  property var pendingAction: null
  property string statusText: ""
  property bool statusError: false
  property string repoRoot: String(Quickshell.env("HYPRLAND_WORKSTATION_REPO_ROOT") || "")
  property string backendScript: repoRoot === "" ? "" : repoRoot + "/project-launcher.lua"

  readonly property var selectedProject:
    selectedProjectIndex >= 0 && selectedProjectIndex < projects.length
      ? projects[selectedProjectIndex] : null
  readonly property var selectedAction:
    selectedActionIndex >= 0 && selectedActionIndex < actions.length
      ? actions[selectedActionIndex] : null

  function backendArgs(args) {
    var result = ["lua5.1", backendScript]
    for (var index = 0; index < args.length; ++index)
      result.push(String(args[index]))
    return result
  }

  function parseEnvelope(text) {
    try {
      var payload = JSON.parse(String(text || "").trim())
      if (!payload || payload.version !== 1 || typeof payload.ok !== "boolean")
        throw new Error("invalid protocol envelope")
      return payload
    } catch (error) {
      statusError = true
      statusText = "Backend protocol error: " + String(error)
      return null
    }
  }

  function showWarnings(data) {
    var warnings = data && Array.isArray(data.warnings) ? data.warnings : []
    statusError = false
    statusText = warnings.length > 0 ? warnings.join(" · ") : ""
  }

  function showLauncher() {
    visible = true
    pendingAction = null
    confirmDialog.opened = false
    Qt.callLater(function() {
      searchField.focusInput()
      requestProjects(["refresh"])
    })
  }

  function closeLauncher() {
    confirmDialog.opened = false
    pendingAction = null
    visible = false
  }

  function toggleLauncher() {
    if (visible)
      closeLauncher()
    else
      showLauncher()
  }

  function requestProjects(args) {
    if (backendScript === "") {
      statusError = true
      statusText = "Launcher repository root is unavailable"
      return
    }
    projectProcess.exec(backendArgs(args))
  }

  function requestActions() {
    if (!selectedProject) {
      actions = []
      selectedActionIndex = -1
      return
    }
    actionProcess.exec(backendArgs(["actions", selectedProject.id]))
  }

  function handleProjectResponse(text) {
    var payload = parseEnvelope(text)
    if (!payload)
      return
    if (!payload.ok) {
      statusError = true
      statusText = payload.error || "Project query failed"
      return
    }

    projects = Array.isArray(payload.data.projects) ? payload.data.projects : []
    selectedProjectIndex = projects.length > 0 ? 0 : -1
    showWarnings(payload.data)
    requestActions()
  }

  function handleActionResponse(text) {
    var payload = parseEnvelope(text)
    if (!payload)
      return
    if (!payload.ok) {
      statusError = true
      statusText = payload.error || "Action query failed"
      actions = []
      selectedActionIndex = -1
      return
    }

    actions = Array.isArray(payload.data.actions) ? payload.data.actions : []
    selectedActionIndex = actions.length > 0 ? 0 : -1
    showWarnings(payload.data)
  }

  function handleRunResponse(text) {
    var payload = parseEnvelope(text)
    if (!payload)
      return
    if (!payload.ok) {
      statusError = true
      statusText = payload.error || "Action failed"
      return
    }

    if (payload.data.requires_confirmation === true) {
      pendingAction = payload.data.action || selectedAction
      confirmDialog.actionLabel = pendingAction ? pendingAction.label : "Confirm action"
      confirmDialog.opened = true
      return
    }

    if (payload.data.dispatched === true) {
      closeLauncher()
      return
    }

    if (payload.data.favorite !== undefined) {
      requestProjects(["query", searchField.text])
      return
    }

    showWarnings(payload.data)
  }

  function moveProject(delta) {
    if (projects.length === 0)
      return
    selectedProjectIndex = Math.max(0, Math.min(projects.length - 1, selectedProjectIndex + delta))
    requestActions()
  }

  function selectProject(index) {
    if (index < 0 || index >= projects.length)
      return
    selectedProjectIndex = index
    requestActions()
    searchField.focusInput()
  }

  function selectAction(index) {
    if (index < 0 || index >= actions.length)
      return
    selectedActionIndex = index
  }

  function focusActions() {
    if (actions.length === 0)
      return
    if (selectedActionIndex < 0)
      selectedActionIndex = 0
    actionList.focusList()
  }

  function activateDefaultAction() {
    if (actions.length === 0)
      return
    if (selectedActionIndex < 0)
      selectedActionIndex = 0
    runSelected(false)
  }

  function runSelected(confirmed) {
    var action = confirmed && pendingAction ? pendingAction : selectedAction
    if (!selectedProject || !action || action.enabled === false)
      return

    if (action.confirm === true && confirmed !== true) {
      pendingAction = action
      confirmDialog.actionLabel = action.label || action.id
      confirmDialog.opened = true
      return
    }

    var args = ["run", selectedProject.id, action.id]
    if (confirmed === true)
      args.push("--confirmed")
    runProcess.exec(backendArgs(args))
  }

  Timer {
    id: queryTimer
    interval: 100
    repeat: false
    onTriggered: root.requestProjects(["query", searchField.text])
  }

  Process {
    id: projectProcess
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.handleProjectResponse(this.text)
    }
  }

  Process {
    id: actionProcess
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.handleActionResponse(this.text)
    }
  }

  Process {
    id: runProcess
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.handleRunResponse(this.text)
    }
  }

  Rectangle {
    anchors.fill: parent
    radius: 18
    color: "#ed111111"
    border.width: 1
    border.color: "#3b3b3b"

    ColumnLayout {
      anchors.fill: parent
      anchors.margins: 16
      spacing: 10

      Components.SearchField {
        id: searchField
        Layout.fillWidth: true

        onQueryChanged: queryTimer.restart()
        onMoveUp: root.moveProject(-1)
        onMoveDown: root.moveProject(1)
        onToActions: root.focusActions()
        onActivate: root.activateDefaultAction()
        onEscapePressed: root.closeLauncher()
      }

      RowLayout {
        Layout.fillWidth: true
        Layout.fillHeight: true
        spacing: 10

        Rectangle {
          Layout.fillWidth: true
          Layout.fillHeight: true
          Layout.preferredWidth: 1
          radius: 12
          color: "#151515"
          border.width: 1
          border.color: "#282828"

          ColumnLayout {
            anchors.fill: parent
            anchors.margins: 10
            spacing: 8

            Text {
              text: "Projects"
              color: "#9a9a9a"
              font.family: "monospace"
              font.pixelSize: 11
              font.bold: true
            }

            Components.ProjectList {
              id: projectList
              Layout.fillWidth: true
              Layout.fillHeight: true
              projectsModel: root.projects
              currentIndex: root.selectedProjectIndex
              onSelected: function(index) { root.selectProject(index) }
            }
          }
        }

        Rectangle {
          Layout.fillWidth: true
          Layout.fillHeight: true
          Layout.preferredWidth: 1
          radius: 12
          color: "#151515"
          border.width: 1
          border.color: "#282828"

          ColumnLayout {
            anchors.fill: parent
            anchors.margins: 10
            spacing: 8

            Text {
              text: "Actions"
              color: "#9a9a9a"
              font.family: "monospace"
              font.pixelSize: 11
              font.bold: true
            }

            Components.ActionList {
              id: actionList
              Layout.fillWidth: true
              Layout.fillHeight: true
              actionsModel: root.actions
              currentIndex: root.selectedActionIndex

              onSelected: function(index) { root.selectAction(index) }
              onActivated: function(index) {
                root.selectAction(index)
                root.runSelected(false)
              }
              onBack: searchField.focusInput()
              onEscapePressed: root.closeLauncher()
            }
          }
        }
      }

      Components.StatusMessage {
        Layout.fillWidth: true
        message: root.statusText
        error: root.statusError
      }

      Text {
        Layout.fillWidth: true
        text: "↑↓ navigate   Tab/→ actions   Enter run   Esc close"
        color: "#686868"
        horizontalAlignment: Text.AlignRight
        font.family: "monospace"
        font.pixelSize: 9
      }
    }

    Components.ConfirmDialog {
      id: confirmDialog
      anchors.fill: parent

      onConfirmed: {
        opened = false
        root.runSelected(true)
      }
      onCancelled: {
        opened = false
        root.pendingAction = null
        actionList.focusList()
      }
    }
  }
}
