local M = {}

local function normalized(value)
  return tostring(value or ""):lower()
end

local function boundary(text, index)
  if index <= 1 then
    return true
  end
  local previous = text:sub(index - 1, index - 1)
  return previous == "/" or previous == "_" or previous == "-" or previous == "." or previous == " "
end

local function fuzzy_score(value, query)
  local text = normalized(value)
  query = normalized(query)

  if query == "" then
    return 0
  end
  if text == query then
    return 10000
  end
  if text:sub(1, #query) == query then
    return 9000 - math.max(0, #text - #query)
  end

  local start = text:find(query, 1, true)
  if start then
    local bonus = boundary(text, start) and 100 or 0
    return 8000 + bonus - (start - 1) * 5 - math.max(0, #text - #query)
  end

  local cursor = 1
  local last = nil
  local score = 4000
  for query_index = 1, #query do
    local char = query:sub(query_index, query_index)
    local found = text:find(char, cursor, true)
    if not found then
      return nil
    end

    if last and found == last + 1 then
      score = score + 80
    else
      score = score - math.max(0, found - cursor) * 5
    end
    if boundary(text, found) then
      score = score + 40
    end

    last = found
    cursor = found + 1
  end

  return score - math.max(0, #text - #query)
end

local function recent_positions(state)
  local positions = {}
  for index, item in ipairs((state and state.recent) or {}) do
    if positions[item.id] == nil then
      positions[item.id] = index
    end
  end
  return positions
end

local function alpha(left, right)
  local left_name = normalized(left.project.name)
  local right_name = normalized(right.project.name)
  if left_name == right_name then
    return tostring(left.project.path) < tostring(right.project.path)
  end
  return left_name < right_name
end

function M.rank(projects, query, state)
  projects = projects or {}
  query = normalized(query)
  state = state or { favorites = {}, recent = {} }

  local recent = recent_positions(state)
  local entries = {}

  for _, project in ipairs(projects) do
    if query == "" then
      local tier
      local recent_index = recent[project.id]
      if state.favorites and state.favorites[project.id] then
        tier = 1
      elseif recent_index then
        tier = 2
      else
        tier = 3
      end
      entries[#entries + 1] = {
        project = project,
        tier = tier,
        recent = recent_index or math.huge,
      }
    else
      local name_score = fuzzy_score(project.name, query)
      local path_score = fuzzy_score(project.path, query)
      if path_score then
        path_score = path_score - 200
      end
      local score = math.max(name_score or -math.huge, path_score or -math.huge)

      if score > -math.huge then
        if state.favorites and state.favorites[project.id] then
          score = score + 20
        end
        local recent_index = recent[project.id]
        if recent_index then
          score = score + math.max(1, 11 - math.min(recent_index, 10))
        end
        entries[#entries + 1] = {
          project = project,
          score = score,
        }
      end
    end
  end

  table.sort(entries, function(left, right)
    if query == "" then
      if left.tier ~= right.tier then
        return left.tier < right.tier
      end
      if left.tier == 2 and left.recent ~= right.recent then
        return left.recent < right.recent
      end
      return alpha(left, right)
    end

    if left.score ~= right.score then
      return left.score > right.score
    end
    return alpha(left, right)
  end)

  local ranked = {}
  for index, entry in ipairs(entries) do
    ranked[index] = entry.project
  end
  return ranked
end

return M
