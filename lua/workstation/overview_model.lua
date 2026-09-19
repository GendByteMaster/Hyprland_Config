local M = {}

local DEFAULT_OVERVIEW_CLASS = "gendbyte-workspace-overview"

local function trim(value)
  if type(value) ~= "string" then
    return ""
  end
  return (value:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function finite_number(value)
  return type(value) == "number"
    and value == value
    and value ~= math.huge
    and value ~= -math.huge
end

local function numeric(value, fallback)
  local number = tonumber(value)
  if finite_number(number) then
    return number
  end
  return fallback
end

local function pair_values(value, first, second)
  if type(value) ~= "table" then
    return nil, nil
  end
  return numeric(value[first] or value[1]), numeric(value[second] or value[2])
end

function M.normalize_address(value)
  local address = trim(tostring(value or "")):lower()
  if address:sub(1, 2) == "0x" then
    address = address:sub(3)
  end
  if #address < 1 or #address > 16 or address:find("[^0-9a-f]") then
    return nil
  end
  return "0x" .. address
end

local function workspace_fields(raw)
  local workspace = type(raw.workspace) == "table" and raw.workspace or {}
  local id = numeric(workspace.id, numeric(raw.workspace_id))
  local name = trim(workspace.name or raw.workspace_name or "")

  return id, name
end

local function geometry(raw)
  local x, y = pair_values(raw.at, "x", "y")
  local width, height = pair_values(raw.size, "width", "height")

  x = numeric(raw.x, x or 0)
  y = numeric(raw.y, y or 0)
  width = numeric(raw.width, width or 0)
  height = numeric(raw.height, height or 0)

  return {
    x = x,
    y = y,
    width = math.max(0, width),
    height = math.max(0, height),
  }
end

function M.normalize_client(raw)
  if type(raw) ~= "table" then
    return nil, "client must be a table"
  end

  local address = M.normalize_address(raw.address)
  if not address then
    return nil, "client address is invalid"
  end

  local workspace_id, workspace_name = workspace_fields(raw)
  if workspace_id == nil then
    return nil, "client workspace is invalid"
  end

  local class = trim(raw.class or raw.initialClass or raw.app_id or raw.appId or "")
  local title = trim(raw.title or raw.initialTitle or "")
  local special = workspace_id < 0 or workspace_name:sub(1, 8) == "special:"

  return {
    address = address,
    title = title,
    class = class,
    workspace_id = workspace_id,
    workspace_name = workspace_name,
    monitor_id = numeric(raw.monitor_id, numeric(raw.monitor, -1)),
    monitor_name = trim(raw.monitor_name or raw.monitorName or ""),
    focus_history_id = numeric(raw.focus_history_id, numeric(raw.focusHistoryID)),
    focused = raw.focused == true,
    fullscreen = raw.fullscreen == true or numeric(raw.fullscreen, 0) > 0,
    floating = raw.floating == true,
    mapped = raw.mapped ~= false,
    special = special,
    pid = numeric(raw.pid),
    geometry = geometry(raw),
  }
end

local function excluded_class(class, options)
  if class == DEFAULT_OVERVIEW_CLASS then
    return true
  end
  for _, value in ipairs(options.excluded_classes or {}) do
    if class == value then
      return true
    end
  end
  return false
end

function M.visible_clients(raw_clients, options)
  options = options or {}
  local clients = {}

  for _, raw in ipairs(raw_clients or {}) do
    local client = M.normalize_client(raw)
    if client
      and client.mapped
      and (options.show_special == true or not client.special)
      and not excluded_class(client.class, options) then
      clients[#clients + 1] = client
    end
  end

  return clients
end

function M.workspace_ids(clients, workspaces)
  local seen = {}

  for _, workspace in ipairs(workspaces or {}) do
    local id = type(workspace) == "table" and numeric(workspace.id) or numeric(workspace)
    if id and id > 0 then
      seen[id] = true
    end
  end

  for _, client in ipairs(clients or {}) do
    if type(client) == "table" and numeric(client.workspace_id) and client.workspace_id > 0 then
      seen[client.workspace_id] = true
    end
  end

  local ids = {}
  for id in pairs(seen) do
    ids[#ids + 1] = id
  end
  table.sort(ids)
  return ids
end

function M.mru_clients(clients)
  local ordered = {}

  for index, client in ipairs(clients or {}) do
    ordered[index] = client
  end

  table.sort(ordered, function(left, right)
    local left_order = numeric(left and left.focus_history_id, math.huge)
    local right_order = numeric(right and right.focus_history_id, math.huge)

    if left_order ~= right_order then
      return left_order < right_order
    end

    return tostring(left and left.address or "") < tostring(right and right.address or "")
  end)

  return ordered
end

function M.group_by_workspace(clients)
  local groups = {}
  for _, client in ipairs(clients or {}) do
    local id = client.workspace_id
    if id ~= nil then
      groups[id] = groups[id] or {}
      groups[id][#groups[id] + 1] = client
    end
  end
  return groups
end

local function find_by_address(clients, address)
  local normalized = M.normalize_address(address)
  if not normalized then
    return nil, nil
  end

  for index, client in ipairs(clients or {}) do
    if client.address == normalized then
      return client, index
    end
  end
  return nil, nil
end

function M.reconcile_selection(clients, selected_address)
  local selected = find_by_address(clients, selected_address)
  if selected then
    return selected.address
  end

  for _, client in ipairs(clients or {}) do
    if client.focused then
      return client.address
    end
  end

  return clients and clients[1] and clients[1].address or nil
end

local function center(client)
  local g = client.geometry or {}
  return numeric(g.x, 0) + numeric(g.width, 0) / 2,
    numeric(g.y, 0) + numeric(g.height, 0) / 2
end

local function directional_score(dx, dy, direction)
  local primary
  local perpendicular

  if direction == "left" then
    if dx >= 0 then return nil end
    primary, perpendicular = -dx, math.abs(dy)
  elseif direction == "right" then
    if dx <= 0 then return nil end
    primary, perpendicular = dx, math.abs(dy)
  elseif direction == "up" then
    if dy >= 0 then return nil end
    primary, perpendicular = -dy, math.abs(dx)
  elseif direction == "down" then
    if dy <= 0 then return nil end
    primary, perpendicular = dy, math.abs(dx)
  else
    return nil
  end

  return primary + perpendicular * 0.35
end

function M.move_selection(clients, selected_address, direction)
  if direction ~= "left" and direction ~= "right"
    and direction ~= "up" and direction ~= "down" then
    return M.reconcile_selection(clients, selected_address)
  end

  local current = find_by_address(clients, selected_address)
  if not current then
    return M.reconcile_selection(clients, selected_address)
  end

  local cx, cy = center(current)
  local best_address = current.address
  local best_score = nil

  for _, candidate in ipairs(clients or {}) do
    if candidate.address ~= current.address then
      local x, y = center(candidate)
      local score = directional_score(x - cx, y - cy, direction)
      if score and (best_score == nil or score < best_score) then
        best_score = score
        best_address = candidate.address
      end
    end
  end

  return best_address
end

function M.contains_address(clients, address)
  return find_by_address(clients, address) ~= nil
end

return M
