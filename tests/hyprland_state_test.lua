local testlib = require("tests.testlib")
local test = testlib.test

local state = require("workstation.hyprland_state")

local function runtime(responses)
  responses = responses or {}
  local calls = {
    capture = {},
    run = {},
  }

  return {
    calls = calls,
    capture_argv = function(argv)
      calls.capture[#calls.capture + 1] = argv
      local key = table.concat(argv, "|")
      return responses[key]
    end,
    run_argv = function(argv)
      calls.run[#calls.run + 1] = argv
      return responses["run:" .. table.concat(argv, "|")] ~= false
    end,
  }
end

test("hyprland state parses clients and normalizes addresses", function()
  local rt = runtime({
    ["hyprctl|clients|-j"] = [[
      [
        {
          "address": "0xAbC",
          "class": "Code",
          "initialClass": "code",
          "title": "Editor",
          "initialTitle": "Editor",
          "workspace": {"id": 3, "name": "3"},
          "monitor": 1,
          "pid": 42,
          "mapped": true,
          "hidden": false
        }
      ]
    ]],
  })

  local clients, err = state.clients(rt)
  testlib.eq(err, nil)
  testlib.eq(#clients, 1)
  testlib.eq(clients[1].address, "0xabc")
  testlib.eq(clients[1].class, "Code")
  testlib.eq(clients[1].initial_class, "code")
  testlib.eq(clients[1].workspace_id, 3)
  testlib.eq(clients[1].monitor_id, 1)
end)

test("hyprland state exact matching is case insensitive and conjunctive", function()
  local client = {
    address = "0x1",
    class = "Code",
    initial_class = "code",
    title = "Voxelyra",
    initial_title = "Voxelyra",
    mapped = true,
    hidden = false,
  }

  testlib.eq(state.matches(client, { class = "code" }), true)
  testlib.eq(state.matches(client, { class = "CODE", title = "voxelyra" }), true)
  testlib.eq(state.matches(client, { class = "code", title = "other" }), false)
  testlib.eq(state.matches(client, {}), false)
end)

test("hyprland state find match excludes preexisting addresses", function()
  local clients = {
    {
      address = "0x1",
      class = "Code",
      mapped = true,
      hidden = false,
    },
    {
      address = "0x2",
      class = "Code",
      mapped = true,
      hidden = false,
    },
  }

  local found = state.find_match(clients, { class = "code" }, { ["0x1"] = true })
  testlib.eq(found.address, "0x2")
end)

test("hyprland state parses monitors", function()
  local rt = runtime({
    ["hyprctl|monitors|-j"] = [[
      [
        {"id":0,"name":"DP-1","focused":true,"x":0,"y":0,"width":1920,"height":1080},
        {"id":1,"name":"HDMI-A-1","focused":false,"x":1920,"y":0,"width":1920,"height":1080}
      ]
    ]],
  })

  local monitors, err = state.monitors(rt)
  testlib.eq(err, nil)
  testlib.eq(#monitors, 2)
  testlib.eq(monitors[1].name, "DP-1")
  testlib.eq(monitors[1].focused, true)
  testlib.eq(monitors[2].x, 1920)
end)

test("hyprland state workspace placement focuses target and restores previous focus", function()
  local rt = runtime({
    ["hyprctl|activewindow|-j"] = [[{"address":"0xaaa"}]],
  })

  local ok, err = state.place_client("0xbbb", "3", nil, rt)
  testlib.eq(ok, true)
  testlib.eq(err, nil)
  testlib.eq(#rt.calls.run, 3)
  testlib.truthy(rt.calls.run[1][3]:find('address:0xbbb', 1, true))
  testlib.truthy(rt.calls.run[2][3]:find('workspace = "3"', 1, true))
  testlib.truthy(rt.calls.run[3][3]:find('address:0xaaa', 1, true))
end)

test("hyprland state monitor placement uses native Lua dispatcher", function()
  local rt = runtime({
    ["hyprctl|activewindow|-j"] = [[{"address":"0xaaa"}]],
  })

  local ok = state.place_client("0xbbb", nil, "DP-2", rt)
  testlib.eq(ok, true)
  testlib.truthy(rt.calls.run[2][3]:find('monitor = "DP-2"', 1, true))
end)

test("hyprland state refuses ambiguous combined post launch correction", function()
  local rt = runtime({
    ["hyprctl|activewindow|-j"] = [[{"address":"0xaaa"}]],
  })

  local ok, err = state.place_client("0xbbb", "3", "DP-2", rt)
  testlib.eq(ok, nil)
  testlib.truthy(err:match("combined"))
  testlib.eq(#rt.calls.run, 0)
end)

test("hyprland state rejects malformed JSON cleanly", function()
  local rt = runtime({
    ["hyprctl|clients|-j"] = "not-json",
  })

  local clients, err = state.clients(rt)
  testlib.eq(clients, nil)
  testlib.truthy(err:match("JSON"))
end)
