local t = require("tests.testlib")

local function read_file(path)
  local file = io.open(path, "r")
  if not file then
    return nil
  end
  local content = file:read("*a")
  file:close()
  return content
end

local function must_read(path)
  local content = read_file(path)
  t.truthy(content, "missing file: " .. path)
  return content
end

local function assert_contains(content, value)
  t.truthy(content:find(value, 1, true), "missing text: " .. value)
end

local function assert_not_contains(content, value)
  t.eq(content:find(value, 1, true), nil, "unexpected text: " .. value)
end

t.test("project launcher shell declares stable standalone identity and IPC", function()
  local qml = must_read("quickshell/gendbyte-project-launcher/shell.qml")
  assert_contains(qml, "//@ pragma AppId gendbyte-project-launcher")
  assert_contains(qml, "//@ pragma ShellId gendbyte-project-launcher")
  assert_contains(qml, "ShellRoot {")
  assert_contains(qml, "ProjectLauncher {")
  assert_contains(qml, "id: launcher")
  assert_not_contains(qml, "LazyLoader {")
  assert_contains(qml, "IpcHandler {")
  assert_contains(qml, 'target: "gendbyte-project-launcher"')
  assert_contains(qml, "function toggle(): string")
  assert_contains(qml, "function show(): string")
  assert_contains(qml, "function hide(): string")
  assert_contains(qml, "function ping(): string")
end)

t.test("project launcher UI is a hidden floating window with backend processes", function()
  local qml = must_read("quickshell/gendbyte-project-launcher/ProjectLauncher.qml")
  assert_contains(qml, "FloatingWindow {")
  assert_contains(qml, "visible: false")
  assert_contains(qml, 'title: "GendByte Project Launcher"')
  assert_contains(qml, "Process {")
  assert_contains(qml, "StdioCollector {")
  assert_contains(qml, "JSON.parse")
  assert_contains(qml, 'requestProjects(["refresh"])')
  assert_contains(qml, 'requestProjects(["query", searchField.text])')
  assert_contains(qml, 'backendArgs(["actions", selectedProject.id])')
  assert_contains(qml, '"run"')
  assert_contains(qml, '"--confirmed"')
  assert_contains(qml, "import QtQuick.Dialogs")
  assert_contains(qml, "FolderDialog {")
  assert_contains(qml, 'root.backendArgs(["add-root", path])')
  assert_contains(qml, 'text: "Add folder"')
  assert_contains(qml, 'text: "No project folders yet"')
  assert_contains(qml, 'text: "Select folder"')
  assert_contains(qml, 'color: "#ff8a3d"')
  assert_not_contains(qml, 'text: "Choose project folder…"')
end)

t.test("project launcher QML keeps project detection in Lua", function()
  local paths = {
    "quickshell/gendbyte-project-launcher/shell.qml",
    "quickshell/gendbyte-project-launcher/ProjectLauncher.qml",
    "quickshell/gendbyte-project-launcher/components/SearchField.qml",
    "quickshell/gendbyte-project-launcher/components/ProjectList.qml",
    "quickshell/gendbyte-project-launcher/components/ActionList.qml",
  }
  local all = ""
  for _, path in ipairs(paths) do
    all = all .. (read_file(path) or "")
  end

  assert_not_contains(all, "Cargo.toml")
  assert_not_contains(all, "package.json")
  assert_not_contains(all, "docker-compose")
  assert_not_contains(all, "pyproject.toml")
  assert_not_contains(all, ".git/")
end)

t.test("project launcher implements approved keyboard contract", function()
  local search = must_read("quickshell/gendbyte-project-launcher/components/SearchField.qml")
  local actions = must_read("quickshell/gendbyte-project-launcher/components/ActionList.qml")
  assert_contains(search, "Qt.Key_Up")
  assert_contains(search, "Qt.Key_Down")
  assert_contains(search, "Qt.Key_Tab")
  assert_contains(search, "Qt.Key_Right")
  assert_contains(search, "Qt.Key_Return")
  assert_contains(search, "Qt.Key_Escape")
  assert_contains(actions, "Qt.Key_Up")
  assert_contains(actions, "Qt.Key_Down")
  assert_contains(actions, "Qt.Key_Left")
  assert_contains(actions, "Qt.Key_Return")
  assert_contains(actions, "Qt.Key_Escape")
end)

t.test("project launcher debounces project query and has confirmation UI", function()
  local launcher = must_read("quickshell/gendbyte-project-launcher/ProjectLauncher.qml")
  local confirm = must_read("quickshell/gendbyte-project-launcher/components/ConfirmDialog.qml")
  assert_contains(launcher, "interval: 100")
  assert_contains(launcher, "queryTimer.restart()")
  assert_contains(launcher, "ConfirmDialog {")
  assert_contains(confirm, "signal confirmed()")
  assert_contains(confirm, "signal cancelled()")
end)

t.test("project launcher wrapper uses canonical qs IPC and race-safe bounded startup", function()
  local script = must_read("bin/hyprland-workstation-launcher")
  assert_contains(script, 'QS_SELECTOR=(-c "$CONFIG_NAME")')
  assert_contains(script, 'QS_SELECTOR=(-p "$CONFIG_DIR")')
  assert_contains(script, 'qs "${QS_SELECTOR[@]}" "$@"')
  assert_contains(script, "if ipc toggle")
  assert_contains(script, "if ipc ping")
  assert_contains(script, "ipc show")
  assert_contains(script, 'HYPRLAND_WORKSTATION_REPO_ROOT')
  assert_contains(script, 'CONFIG_NAME="gendbyte-project-launcher"')
  assert_contains(script, "STARTUP_ATTEMPTS=100")
  assert_contains(script, "STARTUP_DELAY=0.05")
  assert_contains(script, "acquire_start_lock")
  assert_contains(script, "wait_for_ipc")
  assert_contains(script, "project-launcher.log")
  assert_not_contains(script, "seq 1 20")
  assert_not_contains(script, "quickshell ipc")
end)

t.test("project launcher visual components are present", function()
  must_read("quickshell/gendbyte-project-launcher/components/SearchField.qml")
  must_read("quickshell/gendbyte-project-launcher/components/ProjectList.qml")
  must_read("quickshell/gendbyte-project-launcher/components/ActionList.qml")
  must_read("quickshell/gendbyte-project-launcher/components/ConfirmDialog.qml")
  must_read("quickshell/gendbyte-project-launcher/components/StatusMessage.qml")
end)
