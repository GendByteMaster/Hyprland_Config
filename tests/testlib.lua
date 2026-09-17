local M = {
  cases = {},
}

function M.test(name, fn)
  table.insert(M.cases, { name = name, fn = fn })
end

function M.eq(actual, expected, message)
  if actual ~= expected then
    error((message or "values differ") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual), 2)
  end
end

function M.truthy(value, message)
  if not value then
    error(message or "expected a truthy value", 2)
  end
end

function M.run()
  local failed = 0

  for _, case in ipairs(M.cases) do
    local ok, err = pcall(case.fn)
    if ok then
      io.write("PASS ", case.name, "\n")
    else
      failed = failed + 1
      io.stderr:write("FAIL ", case.name, "\n", tostring(err), "\n")
    end
  end

  io.write(string.format("\n%d tests, %d failed\n", #M.cases, failed))

  if failed > 0 then
    os.exit(1)
  end
end

return M
