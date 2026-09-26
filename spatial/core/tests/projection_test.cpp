#include "spatial/Projection.hpp"

#include <cmath>
#include <cstdlib>
#include <iostream>

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

void requireRect(const spatial::Rect& actual, const spatial::Rect& expected, const char* message) {
    require(
        near(actual.x, expected.x) &&
        near(actual.y, expected.y) &&
        near(actual.width, expected.width) &&
        near(actual.height, expected.height),
        message
    );
}

} // namespace

int main() {
    const spatial::DeskRect desk{-1920.0, 0.0, 1920.0, 1080.0};
    spatial::Camera camera;

    const spatial::Rect compositor{-1820.0, 100.0, 900.0, 700.0};
    const auto world = spatial::captureWorldRect(compositor, camera, desk);
    requireRect(world, {100.0, 100.0, 900.0, 700.0}, "capture normalizes negative compositor origin");

    const auto initialProjection = spatial::projectWorldRect(world, camera, desk);
    requireRect(initialProjection, compositor, "camera zero preserves initial compositor geometry");

    require(camera.pan(200.0, -100.0), "camera pan succeeds");
    const auto projected = spatial::projectWorldRect(world, camera, desk);
    requireRect(projected, {-2020.0, 200.0, 900.0, 700.0}, "camera pan projects world without mutating its size");

    const auto worldAfterProjection = spatial::captureWorldRect(projected, camera, desk);
    requireRect(worldAfterProjection, world, "capture/project round-trip preserves world geometry");

    require(camera.setZoom(0.74), "zoom 0.74 succeeds");
    const auto zoomed = spatial::projectWorldRect(world, camera, desk);
    require(near(zoomed.width, world.width * 0.74), "zoom scales projected width");
    require(near(zoomed.height, world.height * 0.74), "zoom scales projected height");
    const auto worldAfterZoom = spatial::captureWorldRect(zoomed, camera, desk);
    requireRect(worldAfterZoom, world, "zoomed capture/project round-trip preserves world geometry");

    std::cout << "projection_test: PASS\n";
    return 0;
}
