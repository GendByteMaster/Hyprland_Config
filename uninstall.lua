local source = debug.getinfo(1, "S").source
if source:sub(1, 1) == "@" then
  source = source:sub(2)
end

local script_dir = source:match("^(.*)/[^/]+$") or "."
package.path = script_dir .. "/lua/?.lua;" .. script_dir .. "/lua/?/init.lua;" .. package.path

local command = require("workstation.command")
local uninstaller = require("workstation.uninstaller")

local HUD_PLUGIN_ID = "gendbyte.mouse-hud"
local home = assert(os.getenv("HOME"), "HOME is not set")

if command.command_exists("omarchy-shell") then
  command.capture("omarchy-shell shell setPluginEnabled " .. HUD_PLUGIN_ID .. " false")
end

local result = uninstaller.uninstall({ home = home })

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
