local source = debug.getinfo(1, "S").source
if source:sub(1, 1) == "@" then
  source = source:sub(2)
end

local script_dir = source:match("^(.*)/[^/]+$") or "."
package.path = script_dir .. "/lua/?.lua;" .. script_dir .. "/lua/?/init.lua;" .. package.path

local command = require("workstation.command")
local plugins = require("workstation.omarchy_plugins")

local home = assert(os.getenv("HOME"), "HOME is not set")
local repo_root = assert(command.realpath(script_dir), "cannot resolve repository root")
local manifest, manifest_error = plugins.load_manifest(
  repo_root .. "/omarchy/external-plugins.lua"
)

if not manifest then
  io.stderr:write(manifest_error .. "\n")
  os.exit(1)
end

local action = arg[1] or "sync"
local result
if action == "sync" then
  result = plugins.sync({ home = home, manifest = manifest })
elseif action == "remove" then
  result = plugins.remove({ home = home, manifest = manifest })
else
  io.stderr:write("usage: lua5.1 omarchy-plugins.lua [sync|remove]\n")
  os.exit(2)
end

if result.skipped then
  print("External Omarchy plugins skipped: " .. tostring(result.reason))
  os.exit(0)
end

for _, item in ipairs(result.results or {}) do
  if item.ok then
    print(string.format(
      "[OK] %s%s",
      item.name,
      item.changed and " (changed)" or ""
    ))
  else
    io.stderr:write(string.format(
      "[FAIL] %s - %s\n",
      item.name,
      tostring(item.error)
    ))
  end
end

if not result.ok then
  if result.error then
    io.stderr:write(tostring(result.error) .. "\n")
  end
  os.exit(1)
end
