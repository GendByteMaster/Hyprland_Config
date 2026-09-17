local t = require("tests.testlib")
local sound_assets = require("workstation.sound_assets")
local command = require("workstation.command")
local paths = require("workstation.paths")

local function temp_dir(label)
  local path = os.tmpname() .. "-" .. label
  os.remove(path)
  assert(command.mkdir_p(path))
  return path
end

local function write(path, content)
  assert(command.mkdir_p(paths.dirname(path)))
  local file = assert(io.open(path, "wb"))
  file:write(content)
  file:close()
end

local function read(path)
  local file = assert(io.open(path, "rb"))
  local content = file:read("*a")
  file:close()
  return content
end

t.test("sound assets decode bundled base64 into local Ogg files", function()
  local root = temp_dir("sound-assets")
  local home = paths.join(root, "home")
  local repo = paths.join(root, "repo")

  write(paths.join(repo, "assets", "sounds", "uisfx-mechanical-toggle-on.ogg.b64"), "T2dnUw==\n")
  write(paths.join(repo, "assets", "sounds", "uisfx-mechanical-toggle-off.ogg.b64"), "T2dnUw==\n")

  local result = sound_assets.install({ home = home, repo_root = repo })
  t.truthy(result.ok)
  t.eq(read(paths.join(home, ".local", "share", "hyprland_config", "sounds", "toggle-on.ogg")), "OggS")
  t.eq(read(paths.join(home, ".local", "share", "hyprland_config", "sounds", "toggle-off.ogg")), "OggS")

  command.remove_tree(root)
end)

t.test("vendored UI SFX mechanical cues decode to the published asset sizes", function()
  local root = temp_dir("sound-assets-vendored")
  local home = paths.join(root, "home")
  local result = sound_assets.install({ home = home, repo_root = "." })

  t.truthy(result.ok)
  local on = read(paths.join(home, ".local", "share", "hyprland_config", "sounds", "toggle-on.ogg"))
  local off = read(paths.join(home, ".local", "share", "hyprland_config", "sounds", "toggle-off.ogg"))
  t.eq(on:sub(1, 4), "OggS")
  t.eq(off:sub(1, 4), "OggS")
  t.eq(#on, 2674)
  t.eq(#off, 2532)

  command.remove_tree(root)
end)

t.test("sound asset installation is best effort when bundled files are unavailable", function()
  local root = temp_dir("sound-assets-missing")
  local result = sound_assets.install({
    home = paths.join(root, "home"),
    repo_root = paths.join(root, "repo"),
  })

  t.eq(result.ok, false)
  t.truthy(result.error)
  command.remove_tree(root)
end)
