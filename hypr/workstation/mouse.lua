local mouse_state = require("hypr.workstation.mouse_state")
local numlock_store_module = require("hypr.workstation.numlock_store")
local hud_module = require("hypr.workstation.hud")
local sound_module = require("hypr.workstation.sound")

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

local function bind_aliases(bind_fn, keys, dispatcher, options)
  for _, key in ipairs(keys) do
    bind_fn(key, dispatcher, options)
  end
end

local function ensure_kb_option(current, required)
  if type(current) ~= "string" or current == "" then
    return required
  end

  for option in current:gmatch("[^,]+") do
    local normalized = option:match("^%s*(.-)%s*$")
    if normalized == required then
      return current
    end
  end

  return current .. "," .. required
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
  local sound = options.sound or sound_module.new(hl)
  local saved_numlock = numlock_store.load()
  local numlock_on = saved_numlock == nil and true or saved_numlock
  local selected = BUTTONS.LMB
  local held_key = nil
  local live_timers = {}
  local mouse_bind_handles = {}

  local current_kb_options = ""
  if type(hl.get_config) == "function" then
    local ok, value = pcall(hl.get_config, "input.kb_options")
    if ok and type(value) == "string" then
      current_kb_options = value
    end
  end

  hl.config({
    input = {
      numlock_by_default = true,
      -- Mouse Mode owns Num Lock as a mode switch. Force stable numeric keypad
      -- keysyms so Num Lock ON produces digits instead of KP_Left/KP_Up/etc.
      -- Preserve any existing XKB options configured by Omarchy or the user.
      kb_options = ensure_kb_option(current_kb_options, "numpad:mac"),
    },
    cursor = {
      -- Omarchy hides the cursor after keyboard input by default. Mouse Mode
      -- itself is keyboard-driven, so that policy makes the pointer disappear
      -- while NumPad movement is active. Keep it renderable for this layer.
      hide_on_key_press = false,
    },
  })

  local function register_mouse_bind(key, dispatcher, bind_options)
    local handle = hl.bind(key, dispatcher, bind_options)
    if handle then
      table.insert(mouse_bind_handles, handle)
    end
    return handle
  end

  local function set_mouse_bindings_enabled(enabled)
    for _, handle in ipairs(mouse_bind_handles) do
      if handle and type(handle.set_enabled) == "function" then
        handle:set_enabled(enabled)
      end
    end
  end

  local function dispatch(action)
    hl.dispatch(action)
  end

  local function send_button(key, key_state, target_window)
    dispatch(hl.dsp.send_key_state({
      mods = "",
      key = key,
      state = key_state,
      window = target_window,
    }))
  end

  local function window_contains_cursor(window, cursor)
    if not window or not cursor then
      return false
    end
    if window.mapped == false or window.visible == false or window.accepts_input == false then
      return false
    end

    -- Hyprland keeps mapped windows from hidden workspaces in the global
    -- window list. Their geometry can overlap the current workspace, so they
    -- must never win cursor hit-testing or a click would switch workspaces.
    local workspace = window.workspace
    if workspace and workspace.visible == false then
      return false
    end

    local at = window.at
    local size = window.size
    if not at or not size then
      return false
    end
    if type(at.x) ~= "number" or type(at.y) ~= "number" or type(size.x) ~= "number" or type(size.y) ~= "number" then
      return false
    end
    if size.x <= 0 or size.y <= 0 then
      return false
    end

    return cursor.x >= at.x and cursor.x < at.x + size.x
      and cursor.y >= at.y and cursor.y < at.y + size.y
  end

  local function window_at_cursor()
    if type(hl.get_windows) ~= "function" then
      return nil
    end

    local cursor = hl.get_cursor_pos()
    local windows = hl.get_windows({ mapped = true }) or {}
    local candidate = nil

    for _, window in ipairs(windows) do
      if window_contains_cursor(window, cursor) then
        if window.active then
          return window
        end

        if not candidate or (window.floating and not candidate.floating) then
          candidate = window
        end
      end
    end

    return candidate
  end

  local function focus_cursor_target()
    local target = window_at_cursor()
    if target and not target.active then
      dispatch(hl.dsp.focus({ window = target }))
    end
    return target
  end

  local function click(key)
    local target = focus_cursor_target()
    send_button(key, "down", target)
    send_button(key, "up", target)
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

  local function play_mode_sound(enabled)
    if sound and type(sound.play_mouse_mode) == "function" then
      -- Audio feedback must never prevent Num Lock or Mouse Mode from changing.
      pcall(sound.play_mouse_mode, enabled)
    end
  end

  local function enter()
    set_mouse_bindings_enabled(true)
    cleanup()
    show_hud("mouse")
  end

  local function exit()
    cleanup()
    set_mouse_bindings_enabled(false)
    show_hud("numpad")
  end

  local function on_numlock()
    numlock_on = not numlock_on
    numlock_store.save(numlock_on)

    if numlock_on then
      exit()
      play_mode_sound(false)
    else
      enter()
      play_mode_sound(true)
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

  -- Mouse Mode stays in the global submap, but its NumPad binds are enabled
  -- only while Num Lock is off. With Num Lock on, Hyprland sees no active
  -- custom NumPad bind and the focused application receives normal NumPad input.
  for _, direction in ipairs(DIRECTIONS) do
    local current = direction
    bind_aliases(register_mouse_bind, current.keys, mouse_only(function()
      move(current)
    end), { repeating = true, auto_consuming = true })

    bind_aliases(register_mouse_bind, current.keys, mouse_only(function()
      reset_direction(current)
    end), { release = true, auto_consuming = true })
  end

  -- Windows-style selection model: these keys choose which virtual mouse
  -- button 5/+ /0/. operate on. Selecting a mode does not click immediately.
  register_mouse_bind("KP_Divide", mouse_only(function()
    select_button("LMB")
  end), { auto_consuming = true })
  register_mouse_bind("KP_Multiply", mouse_only(function()
    select_button("RMB")
  end), { auto_consuming = true })
  register_mouse_bind("KP_Subtract", mouse_only(function()
    select_button("MMB")
  end), { auto_consuming = true })

  bind_aliases(register_mouse_bind, { "KP_5", "KP_Begin" }, mouse_only(function()
    click(selected.key)
  end), { auto_consuming = true })
  register_mouse_bind("KP_Add", mouse_only(double_click_selected), { auto_consuming = true })
  bind_aliases(register_mouse_bind, { "KP_0", "KP_Insert" }, mouse_only(hold_selected), { auto_consuming = true })
  bind_aliases(register_mouse_bind, { "KP_Decimal", "KP_Delete" }, mouse_only(release_held), { auto_consuming = true })

  set_mouse_bindings_enabled(not numlock_on)

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