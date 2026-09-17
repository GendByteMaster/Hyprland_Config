package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

require("tests.mouse_state_test")
require("tests.numlock_store_test")
require("tests.hud_test")
require("tests.mouse_test")
require("tests.numlock_sound_test")
require("tests.sound_test")
require("tests.sound_assets_test")
require("tests.compat_test")
require("tests.installer_test")
require("tests.uninstaller_test")
require("tests.verifier_test")
require("tests.telemetry_test")
require("tests.telemetry_collector_test")
require("tests.system_monitor_plugin_test")

require("tests.testlib").run()