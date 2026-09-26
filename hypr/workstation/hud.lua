local M = {}

local PLUGIN_ID = "gendbyte.mouse-hud"
local MODES = { mouse = true, numpad = true }
local BUTTONS = { LMB = true, RMB = true, MMB = true }

local function shell_quote(value)
  return "'" .. tostring(value):gsub("'", "'\\''") .. "'"
end

function M.new(hl, o)
  o = o or {}

  local client = {}
  local quote = type(o.shell_quote) == "function" and o.shell_quote or shell_quote

  function client.show(mode, button)
    if not MODES[mode] or not BUTTONS[button] then
      return false
    end
    if type(hl.exec_cmd) ~= "function" then
      return false
    end

    local payload = string.format('{"mode":"%s","button":"%s"}', mode, button)
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
