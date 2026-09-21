local command = require("workstation.command")
local paths = require("workstation.paths")

local M = {}

local function default_runtime()
  return {
    mkdir_p = command.mkdir_p,
    mktemp = function(template)
      return command.capture_argv({ "mktemp", template })
    end,
    open = io.open,
    rename = os.rename,
    remove = os.remove,
  }
end

function M.write(path, content, runtime)
  if type(path) ~= "string" or path == "" then
    return nil, "atomic write path is required"
  end
  if type(content) ~= "string" then
    return nil, "atomic write content must be a string"
  end

  runtime = runtime or default_runtime()
  local directory = paths.dirname(path)

  if not runtime.mkdir_p(directory) then
    return nil, "failed to create output directory"
  end

  local temp = runtime.mktemp(path .. ".tmp.XXXXXX")
  if type(temp) ~= "string" or temp == "" then
    return nil, "failed to create secure temporary file"
  end

  local expected_prefix = path .. ".tmp."
  if temp:sub(1, #expected_prefix) ~= expected_prefix then
    runtime.remove(temp)
    return nil, "temporary file escaped expected path"
  end

  local file = runtime.open(temp, "wb")
  if not file then
    runtime.remove(temp)
    return nil, "failed to open secure temporary file"
  end

  local ok, write_error = file:write(content)
  local close_ok, close_error = file:close()
  if not ok or close_ok == nil then
    runtime.remove(temp)
    return nil, tostring(write_error or close_error or "failed to write temporary file")
  end

  if not runtime.rename(temp, path) then
    runtime.remove(temp)
    return nil, "failed to replace output file"
  end

  return true
end

return M
