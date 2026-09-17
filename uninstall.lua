local source = debug.getinfo(1, "S").source
if source:sub(1, 1) == "@" then
  source = source:sub(2)
end

local script_dir = source:match("^(.*)/[^/]+$") or "."
package.path = script_dir .. "/lua/?.lua;" .. script_dir .. "/lua/?/init.lua;" .. package.path

local uninstaller = require("workstation.uninstaller")
local home = assert(os.getenv("HOME"), "HOME is not set")
local result = uninstaller.uninstall({ home = home })

if result.changed then
  print("Hyprland_Config uninstalled.")
  if result.restored_from ~= "" then
    print("Previous configuration restored from: " .. result.restored_from)
  end
else
  print("Hyprland_Config is not installed.")
end
