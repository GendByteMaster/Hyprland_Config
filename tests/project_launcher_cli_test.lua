local testlib = require("tests.testlib")
local test = testlib.test

local function fake_context(options)
  options = options or {}
  local ctx = {
    discovery_calls = 0,
    cache_reads = 0,
    cache_writes = 0,
    state_saves = 0,
    execute_calls = 0,
    cache_projects = options.cache_projects,
    discovered_projects = options.discovered_projects or {},
    warnings = options.warnings or {},
    state = options.state or { favorites = {}, recent = {} },
    action_list = options.action_list or {},
    execute_result = options.execute_result or { ok = true },
    now_value = options.now_value or 100,
  }

  function ctx.load_config()
    return {
      roots = { "/repo" },
      projects = {},
      hidden = {},
      overrides = {},
      apps = { terminal = "auto" },
      max_depth = 4,
    }, options.config_warning
  end

  function ctx.discover()
    ctx.discovery_calls = ctx.discovery_calls + 1
    return {
      projects = ctx.discovered_projects,
      warnings = ctx.warnings,
    }
  end

  function ctx.cache_read()
    ctx.cache_reads = ctx.cache_reads + 1
    return ctx.cache_projects
  end

  function ctx.cache_write(projects)
    ctx.cache_writes = ctx.cache_writes + 1
    ctx.cache_projects = projects
    return true
  end

  function ctx.load_state()
    return ctx.state, options.state_warning
  end

  function ctx.save_state(state)
    ctx.state_saves = ctx.state_saves + 1
    ctx.state = state
    return true
  end

  function ctx.rank(projects, query, state)
    local result = {}
    local needle = tostring(query or ""):lower()
    for _, project in ipairs(projects or {}) do
      if needle == "" or project.name:lower():find(needle, 1, true) then
        result[#result + 1] = project
      end
    end
    return result
  end

  function ctx.resolve_actions(project, state)
    local actions = {}
    for index, action in ipairs(ctx.action_list) do
      local copy = {}
      for key, value in pairs(action) do
        copy[key] = value
      end
      actions[index] = copy
    end
    return actions
  end

  function ctx.execute(project, action, confirmed)
    ctx.execute_calls = ctx.execute_calls + 1
    ctx.last_execute = {
      project = project,
      action = action,
      confirmed = confirmed,
    }
    return ctx.execute_result
  end

  function ctx.toggle_favorite(state, project_id)
    if state.favorites[project_id] then
      state.favorites[project_id] = nil
      return false
    end
    state.favorites[project_id] = true
    return true
  end

  function ctx.mark_recent(state, project_id, now)
    state.recent = {
      { id = project_id, used_at = now },
    }
  end

  function ctx.now()
    return ctx.now_value
  end

  return ctx
end

local function project(id, name)
  return {
    id = id,
    path = id,
    name = name,
    source = "discovered",
    stale = false,
  }
end

test("refresh discovers writes cache and returns warnings", function()
  local cli = require("workstation.project_launcher_cli")
  local ctx = fake_context({
    discovered_projects = {
      project("/repo/NumFlow", "NumFlow"),
    },
    warnings = { "root missing: /other" },
  })

  local result = cli.run({ "refresh" }, ctx)
  testlib.eq(result.ok, true)
  testlib.eq(ctx.discovery_calls, 1)
  testlib.eq(ctx.cache_writes, 1)
  testlib.eq(result.data.projects[1].name, "NumFlow")
  testlib.eq(result.data.warnings[1], "root missing: /other")
end)

test("query reads cache instead of rescanning", function()
  local cli = require("workstation.project_launcher_cli")
  local ctx = fake_context({
    cache_projects = {
      project("/repo/NumFlow", "NumFlow"),
      project("/repo/Voxelyra", "Voxelyra"),
    },
  })

  local result = cli.run({ "query", "num" }, ctx)
  testlib.eq(result.ok, true)
  testlib.eq(result.data.projects[1].name, "NumFlow")
  testlib.eq(#result.data.projects, 1)
  testlib.eq(ctx.discovery_calls, 0)
end)

test("query refreshes once when cache is absent", function()
  local cli = require("workstation.project_launcher_cli")
  local ctx = fake_context({
    discovered_projects = {
      project("/repo/NumFlow", "NumFlow"),
    },
  })

  local result = cli.run({ "query", "num" }, ctx)
  testlib.eq(result.ok, true)
  testlib.eq(ctx.discovery_calls, 1)
  testlib.eq(ctx.cache_writes, 1)
  testlib.eq(result.data.projects[1].id, "/repo/NumFlow")
end)

test("actions resolves cached project only", function()
  local cli = require("workstation.project_launcher_cli")
  local ctx = fake_context({
    cache_projects = {
      project("/repo/a", "A"),
    },
    action_list = {
      { id = "open-shell", label = "Open Shell", enabled = true, terminal = true },
    },
  })

  local result = cli.run({ "actions", "/repo/a" }, ctx)
  testlib.eq(result.ok, true)
  testlib.eq(result.data.project.id, "/repo/a")
  testlib.eq(result.data.actions[1].id, "open-shell")
end)

test("actions rejects unknown project", function()
  local cli = require("workstation.project_launcher_cli")
  local ctx = fake_context({
    cache_projects = {
      project("/repo/a", "A"),
    },
  })

  local result = cli.run({ "actions", "/repo/missing" }, ctx)
  testlib.eq(result.ok, false)
  testlib.truthy(result.error:match("project"))
end)

test("favorite toggles and persists state", function()
  local cli = require("workstation.project_launcher_cli")
  local ctx = fake_context({
    cache_projects = {
      project("/repo/a", "A"),
    },
  })

  local result = cli.run({ "favorite", "/repo/a" }, ctx)
  testlib.eq(result.ok, true)
  testlib.eq(result.data.favorite, true)
  testlib.eq(ctx.state.favorites["/repo/a"], true)
  testlib.eq(ctx.state_saves, 1)
end)

test("run returns confirmation request without recent or spawn success bookkeeping", function()
  local cli = require("workstation.project_launcher_cli")
  local ctx = fake_context({
    cache_projects = {
      project("/repo/a", "A"),
    },
    action_list = {
      {
        id = "compose-down",
        label = "Compose Down",
        enabled = true,
        confirm = true,
        terminal = true,
      },
    },
    execute_result = {
      ok = false,
      requires_confirmation = true,
    },
  })

  local result = cli.run({ "run", "/repo/a", "compose-down" }, ctx)
  testlib.eq(result.ok, true)
  testlib.eq(result.data.requires_confirmation, true)
  testlib.eq(ctx.execute_calls, 1)
  testlib.eq(ctx.state_saves, 0)
  testlib.eq(#ctx.state.recent, 0)
end)

test("confirmed run marks recent only after successful dispatch", function()
  local cli = require("workstation.project_launcher_cli")
  local ctx = fake_context({
    cache_projects = {
      project("/repo/a", "A"),
    },
    action_list = {
      {
        id = "git-status",
        label = "Git Status",
        enabled = true,
        terminal = true,
      },
    },
    execute_result = { ok = true },
    now_value = 1234,
  })

  local result = cli.run({ "run", "/repo/a", "git-status", "--confirmed" }, ctx)
  testlib.eq(result.ok, true)
  testlib.eq(result.data.dispatched, true)
  testlib.eq(ctx.last_execute.confirmed, true)
  testlib.eq(ctx.state.recent[1].id, "/repo/a")
  testlib.eq(ctx.state.recent[1].used_at, 1234)
  testlib.eq(ctx.state_saves, 1)
end)

test("failed run does not mark recent", function()
  local cli = require("workstation.project_launcher_cli")
  local ctx = fake_context({
    cache_projects = {
      project("/repo/a", "A"),
    },
    action_list = {
      {
        id = "git-status",
        label = "Git Status",
        enabled = true,
        terminal = true,
      },
    },
    execute_result = {
      ok = false,
      error = "terminal unavailable",
    },
  })

  local result = cli.run({ "run", "/repo/a", "git-status" }, ctx)
  testlib.eq(result.ok, false)
  testlib.truthy(result.error:match("terminal"))
  testlib.eq(ctx.state_saves, 0)
  testlib.eq(#ctx.state.recent, 0)
end)

test("run favorite action uses state layer instead of executor", function()
  local cli = require("workstation.project_launcher_cli")
  local ctx = fake_context({
    cache_projects = {
      project("/repo/a", "A"),
    },
    action_list = {
      {
        id = "favorite",
        label = "Favorite",
        operation = "favorite",
        enabled = true,
      },
    },
  })

  local result = cli.run({ "run", "/repo/a", "favorite" }, ctx)
  testlib.eq(result.ok, true)
  testlib.eq(result.data.favorite, true)
  testlib.eq(ctx.execute_calls, 0)
  testlib.eq(ctx.state_saves, 1)
end)

test("protocol encoding preserves empty launcher lists as arrays", function()
  local cli = require("workstation.project_launcher_cli")
  local protocol = require("workstation.launcher_protocol")
  local ctx = fake_context({
    discovered_projects = {},
    warnings = {},
  })

  local result = cli.run({ "refresh" }, ctx)
  local encoded = protocol.encode(result)
  testlib.truthy(encoded:match('"projects":%[%]'))
  testlib.truthy(encoded:match('"warnings":%[%]'))
end)

test("unknown launcher command returns protocol failure", function()
  local cli = require("workstation.project_launcher_cli")
  local result = cli.run({ "wat" }, fake_context())
  testlib.eq(result.ok, false)
  testlib.truthy(result.error:match("unknown"))
end)

test("missing launcher command returns usage failure", function()
  local cli = require("workstation.project_launcher_cli")
  local result = cli.run({}, fake_context())
  testlib.eq(result.ok, false)
  testlib.truthy(result.error:match("usage"))
end)
