local telemetry = require("workstation.telemetry")

local M = {}

function M.sample_once(state, io_api)
  state = state or {}
  assert(type(io_api) == "table", "io_api is required")
  assert(type(io_api.read) == "function", "io_api.read is required")
  assert(type(io_api.temperature_candidates) == "function", "io_api.temperature_candidates is required")

  local cpu_snapshot = telemetry.parse_cpu_stat(io_api.read("/proc/stat"))
  local memory = telemetry.parse_meminfo(io_api.read("/proc/meminfo"))
  local chosen_temperature = telemetry.choose_temperature(io_api.temperature_candidates())

  local sample = {
    cpu = telemetry.cpu_percent(state.previous_cpu, cpu_snapshot),
    memory = telemetry.memory_percent(memory),
    temperature = chosen_temperature and chosen_temperature.value or nil,
  }

  return sample, {
    previous_cpu = cpu_snapshot or state.previous_cpu,
    temperature_path = chosen_temperature and chosen_temperature.path or state.temperature_path,
  }
end

return M
