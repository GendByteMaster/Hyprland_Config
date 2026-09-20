local command = require("workstation.command")

local M = {}

local AMNEZIA_PACKAGE = "aur/amneziavpn-bin"

local function default_runtime()
  return {
    command_exists = command.command_exists,
    run_argv = command.run_argv,
  }
end

function M.install_amneziavpn(options)
  options = options or {}
  local runtime = options.runtime or default_runtime()

  if not runtime.command_exists("omarchy") then
    return {
      ok = true,
      changed = false,
      skipped = true,
      reason = "Omarchy is not installed",
    }
  end

  if runtime.command_exists("AmneziaVPN") then
    return {
      ok = true,
      changed = false,
      installed = true,
      reason = "AmneziaVPN is already installed",
    }
  end

  if not runtime.command_exists("pacman") then
    return {
      ok = true,
      changed = false,
      skipped = true,
      reason = "pacman is unavailable; AmneziaVPN auto-install is Arch/Omarchy only",
    }
  end

  local helper
  if runtime.command_exists("yay") then
    helper = "yay"
  elseif runtime.command_exists("paru") then
    helper = "paru"
  else
    return {
      ok = false,
      changed = false,
      error = "no supported AUR helper found (yay or paru)",
    }
  end

  local args = {
    helper,
    "-S",
    "--needed",
    "--noconfirm",
    AMNEZIA_PACKAGE,
  }

  if not runtime.run_argv(args) then
    return {
      ok = false,
      changed = false,
      helper = helper,
      error = helper .. " failed to install " .. AMNEZIA_PACKAGE,
    }
  end

  if not runtime.command_exists("AmneziaVPN") then
    return {
      ok = false,
      changed = false,
      helper = helper,
      error = "AmneziaVPN executable was not found after package installation",
    }
  end

  return {
    ok = true,
    changed = true,
    installed = true,
    helper = helper,
    package = AMNEZIA_PACKAGE,
  }
end

return M
