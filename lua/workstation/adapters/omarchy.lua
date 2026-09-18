local generic = require("workstation.adapters.generic")
local command = require("workstation.command")

local M = {}

local function default_runtime()
  return {
    command_exists = command.command_exists,
    getenv = os.getenv,
  }
end

function M.detect(config, runtime)
  runtime = runtime or default_runtime()
  if not runtime.command_exists("omarchy") then
    return nil
  end

  -- Omarchy's selected default terminal is already represented by
  -- xdg-terminal-exec. Reuse the generic explicit-cwd adapter rather than
  -- omarchy-launch-terminal, which inherits the active terminal cwd.
  local adapter = generic.detect(config, runtime)
  adapter.kind = "omarchy"
  return adapter
end

return M
