#include "spatial/SpatialState.hpp"

#include <cmath>
#include <cstdlib>
#include <iostream>
#include <string>
#include <vector>

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
    spatial::SpatialState state;
    const spatial::DeskRect desk{-1920.0, 0.0, 1920.0, 1080.0};

    require(!state.enabled(), "state starts disabled");
    require(state.epoch() == 0, "state starts at epoch zero");
    require(!state.pan(1.0, 1.0), "pan is rejected while disabled");
    require(!state.addWindow({"0x1", {0.0, 0.0, 100.0, 100.0}}), "window adoption is rejected while disabled");

    require(state.enable(desk), "valid desk enables spatial state");
    require(state.enabled(), "state reports enabled");
    require(state.epoch() == 1, "enable increments epoch once");
    require(state.desk() == desk, "desk is stored");

    require(state.enable(desk), "repeated enable with same desk is idempotent");
    require(state.epoch() == 1, "idempotent enable does not increment epoch");
    require(!state.enable({0.0, 0.0, -1.0, 100.0}), "invalid desk is rejected");
    require(state.epoch() == 1, "failed enable does not change epoch");

    const spatial::ManagedWindow first{"0x1", {100.0, 200.0, 800.0, 600.0}};
    require(state.addWindow(first), "valid window is added");
    require(state.epoch() == 2, "adding a window increments epoch");
    require(state.windows().size() == 1, "window registry contains added window");
    require(state.findWindow("0x1") != nullptr, "window can be found by id");
    require(!state.addWindow(first), "duplicate window id is rejected");
    require(state.epoch() == 2, "duplicate rejection does not increment epoch");
    require(!state.addWindow({"", {0.0, 0.0, 1.0, 1.0}}), "empty id is rejected");
    require(!state.addWindow({"bad", {0.0, 0.0, -1.0, 1.0}}), "invalid world rect is rejected");

    const auto storedBeforePan = *state.findWindow("0x1");
    require(state.pan(25.5, -10.25), "valid pan succeeds");
    require(state.epoch() == 3, "camera mutation increments epoch");
    require(*state.findWindow("0x1") == storedBeforePan, "pan does not mutate stored world rectangle");

    require(state.pan(0.0, 0.0), "zero pan is a valid no-op");
    require(state.epoch() == 3, "zero pan does not increment epoch");

    require(!state.removeWindow("missing"), "missing window removal is rejected");
    require(state.epoch() == 3, "failed removal does not increment epoch");
    require(state.removeWindow("0x1"), "existing window is removed");
    require(state.epoch() == 4, "removing a window increments epoch");
    require(state.windows().empty(), "registry is empty after removal");

    for (std::size_t i = 0; i < spatial::SpatialState::kMaxManagedWindows; ++i) {
        require(state.addWindow({"w" + std::to_string(i), {0.0, 0.0, 1.0, 1.0}}), "bounded registry accepts entries up to limit");
    }
    require(!state.addWindow({"overflow", {0.0, 0.0, 1.0, 1.0}}), "bounded registry rejects overflow");

    const auto epochBeforeDisable = state.epoch();
    state.disable();
    require(!state.enabled(), "disable clears enabled state");
    require(state.windows().empty(), "disable clears managed windows");
    require(state.camera().position() == spatial::Point{}, "disable resets camera");
    require(state.epoch() == epochBeforeDisable + 1, "disable increments epoch once");

    const auto epochAfterDisable = state.epoch();
    state.disable();
    require(state.epoch() == epochAfterDisable, "repeated disable is idempotent");

    spatial::SpatialState transactional;
    std::vector<spatial::ManagedWindow> initial{
        {"a", {10.0, 20.0, 100.0, 100.0}},
        {"b", {120.0, 20.0, 100.0, 100.0}},
    };
    require(transactional.enable(desk, initial), "transactional enable accepts a valid initial window set");
    require(transactional.epoch() == 1, "transactional enable increments epoch once");
    require(transactional.windows().size() == 2, "transactional enable commits all windows together");

    const spatial::Point deskCenter{desk.width() / 2.0, desk.height() / 2.0};
    const auto worldCenterBeforeZoom = transactional.camera().deskToWorld(deskCenter);
    require(transactional.setZoom(0.74), "state accepts 74 percent zoom");
    require(near(transactional.camera().zoom(), 0.74), "state stores zoom");
    const auto worldCenterAfterZoom = transactional.camera().deskToWorld(deskCenter);
    require(
        near(worldCenterAfterZoom.x, worldCenterBeforeZoom.x) &&
        near(worldCenterAfterZoom.y, worldCenterBeforeZoom.y),
        "zoom preserves world point under desk center"
    );
    require(transactional.pan(120.0, -80.0), "zoomed camera can pan");
    require(transactional.resetCamera(), "zoom-aware camera reset succeeds");
    require(near(transactional.camera().zoom(), 0.74), "camera reset preserves zoom");
    const auto worldCenterAfterReset = transactional.camera().deskToWorld(deskCenter);
    require(
        near(worldCenterAfterReset.x, deskCenter.x) &&
        near(worldCenterAfterReset.y, deskCenter.y),
        "camera reset returns to initial centered world point"
    );

    spatial::SpatialState duplicateSet;
    require(!duplicateSet.enable(desk, {
        {"dup", {0.0, 0.0, 1.0, 1.0}},
        {"dup", {2.0, 0.0, 1.0, 1.0}},
    }), "transactional enable rejects duplicate IDs");
    require(!duplicateSet.enabled(), "failed transactional enable leaves state disabled");
    require(duplicateSet.epoch() == 0, "failed transactional enable does not advance epoch");

    std::cout << "state_test: PASS\n";
    return 0;
}
