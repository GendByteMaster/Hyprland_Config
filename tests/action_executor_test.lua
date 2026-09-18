local testlib = require("tests.testlib")
local test = testlib.test

local function fake_adapter()
  return {
    terminal_argv = function(cwd, argv)
      local result = { "terminal", "--cwd", cwd }
      for _, item in ipairs(argv or {}) do
        result[#result + 1] = item
      end
      return result
    end,
    editor_argv = function(path)
      return { "editor", path }
    end,
    file_manager_argv = function(path)
      return { "files", path }
    end,
    clipboard_argv = function(text)
      return { "wl-copy" }, text
    end,
  }
end

local function runtime(options)
  options = options or {}
  local calls = {
    spawn = {},
    stdin = {},
  }

  return {
    calls = calls,
    realpath = function(path)
      if options.missing == path then
        return nil
      end
      if options.realpaths and options.realpaths[path] then
        return options.realpaths[path]
      end
      return path
    end,
    spawn_argv = function(argv)
      calls.spawn[#calls.spawn + 1] = argv
      return options.spawn_ok ~= false
    end,
    run_argv_with_stdin = function(argv, input)
      calls.stdin[#calls.stdin + 1] = { argv = argv, input = input }
      return options.stdin_ok ~= false
    end,
  }
end

local project = {
  id = "/repo/a",
  path = "/repo/a",
  name = "a",
}

test("executor refuses confirmation action until confirmed", function()
  local executor = require("workstation.action_executor")
  local rt = runtime()
  local result = executor.run(project, {
    id = "compose-down",
    argv = { "docker", "compose", "down" },
    terminal = true,
    enabled = true,
    confirm = true,
  }, fake_adapter(), rt, { confirmed = false })

  testlib.eq(result.requires_confirmation, true)
  testlib.eq(#rt.calls.spawn, 0)
end)

test("executor dispatches confirmed terminal action at explicit project cwd", function()
  local executor = require("workstation.action_executor")
  local rt = runtime()
  local result = executor.run(project, {
    id = "git-status",
    argv = { "git", "status" },
    terminal = true,
    enabled = true,
    confirm = false,
  }, fake_adapter(), rt, { confirmed = true })

  testlib.eq(result.ok, true)
  testlib.eq(table.concat(rt.calls.spawn[1], "|"), "terminal|--cwd|/repo/a|git|status")
end)

test("executor rejects missing project before spawn", function()
  local executor = require("workstation.action_executor")
  local rt = runtime({ missing = "/repo/a" })
  local result = executor.run(project, {
    id = "git-status",
    argv = { "git", "status" },
    terminal = true,
    enabled = true,
  }, fake_adapter(), rt)

  testlib.eq(result.ok, false)
  testlib.truthy(result.error:match("no longer exists"))
  testlib.eq(#rt.calls.spawn, 0)
end)

test("executor rejects changed canonical project identity", function()
  local executor = require("workstation.action_executor")
  local rt = runtime({
    realpaths = {
      ["/repo/a"] = "/repo/replaced",
    },
  })
  local result = executor.run(project, {
    id = "git-status",
    argv = { "git", "status" },
    terminal = true,
    enabled = true,
  }, fake_adapter(), rt)

  testlib.eq(result.ok, false)
  testlib.truthy(result.error:match("identity"))
  testlib.eq(#rt.calls.spawn, 0)
end)

test("executor refuses disabled action", function()
  local executor = require("workstation.action_executor")
  local rt = runtime()
  local result = executor.run(project, {
    id = "rust-test",
    argv = { "cargo", "test" },
    terminal = true,
    enabled = false,
    reason = "cargo is unavailable",
  }, fake_adapter(), rt)

  testlib.eq(result.ok, false)
  testlib.truthy(result.error:match("cargo"))
  testlib.eq(#rt.calls.spawn, 0)
end)

test("executor dispatches editor and file manager quick actions", function()
  local executor = require("workstation.action_executor")
  local rt = runtime()

  local editor = executor.run(project, {
    id = "open-editor",
    operation = "editor",
    enabled = true,
    terminal = false,
  }, fake_adapter(), rt)
  testlib.eq(editor.ok, true)
  testlib.eq(table.concat(rt.calls.spawn[1], "|"), "editor|/repo/a")

  local files = executor.run(project, {
    id = "open-file-manager",
    operation = "file-manager",
    enabled = true,
    terminal = false,
  }, fake_adapter(), rt)
  testlib.eq(files.ok, true)
  testlib.eq(table.concat(rt.calls.spawn[2], "|"), "files|/repo/a")
end)

test("executor sends clipboard text through stdin without shell interpolation", function()
  local executor = require("workstation.action_executor")
  local rt = runtime()
  local malicious = {
    id = "/repo/a;touch /tmp/pwn",
    path = "/repo/a;touch /tmp/pwn",
    name = "a",
  }

  local result = executor.run(malicious, {
    id = "copy-path",
    operation = "clipboard",
    enabled = true,
    terminal = false,
  }, fake_adapter(), rt)

  testlib.eq(result.ok, true)
  testlib.eq(rt.calls.stdin[1].input, "/repo/a;touch /tmp/pwn")
  testlib.eq(#rt.calls.spawn, 0)
end)

test("executor dispatches direct custom argv without a terminal", function()
  local executor = require("workstation.action_executor")
  local rt = runtime()
  local result = executor.run(project, {
    id = "custom",
    argv = { "notify-send", "hello; touch /tmp/pwn" },
    enabled = true,
    terminal = false,
  }, fake_adapter(), rt)

  testlib.eq(result.ok, true)
  testlib.eq(rt.calls.spawn[1][1], "notify-send")
  testlib.eq(rt.calls.spawn[1][2], "hello; touch /tmp/pwn")
end)
