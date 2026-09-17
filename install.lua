local source = debug.getinfo(1, "S").source
if source:sub(1, 1) == "@" then
  source = source:sub(2)
end

local script_dir = source:match("^(.*)/[^/]+$") or "."
package.path = script_dir .. "/lua/?.lua;" .. script_dir .. "/lua/?/init.lua;" .. package.path

local command = require("workstation.command")
local installer = require("workstation.installer")

local HUD_PLUGIN_ID = "gendbyte.mouse-hud"
local home = assert(os.getenv("HOME"), "HOME is not set")
local repo_root = assert(command.realpath(script_dir), "cannot resolve repository root")
local result = installer.install({ home = home, repo_root = repo_root })

if result.changed then
  print("Hyprland_Config installed.")
  if result.backup_dir ~= "" then
    print("Previous configuration backed up to: " .. result.backup_dir)
  end
else
  print("Hyprland_Config is already installed and up to date.")
end

local hud_enabled = false
if command.command_exists("omarchy-shell") then
  local rescanned = command.capture("omarchy-shell shell rescanPlugins")
  if rescanned ~= nil then
    hud_enabled = command.capture("omarchy-shell shell setPluginEnabled " .. HUD_PLUGIN_ID .. " true") == "ok"
  end
end

if hud_enabled then
  print("Mouse Mode HUD plugin enabled in Omarchy Shell.")
else
  print("Mouse Mode HUD plugin is installed but could not be enabled automatically.")
  print("Run after Omarchy Shell is available:")
  print("  omarchy-shell shell rescanPlugins")
  print("  omarchy-shell shell setPluginEnabled " .. HUD_PLUGIN_ID .. " true")
end
