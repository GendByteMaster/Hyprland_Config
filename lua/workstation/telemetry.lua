local M = {}

local function finite_number(value)
  local number = tonumber(value)
  if not number or number ~= number or number == math.huge or number == -math.huge then
    return nil
  end
  return number
end

function M.parse_cpu_stat(text)
  if type(text) ~= "string" then
    return nil
  end

  local line = text:match("^([^\n]+)")
  if not line or not line:match("^cpu%s") then
    return nil
  end

  local fields = {}
  for value in line:gmatch("(%d+)") do
    fields[#fields + 1] = tonumber(value)
  end
  if #fields < 4 then
    return nil
  end

  local total = 0
  for _, value in ipairs(fields) do
    total = total + value
  end

  local idle = fields[4] + (fields[5] or 0)
  return { total = total, idle = idle }
end

function M.cpu_percent(previous, current)
  if type(previous) ~= "table" or type(current) ~= "table" then
    return nil
  end

  local previous_total = finite_number(previous.total)
  local previous_idle = finite_number(previous.idle)
  local current_total = finite_number(current.total)
  local current_idle = finite_number(current.idle)
  if not previous_total or not previous_idle or not current_total or not current_idle then
    return nil
  end

  local total_delta = current_total - previous_total
  local idle_delta = current_idle - previous_idle
  if total_delta <= 0 or idle_delta < 0 then
    return nil
  end

  local percent = (1 - idle_delta / total_delta) * 100
  if percent < 0 then
    percent = 0
  elseif percent > 100 then
    percent = 100
  end
  return percent
end

function M.parse_meminfo(text)
  if type(text) ~= "string" then
    return nil
  end

  local total = tonumber(text:match("MemTotal:%s+(%d+)%s+kB"))
  local available = tonumber(text:match("MemAvailable:%s+(%d+)%s+kB"))
  if not total or not available or total <= 0 or available < 0 or available > total then
    return nil
  end

  return { total_kib = total, available_kib = available }
end

function M.memory_percent(memory)
  if type(memory) ~= "table" then
    return nil
  end

  local total = finite_number(memory.total_kib)
  local available = finite_number(memory.available_kib)
  if not total or not available or total <= 0 or available < 0 or available > total then
    return nil
  end

  return ((total - available) / total) * 100
end

return M
