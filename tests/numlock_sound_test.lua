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
  return { show = function() return true end }
end

local function fake_sound()
  local sound = { events = {} }

  function sound.play_mouse_mode(enabled)
    table.insert(sound.events, enabled)
    return true
  end

  return sound
end

local function fake_api()
  local calls = { binds = {}, rebinds = {}, configs = {}, events = {} }
  local cursor = { x = 100, y = 100 }

  local hl = { dsp = { cursor = {} } }

  function hl.dsp.cursor.move(args) return { kind = "cursor_move", x = args.x, y = args.y } end
  function hl.dsp.send_key_state(args) return { kind = "send_key_state", key = args.key, state = args.state, mods = args.mods } end
  function hl.config(config) table.insert(calls.configs, config) end
  function hl.bind(keys, dispatcher, options)
    table.insert(calls.binds, { keys = keys, dispatcher = dispatcher, options = options or {} })
  end
  function hl.dispatch(action)
    if action.kind == "cursor_move" then cursor.x, cursor.y = action.x, action.y end
  end
  function hl.get_cursor_pos() return { x = cursor.x, y = cursor.y } end
  function hl.timer(fn, options) return { fn = fn, options = options } end
  function hl.on(event, fn) calls.events[event] = fn end

  local o = {}
  function o.rebind(keys, description, dispatcher, options)
    table.insert(calls.rebinds, { keys = keys, description = description, dispatcher = dispatcher, options = options or {} })
    hl.bind(keys, dispatcher, options)
  end

  return hl, o, calls
end

t.test("Num Lock plays distinct Mouse Mode on and off feedback", function()
  local hl, o, calls = fake_api()
  local sound = fake_sound()
  local store = fake_store(true)

  mouse.register(hl, o, {
    numlock_store = store,
    hud = fake_hud(),
    sound = sound,
  })

  local numlock = calls.rebinds[1].dispatcher

  numlock()
  t.eq(store.value, false)
  t.eq(#sound.events, 1)
  t.eq(sound.events[1], true)

  numlock()
  t.eq(store.value, true)
  t.eq(#sound.events, 2)
  t.eq(sound.events[2], false)
end)
