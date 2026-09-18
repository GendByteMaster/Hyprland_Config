local testlib = require("tests.testlib")
local test = testlib.test

local function runtime(commands, env)
  commands = commands or {}
  env = env or {}
  return {
    command_exists = function(name)
      return commands[name] == true
    end,
    getenv = function(name)
      return env[name]
    end,
  }
end

test("generic adapter prefers xdg terminal exec in auto mode", function()
  local generic = require("workstation.adapters.generic")
  local adapter = generic.detect({ apps = { terminal = "auto" } }, runtime({
    ["xdg-terminal-exec"] = true,
    foot = true,
  }))

  local argv = assert(adapter.terminal_argv("/tmp/My Project", { "git", "status" }))
  testlib.eq(argv[1], "xdg-terminal-exec")
  testlib.eq(argv[2], "--dir=/tmp/My Project")
  testlib.eq(argv[3], "git")
  testlib.eq(argv[4], "status")
end)

test("explicit foot adapter keeps cwd as one argv element", function()
  local generic = require("workstation.adapters.generic")
  local adapter = generic.detect({ apps = { terminal = "foot" } }, runtime({ foot = true }))
  local argv = assert(adapter.terminal_argv("/tmp/a;echo bad", { "git", "status" }))

  testlib.eq(argv[1], "foot")
  testlib.eq(argv[2], "--working-directory=/tmp/a;echo bad")
  testlib.eq(argv[3], "git")
end)

test("known terminal adapters keep terminal specific cwd flags", function()
  local generic = require("workstation.adapters.generic")
  local cases = {
    ghostty = { "ghostty", "--working-directory=/repo/a", "-e", "git", "status" },
    kitty = { "kitty", "--directory", "/repo/a", "git", "status" },
    alacritty = { "alacritty", "--working-directory", "/repo/a", "-e", "git", "status" },
  }

  for name, expected in pairs(cases) do
    local adapter = generic.detect({ apps = { terminal = name } }, runtime({ [name] = true }))
    local argv = assert(adapter.terminal_argv("/repo/a", { "git", "status" }))
    testlib.eq(table.concat(argv, "|"), table.concat(expected, "|"), name)
  end
end)

test("auto terminal uses exact TERMINAL preference before single fallback", function()
  local generic = require("workstation.adapters.generic")
  local adapter = generic.detect({ apps = { terminal = "auto" } }, runtime({
    foot = true,
    kitty = true,
  }, {
    TERMINAL = "kitty",
  }))

  local argv = assert(adapter.terminal_argv("/repo/a", {}))
  testlib.eq(argv[1], "kitty")
end)

test("auto terminal is unavailable when multiple known terminals are ambiguous", function()
  local generic = require("workstation.adapters.generic")
  local adapter = generic.detect({ apps = { terminal = "auto" } }, runtime({
    foot = true,
    kitty = true,
  }))

  local argv, reason = adapter.terminal_argv("/repo/a", {})
  testlib.eq(argv, nil)
  testlib.truthy(reason:match("terminal"))
end)

test("generic adapter appends project path to explicit editor and file manager", function()
  local generic = require("workstation.adapters.generic")
  local adapter = generic.detect({
    apps = {
      terminal = "auto",
      editor = { "code", "--reuse-window" },
      file_manager = { "thunar" },
    },
  }, runtime({
    code = true,
    thunar = true,
  }))

  local editor = assert(adapter.editor_argv("/repo/a"))
  testlib.eq(table.concat(editor, "|"), "code|--reuse-window|/repo/a")

  local files = assert(adapter.file_manager_argv("/repo/a"))
  testlib.eq(table.concat(files, "|"), "thunar|/repo/a")
end)

test("generic adapter detects xdg open as file manager fallback", function()
  local generic = require("workstation.adapters.generic")
  local adapter = generic.detect({ apps = { terminal = "auto" } }, runtime({
    ["xdg-open"] = true,
  }))

  local argv = assert(adapter.file_manager_argv("/repo/a"))
  testlib.eq(table.concat(argv, "|"), "xdg-open|/repo/a")
end)

test("generic clipboard uses wl copy with stdin payload", function()
  local generic = require("workstation.adapters.generic")
  local adapter = generic.detect({ apps = { terminal = "auto" } }, runtime({
    ["wl-copy"] = true,
  }))

  local argv, input, reason = adapter.clipboard_argv("/repo/My Project")
  testlib.eq(reason, nil)
  testlib.eq(argv[1], "wl-copy")
  testlib.eq(input, "/repo/My Project")
end)

test("adapter capabilities reflect resolved tools", function()
  local generic = require("workstation.adapters.generic")
  local adapter = generic.detect({
    apps = {
      terminal = "foot",
      editor = { "code" },
    },
  }, runtime({
    foot = true,
    code = true,
    ["wl-copy"] = true,
  }))

  local caps = adapter.capabilities()
  testlib.eq(caps.terminal, true)
  testlib.eq(caps.editor, true)
  testlib.eq(caps.file_manager, false)
  testlib.eq(caps.clipboard, true)
end)

test("omarchy adapter is selected only when omarchy exists", function()
  local omarchy = require("workstation.adapters.omarchy")

  local absent = omarchy.detect({ apps = { terminal = "auto" } }, runtime({
    ["xdg-terminal-exec"] = true,
  }))
  testlib.eq(absent, nil)

  local present = omarchy.detect({ apps = { terminal = "auto" } }, runtime({
    omarchy = true,
    ["xdg-terminal-exec"] = true,
  }))
  testlib.truthy(present)
  testlib.eq(present.kind, "omarchy")
  local argv = assert(present.terminal_argv("/repo/a", { "git", "status" }))
  testlib.eq(argv[1], "xdg-terminal-exec")
  testlib.eq(argv[2], "--dir=/repo/a")
end)
