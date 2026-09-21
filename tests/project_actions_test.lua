local testlib = require("tests.testlib")
local test = testlib.test

local function find_action(actions, id)
  for _, action in ipairs(actions) do
    if action.id == id then
      return action
    end
  end
end

local function assert_no_action(actions, id)
  testlib.eq(find_action(actions, id), nil, "unexpected action " .. id)
end

local function capabilities(commands)
  return {
    terminal = true,
    editor = true,
    file_manager = true,
    clipboard = true,
    is_favorite = false,
    commands = commands or {},
  }
end

local project = {
  id = "/repo/app",
  path = "/repo/app",
  name = "app",
}

test("universal actions expose quick and terminal behavior", function()
  local resolver = require("workstation.project_actions")
  local actions = resolver.resolve(project, {}, { overrides = {} }, capabilities())

  testlib.eq(find_action(actions, "open-shell").terminal, true)
  testlib.eq(find_action(actions, "open-editor").terminal, false)
  testlib.eq(find_action(actions, "open-file-manager").terminal, false)
  testlib.eq(find_action(actions, "favorite").label, "Favorite")
  testlib.eq(find_action(actions, "copy-path").terminal, false)
end)

test("favorite action label flips for favorite project", function()
  local resolver = require("workstation.project_actions")
  local caps = capabilities()
  caps.is_favorite = true
  local actions = resolver.resolve(project, {}, { overrides = {} }, caps)
  testlib.eq(find_action(actions, "favorite").label, "Unfavorite")
end)

test("copy path is omitted without clipboard capability", function()
  local resolver = require("workstation.project_actions")
  local caps = capabilities()
  caps.clipboard = false
  local actions = resolver.resolve(project, {}, { overrides = {} }, caps)
  assert_no_action(actions, "copy-path")
end)

test("git actions become disabled when git executable is missing", function()
  local resolver = require("workstation.project_actions")
  local actions = resolver.resolve(project, { git = true }, { overrides = {} }, capabilities())
  local status = find_action(actions, "git-status")
  testlib.eq(status.enabled, false)
  testlib.truthy(status.reason:match("git"))
end)

test("rust actions use cargo and remain visible when cargo is missing", function()
  local resolver = require("workstation.project_actions")
  local actions = resolver.resolve(project, { rust = true }, { overrides = {} }, capabilities())
  local action = find_action(actions, "rust-test")
  testlib.eq(action.argv[1], "cargo")
  testlib.eq(action.argv[2], "test")
  testlib.eq(action.enabled, false)
end)

test("node actions only expose declared scripts", function()
  local resolver = require("workstation.project_actions")
  local actions = resolver.resolve(project, {
    node = true,
    package_manager = "pnpm",
    node_scripts = { dev = true, build = true },
  }, { overrides = {} }, capabilities({ pnpm = true }))

  testlib.eq(find_action(actions, "node-dev").argv[1], "pnpm")
  testlib.eq(find_action(actions, "node-dev").argv[3], "dev")
  testlib.truthy(find_action(actions, "node-build"))
  assert_no_action(actions, "node-test")
end)

test("python test appears only when supported runner resolves", function()
  local resolver = require("workstation.project_actions")
  local without = resolver.resolve(project, { python = true }, { overrides = {} }, capabilities())
  assert_no_action(without, "python-test")

  local with_pytest = resolver.resolve(project, { python = true }, { overrides = {} }, capabilities({ pytest = true }))
  testlib.eq(find_action(with_pytest, "python-test").argv[1], "pytest")
end)

test("compose down requires confirmation", function()
  local resolver = require("workstation.project_actions")
  local actions = resolver.resolve(project, { compose = true }, { overrides = {} }, capabilities({ docker = true }))
  local action = find_action(actions, "compose-down")
  testlib.eq(action.confirm, true)
  testlib.eq(action.terminal, true)
  testlib.eq(action.argv[1], "docker")
  testlib.eq(action.argv[2], "compose")
  testlib.eq(action.argv[3], "down")
end)

test("manual override replaces auto action by stable id and rechecks command", function()
  local resolver = require("workstation.project_actions")
  local actions = resolver.resolve(project, {
    node = true,
    package_manager = "pnpm",
    node_scripts = { dev = true },
  }, {
    overrides = {
      [project.path] = {
        actions = {
          {
            id = "node-dev",
            label = "Dev",
            argv = { "bun", "dev" },
            terminal = true,
          },
        },
      },
    },
  }, capabilities({ pnpm = true, bun = true }))

  local action = find_action(actions, "node-dev")
  testlib.eq(action.argv[1], "bun")
  testlib.eq(action.argv[2], "dev")
  testlib.eq(action.enabled, true)
end)

test("manual visibility override can hide auto action", function()
  local resolver = require("workstation.project_actions")
  local actions = resolver.resolve(project, { git = true }, {
    overrides = {
      [project.path] = {
        actions = {
          { id = "git-log", visible = false },
        },
      },
    },
  }, capabilities({ git = true }))

  assert_no_action(actions, "git-log")
  testlib.truthy(find_action(actions, "git-status"))
end)

test("custom shell action is marked explicitly", function()
  local resolver = require("workstation.project_actions")
  local actions = resolver.resolve(project, {}, {
    overrides = {
      [project.path] = {
        actions = {
          {
            id = "custom-dev",
            label = "Custom Dev",
            argv = { "bash", "-lc", "echo ok" },
            terminal = true,
            shell = true,
            confirm = true,
          },
        },
      },
    },
  }, capabilities({ bash = true }))

  local action = find_action(actions, "custom-dev")
  testlib.eq(action.shell, true)
  testlib.eq(action.confirm, true)
  testlib.eq(action.enabled, true)
end)

test("Open Workspace appears only for configured project workspace", function()
  local resolver = require("workstation.project_actions")
  local actions = resolver.resolve(project, {}, {
    overrides = {
      [project.path] = {
        workspace = {
          targets = {
            {
              name = "editor",
              workspace = 1,
              operation = "editor",
            },
          },
        },
      },
    },
  }, capabilities())

  local workspace = find_action(actions, "open-workspace")
  testlib.truthy(workspace)
  testlib.eq(workspace.label, "Open Workspace")
  testlib.eq(workspace.operation, "workspace")
  testlib.eq(workspace.terminal, false)
end)

test("Open Workspace is absent without workspace targets", function()
  local resolver = require("workstation.project_actions")
  local actions = resolver.resolve(project, {}, {
    overrides = {
      [project.path] = {
        actions = {},
      },
    },
  }, capabilities())

  assert_no_action(actions, "open-workspace")
end)
