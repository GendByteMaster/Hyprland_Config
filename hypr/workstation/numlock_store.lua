local M = {}

function M.default_path(runtime_dir, instance_signature)
  if not runtime_dir or runtime_dir == "" or not instance_signature or instance_signature == "" then
    return nil
  end

  local safe_signature = tostring(instance_signature):gsub("[^%w%._%-]", "_")
  return runtime_dir .. "/hyprland-config-numlock-" .. safe_signature .. ".state"
end

function M.new(path)
  local store = {}

  function store.load()
    if not path then
      return nil
    end

    local file = io.open(path, "r")
    if not file then
      return nil
    end

    local value = file:read("*l")
    file:close()

    if value == "on" then
      return true
    elseif value == "off" then
      return false
    end

    return nil
  end

  function store.save(enabled)
    if not path then
      return false
    end

    local file = io.open(path, "w")
    if not file then
      return false
    end

    file:write(enabled and "on\n" or "off\n")
    file:close()
    return true
  end

  function store.clear()
    if not path then
      return true
    end

    local ok, _, code = os.remove(path)
    if ok or code == 2 then
      return true
    end

    return false
  end

  return store
end

function M.session()
  return M.new(M.default_path(
    os.getenv("XDG_RUNTIME_DIR"),
    os.getenv("HYPRLAND_INSTANCE_SIGNATURE")
  ))
end

return M
