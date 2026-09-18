local M = {}

M.null = setmetatable({}, {
  __tostring = function()
    return "null"
  end,
})

local ARRAY_MT = {}
local OBJECT_MT = {}

function M.array(value)
  return setmetatable(value or {}, ARRAY_MT)
end

function M.object(value)
  return setmetatable(value or {}, OBJECT_MT)
end

local function escape_string(value)
  local escapes = {
    ['"'] = '\\"',
    ["\\"] = "\\\\",
    ["\b"] = "\\b",
    ["\f"] = "\\f",
    ["\n"] = "\\n",
    ["\r"] = "\\r",
    ["\t"] = "\\t",
  }

  return '"' .. value:gsub('[%z\1-\31\\"]', function(char)
    return escapes[char] or string.format("\\u%04x", string.byte(char))
  end) .. '"'
end

local function is_array(value)
  local mt = getmetatable(value)
  if mt == ARRAY_MT then
    return true, #value
  end
  if mt == OBJECT_MT then
    return false, 0
  end

  local max = 0
  local count = 0
  for key in pairs(value) do
    if type(key) ~= "number" or key < 1 or key % 1 ~= 0 then
      return false, 0
    end
    if key > max then
      max = key
    end
    count = count + 1
  end

  if count == 0 then
    return false, 0
  end
  if max ~= count then
    return false, 0
  end
  return true, max
end

local encode_value

local function encode_table(value, stack)
  if stack[value] then
    error("cannot encode recursive table", 3)
  end
  stack[value] = true

  local array, length = is_array(value)
  local parts = {}

  if array then
    for index = 1, length do
      parts[index] = encode_value(value[index], stack)
    end
    stack[value] = nil
    return "[" .. table.concat(parts, ",") .. "]"
  end

  for key, item in pairs(value) do
    if type(key) ~= "string" then
      stack[value] = nil
      error("JSON object keys must be strings", 3)
    end
    parts[#parts + 1] = escape_string(key) .. ":" .. encode_value(item, stack)
  end
  table.sort(parts)
  stack[value] = nil
  return "{" .. table.concat(parts, ",") .. "}"
end

encode_value = function(value, stack)
  if value == M.null or value == nil then
    return "null"
  end

  local kind = type(value)
  if kind == "boolean" then
    return value and "true" or "false"
  end
  if kind == "number" then
    if value ~= value or value == math.huge or value == -math.huge then
      error("cannot encode non-finite number", 3)
    end
    return tostring(value)
  end
  if kind == "string" then
    return escape_string(value)
  end
  if kind == "table" then
    return encode_table(value, stack)
  end

  error("unsupported JSON type: " .. kind, 3)
end

function M.encode(value)
  return encode_value(value, {})
end

local function utf8(codepoint)
  if codepoint <= 0x7f then
    return string.char(codepoint)
  elseif codepoint <= 0x7ff then
    return string.char(
      0xc0 + math.floor(codepoint / 0x40),
      0x80 + (codepoint % 0x40)
    )
  elseif codepoint <= 0xffff then
    return string.char(
      0xe0 + math.floor(codepoint / 0x1000),
      0x80 + (math.floor(codepoint / 0x40) % 0x40),
      0x80 + (codepoint % 0x40)
    )
  elseif codepoint <= 0x10ffff then
    return string.char(
      0xf0 + math.floor(codepoint / 0x40000),
      0x80 + (math.floor(codepoint / 0x1000) % 0x40),
      0x80 + (math.floor(codepoint / 0x40) % 0x40),
      0x80 + (codepoint % 0x40)
    )
  end
  error("invalid unicode codepoint")
end

local function decoder(text)
  local index = 1
  local length = #text

  local function fail(message)
    error(string.format("%s at byte %d", message, index), 0)
  end

  local function skip_space()
    while index <= length and text:sub(index, index):match("%s") do
      index = index + 1
    end
  end

  local parse_value

  local function parse_hex4()
    local raw = text:sub(index, index + 3)
    if #raw ~= 4 or not raw:match("^%x%x%x%x$") then
      fail("invalid unicode escape")
    end
    index = index + 4
    return tonumber(raw, 16)
  end

  local function parse_string()
    if text:sub(index, index) ~= '"' then
      fail("expected string")
    end
    index = index + 1
    local parts = {}
    local start = index

    while index <= length do
      local char = text:sub(index, index)
      local byte = string.byte(char)

      if char == '"' then
        if index > start then
          parts[#parts + 1] = text:sub(start, index - 1)
        end
        index = index + 1
        return table.concat(parts)
      end

      if byte and byte < 32 then
        fail("control character in string")
      end

      if char == "\\" then
        if index > start then
          parts[#parts + 1] = text:sub(start, index - 1)
        end
        index = index + 1
        local esc = text:sub(index, index)
        local simple = {
          ['"'] = '"',
          ["\\"] = "\\",
          ["/"] = "/",
          ["b"] = "\b",
          ["f"] = "\f",
          ["n"] = "\n",
          ["r"] = "\r",
          ["t"] = "\t",
        }

        if simple[esc] then
          parts[#parts + 1] = simple[esc]
          index = index + 1
        elseif esc == "u" then
          index = index + 1
          local codepoint = parse_hex4()

          if codepoint >= 0xd800 and codepoint <= 0xdbff then
            if text:sub(index, index + 1) ~= "\\u" then
              fail("missing low surrogate")
            end
            index = index + 2
            local low = parse_hex4()
            if low < 0xdc00 or low > 0xdfff then
              fail("invalid low surrogate")
            end
            codepoint = 0x10000 + (codepoint - 0xd800) * 0x400 + (low - 0xdc00)
          elseif codepoint >= 0xdc00 and codepoint <= 0xdfff then
            fail("unexpected low surrogate")
          end

          parts[#parts + 1] = utf8(codepoint)
        else
          fail("invalid escape")
        end

        start = index
      else
        index = index + 1
      end
    end

    fail("unterminated string")
  end

  local function parse_number()
    local rest = text:sub(index)
    local raw = rest:match("^%-?%d+%.?%d*[eE][%+%-]?%d+")
      or rest:match("^%-?%d+%.%d+")
      or rest:match("^%-?%d+")

    if not raw then
      fail("invalid number")
    end
    if raw:match("^%-?0%d") then
      fail("leading zero in number")
    end

    index = index + #raw
    local value = tonumber(raw)
    if value == nil then
      fail("invalid number")
    end
    return value
  end

  local function parse_array()
    index = index + 1
    skip_space()
    local result = M.array({})

    if text:sub(index, index) == "]" then
      index = index + 1
      return result
    end

    while true do
      result[#result + 1] = parse_value()
      skip_space()

      local char = text:sub(index, index)
      if char == "]" then
        index = index + 1
        return result
      end
      if char ~= "," then
        fail("expected comma or closing bracket")
      end

      index = index + 1
      skip_space()
    end
  end

  local function parse_object()
    index = index + 1
    skip_space()
    local result = M.object({})

    if text:sub(index, index) == "}" then
      index = index + 1
      return result
    end

    while true do
      if text:sub(index, index) ~= '"' then
        fail("expected object key")
      end

      local key = parse_string()
      skip_space()
      if text:sub(index, index) ~= ":" then
        fail("expected colon")
      end

      index = index + 1
      skip_space()
      result[key] = parse_value()
      skip_space()

      local char = text:sub(index, index)
      if char == "}" then
        index = index + 1
        return result
      end
      if char ~= "," then
        fail("expected comma or closing brace")
      end

      index = index + 1
      skip_space()
    end
  end

  parse_value = function()
    skip_space()
    local char = text:sub(index, index)

    if char == '"' then
      return parse_string()
    end
    if char == "{" then
      return parse_object()
    end
    if char == "[" then
      return parse_array()
    end
    if char == "-" or char:match("%d") then
      return parse_number()
    end
    if text:sub(index, index + 3) == "true" then
      index = index + 4
      return true
    end
    if text:sub(index, index + 4) == "false" then
      index = index + 5
      return false
    end
    if text:sub(index, index + 3) == "null" then
      index = index + 4
      return M.null
    end

    fail("unexpected token")
  end

  local value = parse_value()
  skip_space()
  if index <= length then
    fail("trailing data")
  end
  return value
end

function M.decode(text)
  if type(text) ~= "string" then
    return nil, "JSON input must be a string"
  end

  local ok, value = pcall(decoder, text)
  if not ok then
    return nil, tostring(value)
  end
  return value, nil
end

return M
