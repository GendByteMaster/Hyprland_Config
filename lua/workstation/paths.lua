local M = {}

function M.join(...)
  local parts = { ... }
  local result = ""

  for _, raw_part in ipairs(parts) do
    local part = tostring(raw_part or "")
    if part ~= "" then
      if result == "" then
        result = part:gsub("/+$", "")
        if result == "" and part:sub(1, 1) == "/" then
          result = "/"
        end
      else
        local clean = part:gsub("^/+", ""):gsub("/+$", "")
        if clean ~= "" then
          result = result == "/" and (result .. clean) or (result .. "/" .. clean)
        end
      end
    end
  end

  return result
end

function M.dirname(path)
  local normalized = tostring(path):gsub("/+$", "")
  local dir = normalized:match("^(.*)/[^/]*$")
  if not dir or dir == "" then
    return "."
  end
  return dir
end

return M
