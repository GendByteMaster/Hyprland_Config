local t = require("tests.testlib")
local mouse = require("hypr.workstation.mouse")

local function fake_store(initial)
  local store = { value = initial }

  function store.load()
    return store.value
  end

  function store.save(value)
    store.value = value
  end

  function store.clear()
    store.value = nil
  end

  return store
end

local function fake_api()
  local calls = { binds = {}, events = {}, configs = {} }
  local hl = { dsp = {} }

  function hl.config(config)
    table.insert(calls.configs, config)
  end

  function hl.bind(key, dispatcher, options)
    local handle = {
      key = key,
      dispatcher = dispatcher,
      options = options or {},
      enabled = true,
    }

    function handle.set_enabled(_, enabled)
      handle.enabled = enabled
    end

    function handle.is_enabled()
      return handle.enabled
    end

    table.insert(calls.binds, handle)
    return handle
  end

  function hl.unbind() end
  function hl.dispatch() end
  function hl.get_cursor_pos() return { x = 0, y = 0 } end
  function hl.get_windows() return {} end
  function hl.timer() return {} end
  function hl.on(event, fn) calls.events[event] = fn end

  local o = {}
  function o.rebind(keys, _, dispatcher, options)
    hl.unbind(keys)
    return hl.bind(keys, dispatcher, options)
  end

  return hl, o, calls
end

local function fake_hud()
  return { show = function() return true end }
end

local function fake_sound()
  return { play_mouse_mode = function() return true end }
end

t.test("Num Lock mode disables every Mouse Mode NumPad bind", function()
  local hl, o, calls = fake_api()
  mouse.register(hl, o, {
    numlock_store = fake_store(true),
    hud = fake_hud(),
    sound = fake_sound(),
  })

  local numlock_bind
  local mouse_binds = {}
  for _, bind in ipairs(calls.binds) do
    if bind.key == "Num_Lock" then
      numlock_bind = bind
    else
      table.insert(mouse_binds, bind)
    end
  end

  t.truthy(numlock_bind ~= nil)
  t.truthy(#mouse_binds > 0)

  for _, bind in ipairs(mouse_binds) do
    t.eq(bind.enabled, false)
  end

  numlock_bind.dispatcher()
  for _, bind in ipairs(mouse_binds) do
    t.eq(bind.enabled, true)
  end

  numlock_bind.dispatcher()
  for _, bind in ipairs(mouse_binds) do
    t.eq(bind.enabled, false)
  end
end)
