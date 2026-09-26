local M = {}

local PLUGIN_ID = "gendbyte.spatial-hud"
local ACTIONS = { toggle = true, reset = true }

local function shell_quote(value)
  return "'" .. tostring(value):gsub("'", "'\\''") .. "'"
end

function M.new(hl, o)
  o = o or {}

  local client = {}
  local quote = type(o.shell_quote) == "function" and o.shell_quote or shell_quote

  function client.show(enabled, zoom_percent, action)
    if type(enabled) ~= "boolean" then
      return false
    end
    if type(zoom_percent) ~= "number" or zoom_percent < 1 or zoom_percent > 400 then
      return false
    end

    action = action or "toggle"
    if not ACTIONS[action] then
      return false
    end
    if type(hl.exec_cmd) ~= "function" then
      return false
    end

    local payload = string.format(
      '{"enabled":%s,"zoomPercent":%d,"action":"%s"}',
      enabled and "true" or "false",
      math.floor(zoom_percent + 0.5),
      action
    )

    hl.exec_cmd(
      "omarchy-shell shell summon "
        .. PLUGIN_ID
        .. " "
        .. quote(payload)
    )
    return true
  end

  return client
end

return M
