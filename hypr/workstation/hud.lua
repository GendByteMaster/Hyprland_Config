local M = {}

local PLUGIN_ID = "gendbyte.mouse-hud"
local MODES = { mouse = true, numpad = true }
local BUTTONS = { LMB = true, RMB = true, MMB = true }

function M.new(hl, o)
  local client = {}

  function client.show(mode, button)
    if not MODES[mode] or not BUTTONS[button] then
      return false
    end
    if type(hl.exec_cmd) ~= "function" or type(o.shell_quote) ~= "function" then
      return false
    end

    local payload = string.format('{"mode":"%s","button":"%s"}', mode, button)
    hl.exec_cmd(
      "omarchy-shell shell summon "
        .. PLUGIN_ID
        .. " "
        .. o.shell_quote(payload)
    )
    return true
  end

  return client
end

return M
