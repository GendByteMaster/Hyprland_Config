local M = {}

local function shell_quote(value)
  return "'" .. tostring(value):gsub("'", "'\\''") .. "'"
end

function M.new(hl, options)
  options = options or {}
  local home = options.home or os.getenv("HOME")
  local client = {}

  function client.play_mouse_mode(enabled)
    if type(hl.exec_cmd) ~= "function" or not home or home == "" then
      return false
    end

    local cue = enabled and "toggle-on.ogg" or "toggle-off.ogg"
    local path = home .. "/.local/share/hyprland_config/sounds/" .. cue
    local inner = table.concat({
      "if command -v pw-play >/dev/null 2>&1 && test -r " .. shell_quote(path) .. "; then",
      "pw-play --volume 0.35 " .. shell_quote(path) .. " >/dev/null 2>&1 </dev/null &",
      "fi",
    }, " ")
    local command = "sh -lc " .. shell_quote(inner)

    local ok = pcall(hl.exec_cmd, command)
    return ok
  end

  return client
end

return M
