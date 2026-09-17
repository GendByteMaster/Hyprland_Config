local mouse_state = require("hypr.workstation.mouse_state")

local M = {}

local SQRT_HALF = 0.7071067811865476
local LEFT_BUTTON = "mouse:272"
local RIGHT_BUTTON = "mouse:273"
local MIDDLE_BUTTON = "mouse:274"

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

function M.register(hl, o)
  local state = mouse_state.new()
  local left_held = false
  local live_timers = {}

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

  local function release_left()
    if left_held then
      send_button(LEFT_BUTTON, "up")
      left_held = false
    end
  end

  local function cleanup()
    release_left()
    mouse_state.reset(state)
  end

  local function notify(text, icon)
    if hl.notification and hl.notification.create then
      hl.notification.create({
        text = text,
        timeout = 1000,
        icon = icon or "info",
      })
    end
  end

  local function enter()
    cleanup()
    dispatch(hl.dsp.submap("mouse"))
    notify("Mouse Mode", "info")
  end

  local function exit()
    cleanup()
    dispatch(hl.dsp.submap("reset"))
    notify("Mouse Mode off", "ok")
  end

  local function toggle()
    if hl.get_current_submap() == "mouse" then
      exit()
    else
      enter()
    end
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

  local function double_click()
    click(LEFT_BUTTON)

    local timer
    timer = hl.timer(function()
      click(LEFT_BUTTON)
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

  local function hold_left()
    if not left_held then
      send_button(LEFT_BUTTON, "down")
      left_held = true
    end
  end

  o.rebind("SUPER + M", "Mouse mode", toggle, { submap_universal = true })

  hl.define_submap("mouse", function()
    for _, direction in ipairs(DIRECTIONS) do
      bind_aliases(hl, direction.keys, function()
        move(direction)
      end, { repeating = true })

      bind_aliases(hl, direction.keys, function()
        reset_direction(direction)
      end, { release = true })
    end

    bind_aliases(hl, { "KP_5", "KP_Begin" }, function()
      click(LEFT_BUTTON)
    end)
    hl.bind("KP_Add", double_click)
    hl.bind("KP_Multiply", function()
      click(RIGHT_BUTTON)
    end)
    hl.bind("KP_Subtract", function()
      click(MIDDLE_BUTTON)
    end)
    bind_aliases(hl, { "KP_0", "KP_Insert" }, hold_left)
    bind_aliases(hl, { "KP_Decimal", "KP_Delete" }, release_left)
    hl.bind("escape", exit)
    hl.bind("SUPER + M", exit, { submap_universal = true })
  end)

  hl.on("keybinds.submap", function(name)
    if name ~= "mouse" then
      cleanup()
    end
  end)
  hl.on("config.unload", cleanup)
end

return M
