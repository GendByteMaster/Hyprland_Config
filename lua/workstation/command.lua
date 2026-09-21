local M = {}

function M.quote(value)
  return "'" .. tostring(value):gsub("'", "'\\''") .. "'"
end

local function success(a, _, c)
  if type(a) == "number" then
    return a == 0
  end
  if type(a) == "boolean" then
    return a and (c == nil or c == 0)
  end
  return false
end

function M.argv(args)
  local quoted = {}
  for index, value in ipairs(args) do
    quoted[index] = M.quote(value)
  end
  return table.concat(quoted, " ")
end

function M.run(command)
  local a, b, c = os.execute(command)
  return success(a, b, c)
end

function M.run_argv(args)
  return M.run(M.argv(args))
end

function M.run_argv_silent(args)
  if type(args) ~= "table" or #args == 0 then
    return false
  end
  return M.run(M.argv(args) .. " >/dev/null 2>&1")
end

function M.spawn_argv(args)
  if type(args) ~= "table" or #args == 0 then
    return false
  end
  return M.run("setsid " .. M.argv(args) .. " >/dev/null 2>&1 &")
end

function M.run_argv_with_stdin(args, input)
  if type(args) ~= "table" or #args == 0 then
    return false
  end
  local shell = "printf '%s' " .. M.quote(input or "") .. " | " .. M.argv(args)
  return M.run(shell)
end

function M.capture(command)
  local pipe = io.popen(command .. " 2>/dev/null")
  if not pipe then
    return nil
  end

  local output = pipe:read("*a") or ""
  local a, b, c = pipe:close()
  if not success(a, b, c) then
    return nil
  end

  return (output:gsub("[\r\n]+$", ""))
end

function M.capture_argv(args)
  return M.capture(M.argv(args))
end

function M.exists(path)
  return M.run("test -e " .. M.quote(path))
end

function M.exists_or_symlink(path)
  return M.run("test -e " .. M.quote(path) .. " || test -L " .. M.quote(path))
end

function M.is_symlink(path)
  return M.run("test -L " .. M.quote(path))
end

function M.realpath(path)
  return M.capture("readlink -f -- " .. M.quote(path))
end

function M.mkdir_p(path)
  return M.run("mkdir -p -- " .. M.quote(path))
end

function M.move(source, target)
  return M.run("mv -- " .. M.quote(source) .. " " .. M.quote(target))
end

function M.symlink(source, target)
  return M.run("ln -s -- " .. M.quote(source) .. " " .. M.quote(target))
end

function M.remove(path)
  return M.run("rm -f -- " .. M.quote(path))
end

function M.remove_tree(path)
  return M.run("rm -rf -- " .. M.quote(path))
end

function M.command_exists(name)
  return M.run("command -v " .. M.quote(name) .. " >/dev/null 2>&1")
end

return M
