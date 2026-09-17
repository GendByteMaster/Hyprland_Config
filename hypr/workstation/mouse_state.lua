local M = {}

function M.new()
  return { repeats = {} }
end

local function step_for(repeat_count)
  if repeat_count <= 2 then
    return 3
  elseif repeat_count <= 5 then
    return 6
  elseif repeat_count <= 10 then
    return 12
  end

  return 24
end

function M.next_step(state, direction)
  local repeat_count = (state.repeats[direction] or 0) + 1
  state.repeats[direction] = repeat_count
  return step_for(repeat_count)
end

function M.release(state, direction)
  state.repeats[direction] = nil
end

function M.reset(state)
  state.repeats = {}
end

return M
