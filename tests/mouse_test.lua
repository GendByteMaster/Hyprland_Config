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
  local calls = {
    binds = {}, rebinds = {}, dispatches = {}, timers = {}, events = {}, notifications = {}, configs = {}
  }
  local current_definition = "reset"
  local current_submap = ""
  local cursor = { x = 100, y = 100 }

  local hl = {
    dsp = { cursor = {} },
    notification = {},
  }

  function hl.dsp.submap(name) return { kind = "submap", name = name } end
  function hl.dsp.cursor.move(args) return { kind = "cursor_move", x = args.x, y = args.y } end
  function hl.dsp.send_key_state(args) return { kind = "send_key_state", key = args.key, state = args.state, mods = args.mods } end
  function hl.dsp.exec_cmd() error("Mouse Mode must not execute external commands") end
  function hl.config(options) table.insert(calls.configs, options) end
  function hl.bind(keys, dispatcher, options)
    table.insert(calls.binds, { submap = current_definition, keys = keys, dispatcher = dispatcher, options = options or {} })
  end
  function hl.define_submap(name, fn)
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
  function hl.timer(fn, options)
    local timer = { fn = fn, options = options }
    table.insert(calls.timers, timer)
    return timer
  end
  function hl.on(event, fn) calls.events[event] = fn end
  function hl.notification.create(options) table.insert(calls.notifications, options) end

  local o = {}
  function o.rebind(keys, description, dispatcher, options)
    table.insert(calls.rebinds, { keys = keys, description = description, dispatcher = dispatcher, options = options or {} })
    hl.bind(keys, dispatcher, options)
  end

  local function find_bind(key, release)
    for _, bind in ipairs(calls.binds) do
      if bind.submap == "mouse" and bind.keys == key and not not bind.options.release == not not release then
        return bind
      end
    end
  end

  return hl, o, calls, find_bind
end

t.test("register reserves Num Lock and starts with Num Lock enabled", function()
  local hl, o, calls, find = fake_api()
  local store = fake_store(nil)
  mouse.register(hl, o, { numlock_store = store })

  t.eq(#calls.rebinds, 1)
  t.eq(calls.rebinds[1].keys, "Num_Lock")
  t.eq(calls.rebinds[1].description, "Mouse mode / Num Lock")
  t.truthy(calls.rebinds[1].options.submap_universal)
  t.truthy(calls.rebinds[1].options.non_consuming)
  t.eq(calls.configs[1].input.numlock_by_default, true)
  t.truthy(find("KP_8", false))
  t.truthy(find("KP_Up", false))
  t.truthy(find("KP_2", false))
  t.truthy(find("KP_5", false))
  t.truthy(find("KP_Add", false))
  t.truthy(find("KP_0", false))
  t.truthy(find("KP_Insert", false))
  t.truthy(find("KP_Decimal", false))
  t.truthy(find("KP_Delete", false))
  t.eq(find("escape", false), nil)
end)

t.test("Num Lock off enables Mouse Mode and Num Lock on disables it", function()
  local hl, o, calls = fake_api()
  local store = fake_store(true)
  mouse.register(hl, o, { numlock_store = store })
  local numlock = calls.rebinds[1].dispatcher

  numlock()
  t.eq(store.value, false)
  t.eq(calls.dispatches[#calls.dispatches].name, "mouse")

  numlock()
  t.eq(store.value, true)
  t.eq(calls.dispatches[#calls.dispatches].name, "reset")
end)

t.test("reload restores Mouse Mode when session Num Lock state is off", function()
  local hl, o, calls = fake_api()
  local store = fake_store(false)
  mouse.register(hl, o, { numlock_store = store })

  t.eq(#calls.dispatches, 0)
  calls.events["config.reloaded"]()
  t.eq(calls.dispatches[#calls.dispatches].name, "mouse")
end)

t.test("movement uses cursor dispatcher with acceleration and release reset", function()
  local hl, o, calls, find = fake_api()
  mouse.register(hl, o, { numlock_store = fake_store(true) })
  local up = find("KP_8", false)
  local up_release = find("KP_8", true)

  up.dispatcher()
  t.eq(calls.dispatches[#calls.dispatches].x, 100)
  t.eq(calls.dispatches[#calls.dispatches].y, 97)
  up.dispatcher()
  up.dispatcher()
  t.eq(calls.dispatches[#calls.dispatches].y, 88)
  up_release.dispatcher()
  up.dispatcher()
  t.eq(calls.dispatches[#calls.dispatches].y, 85)
end)

t.test("diagonal movement is normalized", function()
  local hl, o, calls, find = fake_api()
  mouse.register(hl, o, { numlock_store = fake_store(true) })
  find("KP_9", false).dispatcher()
  local action = calls.dispatches[#calls.dispatches]
  t.eq(action.x, 102)
  t.eq(action.y, 98)
end)

t.test("click mappings send pointer key states", function()
  local hl, o, calls, find = fake_api()
  mouse.register(hl, o, { numlock_store = fake_store(true) })

  find("KP_5", false).dispatcher()
  t.eq(calls.dispatches[#calls.dispatches - 1].key, "mouse:272")
  t.eq(calls.dispatches[#calls.dispatches - 1].state, "down")
  t.eq(calls.dispatches[#calls.dispatches].state, "up")

  find("KP_Multiply", false).dispatcher()
  t.eq(calls.dispatches[#calls.dispatches - 1].key, "mouse:273")

  find("KP_Subtract", false).dispatcher()
  t.eq(calls.dispatches[#calls.dispatches - 1].key, "mouse:274")
end)

t.test("double click schedules the second click", function()
  local hl, o, calls, find = fake_api()
  mouse.register(hl, o, { numlock_store = fake_store(true) })
  find("KP_Add", false).dispatcher()
  t.eq(#calls.timers, 1)
  t.eq(calls.timers[1].options.type, "oneshot")
  t.eq(calls.timers[1].options.timeout, 70)
  calls.timers[1].fn()
  t.eq(calls.dispatches[#calls.dispatches - 1].key, "mouse:272")
  t.eq(calls.dispatches[#calls.dispatches].state, "up")
end)

t.test("held left button is released on explicit release and cleanup", function()
  local hl, o, calls, find = fake_api()
  mouse.register(hl, o, { numlock_store = fake_store(true) })
  find("KP_0", false).dispatcher()
  find("KP_0", false).dispatcher()
  t.eq(calls.dispatches[#calls.dispatches].state, "down")

  local before = #calls.dispatches
  find("KP_Decimal", false).dispatcher()
  t.eq(#calls.dispatches, before + 1)
  t.eq(calls.dispatches[#calls.dispatches].state, "up")

  find("KP_0", false).dispatcher()
  calls.events["config.unload"]()
  t.eq(calls.dispatches[#calls.dispatches].state, "up")
end)

t.test("Hyprland shutdown clears the session Num Lock state", function()
  local hl, o, calls = fake_api()
  local store = fake_store(false)
  mouse.register(hl, o, { numlock_store = store })

  calls.events["hyprland.shutdown"]()
  t.eq(store.value, nil)
end)
