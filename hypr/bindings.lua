local home = os.getenv("HOME") or ""
local preserved_bindings = home .. "/.local/state/hyprland_config/preserved_bindings.lua"

local preserved = io.open(preserved_bindings, "r")
if preserved then
  preserved:close()
  dofile(preserved_bindings)
end

require("hypr.workstation.compat").apply(hl)
require("hypr.workstation.mouse").register(hl, o)
