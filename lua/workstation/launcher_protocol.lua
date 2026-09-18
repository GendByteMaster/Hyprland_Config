local json = require("workstation.json")

local M = {}

M.VERSION = 1

function M.success(data)
  return {
    version = M.VERSION,
    ok = true,
    data = data or {},
  }
end

function M.failure(message, data)
  local payload = {
    version = M.VERSION,
    ok = false,
    error = tostring(message or "unknown launcher error"),
  }
  if data ~= nil then
    payload.data = data
  end
  return payload
end

function M.encode(payload)
  return json.encode(payload)
end

return M
