local json = require("workstation.json")

local M = {}

local MAX_BYTES = 262144
local MAX_STATEMENTS = 4096

local function trim(value)
  return (tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

local function fail(line, message)
  if line then
    return nil, string.format("TOML line %d: %s", line, message)
  end
  return nil, "TOML: " .. message
end

local function strip_comment(line)
  local quote = nil
  local escaped = false

  for index = 1, #line do
    local char = line:sub(index, index)

    if quote == '"' then
      if escaped then
        escaped = false
      elseif char == "\" then
        escaped = true
      elseif char == '"' then
        quote = nil
      end
    elseif quote == "'" then
      if char == "'" then
        quote = nil
      end
    elseif char == '"' or char == "'" then
      quote = char
    elseif char == "#" then
      return line:sub(1, index - 1)
    end
  end

  return line
end

local function scan_balance(text)
  local quote = nil
  local escaped = false
  local brackets = 0

  for index = 1, #text do
    local char = text:sub(index, index)

    if quote == '"' then
      if escaped then
        escaped = false
      elseif char == "\" then
        escaped = true
      elseif char == '"' then
        quote = nil
      end
    elseif quote == "'" then
      if char == "'" then
        quote = nil
      end
    elseif char == '"' or char == "'" then
      quote = char
    elseif char == "[" then
      brackets = brackets + 1
    elseif char == "]" then
      brackets = brackets - 1
      if brackets < 0 then
        return nil, "unexpected closing bracket"
      end
    end
  end

  return {
    quote = quote,
    brackets = brackets,
  }
end

local function logical_statements(text)
  local statements = {}
  local pending = nil
  local pending_line = nil
  local line_number = 0

  for raw in (text .. "\n"):gmatch("(.-)\n") do
    line_number = line_number + 1
    local cleaned = trim(strip_comment(raw))

    if cleaned ~= "" then
      if pending then
        pending = pending .. " " .. cleaned
      else
        pending = cleaned
        pending_line = line_number
      end

      local state, scan_error = scan_balance(pending)
      if not state then
        return fail(pending_line, scan_error)
      end
      if state.quote then
        return fail(pending_line, "multiline strings are not supported")
      end

      if state.brackets == 0 then
        statements[#statements + 1] = {
          text = pending,
          line = pending_line,
        }
        if #statements > MAX_STATEMENTS then
          return fail(pending_line, "too many statements")
        end
        pending = nil
        pending_line = nil
      end
    end
  end

  if pending then
    return fail(pending_line, "unterminated array or table")
  end

  return statements
end

local function parse_basic_string(raw, line)
  local value, err = json.decode(raw)
  if value == nil then
    return fail(line, "invalid basic string: " .. tostring(err))
  end
  if type(value) ~= "string" then
    return fail(line, "basic string expected")
  end
  return value
end

local function parse_key_segment(raw, line)
  raw = trim(raw)
  if raw == "" then
    return fail(line, "empty key segment")
  end

  if raw:sub(1, 1) == '"' then
    if raw:sub(-1) ~= '"' then
      return fail(line, "unterminated quoted key")
    end
    return parse_basic_string(raw, line)
  end

  if raw:sub(1, 1) == "'" then
    if raw:sub(-1) ~= "'" or #raw < 2 then
      return fail(line, "unterminated literal key")
    end
    return raw:sub(2, -2)
  end

  if not raw:match("^[A-Za-z0-9_-]+$") then
    return fail(line, "invalid bare key: " .. raw)
  end

  return raw
end

local function parse_key_path(raw, line)
  local result = {}
  local start = 1
  local quote = nil
  local escaped = false

  for index = 1, #raw + 1 do
    local char = raw:sub(index, index)

    if index > #raw or (char == "." and quote == nil) then
      local segment, err = parse_key_segment(raw:sub(start, index - 1), line)
      if segment == nil then
        return nil, err
      end
      result[#result + 1] = segment
      start = index + 1
    elseif quote == '"' then
      if escaped then
        escaped = false
      elseif char == "\" then
        escaped = true
      elseif char == '"' then
        quote = nil
      end
    elseif quote == "'" then
      if char == "'" then
        quote = nil
      end
    elseif char == '"' or char == "'" then
      quote = char
    end
  end

  if quote then
    return fail(line, "unterminated quoted key")
  end
  if #result == 0 then
    return fail(line, "empty key")
  end
  return result
end

local parse_value

local function split_array(raw, line)
  local result = {}
  local start = 1
  local quote = nil
  local escaped = false
  local depth = 0

  for index = 1, #raw + 1 do
    local char = raw:sub(index, index)

    if index > #raw or (char == "," and quote == nil and depth == 0) then
      local item = trim(raw:sub(start, index - 1))
      if item ~= "" then
        result[#result + 1] = item
      elseif index <= #raw then
        return fail(line, "empty array item")
      end
      start = index + 1
    elseif quote == '"' then
      if escaped then
        escaped = false
      elseif char == "\" then
        escaped = true
      elseif char == '"' then
        quote = nil
      end
    elseif quote == "'" then
      if char == "'" then
        quote = nil
      end
    elseif char == '"' or char == "'" then
      quote = char
    elseif char == "[" then
      depth = depth + 1
    elseif char == "]" then
      depth = depth - 1
      if depth < 0 then
        return fail(line, "unexpected closing bracket in array")
      end
    end
  end

  if quote or depth ~= 0 then
    return fail(line, "unterminated array value")
  end

  return result
end

local function parse_array(raw, line)
  local inner = trim(raw:sub(2, -2))
  if inner == "" then
    return {}
  end

  local items, split_error = split_array(inner, line)
  if not items then
    return nil, split_error
  end

  local result = {}
  local kind = nil
  for index, item in ipairs(items) do
    local value, value_error = parse_value(item, line)
    if value == nil and value_error then
      return nil, value_error
    end

    local value_kind = type(value)
    if not kind then
      kind = value_kind
    elseif value_kind ~= kind then
      return fail(line, "mixed-type arrays are not supported")
    end
    result[index] = value
  end

  return result
end

parse_value = function(raw, line)
  raw = trim(raw)
  if raw == "" then
    return fail(line, "missing value")
  end

  local first = raw:sub(1, 1)
  if first == '"' then
    if raw:sub(-1) ~= '"' then
      return fail(line, "unterminated basic string")
    end
    return parse_basic_string(raw, line)
  end

  if first == "'" then
    if raw:sub(-1) ~= "'" or #raw < 2 then
      return fail(line, "unterminated literal string")
    end
    return raw:sub(2, -2)
  end

  if first == "[" then
    if raw:sub(-1) ~= "]" then
      return fail(line, "unterminated array")
    end
    return parse_array(raw, line)
  end

  if raw == "true" then
    return true
  end
  if raw == "false" then
    return false
  end

  if raw:match("^[+-]?%d[%d_]*$") then
    local normalized = raw:gsub("_", "")
    if normalized:match("^[+-]?0%d") then
      return fail(line, "leading zero in integer")
    end
    local number = tonumber(normalized)
    if not number or number ~= math.floor(number) then
      return fail(line, "invalid integer")
    end
    return number
  end

  return fail(line, "unsupported value type")
end

local function find_assignment(text, line)
  local quote = nil
  local escaped = false
  local depth = 0

  for index = 1, #text do
    local char = text:sub(index, index)

    if quote == '"' then
      if escaped then
        escaped = false
      elseif char == "\" then
        escaped = true
      elseif char == '"' then
        quote = nil
      end
    elseif quote == "'" then
      if char == "'" then
        quote = nil
      end
    elseif char == '"' or char == "'" then
      quote = char
    elseif char == "[" then
      depth = depth + 1
    elseif char == "]" then
      depth = depth - 1
    elseif char == "=" and depth == 0 then
      return text:sub(1, index - 1), text:sub(index + 1)
    end
  end

  return fail(line, "expected key = value")
end

local function descend(root, path, line)
  local current = root

  for _, key in ipairs(path) do
    local value = current[key]
    if value == nil then
      value = {}
      current[key] = value
    elseif type(value) ~= "table" then
      return fail(line, "table path conflicts with scalar key: " .. tostring(key))
    end

    current = value
  end

  return current
end

local function array_table(root, path, line)
  if #path == 0 then
    return fail(line, "empty array table path")
  end

  local parent_path = {}
  for index = 1, #path - 1 do
    parent_path[index] = path[index]
  end

  local parent, parent_error = descend(root, parent_path, line)
  if not parent then
    return nil, parent_error
  end

  local key = path[#path]
  local array = parent[key]
  if array == nil then
    array = {}
    parent[key] = array
  elseif type(array) ~= "table" then
    return fail(line, "array table conflicts with scalar key: " .. tostring(key))
  end

  local entry = {}
  array[#array + 1] = entry
  return entry
end

local function assign(current, key_path, value, line)
  local parent = current
  for index = 1, #key_path - 1 do
    local key = key_path[index]
    if parent[key] == nil then
      parent[key] = {}
    elseif type(parent[key]) ~= "table" then
      return fail(line, "dotted key conflicts with scalar key: " .. tostring(key))
    end
    parent = parent[key]
  end

  local key = key_path[#key_path]
  if parent[key] ~= nil then
    return fail(line, "duplicate key: " .. tostring(key))
  end
  parent[key] = value
  return true
end

function M.decode(text)
  if type(text) ~= "string" then
    return nil, "TOML input must be a string"
  end
  if #text > MAX_BYTES then
    return nil, "TOML input exceeds 256 KiB limit"
  end
  if text:find(string.char(0), 1, true) then
    return nil, "TOML input contains NUL"
  end

  local statements, statement_error = logical_statements(text)
  if not statements then
    return nil, statement_error
  end

  local root = {}
  local current = root

  for _, statement in ipairs(statements) do
    local source = statement.text
    local line = statement.line

    if source:sub(1, 2) == "[[" and source:sub(-2) == "]]" then
      local path, path_error = parse_key_path(trim(source:sub(3, -3)), line)
      if not path then
        return nil, path_error
      end
      current, path_error = array_table(root, path, line)
      if not current then
        return nil, path_error
      end
    elseif source:sub(1, 1) == "[" and source:sub(-1) == "]" then
      local path, path_error = parse_key_path(trim(source:sub(2, -2)), line)
      if not path then
        return nil, path_error
      end
      current, path_error = descend(root, path, line)
      if not current then
        return nil, path_error
      end
    else
      local key_raw, value_raw = find_assignment(source, line)
      if not key_raw then
        return nil, value_raw
      end

      local key_path, key_error = parse_key_path(trim(key_raw), line)
      if not key_path then
        return nil, key_error
      end

      local value, value_error = parse_value(trim(value_raw), line)
      if value == nil and value_error then
        return nil, value_error
      end

      local ok, assign_error = assign(current, key_path, value, line)
      if not ok then
        return nil, assign_error
      end
    end
  end

  return root
end

return M
