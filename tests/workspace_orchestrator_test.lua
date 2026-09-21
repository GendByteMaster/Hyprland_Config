local testlib = require("tests.testlib")
local test = testlib.test

local project = {
  id = "/repo/app",
  path = "/repo/app",
  name = "app",
}

local function adapter(options)
  options = options or {}

  return {
    editor_argv = function(path)
      if options.no_editor then
        return nil, "editor unavailable"
      end
      return { "code", "--reuse-window", path }
    end,
    terminal_argv = function(cwd, argv)
      if options.no_terminal then
        return nil, "terminal unavailable"
      end
      local result = { "foot", "--working-directory=" .. cwd }
      for _, value in ipairs(argv or {}) do
        result[#result + 1] = value
      end
      return result
    end,
    url_argv = function(url)
      if options.no_url then
        return nil, "URL opener unavailable"
      end
      return { "xdg-open", url }
    end,
  }
end

local function config(targets)
  return {
    overrides = {
      [project.path] = {
        workspace = {
          targets = targets,
        },
      },
    },
  }
end

local function runtime(options)
  options = options or {}
  local calls = {
    spawn = {},
    run = {},
  }

  return {
    calls = calls,
    realpath = function(path)
      if options.missing then
        return nil
      end
      return options.realpath or path
    end,
    command_exists = function(name)
      if name == "hyprctl" then
        return options.hyprctl ~= false
      end
      return true
    end,
    spawn_argv = function(argv)
      calls.spawn[#calls.spawn + 1] = argv
      if options.fail_spawn_at and #calls.spawn == options.fail_spawn_at then
        return false
      end
      return true
    end,
    run_argv = function(argv)
      calls.run[#calls.run + 1] = argv
      if options.fail_run_at and #calls.run == options.fail_run_at then
        return false
      end
      return true
    end,
  }
end

test("workspace planner resolves editor terminal direct and URL targets", function()
  local orchestrator = require("workstation.workspace_orchestrator")
  local plan, err = orchestrator.plan(project, config({
    {
      name = "editor",
      workspace = 1,
      operation = "editor",
    },
    {
      name = "backend",
      workspace = 2,
      terminal = true,
      argv = { "uv", "run", "fastapi", "dev" },
    },
    {
      name = "worker",
      argv = { "worker", "--once" },
    },
    {
      name = "browser",
      workspace = "name:web",
      url = "http://localhost:3000",
    },
  }), adapter())

  testlib.eq(err, nil)
  testlib.eq(#plan.targets, 4)
  testlib.eq(plan.targets[1].workspace, "1")
  testlib.eq(table.concat(plan.targets[1].argv, "|"), "code|--reuse-window|/repo/app")
  testlib.eq(plan.targets[2].workspace, "2")
  testlib.eq(plan.targets[2].argv[1], "foot")
  testlib.eq(plan.targets[2].argv[3], "uv")
  testlib.eq(table.concat(plan.targets[3].argv, "|"), "worker|--once")
  testlib.eq(plan.targets[4].workspace, "name:web")
  testlib.eq(table.concat(plan.targets[4].argv, "|"), "xdg-open|http://localhost:3000")
end)

test("workspace planner keeps unavailable target as an isolated failure", function()
  local orchestrator = require("workstation.workspace_orchestrator")
  local plan = assert(orchestrator.plan(project, config({
    {
      name = "editor",
      workspace = 1,
      operation = "editor",
    },
    {
      name = "backend",
      workspace = 2,
      terminal = true,
      argv = { "uv", "run", "fastapi", "dev" },
    },
  }), adapter({ no_editor = true })))

  testlib.eq(plan.targets[1].enabled, false)
  testlib.truthy(plan.targets[1].reason:match("editor"))
  testlib.eq(plan.targets[2].enabled, true)
end)

test("hyprland execution keeps project derived argv inside one dispatcher argument", function()
  local orchestrator = require("workstation.workspace_orchestrator")
  local argv = orchestrator.hyprland_exec_argv(
    { "notify-send", "hello; touch /tmp/pwn", "/repo/it's safe" },
    "2",
    "DP-1"
  )

  testlib.eq(#argv, 3)
  testlib.eq(argv[1], "hyprctl")
  testlib.eq(argv[2], "dispatch")
  testlib.truthy(argv[3]:match("hl%.dsp%.exec_cmd"))
  testlib.truthy(argv[3]:match('workspace = "2 silent"'))
  testlib.truthy(argv[3]:match('monitor = "DP%-1 silent"'))
  testlib.truthy(argv[3]:find("touch /tmp/pwn", 1, true))
end)

test("workspace executor continues after independent target failure", function()
  local orchestrator = require("workstation.workspace_orchestrator")
  local rt = runtime({ fail_spawn_at = 1 })
  local result = orchestrator.run(project, config({
    {
      name = "worker",
      argv = { "worker" },
    },
    {
      name = "editor",
      workspace = 2,
      operation = "editor",
    },
  }), adapter(), rt)

  testlib.eq(result.ok, false)
  testlib.eq(result.started, 1)
  testlib.eq(result.failed, 1)
  testlib.eq(result.results[1].status, "failed")
  testlib.eq(result.results[2].status, "started")
  testlib.eq(#rt.calls.spawn, 1)
  testlib.eq(#rt.calls.run, 1)
end)

test("workspace executor reports missing hyprctl only for placed targets", function()
  local orchestrator = require("workstation.workspace_orchestrator")
  local rt = runtime({ hyprctl = false })
  local result = orchestrator.run(project, config({
    {
      name = "placed",
      workspace = 2,
      argv = { "tool", "placed" },
    },
    {
      name = "plain",
      argv = { "tool", "plain" },
    },
  }), adapter(), rt)

  testlib.eq(result.ok, false)
  testlib.eq(result.started, 1)
  testlib.eq(result.failed, 1)
  testlib.truthy(result.results[1].error:match("hyprctl"))
  testlib.eq(rt.calls.spawn[1][2], "plain")
end)

test("workspace executor revalidates project identity before dispatch", function()
  local orchestrator = require("workstation.workspace_orchestrator")
  local rt = runtime({ realpath = "/repo/replaced" })
  local result = orchestrator.run(project, config({
    {
      name = "worker",
      argv = { "worker" },
    },
  }), adapter(), rt)

  testlib.eq(result.ok, false)
  testlib.truthy(result.error:match("identity"))
  testlib.eq(#rt.calls.spawn, 0)
  testlib.eq(#rt.calls.run, 0)
end)

test("workspace planner rejects missing workspace configuration", function()
  local orchestrator = require("workstation.workspace_orchestrator")
  local plan, err = orchestrator.plan(project, { overrides = {} }, adapter())

  testlib.eq(plan, nil)
  testlib.truthy(err:match("not configured"))
end)
