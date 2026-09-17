local telemetry = require("workstation.telemetry")

local M = {}

function M.sample_once(state, io_api)
  state = state or {}
  assert(type(io_api) == "table", "io_api is required")
  assert(type(io_api.read) == "function", "io_api.read is required")
  assert(type(io_api.temperature_candidates) == "function", "io_api.temperature_candidates is required")

  local cpu_snapshot = telemetry.parse_cpu_stat(io_api.read("/proc/stat"))
  local memory = telemetry.parse_meminfo(io_api.read("/proc/meminfo"))
  local network_snapshot = telemetry.parse_net_dev(io_api.read("/proc/net/dev"))
  local chosen_temperature = telemetry.choose_temperature(io_api.temperature_candidates())

  local cpu_ghz
  if type(io_api.cpu_frequencies) == "function" then
    cpu_ghz = telemetry.cpu_frequency_ghz(io_api.cpu_frequencies())
  end
  if not cpu_ghz then
    cpu_ghz = telemetry.cpuinfo_frequency_ghz(io_api.read("/proc/cpuinfo"))
  end

  local memory_used_gib, memory_total_gib = telemetry.memory_gib(memory)
  local network_rx_bps, network_tx_bps = telemetry.network_bytes_per_second(
    state.previous_network,
    network_snapshot,
    tonumber(io_api.sample_interval_seconds) or 2
  )

  local gpu
  if type(io_api.gpu_utilization) == "function" then
    gpu = telemetry.gpu_percent(io_api.gpu_utilization())
  end

  local sample = {
    cpu = telemetry.cpu_percent(state.previous_cpu, cpu_snapshot),
    cpu_ghz = cpu_ghz,
    memory = telemetry.memory_percent(memory),
    memory_used_gib = memory_used_gib,
    memory_total_gib = memory_total_gib,
    gpu = gpu,
    network_rx_bps = network_rx_bps,
    network_tx_bps = network_tx_bps,
    temperature = chosen_temperature and chosen_temperature.value or nil,
  }

  return sample, {
    previous_cpu = cpu_snapshot or state.previous_cpu,
    previous_network = network_snapshot or state.previous_network,
    temperature_path = chosen_temperature and chosen_temperature.path or state.temperature_path,
  }
end

return M
