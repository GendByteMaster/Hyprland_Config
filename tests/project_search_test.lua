local testlib = require("tests.testlib")
local test = testlib.test

local function ids(projects)
  local result = {}
  for index, project in ipairs(projects) do
    result[index] = project.id
  end
  return table.concat(result, ",")
end

test("empty query orders favorite then recent then remaining", function()
  local search = require("workstation.project_search")
  local projects = {
    { id = "/a", path = "/a", name = "Alpha" },
    { id = "/b", path = "/b", name = "Beta" },
    { id = "/c", path = "/c", name = "Gamma" },
    { id = "/d", path = "/d", name = "Delta" },
  }
  local ranked = search.rank(projects, "", {
    favorites = { ["/c"] = true },
    recent = {
      { id = "/b", used_at = 20 },
      { id = "/d", used_at = 10 },
    },
  })

  testlib.eq(ids(ranked), "/c,/b,/d,/a")
end)

test("strong fuzzy match beats favorite boost", function()
  local search = require("workstation.project_search")
  local ranked = search.rank({
    { id = "/num", path = "/repo/NumFlow", name = "NumFlow" },
    { id = "/vox", path = "/repo/Voxelyra", name = "Voxelyra" },
  }, "num", {
    favorites = { ["/vox"] = true },
    recent = {},
  })

  testlib.eq(#ranked, 1)
  testlib.eq(ranked[1].id, "/num")
end)

test("fuzzy search supports ordered non contiguous characters", function()
  local search = require("workstation.project_search")
  local ranked = search.rank({
    { id = "/num", path = "/repo/NumFlow", name = "NumFlow" },
    { id = "/nexus", path = "/repo/Voxelyra_Nexus", name = "Voxelyra_Nexus" },
  }, "nfl", { favorites = {}, recent = {} })

  testlib.eq(ranked[1].id, "/num")
end)

test("query may match project path when name does not", function()
  local search = require("workstation.project_search")
  local ranked = search.rank({
    { id = "/work/backend/auth", path = "/work/backend/auth", name = "auth" },
  }, "backend", { favorites = {}, recent = {} })

  testlib.eq(#ranked, 1)
  testlib.eq(ranked[1].id, "/work/backend/auth")
end)

test("unmatched projects are filtered from query results", function()
  local search = require("workstation.project_search")
  local ranked = search.rank({
    { id = "/a", path = "/repo/Alpha", name = "Alpha" },
    { id = "/b", path = "/repo/Beta", name = "Beta" },
  }, "zzz", { favorites = {}, recent = {} })

  testlib.eq(#ranked, 0)
end)
