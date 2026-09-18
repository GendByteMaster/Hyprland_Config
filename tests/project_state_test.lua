local testlib = require("tests.testlib")
local test = testlib.test

local function memory_runtime(initial)
  local files = initial or {}
  return {
    exists = function(path)
      return files[path] ~= nil
    end,
    read = function(path)
      return files[path]
    end,
    write_atomic = function(path, content)
      files[path] = content
      return true
    end,
    files = files,
  }
end

test("project state starts empty when no file exists", function()
  local state_module = require("workstation.project_state")
  local state, warning = state_module.load({
    home = "/home/test",
    runtime = memory_runtime(),
  })
  testlib.eq(warning, nil)
  testlib.eq(next(state.favorites), nil)
  testlib.eq(#state.recent, 0)
end)

test("project state toggles favorite and persists it", function()
  local state_module = require("workstation.project_state")
  local runtime = memory_runtime()
  local options = { home = "/home/test", runtime = runtime }

  local state = state_module.load(options)
  testlib.eq(state_module.toggle_favorite(state, "/repo/a"), true)
  testlib.eq(state.favorites["/repo/a"], true)
  testlib.truthy(state_module.save(state, options))

  local loaded = state_module.load(options)
  testlib.eq(loaded.favorites["/repo/a"], true)
  testlib.eq(state_module.toggle_favorite(loaded, "/repo/a"), false)
  testlib.eq(loaded.favorites["/repo/a"], nil)
end)

test("project state recent deduplicates and moves latest to front", function()
  local state_module = require("workstation.project_state")
  local state = { favorites = {}, recent = {} }

  state_module.mark_recent(state, "/repo/a", 10)
  state_module.mark_recent(state, "/repo/b", 20)
  state_module.mark_recent(state, "/repo/a", 30)

  testlib.eq(#state.recent, 2)
  testlib.eq(state.recent[1].id, "/repo/a")
  testlib.eq(state.recent[1].used_at, 30)
  testlib.eq(state.recent[2].id, "/repo/b")
end)

test("project state caps recent history at fifty", function()
  local state_module = require("workstation.project_state")
  local state = { favorites = {}, recent = {} }

  for index = 1, 60 do
    state_module.mark_recent(state, "/repo/" .. index, index)
  end

  testlib.eq(#state.recent, 50)
  testlib.eq(state.recent[1].id, "/repo/60")
  testlib.eq(state.recent[50].id, "/repo/11")
end)

test("corrupt project state returns empty state with warning", function()
  local state_module = require("workstation.project_state")
  local path = "/state/state.json"
  local runtime = memory_runtime({ [path] = "{oops" })
  local state, warning = state_module.load({
    home = "/home/test",
    state_path = path,
    runtime = runtime,
  })

  testlib.eq(next(state.favorites), nil)
  testlib.eq(#state.recent, 0)
  testlib.truthy(warning)
end)

test("invalid project state shape is ignored", function()
  local state_module = require("workstation.project_state")
  local path = "/state/state.json"
  local runtime = memory_runtime({
    [path] = '{"version":1,"favorites":[],"recent":"bad"}',
  })
  local state, warning = state_module.load({
    home = "/home/test",
    state_path = path,
    runtime = runtime,
  })

  testlib.eq(next(state.favorites), nil)
  testlib.truthy(warning)
end)
