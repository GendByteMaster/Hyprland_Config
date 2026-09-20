local t = require("tests.testlib")
local optional_apps = require("workstation.optional_apps")

local EXPECTED_URL = "https://github.com/amnezia-vpn/amnezia-client/releases/download/5.0.1.5/AmneziaVPN_5.0.1.5_linux_x64.run"
local EXPECTED_SHA256 = "ddb471efbe149232aa98c75534f98d42114b15fdc7976802f8feaeba320bc791"

local function fake_runtime(initial)
  local state = initial or {}
  local calls = {
    run = {},
    capture = {},
    removed = {},
  }

  local runtime = {}

  function runtime.command_exists(name)
    return state[name] == true
  end

  function runtime.file_exists(path)
    return state[path] == true
  end

  function runtime.capture_argv(args)
    calls.capture[#calls.capture + 1] = args
    if args[1] == "uname" then
      return state.arch or "x86_64"
    end
    if args[1] == "mktemp" then
      return "/tmp/amnezia-test.run"
    end
    if args[1] == "sha256sum" then
      return (state.digest or EXPECTED_SHA256) .. "  " .. tostring(args[2])
    end
    return nil
  end

  function runtime.run_argv(args)
    calls.run[#calls.run + 1] = args

    if args[1] == "curl" then
      return state.download_ok ~= false
    end
    if args[1] == "chmod" then
      return state.chmod_ok ~= false
    end
    if args[1] == "sudo" then
      if state.install_ok == false then
        return false
      end
      if state.install_creates_binary ~= false then
        state.AmneziaVPN = true
      end
      return true
    end

    return true
  end

  function runtime.remove(path)
    calls.removed[#calls.removed + 1] = path
    return true
  end

  return runtime, calls
end

local function ready_state(extra)
  local state = {
    omarchy = true,
    pacman = true,
    curl = true,
    sha256sum = true,
    mktemp = true,
    chmod = true,
    sudo = true,
    uname = true,
  }
  for key, value in pairs(extra or {}) do
    state[key] = value
  end
  return state
end

t.test("AmneziaVPN install skips non-Omarchy systems", function()
  local runtime, calls = fake_runtime(ready_state({ omarchy = false }))

  local result = optional_apps.install_amneziavpn({ runtime = runtime })

  t.eq(result.ok, true)
  t.eq(result.skipped, true)
  t.eq(result.changed, false)
  t.eq(#calls.run, 0)
end)

t.test("AmneziaVPN install is idempotent when executable already exists", function()
  local runtime, calls = fake_runtime(ready_state({ AmneziaVPN = true }))

  local result = optional_apps.install_amneziavpn({ runtime = runtime })

  t.eq(result.ok, true)
  t.eq(result.installed, true)
  t.eq(result.changed, false)
  t.eq(#calls.run, 0)
end)

t.test("AmneziaVPN install downloads the pinned official release and verifies SHA-256", function()
  local runtime, calls = fake_runtime(ready_state())

  local result = optional_apps.install_amneziavpn({ runtime = runtime })

  t.eq(result.ok, true)
  t.eq(result.changed, true)
  t.eq(result.version, "5.0.1.5")
  t.eq(result.source, "official GitHub release")

  t.eq(calls.run[1][1], "curl")
  t.eq(calls.run[1][#calls.run[1]], EXPECTED_URL)
  t.eq(table.concat(calls.run[2], " "), "chmod +x /tmp/amnezia-test.run")
  t.eq(table.concat(calls.run[3], " "), "sudo /tmp/amnezia-test.run in -c --al --am")
  t.eq(#calls.removed, 1)
  t.eq(calls.removed[1], "/tmp/amnezia-test.run")
end)

t.test("AmneziaVPN install rejects a checksum mismatch before execution", function()
  local runtime, calls = fake_runtime(ready_state({ digest = string.rep("0", 64) }))

  local result = optional_apps.install_amneziavpn({ runtime = runtime })

  t.eq(result.ok, false)
  t.truthy(result.error:match("SHA%-256"))
  t.eq(#calls.run, 1)
  t.eq(calls.run[1][1], "curl")
  t.eq(#calls.removed, 1)
end)

t.test("AmneziaVPN install rejects unsupported architecture", function()
  local runtime, calls = fake_runtime(ready_state({ arch = "aarch64" }))

  local result = optional_apps.install_amneziavpn({ runtime = runtime })

  t.eq(result.ok, false)
  t.truthy(result.error:match("x86_64"))
  t.eq(#calls.run, 0)
end)

t.test("AmneziaVPN install reports installer failure without pretending core install failed", function()
  local runtime, calls = fake_runtime(ready_state({ install_ok = false }))

  local result = optional_apps.install_amneziavpn({ runtime = runtime })

  t.eq(result.ok, false)
  t.eq(result.changed, false)
  t.truthy(result.error:match("installer failed"))
  t.eq(#calls.removed, 1)
end)

t.test("AmneziaVPN install verifies installed executable after installer exits", function()
  local runtime = fake_runtime(ready_state({ install_creates_binary = false }))

  local result = optional_apps.install_amneziavpn({ runtime = runtime })

  t.eq(result.ok, false)
  t.eq(result.changed, false)
  t.truthy(result.error:match("executable"))
end)

t.test("AmneziaVPN release metadata stays pinned and reviewable", function()
  local release = optional_apps.amneziavpn_release()
  t.eq(release.version, "5.0.1.5")
  t.eq(release.url, EXPECTED_URL)
  t.eq(release.sha256, EXPECTED_SHA256)
end)
