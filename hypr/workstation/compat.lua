local M = {}

local function read_kernel_cmdline()
  if type(io) ~= "table" or type(io.open) ~= "function" then
    return ""
  end

  local file = io.open("/proc/cmdline", "r")
  if not file then
    return ""
  end

  local cmdline = file:read("*l") or ""
  file:close()
  return cmdline
end

local function has_kernel_option(cmdline, expected)
  for option in tostring(cmdline or ""):gmatch("%S+") do
    if option == expected then
      return true
    end
  end
  return false
end

function M.is_try_omarchy(options)
  options = options or {}

  local cmdline = options.kernel_cmdline
  if cmdline == nil then
    cmdline = read_kernel_cmdline()
  end

  return has_kernel_option(cmdline, "omarchy.qemu=1")
end

function M.apply(hl, options)
  options = options or {}

  if not M.is_try_omarchy(options) then
    return false
  end

  -- Older try-omarchy-windows guest images hid the guest cursor for VNC.
  -- SDL/QEMU needs Hyprland to render it, so override that setting after
  -- hypr.monitors has loaded. Current guest images already use this value.
  hl.config({
    cursor = {
      invisible = false,
    },
  })

  return true
end

return M
