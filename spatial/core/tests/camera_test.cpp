#include "spatial/Camera.hpp"

#include <cmath>
#include <cstdlib>
#include <iostream>
#include <limits>

namespace {

void require(bool condition, const char* message) {
    if (!condition) {
        std::cerr << "FAIL: " << message << '\n';
        std::exit(1);
    }
}

bool near(double lhs, double rhs, double epsilon = 1e-9) {
    return std::abs(lhs - rhs) <= epsilon;
}

} // namespace

int main() {
    spatial::Camera camera;

    require(camera.position() == spatial::Point{}, "camera starts at origin");
    require(camera.zoom() == 1.0, "camera starts at zoom 1");

    require(camera.pan(125.5, -77.25), "finite pan succeeds");
    require(camera.position() == spatial::Point{125.5, -77.25}, "pan updates camera position");

    const spatial::Point desk{400.25, 200.75};
    const auto world = camera.deskToWorld(desk);
    const auto roundTrip = camera.worldToDesk(world);
    require(near(roundTrip.x, desk.x) && near(roundTrip.y, desk.y), "desk/world round-trip preserves coordinates");

    for (int i = 0; i < 10000; ++i) {
        require(camera.pan(0.1, -0.1), "small pan succeeds");
    }
    require(near(camera.position().x, 1125.5, 1e-6), "repeated pan keeps subpixel precision on x");
    require(near(camera.position().y, -1077.25, 1e-6), "repeated pan keeps subpixel precision on y");

    const auto beforeInvalid = camera.position();
    require(!camera.pan(std::numeric_limits<double>::quiet_NaN(), 0.0), "NaN pan is rejected");
    require(!camera.pan(std::numeric_limits<double>::infinity(), 0.0), "infinite pan is rejected");
    require(camera.position() == beforeInvalid, "invalid pan does not mutate camera");

    require(camera.setPosition({spatial::Camera::kMaxCoordinate, spatial::Camera::kMinCoordinate}), "boundary coordinates are accepted");
    require(!camera.pan(1.0, 0.0), "pan beyond max bound is rejected");
    require(!camera.pan(0.0, -1.0), "pan beyond min bound is rejected");

    require(camera.setZoom(1.0), "phase 1 accepts zoom 1");
    require(!camera.setZoom(0.5), "phase 1 rejects zoom below 1");
    require(!camera.setZoom(2.0), "phase 1 rejects zoom above 1");
    require(!camera.setZoom(std::numeric_limits<double>::quiet_NaN()), "phase 1 rejects NaN zoom");

    std::cout << "camera_test: PASS\n";
    return 0;
}
