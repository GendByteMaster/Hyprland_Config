local command = require("workstation.command")
local json = require("workstation.json")
local overview_model = require("workstation.overview_model")

local M = {}

local function trim(value)
  if type(value) ~= "string" then
    return ""
  end
  return (value:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function lower(value)
  return trim(value):lower()
end

local function decode_array(raw, label)
  local decoded, decode_error = json.decode(raw or "")
  if not decoded then
    return nil, tostring(label) .. " JSON is invalid: " .. tostring(decode_error)
  end
  if type(decoded) ~= "table" then
    return nil, tostring(label) .. " JSON must be an array"
  end
  return decoded
end

local function default_runtime()
  return {
    capture_argv = command.capture_argv,
    run_argv_silent = command.run_argv_silent,
  }
end

local function capture_json(runtime, argv, label)
  local raw = runtime.capture_argv(argv)
  if type(raw) ~= "string" then
    return nil, tostring(label) .. " is unavailable"
  end
  return decode_array(raw, label)
end

function M.clients(runtime)
  runtime = runtime or default_runtime()
  local raw_clients, err = capture_json(runtime, { "hyprctl", "clients", "-j" }, "Hyprland clients")
  if not raw_clients then
    return nil, err
  end

  local clients = {}
  for _, raw in ipairs(raw_clients) do
    if type(raw) == "table" then
      local address = overview_model.normalize_address(raw.address)
      if address then
        local workspace = type(raw.workspace) == "table" and raw.workspace or {}
        clients[#clients + 1] = {
          address = address,
          class = trim(raw.class or raw.app_id or raw.appId or ""),
          initial_class = trim(raw.initialClass or raw.initial_class or ""),
          title = trim(raw.title or ""),
          initial_title = trim(raw.initialTitle or raw.initial_title or ""),
          workspace_id = tonumber(workspace.id or raw.workspace_id),
          workspace_name = trim(workspace.name or raw.workspace_name or ""),
          monitor_id = tonumber(raw.monitor or raw.monitor_id),
          monitor_name = trim(raw.monitor_name or raw.monitorName or ""),
          pid = tonumber(raw.pid),
          mapped = raw.mapped ~= false,
          hidden = raw.hidden == true,
          focused = raw.focused == true,
        }
      end
    end
  end

  return clients
end

function M.monitors(runtime)
  runtime = runtime or default_runtime()
  local raw_monitors, err = capture_json(runtime, { "hyprctl", "monitors", "-j" }, "Hyprland monitors")
  if not raw_monitors then
    return nil, err
  end

  local monitors = {}
  for _, raw in ipairs(raw_monitors) do
    if type(raw) == "table" and trim(raw.name) ~= "" then
      monitors[#monitors + 1] = {
        id = tonumber(raw.id),
        name = trim(raw.name),
        focused = raw.focused == true,
        x = tonumber(raw.x) or 0,
        y = tonumber(raw.y) or 0,
        width = tonumber(raw.width) or 0,
        height = tonumber(raw.height) or 0,
      }
    end
  end

  return monitors
end

function M.active_window(runtime)
  runtime = runtime or default_runtime()
  local raw = runtime.capture_argv({ "hyprctl", "activewindow", "-j" })
  if type(raw) ~= "string" or raw == "" then
    return nil
  end

  local decoded = json.decode(raw)
  if type(decoded) ~= "table" then
    return nil
  end

  return overview_model.normalize_address(decoded.address)
end

local function equals(actual, expected)
  return lower(actual) == lower(expected)
end

function M.matches(client, match)
  if type(client) ~= "table" or type(match) ~= "table" then
    return false
  end

  local checked = 0
  for key, field in pairs({
    class = "class",
    initial_class = "initial_class",
    title = "title",
    initial_title = "initial_title",
  }) do
    local expected = match[key]
    if expected ~= nil then
      checked = checked + 1
      if not equals(client[field], expected) then
        return false
      end
    end
  end

  return checked > 0
end

function M.find_match(clients, match, excluded_addresses)
  excluded_addresses = excluded_addresses or {}

  for _, client in ipairs(clients or {}) do
    if client.mapped ~= false
      and client.hidden ~= true
      and not excluded_addresses[client.address]
      and M.matches(client, match) then
      return client
    end
  end

  return nil
end

function M.address_set(clients)
  local result = {}
  for _, client in ipairs(clients or {}) do
    if type(client) == "table" and type(client.address) == "string" then
      result[client.address] = true
    end
  end
  return result
end

local function lua_quote(value)
  return string.format("%q", tostring(value))
end

local function dispatch(runtime, expression)
  return runtime.run_argv_silent({ "hyprctl", "dispatch", expression })
end

function M.place_client(address, workspace, monitor, runtime)
  runtime = runtime or default_runtime()
  local normalized = overview_model.normalize_address(address)
  if not normalized then
    return nil, "client address is invalid"
  end

  if workspace ~= nil and monitor ~= nil then
    return nil, "combined post-launch workspace+monitor correction is not safe"
  end

  local previous = M.active_window(runtime)

  if not dispatch(runtime, 'hl.dsp.focus({ window = "address:' .. normalized .. '" })') then
    return nil, "failed to focus matched client for placement"
  end

  local ok
  if workspace ~= nil then
    ok = dispatch(
      runtime,
      "hl.dsp.window.move({ workspace = " .. lua_quote(workspace) .. ", follow = false })"
    )
  elseif monitor ~= nil then
    ok = dispatch(
      runtime,
      "hl.dsp.window.move({ monitor = " .. lua_quote(monitor) .. ", follow = false })"
    )
  else
    ok = true
  end

  if previous and previous ~= normalized then
    dispatch(runtime, 'hl.dsp.focus({ window = "address:' .. previous .. '" })')
  end

  if not ok then
    return nil, "failed to correct matched client placement"
  end

  return true
end

return M
