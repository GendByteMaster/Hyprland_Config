local mouse_state = require("hypr.workstation.mouse_state")
local numlock_store_module = require("hypr.workstation.numlock_store")
local hud_module = require("hypr.workstation.hud")

local M = {}

local SQRT_HALF = 0.7071067811865476
local BUTTONS = {
  LMB = { label = "LMB", key = "mouse:272" },
  RMB = { label = "RMB", key = "mouse:273" },
  MMB = { label = "MMB", key = "mouse:274" },
}

local DIRECTIONS = {
  { id = "up", keys = { "KP_8", "KP_Up" }, dx = 0, dy = -1 },
  { id = "down", keys = { "KP_2", "KP_Down" }, dx = 0, dy = 1 },
  { id = "left", keys = { "KP_4", "KP_Left" }, dx = -1, dy = 0 },
  { id = "right", keys = { "KP_6", "KP_Right" }, dx = 1, dy = 0 },
  { id = "up_left", keys = { "KP_7", "KP_Home" }, dx = -1, dy = -1 },
  { id = "up_right", keys = { "KP_9", "KP_Prior" }, dx = 1, dy = -1 },
  { id = "down_left", keys = { "KP_1", "KP_End" }, dx = -1, dy = 1 },
  { id = "down_right", keys = { "KP_3", "KP_Next" }, dx = 1, dy = 1 },
}

local function bind_aliases(hl, keys, dispatcher, options)
  for _, key in ipairs(keys) do
    hl.bind(key, dispatcher, options)
  end
end

local function rebind_compat(hl, o, keys, description, dispatcher, options)
  if type(o.rebind) == "function" then
    return o.rebind(keys, description, dispatcher, options)
  end

  if type(hl.unbind) ~= "function" then
    error("Omarchy compatibility requires hl.unbind when o.rebind is unavailable")
  end

  hl.unbind(keys)

  if type(o.bind) == "function" then
    return o.bind(keys, description, dispatcher, options)
  end

  local opts = options or {}
  if description then
    opts.description = description
  end
  return hl.bind(keys, dispatcher, opts)
end

function M.register(hl, o, options)
  options = options or {}

  local state = mouse_state.new()
  local numlock_store = options.numlock_store or numlock_store_module.session()
  local hud = options.hud or hud_module.new(hl, o)
  local saved_numlock = numlock_store.load()
  local numlock_on = saved_numlock == nil and true or saved_numlock
  local selected = BUTTONS.LMB
  local held_key = nil
  local live_timers = {}

  hl.config({
    input = {
      numlock_by_default = true,
    },
  })

  local function dispatch(action)
    hl.dispatch(action)
  end

  local function send_button(key, key_state)
    dispatch(hl.dsp.send_key_state({
      mods = "",
      key = key,
      state = key_state,
    }))
  end

  local function click(key)
    send_button(key, "down")
    send_button(key, "up")
  end

  local function release_held()
    if held_key then
      send_button(held_key, "up")
      held_key = nil
    end
  end

  local function cleanup()
    release_held()
    mouse_state.reset(state)
  end

  local function show_hud(mode)
    hud.show(mode, selected.label)
  end

  local function enter()
    cleanup()
    if hl.get_current_submap() ~= "mouse" then
      dispatch(hl.dsp.submap("mouse"))
    end
    show_hud("mouse")
  end

  local function exit()
    cleanup()
    if hl.get_current_submap() == "mouse" then
      dispatch(hl.dsp.submap("reset"))
    end
    show_hud("numpad")
  end

  local function on_numlock()
    numlock_on = not numlock_on
    numlock_store.save(numlock_on)

    if numlock_on then
      exit()
    else
      enter()
    end
  end

  local function select_button(label)
    local next_button = BUTTONS[label]
    if not next_button then
      return
    end

    release_held()
    selected = next_button
    show_hud("mouse")
  end

  local function move(direction)
    local step = mouse_state.next_step(state, direction.id)
    local scale = (direction.dx ~= 0 and direction.dy ~= 0) and SQRT_HALF or 1
    local amount = math.floor(step * scale + 0.5)
    local cursor = hl.get_cursor_pos()

    dispatch(hl.dsp.cursor.move({
      x = cursor.x + direction.dx * amount,
      y = cursor.y + direction.dy * amount,
    }))
  end

  local function reset_direction(direction)
    mouse_state.release(state, direction.id)
  end

  local function double_click_selected()
    local key = selected.key
    click(key)

    local timer
    timer = hl.timer(function()
      click(key)
      for index, candidate in ipairs(live_timers) do
        if candidate == timer then
          table.remove(live_timers, index)
          break
        end
      end
    end, {
      type = "oneshot",
      timeout = 70,
    })

    table.insert(live_timers, timer)
  end

  local function hold_selected()
    if held_key == selected.key then
      return
    end

    release_held()
    send_button(selected.key, "down")
    held_key = selected.key
  end

  rebind_compat(hl, o, "Num_Lock", "Mouse mode / Num Lock", on_numlock, {
    submap_universal = true,
    non_consuming = true,
  })

  hl.define_submap("mouse", function()
    for _, direction in ipairs(DIRECTIONS) do
      local current = direction
      bind_aliases(hl, current.keys, function()
        move(current)
      end, { repeating = true })

      bind_aliases(hl, current.keys, function()
        reset_direction(current)
      end, { release = true })
    end

    hl.bind("KP_Divide", function()
      select_button("LMB")
    end)
    hl.bind("KP_Multiply", function()
      select_button("RMB")
    end)
    hl.bind("KP_Subtract", function()
      select_button("MMB")
    end)

    bind_aliases(hl, { "KP_5", "KP_Begin" }, function()
      click(selected.key)
    end)
    hl.bind("KP_Add", double_click_selected)
    bind_aliases(hl, { "KP_0", "KP_Insert" }, hold_selected)
    bind_aliases(hl, { "KP_Decimal", "KP_Delete" }, release_held)
  end)

  hl.on("config.reloaded", function()
    if not numlock_on and hl.get_current_submap() ~= "mouse" then
      enter()
    end
  end)

  hl.on("keybinds.submap", function(name)
    if name ~= "mouse" then
      cleanup()
    end
  end)

  hl.on("config.unload", cleanup)
  hl.on("hyprland.shutdown", function()
    cleanup()
    numlock_store.clear()
  end)
end

return M
