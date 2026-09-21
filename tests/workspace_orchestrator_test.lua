local testlib = require("tests.testlib")
local test = testlib.test
local hyprland_state = require("workstation.hyprland_state")

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

local function config(targets, monitors)
  return {
    monitors = monitors or {},
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
    clients = 0,
    monitors = 0,
    place = {},
    sleep = {},
  }

  local client_sequences = options.client_sequences or { options.clients or {} }

  local rt = {
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
    clients = function()
      calls.clients = calls.clients + 1
      if options.clients_error then
        return nil, options.clients_error
      end
      local index = math.min(calls.clients, #client_sequences)
      return client_sequences[index] or {}
    end,
    monitors = function()
      calls.monitors = calls.monitors + 1
      if options.monitors_error then
        return nil, options.monitors_error
      end
      return options.monitors or {
        { id = 0, name = "DP-1", focused = true, x = 0, y = 0 },
        { id = 1, name = "HDMI-A-1", focused = false, x = 1920, y = 0 },
      }
    end,
    find_match = hyprland_state.find_match,
    address_set = hyprland_state.address_set,
    place_client = function(address, workspace, monitor)
      calls.place[#calls.place + 1] = {
        address = address,
        workspace = workspace,
        monitor = monitor,
      }
      if options.fail_place then
        return nil, "placement failed"
      end
      return true
    end,
    sleep_ms = function(ms)
      calls.sleep[#calls.sleep + 1] = ms
      return true
    end,
  }

  return rt
end

local function client(address, class, workspace_id, monitor_id)
  return {
    address = address,
    class = class,
    initial_class = class,
    title = class,
    initial_title = class,
    workspace_id = workspace_id or 1,
    workspace_name = tostring(workspace_id or 1),
    monitor_id = monitor_id or 0,
    mapped = true,
    hidden = false,
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

test("workspace planner preserves singleton matching and monitor aliases", function()
  local orchestrator = require("workstation.workspace_orchestrator")
  local plan = assert(orchestrator.plan(project, config({
    {
      name = "editor",
      workspace = 1,
      monitor = "primary",
      operation = "editor",
      singleton = true,
      wait_ms = 750,
      match = {
        class = "Code",
        title = "Voxelyra",
      },
    },
  }, {
    primary = "DP-2",
  }), adapter()))

  testlib.eq(plan.targets[1].singleton, true)
  testlib.eq(plan.targets[1].wait_ms, 750)
  testlib.eq(plan.targets[1].match.class, "Code")
  testlib.eq(plan.targets[1].match.title, "Voxelyra")
  testlib.eq(plan.monitor_aliases.primary, "DP-2")
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

test("logical monitor roles resolve from focused then geometric order", function()
  local orchestrator = require("workstation.workspace_orchestrator")
  local monitors = {
    { id = 2, name = "LEFT", focused = false, x = -1920, y = 0 },
    { id = 0, name = "CENTER", focused = true, x = 0, y = 0 },
    { id = 1, name = "RIGHT", focused = false, x = 1920, y = 0 },
  }

  local primary = orchestrator.resolve_monitor("primary", {}, monitors)
  local secondary = orchestrator.resolve_monitor("secondary", {}, monitors)
  local tertiary = orchestrator.resolve_monitor("tertiary", {}, monitors)

  testlib.eq(primary, "CENTER")
  testlib.eq(secondary, "LEFT")
  testlib.eq(tertiary, "RIGHT")
end)

test("configured monitor alias wins when target monitor exists", function()
  local orchestrator = require("workstation.workspace_orchestrator")
  local resolved, degraded = orchestrator.resolve_monitor("primary", {
    primary = "RIGHT",
  }, {
    { id = 0, name = "CENTER", focused = true, x = 0, y = 0 },
    { id = 1, name = "RIGHT", focused = false, x = 1920, y = 0 },
  })

  testlib.eq(resolved, "RIGHT")
  testlib.eq(degraded, false)
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

test("singleton target skips an already running matching client", function()
  local orchestrator = require("workstation.workspace_orchestrator")
  local rt = runtime({
    clients = {
      client("0x10", "Code", 1, 0),
    },
  })

  local result = orchestrator.run(project, config({
    {
      name = "editor",
      operation = "editor",
      singleton = true,
      match = { class = "code" },
    },
  }), adapter(), rt)

  testlib.eq(result.ok, true)
  testlib.eq(result.started, 0)
  testlib.eq(result.skipped, 1)
  testlib.eq(result.results[1].status, "skipped")
  testlib.eq(result.results[1].address, "0x10")
  testlib.eq(#rt.calls.spawn, 0)
  testlib.eq(#rt.calls.run, 0)
end)

test("matched forked window gets bounded post launch workspace correction", function()
  local orchestrator = require("workstation.workspace_orchestrator")
  local rt = runtime({
    client_sequences = {
      {},
      {
        client("0x20", "Code", 1, 0),
      },
    },
  })

  local result = orchestrator.run(project, config({
    {
      name = "editor",
      operation = "editor",
      workspace = 2,
      wait_ms = 100,
      match = { class = "code" },
    },
  }), adapter(), rt)

  testlib.eq(result.ok, true)
  testlib.eq(result.started, 1)
  testlib.eq(result.degraded, 0)
  testlib.eq(result.results[1].corrected, true)
  testlib.eq(result.results[1].address, "0x20")
  testlib.eq(#rt.calls.place, 1)
  testlib.eq(rt.calls.place[1].workspace, "2")
  testlib.eq(rt.calls.place[1].monitor, nil)
end)

test("combined workspace and monitor mismatch is reported degraded instead of unsafe correction", function()
  local orchestrator = require("workstation.workspace_orchestrator")
  local rt = runtime({
    client_sequences = {
      {},
      {
        client("0x30", "Code", 1, 0),
      },
    },
    monitors = {
      { id = 0, name = "DP-1", focused = true, x = 0, y = 0 },
      { id = 1, name = "DP-2", focused = false, x = 1920, y = 0 },
    },
  })

  local result = orchestrator.run(project, config({
    {
      name = "editor",
      operation = "editor",
      workspace = 2,
      monitor = "DP-2",
      wait_ms = 100,
      match = { class = "code" },
    },
  }), adapter(), rt)

  testlib.eq(result.ok, false)
  testlib.eq(result.started, 1)
  testlib.eq(result.degraded, 1)
  testlib.eq(result.results[1].degraded, true)
  testlib.truthy(result.results[1].warning:match("combined"))
  testlib.eq(#rt.calls.place, 0)
end)

test("bounded matching timeout reports degraded start instead of blocking indefinitely", function()
  local orchestrator = require("workstation.workspace_orchestrator")
  local rt = runtime({
    client_sequences = {
      {},
      {},
      {},
      {},
    },
  })

  local result = orchestrator.run(project, config({
    {
      name = "editor",
      operation = "editor",
      workspace = 2,
      wait_ms = 100,
      match = { class = "code" },
    },
  }), adapter(), rt)

  testlib.eq(result.ok, false)
  testlib.eq(result.started, 1)
  testlib.eq(result.degraded, 1)
  testlib.truthy(result.results[1].warning:match("100ms"))
  testlib.eq(#rt.calls.sleep, 2)
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

test("workspace planner creates automatic editor and shell targets without config", function()
  local orchestrator = require("workstation.workspace_orchestrator")
  local plan, err = orchestrator.plan(project, { overrides = {} }, adapter())

  testlib.eq(err, nil)
  testlib.eq(plan.automatic, true)
  testlib.eq(#plan.targets, 2)
  testlib.eq(plan.targets[1].name, "editor")
  testlib.eq(plan.targets[1].workspace, "1")
  testlib.eq(plan.targets[1].argv[1], "code")
  testlib.eq(plan.targets[2].name, "shell")
  testlib.eq(plan.targets[2].workspace, "2")
  testlib.eq(plan.targets[2].argv[1], "foot")
  testlib.eq(plan.targets[2].argv[3], "bash")
end)

test("explicit workspace targets replace automatic defaults", function()
  local orchestrator = require("workstation.workspace_orchestrator")
  local plan = assert(orchestrator.plan(project, config({
    {
      name = "custom",
      workspace = 7,
      argv = { "worker" },
    },
  }), adapter()))

  testlib.eq(plan.automatic, false)
  testlib.eq(#plan.targets, 1)
  testlib.eq(plan.targets[1].name, "custom")
  testlib.eq(plan.targets[1].workspace, "7")
end)

test("workspace planner isolates malformed target instead of crashing", function()
  local orchestrator = require("workstation.workspace_orchestrator")
  local plan = assert(orchestrator.plan(project, {
    overrides = {
      [project.path] = {
        workspace = {
          targets = {
            "not-a-table",
            {
              name = "valid",
              argv = { "worker" },
            },
          },
        },
      },
    },
  }, adapter()))

  testlib.eq(plan.targets[1].enabled, false)
  testlib.truthy(plan.targets[1].reason:match("table"))
  testlib.eq(plan.targets[2].enabled, true)
end)

test("disconnected configured monitor alias falls back with degraded reason", function()
  local orchestrator = require("workstation.workspace_orchestrator")
  local resolved, degraded, reason = orchestrator.resolve_monitor("primary", {
    primary = "MISSING",
  }, {
    { id = 0, name = "CENTER", focused = true, x = 0, y = 0 },
    { id = 1, name = "RIGHT", focused = false, x = 1920, y = 0 },
  })

  testlib.eq(resolved, "CENTER")
  testlib.eq(degraded, true)
  testlib.truthy(reason:match("unavailable"))
end)

test("failed prelaunch client snapshot degrades instead of matching an old window", function()
  local orchestrator = require("workstation.workspace_orchestrator")
  local rt = runtime({
    clients_error = "clients unavailable",
  })

  local result = orchestrator.run(project, config({
    {
      name = "editor",
      operation = "editor",
      workspace = 2,
      wait_ms = 100,
      match = { class = "code" },
    },
  }), adapter(), rt)

  testlib.eq(result.ok, false)
  testlib.eq(result.started, 1)
  testlib.eq(result.degraded, 1)
  testlib.truthy(result.results[1].warning:match("snapshot"))
  testlib.eq(#rt.calls.place, 0)
end)
