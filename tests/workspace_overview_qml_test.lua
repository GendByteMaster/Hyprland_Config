local t = require("tests.testlib")

local function read(path)
  local file = assert(io.open(path, "r"), "missing file: " .. path)
  local content = file:read("*a")
  file:close()
  return content
end

local function contains(text, value)
  t.truthy(text:find(value, 1, true), "missing: " .. value)
end

local function excludes(text, value)
  t.eq(text:find(value, 1, true), nil, "unexpected: " .. value)
end

t.test("workspace overview shell exposes isolated IPC lifecycle", function()
  local shell = read("quickshell/gendbyte-workspace-overview/shell.qml")

  contains(shell, "gendbyte-workspace-overview")
  contains(shell, "IpcHandler")
  contains(shell, "function toggle()")
  contains(shell, "function show()")
  contains(shell, "function hide()")
  contains(shell, "function ping()")
end)

t.test("workspace overview uses Hyprland and Wayland live previews", function()
  local overview = read("quickshell/gendbyte-workspace-overview/Overview.qml")
  local preview = read("quickshell/gendbyte-workspace-overview/components/WindowPreview.qml")

  contains(overview, "import Quickshell.Hyprland")
  contains(overview, "WlrLayershell.layer: WlrLayer.Overlay")
  contains(overview, "Hyprland.toplevels")
  contains(preview, "import Quickshell.Wayland")
  contains(preview, "ScreencopyView")
  contains(preview, "captureSource: root.capturing ? root.waylandToplevel : null")
  contains(preview, "live: root.capturing && root.visible")
  excludes(overview, "hyprctl")
  excludes(preview, "hyprctl")
end)

t.test("workspace overview implements keyboard-only focus MVP", function()
  local overview = read("quickshell/gendbyte-workspace-overview/Overview.qml")

  contains(overview, "Qt.Key_Left")
  contains(overview, "Qt.Key_Right")
  contains(overview, "Qt.Key_Up")
  contains(overview, "Qt.Key_Down")
  contains(overview, "Qt.Key_Return")
  contains(overview, "Qt.Key_Escape")
  contains(overview, "hl.dsp.focus")
  contains(overview, "normalizedAddress")
end)

t.test("workspace overview does not introduce screenshot polling", function()
  local overview = read("quickshell/gendbyte-workspace-overview/Overview.qml")
  local preview = read("quickshell/gendbyte-workspace-overview/components/WindowPreview.qml")

  excludes(overview, "grim")
  excludes(overview, "screenshot")
  excludes(overview, "Timer {")
  excludes(preview, "grim")
  excludes(preview, "screenshot")
  excludes(preview, "Timer {")
end)
