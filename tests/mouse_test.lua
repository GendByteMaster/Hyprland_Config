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

local function fake_hud()
  local hud = { events = {} }

  function hud.show(mode, button)
    table.insert(hud.events, { mode = mode, button = button })
    return true
  end

  return hud
end

local function fake_api(options)
  options = options or {}

  local calls = {
    binds = {}, rebinds = {}, unbinds = {}, dispatches = {}, timers = {}, events = {}, configs = {}, submaps = {}
  }
  local current_definition = "reset"
  local current_submap = ""
  local cursor = { x = 100, y = 100 }

  local hl = {
    dsp = { cursor = {} },
  }

  function hl.dsp.submap(name) return { kind = "submap", name = name } end
  function hl.dsp.cursor.move(args) return { kind = "cursor_move", x = args.x, y = args.y } end
  function hl.dsp.send_key_state(args) return { kind = "send_key_state", key = args.key, state = args.state, mods = args.mods } end
  function hl.dsp.exec_cmd() error("Mouse movement must not execute external commands") end
  function hl.config(config) table.insert(calls.configs, config) end
  function hl.bind(keys, dispatcher, bind_options)
    table.insert(calls.binds, { submap = current_definition, keys = keys, dispatcher = dispatcher, options = bind_options or {} })
  end
  function hl.unbind(keys)
    table.insert(calls.unbinds, keys)
  end
  function hl.define_submap(name, fn)
    table.insert(calls.submaps, name)
    local previous = current_definition
    current_definition = name
    fn()
    current_definition = previous
  end
  function hl.dispatch(action)
    table.insert(calls.dispatches, action)
    if action.kind == "submap" then current_submap = action.name == "reset" and "" or action.name end
    if action.kind == "cursor_move" then cursor.x, cursor.y = action.x, action.y end
  end
  function hl.get_cursor_pos() return { x = cursor.x, y = cursor.y } end
  function hl.get_current_submap() return current_submap end
  function hl.timer(fn, timer_options)
    local timer = { fn = fn, options = timer_options }
    table.insert(calls.timers, timer)
    return timer
  end
  function hl.on(event, fn) calls.events[event] = fn end

  local o = {}
  function o.bind(keys, description, dispatcher, bind_options)
    local opts = bind_options or {}
    opts.description = description
    hl.bind(keys, dispatcher, opts)
  end

  if not options.without_rebind then
    function o.rebind(keys, description, dispatcher, bind_options)
      table.insert(calls.rebinds, { keys = keys, description = description, dispatcher = dispatcher, options = bind_options or {} })
      hl.bind(keys, dispatcher, bind_options)
    end
  end

  local function find_bind(key, release)
    for _, bind in ipairs(calls.binds) do
      if bind.submap == "reset" and bind.keys == key and not not bind.options.release == not not release then
        return bind
      end
    end
  end

  return hl, o, calls, find_bind
end

t.test("register reserves Num Lock and defines global NumFlow button selectors", function()
  local hl, o, calls, find = fake_api()
  local hud = fake_hud()
  mouse.register(hl, o, { numlock_store = fake_store(nil), hud = hud })

  t.eq(#calls.rebinds, 1)
  t.eq(calls.rebinds[1].keys, "Num_Lock")
  t.eq(calls.rebinds[1].description, "Mouse mode / Num Lock")
  t.truthy(calls.rebinds[1].options.submap_universal)
  t.truthy(calls.rebinds[1].options.non_consuming)
  t.eq(calls.configs[1].input.numlock_by_default, true)
  t.eq(#calls.submaps, 0)
  t.truthy(find("KP_8", false))
  t.truthy(find("KP_Up", false))
  t.truthy(find("KP_5", false))
  t.truthy(find("KP_Add", false))
  t.truthy(find("KP_Divide", false))
  t.truthy(find("KP_Multiply", false))
  t.truthy(find("KP_Subtract", false))
  t.truthy(find("KP_0", false))
  t.truthy(find("KP_Decimal", false))
  t.eq(find("escape", false), nil)
  t.truthy(find("KP_8", false).options.auto_consuming)
end)

t.test("register supports Omarchy helpers without rebind", function()
  local hl, o, calls = fake_api({ without_rebind = true })
  local ok = pcall(function()
    mouse.register(hl, o, { numlock_store = fake_store(nil), hud = fake_hud() })
  end)

  t.eq(ok, true)
  t.eq(#calls.unbinds, 1)
  t.eq(calls.unbinds[1], "Num_Lock")

  local numlock_bind
  for _, bind in ipairs(calls.binds) do
    if bind.submap == "reset" and bind.keys == "Num_Lock" then
      numlock_bind = bind
      break
    end
  end

  t.truthy(numlock_bind)
  t.truthy(numlock_bind.options.submap_universal)
  t.truthy(numlock_bind.options.non_consuming)
  t.eq(numlock_bind.options.description, "Mouse mode / Num Lock")
end)

t.test("Num Lock off enables Mouse Mode HUD without entering a submap", function()
  local hl, o, calls = fake_api()
  local store = fake_store(true)
  local hud = fake_hud()
  mouse.register(hl, o, { numlock_store = store, hud = hud })
  local numlock = calls.rebinds[1].dispatcher

  numlock()
  t.eq(store.value, false)
  t.eq(#calls.dispatches, 0)
  t.eq(hud.events[#hud.events].mode, "mouse")
  t.eq(hud.events[#hud.events].button, "LMB")

  numlock()
  t.eq(store.value, true)
  t.eq(#calls.dispatches, 0)
  t.eq(hud.events[#hud.events].mode, "numpad")
end)

t.test("NumPad events pass through while Num Lock is on", function()
  local hl, o, calls, find = fake_api()
  mouse.register(hl, o, { numlock_store = fake_store(true), hud = fake_hud() })

  local up = find("KP_8", false)
  local up_release = find("KP_8", true)
  local press_result = up.dispatcher()
  local release_result = up_release.dispatcher()

  t.eq(press_result.ok, false)
  t.eq(release_result.ok, false)
  t.truthy(up.options.auto_consuming)
  t.truthy(up_release.options.auto_consuming)
  t.eq(#calls.dispatches, 0)
end)

t.test("reload restores Mouse Mode HUD when session Num Lock state is off", function()
  local hl, o, calls = fake_api()
  local hud = fake_hud()
  mouse.register(hl, o, { numlock_store = fake_store(false), hud = hud })

  t.eq(#calls.dispatches, 0)
  calls.events["config.reloaded"]()
  t.eq(#calls.dispatches, 0)
  t.eq(hud.events[#hud.events].mode, "mouse")
end)

t.test("movement uses cursor dispatcher with acceleration and does not touch HUD", function()
  local hl, o, calls, find = fake_api()
  local hud = fake_hud()
  mouse.register(hl, o, { numlock_store = fake_store(false), hud = hud })
  local up = find("KP_8", false)
  local up_release = find("KP_8", true)

  t.eq(up.dispatcher().ok, true)
  t.eq(calls.dispatches[#calls.dispatches].x, 100)
  t.eq(calls.dispatches[#calls.dispatches].y, 97)
  up.dispatcher()
  up.dispatcher()
  t.eq(calls.dispatches[#calls.dispatches].y, 88)
  up_release.dispatcher()
  up.dispatcher()
  t.eq(calls.dispatches[#calls.dispatches].y, 85)
  t.eq(#hud.events, 0)
end)

t.test("diagonal movement is normalized", function()
  local hl, o, calls, find = fake_api()
  mouse.register(hl, o, { numlock_store = fake_store(false), hud = fake_hud() })
  find("KP_9", false).dispatcher()
  local action = calls.dispatches[#calls.dispatches]
  t.eq(action.x, 102)
  t.eq(action.y, 98)
end)

t.test("slash star minus select LMB RMB MMB and update HUD", function()
  local hl, o, calls, find = fake_api()
  local hud = fake_hud()
  mouse.register(hl, o, { numlock_store = fake_store(false), hud = hud })

  find("KP_Multiply", false).dispatcher()
  t.eq(hud.events[#hud.events].button, "RMB")
  t.eq(#calls.dispatches, 0)

  find("KP_Subtract", false).dispatcher()
  t.eq(hud.events[#hud.events].button, "MMB")
  t.eq(#calls.dispatches, 0)

  find("KP_Divide", false).dispatcher()
  t.eq(hud.events[#hud.events].button, "LMB")
  t.eq(#calls.dispatches, 0)
end)

t.test("NumPad 5 clicks the selected button", function()
  local hl, o, calls, find = fake_api()
  mouse.register(hl, o, { numlock_store = fake_store(false), hud = fake_hud() })

  find("KP_Multiply", false).dispatcher()
  find("KP_5", false).dispatcher()
  t.eq(calls.dispatches[#calls.dispatches - 1].key, "mouse:273")
  t.eq(calls.dispatches[#calls.dispatches - 1].state, "down")
  t.eq(calls.dispatches[#calls.dispatches].state, "up")
end)

t.test("double click uses the selected button", function()
  local hl, o, calls, find = fake_api()
  mouse.register(hl, o, { numlock_store = fake_store(false), hud = fake_hud() })
  find("KP_Subtract", false).dispatcher()
  find("KP_Add", false).dispatcher()
  t.eq(calls.dispatches[#calls.dispatches - 1].key, "mouse:274")
  t.eq(#calls.timers, 1)
  t.eq(calls.timers[1].options.type, "oneshot")
  t.eq(calls.timers[1].options.timeout, 70)
  calls.timers[1].fn()
  t.eq(calls.dispatches[#calls.dispatches - 1].key, "mouse:274")
  t.eq(calls.dispatches[#calls.dispatches].state, "up")
end)

t.test("hold and release track the actual selected button", function()
  local hl, o, calls, find = fake_api()
  mouse.register(hl, o, { numlock_store = fake_store(false), hud = fake_hud() })

  find("KP_Multiply", false).dispatcher()
  find("KP_0", false).dispatcher()
  find("KP_0", false).dispatcher()
  t.eq(calls.dispatches[#calls.dispatches].key, "mouse:273")
  t.eq(calls.dispatches[#calls.dispatches].state, "down")

  local before = #calls.dispatches
  find("KP_Decimal", false).dispatcher()
  t.eq(#calls.dispatches, before + 1)
  t.eq(calls.dispatches[#calls.dispatches].key, "mouse:273")
  t.eq(calls.dispatches[#calls.dispatches].state, "up")
end)

t.test("changing button mode releases an active hold before switching", function()
  local hl, o, calls, find = fake_api()
  mouse.register(hl, o, { numlock_store = fake_store(false), hud = fake_hud() })

  find("KP_0", false).dispatcher()
  find("KP_Multiply", false).dispatcher()
  t.eq(calls.dispatches[#calls.dispatches].key, "mouse:272")
  t.eq(calls.dispatches[#calls.dispatches].state, "up")
end)

t.test("config reload releases a held selected button", function()
  local hl, o, calls, find = fake_api()
  mouse.register(hl, o, { numlock_store = fake_store(false), hud = fake_hud() })
  find("KP_Subtract", false).dispatcher()
  find("KP_0", false).dispatcher()
  calls.events["config.reloaded"]()
  t.eq(calls.dispatches[#calls.dispatches].key, "mouse:274")
  t.eq(calls.dispatches[#calls.dispatches].state, "up")
end)

t.test("other submaps release a held selected button without owning Mouse Mode", function()
  local hl, o, calls, find = fake_api()
  mouse.register(hl, o, { numlock_store = fake_store(false), hud = fake_hud() })
  find("KP_0", false).dispatcher()
  calls.events["keybinds.submap"]("resize")
  t.eq(calls.dispatches[#calls.dispatches].key, "mouse:272")
  t.eq(calls.dispatches[#calls.dispatches].state, "up")
end)

t.test("Hyprland shutdown clears the session Num Lock state", function()
  local hl, o, calls = fake_api()
  local store = fake_store(false)
  mouse.register(hl, o, { numlock_store = store, hud = fake_hud() })

  calls.events["hyprland.shutdown"]()
  t.eq(store.value, nil)
end)
