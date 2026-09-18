local testlib = require("tests.testlib")
local test = testlib.test

local function runtime(files)
  return {
    exists = function(path)
      return files[path] ~= nil
    end,
    read = function(path)
      local value = files[path]
      if type(value) == "string" then
        return value
      end
      return nil
    end,
  }
end

test("project types detect multi stack project", function()
  local types = require("workstation.project_types")
  local root = "/repo/app"
  local detected = types.detect({ path = root }, runtime({
    [root .. "/.git"] = true,
    [root .. "/Cargo.toml"] = "[package]",
    [root .. "/package.json"] = '{"scripts":{"dev":"next dev","build":"next build"}}',
    [root .. "/pnpm-lock.yaml"] = "lockfileVersion: 9",
    [root .. "/pyproject.toml"] = "[project]",
    [root .. "/compose.yaml"] = "services: {}",
  }))

  testlib.eq(detected.git, true)
  testlib.eq(detected.rust, true)
  testlib.eq(detected.node, true)
  testlib.eq(detected.python, true)
  testlib.eq(detected.compose, true)
  testlib.eq(detected.package_manager, "pnpm")
  testlib.eq(detected.node_scripts.dev, true)
  testlib.eq(detected.node_scripts.test, nil)
  testlib.eq(detected.node_scripts.build, true)
  testlib.eq(detected.compose_file, "compose.yaml")
end)

test("node package manager follows lockfile precedence", function()
  local types = require("workstation.project_types")
  local root = "/repo/app"
  local detected = types.detect({ path = root }, runtime({
    [root .. "/package.json"] = '{"scripts":{"test":"vitest"}}',
    [root .. "/yarn.lock"] = "yarn",
    [root .. "/package-lock.json"] = "{}",
  }))

  testlib.eq(detected.package_manager, "yarn")
  testlib.eq(detected.node_scripts.test, true)
end)

test("node defaults to npm without lockfile", function()
  local types = require("workstation.project_types")
  local root = "/repo/app"
  local detected = types.detect({ path = root }, runtime({
    [root .. "/package.json"] = '{"scripts":{}}',
  }))

  testlib.eq(detected.package_manager, "npm")
end)

test("malformed package json never executes and exposes no scripts", function()
  local types = require("workstation.project_types")
  local root = "/repo/app"
  local detected = types.detect({ path = root }, runtime({
    [root .. "/package.json"] = 'not json; os.execute("touch /tmp/pwn")',
  }))

  testlib.eq(detected.node, true)
  testlib.eq(next(detected.node_scripts), nil)
  testlib.truthy(detected.node_error)
end)

test("compose detection accepts docker compose filename variants", function()
  local types = require("workstation.project_types")
  local root = "/repo/app"
  local detected = types.detect({ path = root }, runtime({
    [root .. "/docker-compose.yml"] = "services: {}",
  }))

  testlib.eq(detected.compose, true)
  testlib.eq(detected.compose_file, "docker-compose.yml")
end)
