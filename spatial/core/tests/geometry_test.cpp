#include "spatial/Geometry.hpp"

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

} // namespace

int main() {
    const spatial::DeskRect desk{-1920.0, 0.0, 2560.0, 1440.0};
    require(spatial::isValid(desk), "negative desk origin is valid");
    require(desk.width() == 4480.0, "desk width is computed from bounds");
    require(desk.height() == 1440.0, "desk height is computed from bounds");

    require(spatial::isValid(spatial::Rect{-500.0, -200.0, 1200.0, 800.0}), "negative window coordinates are valid");
    require(!spatial::isValid(spatial::Rect{0.0, 0.0, -1.0, 10.0}), "negative width is invalid");
    require(!spatial::isValid(spatial::DeskRect{100.0, 0.0, 0.0, 100.0}), "reversed desk bounds are invalid");
    require(!spatial::isFinite(std::numeric_limits<double>::infinity()), "infinity is not finite");

    std::cout << "geometry_test: PASS\n";
    return 0;
}
