local source = debug.getinfo(1, "S").source
if source:sub(1, 1) == "@" then
  source = source:sub(2)
end

local script_dir = source:match("^(.*)/[^/]+$") or "."
package.path = script_dir .. "/lua/?.lua;" .. script_dir .. "/lua/?/init.lua;" .. package.path

local command = require("workstation.command")
local uninstaller = require("workstation.uninstaller")
local omarchy_plugins = require("workstation.omarchy_plugins")

local HUD_PLUGIN_ID = "gendbyte.mouse-hud"
local home = assert(os.getenv("HOME"), "HOME is not set")
local repo_root = assert(command.realpath(script_dir), "cannot resolve repository root")

if command.command_exists("omarchy-shell") then
  command.capture("omarchy-shell shell setPluginEnabled " .. HUD_PLUGIN_ID .. " false")
end

local result = uninstaller.uninstall({ home = home })

local external_manifest, external_manifest_error = omarchy_plugins.load_manifest(
  repo_root .. "/omarchy/external-plugins.lua"
)
if not external_manifest then
  io.stderr:write(
    "External Omarchy plugins were not removed: "
      .. tostring(external_manifest_error)
      .. "\n"
  )
else
  local external_result = omarchy_plugins.remove({
    home = home,
    manifest = external_manifest,
  })
  if not external_result.ok then
    io.stderr:write("Some external Omarchy plugins were preserved for safety.\n")
    for _, item in ipairs(external_result.results or {}) do
      if not item.ok then
        io.stderr:write(
          "  " .. tostring(item.name) .. ": " .. tostring(item.error) .. "\n"
        )
      end
    end
  elseif external_result.changed then
    print("Managed external Omarchy plugins removed.")
  end
end

if command.command_exists("omarchy-shell") then
  command.capture("omarchy-shell shell rescanPlugins")
end

if result.changed then
  print("Hyprland_Config uninstalled.")
  if result.restored_from ~= "" then
    print("Previous configuration restored from: " .. result.restored_from)
  end
else
  print("Hyprland_Config is not installed.")
end
