local test = require("tests.testlib")
local plugins = require("workstation.omarchy_plugins")

local function plugin(overrides)
  local value = {
    id = "example.plugin",
    name = "Example",
    repo = "https://github.com/example/plugin.git",
    rev = "1111111111111111111111111111111111111111",
    enabled = true,
    section = "right",
  }
  for key, item in pairs(overrides or {}) do
    value[key] = item
  end
  return value
end

local function fake_runtime(options)
  options = options or {}
  local state = {
    available = options.available ~= false,
    git_available = options.git_available ~= false,
    sources = {},
    links = {},
    upstreams = options.upstreams or {
      ["https://github.com/example/plugin.git"] = {
        id = "example.plugin",
      },
    },
    clone_count = 0,
    rescans = 0,
    enabled = {},
    disabled = {},
  }

  local runtime = {}

  function runtime.available()
    return state.available
  end

  function runtime.git_available()
    return state.git_available
  end

  function runtime.exists(path)
    return state.sources[path] ~= nil or state.links[path] ~= nil
  end

  function runtime.is_symlink(path)
    return state.links[path] ~= nil
  end

  function runtime.readlink(path)
    return state.links[path]
  end

  function runtime.mkdir_p()
    return true
  end

  function runtime.symlink(source, target)
    if runtime.exists(target) then
      return false
    end
    state.links[target] = source
    return true
  end

  function runtime.remove(path)
    state.links[path] = nil
    return true
  end

  function runtime.remove_tree(path)
    state.sources[path] = nil
    return true
  end

  function runtime.move(source, target)
    if not state.sources[source] then
      return false
    end
    state.sources[target] = state.sources[source]
    state.sources[source] = nil
    return true
  end

  function runtime.current_revision(path)
    return state.sources[path] and state.sources[path].rev or nil
  end

  function runtime.manifest_id(path)
    return state.sources[path] and state.sources[path].id or nil
  end

  function runtime.clone_pinned(repo, rev, path)
    state.clone_count = state.clone_count + 1
    local upstream = state.upstreams[repo]
    if not upstream then
      return false
    end
    state.sources[path] = {
      rev = rev,
      id = upstream.id,
    }
    return true
  end

  function runtime.rescan_plugins()
    state.rescans = state.rescans + 1
    return options.rescan_ok ~= false
  end

  function runtime.enable_plugin(id, section)
    state.enabled[id] = section or true
    return options.enable_ok ~= false
  end

  function runtime.disable_plugin(id)
    state.disabled[id] = true
    return true
  end

  return runtime, state
end

local HOME = "/home/test"
local STORE = HOME .. "/.local/share/hyprland_config/external-plugins/example.plugin"
local TARGET = HOME .. "/.config/omarchy/plugins/example.plugin"

test.test("external plugin manifest rejects floating revisions", function()
  local ok, err = plugins.validate_manifest({
    plugin({ rev = "main" }),
  })
  test.eq(ok, nil)
  test.truthy(err:match("40%-character") ~= nil)
end)

test.test("external plugin sync skips generic Hyprland without Omarchy", function()
  local runtime, state = fake_runtime({ available = false })
  local result = plugins.sync({
    home = HOME,
    manifest = { plugin() },
    runtime = runtime,
  })

  test.eq(result.ok, true)
  test.eq(result.skipped, true)
  test.eq(state.clone_count, 0)
end)

test.test("external plugin sync installs exact pin and enables plugin", function()
  local runtime, state = fake_runtime()
  local result = plugins.sync({
    home = HOME,
    manifest = { plugin() },
    runtime = runtime,
  })

  test.eq(result.ok, true)
  test.eq(result.changed, true)
  test.eq(state.sources[STORE].rev, plugin().rev)
  test.eq(state.links[TARGET], STORE)
  test.eq(state.enabled["example.plugin"], "right")
  test.eq(state.clone_count, 1)
end)

test.test("external plugin sync is idempotent at the pinned revision", function()
  local runtime, state = fake_runtime()

  plugins.sync({
    home = HOME,
    manifest = { plugin() },
    runtime = runtime,
  })
  local second = plugins.sync({
    home = HOME,
    manifest = { plugin() },
    runtime = runtime,
  })

  test.eq(second.ok, true)
  test.eq(second.changed, false)
  test.eq(state.clone_count, 1)
end)

test.test("external plugin sync refuses an occupied user plugin path", function()
  local runtime, state = fake_runtime()
  state.links[TARGET] = "/home/test/custom/plugin"

  local result = plugins.sync({
    home = HOME,
    manifest = { plugin() },
    runtime = runtime,
  })

  test.eq(result.ok, false)
  test.eq(state.links[TARGET], "/home/test/custom/plugin")
  test.eq(state.sources[STORE], nil)
  test.eq(state.clone_count, 0)
end)

test.test("external plugin sync replaces an old managed revision", function()
  local runtime, state = fake_runtime()
  state.sources[STORE] = {
    rev = "2222222222222222222222222222222222222222",
    id = "example.plugin",
  }
  state.links[TARGET] = STORE

  local result = plugins.sync({
    home = HOME,
    manifest = { plugin() },
    runtime = runtime,
  })

  test.eq(result.ok, true)
  test.eq(state.sources[STORE].rev, plugin().rev)
  test.eq(state.links[TARGET], STORE)
  test.eq(state.clone_count, 1)
end)

test.test("external plugin sync rejects an upstream manifest id mismatch", function()
  local runtime, state = fake_runtime({
    upstreams = {
      ["https://github.com/example/plugin.git"] = {
        id = "unexpected.plugin",
      },
    },
  })

  local result = plugins.sync({
    home = HOME,
    manifest = { plugin() },
    runtime = runtime,
  })

  test.eq(result.ok, false)
  test.eq(state.sources[STORE], nil)
  test.eq(state.links[TARGET], nil)
end)

test.test("external plugin removal deletes only owned plugin links and sources", function()
  local runtime, state = fake_runtime()
  state.sources[STORE] = {
    rev = plugin().rev,
    id = "example.plugin",
  }
  state.links[TARGET] = STORE

  local result = plugins.remove({
    home = HOME,
    manifest = { plugin() },
    runtime = runtime,
  })

  test.eq(result.ok, true)
  test.eq(result.changed, true)
  test.eq(state.sources[STORE], nil)
  test.eq(state.links[TARGET], nil)
  test.eq(state.disabled["example.plugin"], true)
end)

test.test("external plugin removal preserves conflicting user paths", function()
  local runtime, state = fake_runtime()
  state.sources[STORE] = {
    rev = plugin().rev,
    id = "example.plugin",
  }
  state.links[TARGET] = "/home/test/custom/plugin"

  local result = plugins.remove({
    home = HOME,
    manifest = { plugin() },
    runtime = runtime,
  })

  test.eq(result.ok, false)
  test.eq(state.links[TARGET], "/home/test/custom/plugin")
  test.truthy(state.sources[STORE] ~= nil)
end)
