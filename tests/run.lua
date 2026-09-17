package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

require("tests.mouse_state_test")
require("tests.mouse_test")
require("tests.installer_test")
require("tests.uninstaller_test")
require("tests.verifier_test")

require("tests.testlib").run()
