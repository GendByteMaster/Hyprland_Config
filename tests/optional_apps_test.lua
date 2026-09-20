local t = require("tests.testlib")
local optional_apps = require("workstation.optional_apps")

local function fake_runtime(initial)
  local state = initial or {}
  local calls = {}

  local runtime = {}

  function runtime.command_exists(name)
    return state[name] == true
  end

  function runtime.run_argv(args)
    calls[#calls + 1] = args
    if state.install_ok == false then
      return false
    end
    if state.install_creates_binary ~= false then
      state.AmneziaVPN = true
    end
    return true
  end

  return runtime, calls
end

t.test("AmneziaVPN install skips non-Omarchy systems", function()
  local runtime, calls = fake_runtime({
    pacman = true,
    yay = true,
  })

  local result = optional_apps.install_amneziavpn({ runtime = runtime })

  t.eq(result.ok, true)
  t.eq(result.skipped, true)
  t.eq(result.changed, false)
  t.eq(#calls, 0)
end)

t.test("AmneziaVPN install is idempotent when executable already exists", function()
  local runtime, calls = fake_runtime({
    omarchy = true,
    pacman = true,
    yay = true,
    AmneziaVPN = true,
  })

  local result = optional_apps.install_amneziavpn({ runtime = runtime })

  t.eq(result.ok, true)
  t.eq(result.installed, true)
  t.eq(result.changed, false)
  t.eq(#calls, 0)
end)

t.test("AmneziaVPN install prefers yay and selects the AUR package explicitly", function()
  local runtime, calls = fake_runtime({
    omarchy = true,
    pacman = true,
    yay = true,
    paru = true,
  })

  local result = optional_apps.install_amneziavpn({ runtime = runtime })

  t.eq(result.ok, true)
  t.eq(result.changed, true)
  t.eq(result.helper, "yay")
  t.eq(#calls, 1)
  t.eq(table.concat(calls[1], " "), "yay -S --needed --noconfirm aur/amneziavpn-bin")
end)

t.test("AmneziaVPN install falls back to paru", function()
  local runtime, calls = fake_runtime({
    omarchy = true,
    pacman = true,
    paru = true,
  })

  local result = optional_apps.install_amneziavpn({ runtime = runtime })

  t.eq(result.ok, true)
  t.eq(result.helper, "paru")
  t.eq(table.concat(calls[1], " "), "paru -S --needed --noconfirm aur/amneziavpn-bin")
end)

t.test("AmneziaVPN install reports a missing AUR helper without failing core callers", function()
  local runtime = fake_runtime({
    omarchy = true,
    pacman = true,
  })

  local result = optional_apps.install_amneziavpn({ runtime = runtime })

  t.eq(result.ok, false)
  t.eq(result.changed, false)
  t.truthy(result.error:match("AUR helper"))
end)

t.test("AmneziaVPN install verifies the executable after package installation", function()
  local runtime = fake_runtime({
    omarchy = true,
    pacman = true,
    yay = true,
    install_creates_binary = false,
  })

  local result = optional_apps.install_amneziavpn({ runtime = runtime })

  t.eq(result.ok, false)
  t.eq(result.changed, false)
  t.truthy(result.error:match("executable"))
end)
