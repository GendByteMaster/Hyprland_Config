local source = debug.getinfo(1, "S").source
if source:sub(1, 1) == "@" then
  source = source:sub(2)
end

local script_dir = source:match("^(.*)/[^/]+$") or "."
package.path = script_dir .. "/lua/?.lua;" .. script_dir .. "/lua/?/init.lua;" .. package.path

local command = require("workstation.command")
local installer = require("workstation.installer")

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
