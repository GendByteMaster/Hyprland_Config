local command = require("workstation.command")
local paths = require("workstation.paths")

local M = {}

local ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local LOOKUP = {}
for index = 1, #ALPHABET do
  LOOKUP[ALPHABET:sub(index, index)] = index - 1
end

local ASSETS = {
  {
    source = "uisfx-mechanical-toggle-on.ogg.b64",
    target = "toggle-on.ogg",
  },
  {
    source = "uisfx-mechanical-toggle-off.ogg.b64",
    target = "toggle-off.ogg",
  },
}

local function read_all(path)
  local file = io.open(path, "rb")
  if not file then
    return nil, "cannot read " .. path
  end

  local content = file:read("*a")
  file:close()
  return content
end

local function decode_base64(input)
  local data = tostring(input or ""):gsub("%s", "")
  if data == "" or #data % 4 ~= 0 then
    return nil, "invalid base64 length"
  end

  local output = {}

  for offset = 1, #data, 4 do
    local c1 = data:sub(offset, offset)
    local c2 = data:sub(offset + 1, offset + 1)
    local c3 = data:sub(offset + 2, offset + 2)
    local c4 = data:sub(offset + 3, offset + 3)

    local a = LOOKUP[c1]
    local b = LOOKUP[c2]
    local c = c3 == "=" and 0 or LOOKUP[c3]
    local d = c4 == "=" and 0 or LOOKUP[c4]

    if a == nil or b == nil or c == nil or d == nil then
      return nil, "invalid base64 character"
    end
    if c3 == "=" and c4 ~= "=" then
      return nil, "invalid base64 padding"
    end
    if (c3 == "=" or c4 == "=") and offset + 3 ~= #data then
      return nil, "invalid base64 padding position"
    end

    local value = a * 262144 + b * 4096 + c * 64 + d
    output[#output + 1] = string.char(math.floor(value / 65536) % 256)

    if c3 ~= "=" then
      output[#output + 1] = string.char(math.floor(value / 256) % 256)
    end
    if c4 ~= "=" then
      output[#output + 1] = string.char(value % 256)
    end
  end

  return table.concat(output)
end

local function write_atomic(path, content)
  local temporary = path .. ".tmp"
  local file = io.open(temporary, "wb")
  if not file then
    return false, "cannot write " .. temporary
  end

  local ok, write_error = file:write(content)
  file:close()
  if not ok then
    os.remove(temporary)
    return false, tostring(write_error or "write failed")
  end

  local renamed, rename_error = os.rename(temporary, path)
  if not renamed then
    os.remove(temporary)
    return false, tostring(rename_error or "rename failed")
  end

  return true
end

function M.install(options)
  options = options or {}
  local home = options.home
  local repo_root = options.repo_root
  if not home or not repo_root then
    return { ok = false, error = "home and repo_root are required" }
  end

  local source_dir = paths.join(repo_root, "assets", "sounds")
  local target_dir = paths.join(home, ".local", "share", "hyprland_config", "sounds")
  if not command.mkdir_p(target_dir) then
    return { ok = false, error = "failed to create local sound directory" }
  end

  for _, asset in ipairs(ASSETS) do
    local encoded, read_error = read_all(paths.join(source_dir, asset.source))
    if not encoded then
      return { ok = false, error = read_error }
    end

    local decoded, decode_error = decode_base64(encoded)
    if not decoded then
      return { ok = false, error = decode_error }
    end
    if decoded:sub(1, 4) ~= "OggS" then
      return { ok = false, error = asset.source .. " did not decode to an Ogg stream" }
    end

    local ok, write_error = write_atomic(paths.join(target_dir, asset.target), decoded)
    if not ok then
      return { ok = false, error = write_error }
    end
  end

  return {
    ok = true,
    directory = target_dir,
  }
end

return M
