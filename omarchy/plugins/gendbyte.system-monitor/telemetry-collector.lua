local function shell_quote(value)
  return "'" .. tostring(value):gsub("'", "'\\''") .. "'"
end

local function capture(command)
  local pipe = io.popen(command .. " 2>/dev/null")
  if not pipe then
    return nil
  end
  local output = pipe:read("*a") or ""
  pipe:close()
  return (output:gsub("[\r\n]+$", ""))
end

local script_path = (arg and arg[0]) or "telemetry-collector.lua"
local resolved_script = capture("readlink -f -- " .. shell_quote(script_path)) or script_path
local plugin_dir = resolved_script:match("^(.*)/[^/]+$") or "."
local repo_root = capture("readlink -f -- " .. shell_quote(plugin_dir .. "/../../../")) or (plugin_dir .. "/../../../")

_G.HYPRLAND_CONFIG_ROOT = repo_root
dofile(repo_root .. "/telemetry-collector.lua")
