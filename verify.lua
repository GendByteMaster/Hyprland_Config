local source = debug.getinfo(1, "S").source
if source:sub(1, 1) == "@" then
  source = source:sub(2)
end

local script_dir = source:match("^(.*)/[^/]+$") or "."
package.path = script_dir .. "/lua/?.lua;" .. script_dir .. "/lua/?/init.lua;" .. package.path

local command = require("workstation.command")
local verifier = require("workstation.verifier")

local home = assert(os.getenv("HOME"), "HOME is not set")
local repo_root = assert(command.realpath(script_dir), "cannot resolve repository root")
local result = verifier.verify({ home = home, repo_root = repo_root })

for _, check in ipairs(result.checks) do
  local marker = check.ok and "OK" or "FAIL"
  print(string.format("[%s] %s%s", marker, check.name, check.detail and (" - " .. tostring(check.detail)) or ""))
end

if not result.ok then
  os.exit(1)
end

print("Hyprland_Config verification passed.")
