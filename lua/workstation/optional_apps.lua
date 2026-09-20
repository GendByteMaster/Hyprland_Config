local command = require("workstation.command")

local M = {}

local AMNEZIA = {
  version = "5.0.1.5",
  asset = "AmneziaVPN_5.0.1.5_linux_x64.run",
  url = "https://github.com/amnezia-vpn/amnezia-client/releases/download/5.0.1.5/AmneziaVPN_5.0.1.5_linux_x64.run",
  sha256 = "ddb471efbe149232aa98c75534f98d42114b15fdc7976802f8feaeba320bc791",
}

local AMNEZIA_FALLBACK_PATH = "/opt/AmneziaVPN/client/AmneziaVPN.sh"

local function default_runtime()
  return {
    command_exists = command.command_exists,
    file_exists = command.exists,
    run_argv = command.run_argv,
    capture_argv = command.capture_argv,
    remove = command.remove,
  }
end

local function installed(runtime)
  return runtime.command_exists("AmneziaVPN")
    or runtime.file_exists(AMNEZIA_FALLBACK_PATH)
end

local function cleanup(runtime, path)
  if path and path ~= "" then
    runtime.remove(path)
  end
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

  if installed(runtime) then
    return {
      ok = true,
      changed = false,
      installed = true,
      version = AMNEZIA.version,
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

  local required = { "curl", "sha256sum", "mktemp", "chmod", "sudo" }
  for _, name in ipairs(required) do
    if not runtime.command_exists(name) then
      return {
        ok = false,
        changed = false,
        error = "required installer command is missing: " .. name,
      }
    end
  end

  local arch = runtime.capture_argv({ "uname", "-m" })
  if arch ~= "x86_64" then
    return {
      ok = false,
      changed = false,
      error = "official pinned AmneziaVPN installer is x86_64-only; detected " .. tostring(arch),
    }
  end

  local installer_path = runtime.capture_argv({
    "mktemp",
    "--tmpdir",
    "hyprland-config-amneziavpn.XXXXXX.run",
  })
  if not installer_path or installer_path == "" then
    return {
      ok = false,
      changed = false,
      error = "failed to allocate a temporary path for AmneziaVPN installer",
    }
  end

  local downloaded = runtime.run_argv({
    "curl",
    "--fail",
    "--location",
    "--retry",
    "3",
    "--retry-delay",
    "1",
    "--output",
    installer_path,
    AMNEZIA.url,
  })
  if not downloaded then
    cleanup(runtime, installer_path)
    return {
      ok = false,
      changed = false,
      version = AMNEZIA.version,
      error = "failed to download the official AmneziaVPN installer",
    }
  end

  local digest_line = runtime.capture_argv({ "sha256sum", installer_path })
  local digest = digest_line and digest_line:match("^(%x+)") or nil
  if digest ~= AMNEZIA.sha256 then
    cleanup(runtime, installer_path)
    return {
      ok = false,
      changed = false,
      version = AMNEZIA.version,
      error = "AmneziaVPN installer SHA-256 verification failed",
    }
  end

  if not runtime.run_argv({ "chmod", "+x", installer_path }) then
    cleanup(runtime, installer_path)
    return {
      ok = false,
      changed = false,
      version = AMNEZIA.version,
      error = "failed to mark the AmneziaVPN installer executable",
    }
  end

  local install_ok = runtime.run_argv({
    "sudo",
    installer_path,
    "in",
    "-c",
    "--al",
    "--am",
  })
  cleanup(runtime, installer_path)

  if not install_ok then
    return {
      ok = false,
      changed = false,
      version = AMNEZIA.version,
      error = "official AmneziaVPN installer failed",
    }
  end

  if not installed(runtime) then
    return {
      ok = false,
      changed = false,
      version = AMNEZIA.version,
      error = "AmneziaVPN executable was not found after installation",
    }
  end

  return {
    ok = true,
    changed = true,
    installed = true,
    version = AMNEZIA.version,
    source = "official GitHub release",
  }
end

function M.amneziavpn_release()
  return {
    version = AMNEZIA.version,
    asset = AMNEZIA.asset,
    url = AMNEZIA.url,
    sha256 = AMNEZIA.sha256,
  }
end

return M
