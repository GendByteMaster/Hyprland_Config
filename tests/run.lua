package.path = "./?.lua;./?/init.lua;" .. package.path

require("tests.mouse_state_test")
require("tests.mouse_test")

require("tests.testlib").run()
