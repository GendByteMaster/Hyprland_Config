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

function M.cpu_frequency_ghz(raw_values)
  if type(raw_values) ~= "table" then
    return nil
  end

  local total_khz = 0
  local count = 0
  for _, raw in ipairs(raw_values) do
    local khz = finite_number(raw)
    if khz and khz > 0 then
      total_khz = total_khz + khz
      count = count + 1
    end
  end

  if count == 0 then
    return nil
  end
  return (total_khz / count) / 1000000
end

function M.cpuinfo_frequency_ghz(text)
  if type(text) ~= "string" then
    return nil
  end

  local total_mhz = 0
  local count = 0
  for raw in text:gmatch("cpu MHz%s*:%s*([%d%.]+)") do
    local mhz = finite_number(raw)
    if mhz and mhz > 0 then
      total_mhz = total_mhz + mhz
      count = count + 1
    end
  end

  if count == 0 then
    return nil
  end
  return (total_mhz / count) / 1000
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

function M.memory_gib(memory)
  if type(memory) ~= "table" then
    return nil
  end

  local total = finite_number(memory.total_kib)
  local available = finite_number(memory.available_kib)
  if not total or not available or total <= 0 or available < 0 or available > total then
    return nil
  end

  local kib_per_gib = 1024 * 1024
  return (total - available) / kib_per_gib, total / kib_per_gib
end

function M.temperature_c(raw)
  local value = finite_number(raw)
  if not value then
    return nil
  end

  if math.abs(value) >= 1000 then
    value = value / 1000
  end
  if value < 0 or value > 150 then
    return nil
  end
  return value
end

local function temperature_priority(label)
  local normalized = string.lower(label or "")
  if normalized:find("package", 1, true) then return 1 end
  if normalized:find("tdie", 1, true) then return 1 end
  if normalized:find("tctl", 1, true) then return 1 end
  if normalized:find("cpu", 1, true) then return 2 end
  if normalized:find("core", 1, true) then return 3 end
  return 10
end

function M.choose_temperature(candidates)
  if type(candidates) ~= "table" then
    return nil
  end

  local best, best_priority
  for _, candidate in ipairs(candidates) do
    local value = M.temperature_c(candidate.raw)
    if value then
      local priority = temperature_priority(candidate.label)
      if not best or priority < best_priority then
        best = {
          path = candidate.path,
          label = candidate.label,
          value = value,
        }
        best_priority = priority
      end
    end
  end
  return best
end

local function encode_metric(value)
  if value == nil then
    return "-"
  end
  return string.format("%.1f", value)
end

function M.encode_sample(sample)
  sample = sample or {}
  return table.concat({
    "v1",
    "cpu=" .. encode_metric(sample.cpu),
    "mem=" .. encode_metric(sample.memory),
    "temp=" .. encode_metric(sample.temperature),
  }, "\t")
end

return M
