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

local repo_root = rawget(_G, "HYPRLAND_CONFIG_ROOT")
if type(repo_root) ~= "string" or repo_root == "" then
  local script_path = (arg and arg[0]) or "telemetry-collector.lua"
  local resolved_script = capture("readlink -f -- " .. shell_quote(script_path)) or script_path
  repo_root = resolved_script:match("^(.*)/[^/]+$") or "."
end

package.path = table.concat({
  repo_root .. "/?.lua",
  repo_root .. "/?/init.lua",
  repo_root .. "/lua/?.lua",
  repo_root .. "/lua/?/init.lua",
  package.path,
}, ";")

local telemetry = require("workstation.telemetry")
local collector = require("workstation.telemetry_collector")

local function read_file(path)
  local file = io.open(path, "r")
  if not file then
    return nil
  end
  local content = file:read("*a")
  file:close()
  return content
end

local function find_paths(command)
  local paths = {}
  local pipe = io.popen(command .. " 2>/dev/null")
  if not pipe then
    return paths
  end
  for path in pipe:lines() do
    if path ~= "" then
      paths[#paths + 1] = path
    end
  end
  pipe:close()
  table.sort(paths)
  return paths
end

local function hwmon_candidates()
  local candidates = {}
  local paths = find_paths("find /sys/class/hwmon -maxdepth 2 -type f -name 'temp*_input' -print")
  for _, path in ipairs(paths) do
    local label_path = path:gsub("_input$", "_label")
    local label = read_file(label_path)
    if label then
      label = label:gsub("[\r\n]+$", "")
    end
    candidates[#candidates + 1] = {
      path = path,
      label = label,
      raw = read_file(path),
    }
  end
  return candidates
end

local function thermal_candidates()
  local candidates = {}
  local paths = find_paths("find /sys/class/thermal -maxdepth 2 -type f -name temp -print")
  for _, path in ipairs(paths) do
    local zone_dir = path:match("^(.*)/temp$")
    local label = zone_dir and read_file(zone_dir .. "/type") or nil
    if label then
      label = label:gsub("[\r\n]+$", "")
    end
    candidates[#candidates + 1] = {
      path = path,
      label = label,
      raw = read_file(path),
    }
  end
  return candidates
end

local function temperature_candidates()
  local hwmon = hwmon_candidates()
  if telemetry.choose_temperature(hwmon) then
    return hwmon
  end
  return thermal_candidates()
end

local io_api = {
  read = read_file,
  temperature_candidates = temperature_candidates,
}

local state = {}
while true do
  local ok, sample, next_state = pcall(collector.sample_once, state, io_api)
  if ok then
    state = next_state
    io.stdout:write(telemetry.encode_sample(sample), "\n")
  else
    io.stdout:write(telemetry.encode_sample({}), "\n")
  end
  io.stdout:flush()
  os.execute("sleep 2")
end
