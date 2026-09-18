local t = require("tests.testlib")
local model = require("workstation.overview_model")

local function client(address, workspace, x, y, width, height, extra)
  local value = {
    address = address,
    workspace = {
      id = workspace,
      name = tostring(workspace),
    },
    at = { x, y },
    size = { width, height },
    class = "app",
    title = address,
    mapped = true,
  }
  for key, item in pairs(extra or {}) do
    value[key] = item
  end
  return value
end

t.test("overview model normalizes Hyprland addresses", function()
  t.eq(model.normalize_address("0x00AbC"), "0x00abc")
  t.eq(model.normalize_address("1f"), "0x1f")
  t.eq(model.normalize_address("not-an-address"), nil)
  t.eq(model.normalize_address(""), nil)
end)

t.test("overview model normalizes client metadata", function()
  local value, err = model.normalize_client({
    address = "0xabc",
    title = "Editor",
    class = "code",
    workspace = { id = 4, name = "4" },
    monitor = 1,
    at = { 100, 200 },
    size = { 1200, 800 },
    pid = 42,
    floating = true,
    fullscreen = 1,
  })

  t.eq(err, nil)
  t.eq(value.address, "0xabc")
  t.eq(value.workspace_id, 4)
  t.eq(value.monitor_id, 1)
  t.eq(value.geometry.x, 100)
  t.eq(value.geometry.height, 800)
  t.eq(value.floating, true)
  t.eq(value.fullscreen, true)
  t.eq(value.special, false)
end)

t.test("overview model filters unmapped special and overview clients", function()
  local visible = model.visible_clients({
    client("0x1", 1, 0, 0, 100, 100),
    client("0x2", 1, 0, 0, 100, 100, { mapped = false }),
    client("0x3", -99, 0, 0, 100, 100, {
      workspace = { id = -99, name = "special:scratch" },
    }),
    client("0x4", 1, 0, 0, 100, 100, {
      class = "gendbyte-workspace-overview",
    }),
  })

  t.eq(#visible, 1)
  t.eq(visible[1].address, "0x1")
end)

t.test("overview model can include special workspace clients explicitly", function()
  local visible = model.visible_clients({
    client("0x3", -99, 0, 0, 100, 100, {
      workspace = { id = -99, name = "special:scratch" },
    }),
  }, { show_special = true })

  t.eq(#visible, 1)
  t.eq(visible[1].special, true)
end)

t.test("overview model preserves non-contiguous workspace ids", function()
  local clients = {
    assert(model.normalize_client(client("0x1", 4, 0, 0, 100, 100))),
    assert(model.normalize_client(client("0x2", 8, 0, 0, 100, 100))),
  }
  local ids = model.workspace_ids(clients, {
    { id = 1 },
    { id = 2 },
    { id = 8 },
  })

  t.eq(#ids, 4)
  t.eq(ids[1], 1)
  t.eq(ids[2], 2)
  t.eq(ids[3], 4)
  t.eq(ids[4], 8)
end)

t.test("overview model groups clients by workspace", function()
  local clients = {
    assert(model.normalize_client(client("0x1", 2, 0, 0, 100, 100))),
    assert(model.normalize_client(client("0x2", 2, 100, 0, 100, 100))),
    assert(model.normalize_client(client("0x3", 7, 0, 0, 100, 100))),
  }
  local groups = model.group_by_workspace(clients)

  t.eq(#groups[2], 2)
  t.eq(#groups[7], 1)
end)

t.test("overview model reconciles disappearing selection", function()
  local clients = {
    assert(model.normalize_client(client("0x1", 1, 0, 0, 100, 100))),
    assert(model.normalize_client(client("0x2", 1, 100, 0, 100, 100, { focused = true }))),
  }

  t.eq(model.reconcile_selection(clients, "0xdead"), "0x2")
  t.eq(model.reconcile_selection(clients, "0x1"), "0x1")
  t.eq(model.reconcile_selection({}, "0x1"), nil)
end)

t.test("overview model uses spatial geometry for keyboard navigation", function()
  local clients = {
    assert(model.normalize_client(client("0x1", 1, 100, 100, 100, 100))),
    assert(model.normalize_client(client("0x2", 1, 300, 100, 100, 100))),
    assert(model.normalize_client(client("0x3", 1, 100, 300, 100, 100))),
    assert(model.normalize_client(client("0x4", 1, 300, 300, 100, 100))),
  }

  t.eq(model.move_selection(clients, "0x1", "right"), "0x2")
  t.eq(model.move_selection(clients, "0x1", "down"), "0x3")
  t.eq(model.move_selection(clients, "0x4", "left"), "0x3")
  t.eq(model.move_selection(clients, "0x4", "up"), "0x2")
  t.eq(model.move_selection(clients, "0x1", "left"), "0x1")
end)

t.test("overview model rejects malformed clients without breaking visible list", function()
  local visible = model.visible_clients({
    { address = "bad", workspace = { id = 1 } },
    client("0x7", 1, 0, 0, 100, 100),
    { address = "0x8" },
  })

  t.eq(#visible, 1)
  t.eq(visible[1].address, "0x7")
end)
