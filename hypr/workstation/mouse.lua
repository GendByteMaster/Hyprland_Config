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
    show_hud("mouse")
  end

  local function exit()
    cleanup()
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

  local function mouse_only(action)
    return function(...)
      if numlock_on then
        return { ok = false }
      end

      action(...)
      return { ok = true }
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

  -- Mouse Mode deliberately stays in the global submap. Each NumPad bind is
  -- auto-consuming only while Num Lock is off; with Num Lock on it returns
  -- { ok = false }, so the original key event reaches the focused app. This
  -- keeps Omarchy's global shortcuts (Super+1..10, Super+arrows, etc.) alive.
  for _, direction in ipairs(DIRECTIONS) do
    local current = direction
    bind_aliases(hl, current.keys, mouse_only(function()
      move(current)
    end), { repeating = true, auto_consuming = true })

    bind_aliases(hl, current.keys, mouse_only(function()
      reset_direction(current)
    end), { release = true, auto_consuming = true })
  end

  hl.bind("KP_Divide", mouse_only(function()
    select_button("LMB")
  end), { auto_consuming = true })
  hl.bind("KP_Multiply", mouse_only(function()
    select_button("RMB")
  end), { auto_consuming = true })
  hl.bind("KP_Subtract", mouse_only(function()
    select_button("MMB")
  end), { auto_consuming = true })

  bind_aliases(hl, { "KP_5", "KP_Begin" }, mouse_only(function()
    click(selected.key)
  end), { auto_consuming = true })
  hl.bind("KP_Add", mouse_only(double_click_selected), { auto_consuming = true })
  bind_aliases(hl, { "KP_0", "KP_Insert" }, mouse_only(hold_selected), { auto_consuming = true })
  bind_aliases(hl, { "KP_Decimal", "KP_Delete" }, mouse_only(release_held), { auto_consuming = true })

  hl.on("config.reloaded", function()
    cleanup()
    if not numlock_on then
      show_hud("mouse")
    end
  end)

  hl.on("keybinds.submap", function()
    cleanup()
  end)

  -- Hyprland 0.56 does not expose config.unload. Keep reload compatibility
  -- by relying on config.reloaded and hyprland.shutdown, both supported there.
  hl.on("hyprland.shutdown", function()
    cleanup()
    numlock_store.clear()
  end)
end

return M
