#include "spatial/Protocol.hpp"

#include <cstdlib>
#include <iostream>
#include <string>

namespace {

void require(bool condition, const char* message) {
    if (!condition) {
        std::cerr << "FAIL: " << message << '\n';
        std::exit(1);
    }
}

void contains(const std::string& value, const std::string& needle, const char* message) {
    require(value.find(needle) != std::string::npos, message);
}

} // namespace

int main() {
    spatial::SpatialState state;

    const auto disabled = spatial::protocol::statusJson(state);
    contains(disabled, "\"protocol\":1", "status includes protocol version");
    contains(disabled, "\"enabled\":false", "status includes disabled state");
    contains(disabled, "\"managed_window_count\":0", "status includes managed count");

    require(state.enable({-1920.0, 0.0, 1920.0, 1080.0}), "state enables");
    require(state.pan(25.5, -10.25), "camera pans");
    require(state.addWindow({"win\\\"1\n", {100.0, 200.0, 800.0, 600.0}}), "test window is added");

    const auto status = spatial::protocol::statusJson(state);
    contains(status, "\"enabled\":true", "status includes enabled state");
    contains(status, "\"x\":25.5", "status includes camera x");
    contains(status, "\"y\":-10.25", "status includes camera y");
    contains(status, "\"zoom\":1", "status includes zoom");
    contains(status, "\"min_x\":-1920", "status includes desk min x");
    contains(status, "\"managed_window_count\":1", "status includes managed count");

    const auto camera = spatial::protocol::cameraJson(state);
    contains(camera, "\"protocol\":1", "camera response includes protocol version");
    contains(camera, "\"epoch\":3", "camera response includes current epoch");

    const auto windows = spatial::protocol::windowsJson(state);
    contains(windows, "\"session_id\":\"win\\\\\\\"1\\n\"", "window id is JSON escaped");
    contains(windows, "\"world\":{\"x\":100,\"y\":200,\"width\":800,\"height\":600}", "window world rect is serialized");

    const auto error = spatial::protocol::errorJson(spatial::protocol::ErrorCode::InvalidArgument, "bad \"value\"\nnext");
    require(error == "{\"protocol\":1,\"error\":{\"code\":\"INVALID_ARGUMENT\",\"message\":\"bad \\\"value\\\"\\nnext\"}}", "error envelope is stable and escaped");
    require(spatial::protocol::errorCodeName(spatial::protocol::ErrorCode::SpatialDisabled) == "SPATIAL_DISABLED", "stable error code is exposed");

    std::cout << "protocol_test: PASS\n";
    return 0;
}
