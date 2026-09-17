local t = require("tests.testlib")

local function fake_hl()
  local configs = {}
  local hl = {}

  function hl.config(config)
    table.insert(configs, config)
  end

  return hl, configs
end

t.test("try-omarchy QEMU forces the guest cursor visible", function()
  local ok, compat = pcall(require, "hypr.workstation.compat")
  t.eq(ok, true, "compat module must load")

  local hl, configs = fake_hl()
  local applied = compat.apply(hl, {
    kernel_cmdline = "quiet omarchy.qemu=1 tryomarchy.render=cpu",
  })

  t.eq(applied, true)
  t.eq(#configs, 1)
  t.eq(configs[1].cursor.invisible, false)
end)

t.test("normal Omarchy leaves cursor visibility untouched", function()
  local ok, compat = pcall(require, "hypr.workstation.compat")
  t.eq(ok, true, "compat module must load")

  local hl, configs = fake_hl()
  local applied = compat.apply(hl, {
    kernel_cmdline = "quiet splash",
  })

  t.eq(applied, false)
  t.eq(#configs, 0)
end)
