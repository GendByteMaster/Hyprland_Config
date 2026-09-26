local M = {}

local PLUGIN_ID = "gendbyte.mouse-hud"
local MODES = { mouse = true, numpad = true }
local BUTTONS = { LMB = true, RMB = true, MMB = true }
local SPATIAL_ACTIONS = { toggle = true, reset = true }

local function shell_quote(value)
  return "'" .. tostring(value):gsub("'", "'\\''") .. "'"
end

function M.new(hl, o)
  o = o or {}

  local client = {}
  local quote = type(o.shell_quote) == "function" and o.shell_quote or shell_quote

  local function summon(payload)
    if type(hl.exec_cmd) ~= "function" then
      return false
    end

    hl.exec_cmd(
      "omarchy-shell shell summon "
        .. PLUGIN_ID
        .. " "
        .. quote(payload)
    )
    return true
  end

  function client.show(mode, button)
    if not MODES[mode] or not BUTTONS[button] then
      return false
    end
    local payload = string.format('{"mode":"%s","button":"%s"}', mode, button)
    return summon(payload)
  end

  function client.show_spatial(enabled, zoom_percent, action)
    if type(enabled) ~= "boolean" then
      return false
    end
    if type(zoom_percent) ~= "number" or zoom_percent < 1 or zoom_percent > 400 then
      return false
    end

    action = action or "toggle"
    if not SPATIAL_ACTIONS[action] then
      return false
    end

    local payload = string.format(
      '{"mode":"spatial","enabled":%s,"zoomPercent":%d,"action":"%s"}',
      enabled and "true" or "false",
      math.floor(zoom_percent + 0.5),
      action
    )
    return summon(payload)
  end

  return client
end

return M
