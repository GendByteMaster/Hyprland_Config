#include "spatial/CameraMotion.hpp"

#include <chrono>
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

} // namespace

int main() {
    using namespace std::chrono_literals;

    spatial::CameraMotion motion;
    const spatial::CameraMotion::TimePoint t0{};

    require(!motion.active(), "motion starts inactive");
    require(!motion.held(), "motion starts released");
    require(!motion.nudge(0, 0, t0), "zero direction is rejected");
    require(!motion.nudge(2, 0, t0), "out-of-range direction is rejected");

    require(motion.nudge(1, 0, t0), "right press starts motion");
    require(motion.active(), "motion becomes active");
    require(motion.held(), "motion records held input");
    require(near(motion.velocity().x, spatial::CameraMotion::kInitialSpeed), "motion starts at initial speed");

    const auto first = motion.tick(t0 + 16ms);
    require(first.active, "first frame is active");
    require(first.delta.x > 0.0, "first frame moves right");
    require(near(first.delta.y, 0.0), "first frame does not drift vertically");

    double lastVelocity = first.velocity.x;
    auto now = t0 + 16ms;
    for (int i = 0; i < 30; ++i) {
        now += 16ms;
        const auto frame = motion.tick(now);
        require(frame.velocity.x >= lastVelocity, "held input accelerates monotonically");
        require(frame.velocity.x <= spatial::CameraMotion::kMaxSpeed + 1e-9, "velocity is capped");
        lastVelocity = frame.velocity.x;
    }
    require(lastVelocity > 1000.0, "held input reaches a fast accelerated speed");

    motion.release();
    require(!motion.held(), "release clears held state");
    const auto beforeRelease = motion.velocity().x;
    const auto releaseFrame = motion.tick(now + 16ms);
    require(releaseFrame.active, "release begins deceleration instead of an instant stop");
    require(releaseFrame.velocity.x < beforeRelease, "released motion decelerates");

    auto decayTime = now + 16ms;
    for (int i = 0; i < 30 && motion.active(); ++i) {
        decayTime += 50ms;
        (void)motion.tick(decayTime);
    }
    require(!motion.active(), "motion eventually stops after release");
    require(motion.velocity() == spatial::Point{}, "stopped motion clears velocity");

    spatial::CameraMotion reverse;
    require(reverse.nudge(1, 0, t0), "reverse test starts rightward");
    (void)reverse.tick(t0 + 50ms);
    require(reverse.nudge(-1, 0, t0 + 60ms), "opposite press is accepted");

    auto reverseTime = t0 + 60ms;
    bool crossedZero = false;
    for (int i = 0; i < 20; ++i) {
        reverseTime += 25ms;
        const auto frame = reverse.tick(reverseTime);
        if (frame.velocity.x < 0.0) {
            crossedZero = true;
            break;
        }
    }
    require(crossedZero, "opposite held input reverses velocity smoothly");

    spatial::CameraMotion diagonal;
    require(diagonal.nudge(1, 1, t0), "diagonal press is supported");
    const auto diagonalFrame = diagonal.tick(t0 + 16ms);
    require(diagonalFrame.delta.x > 0.0 && diagonalFrame.delta.y > 0.0, "diagonal frame moves both axes");
    require(near(diagonalFrame.velocity.x, diagonalFrame.velocity.y, 1e-6), "diagonal velocity is normalized");

    diagonal.stop();
    require(!diagonal.active(), "explicit stop cancels motion");
    require(!diagonal.held(), "explicit stop clears held state");

    std::cout << "motion_test: PASS\n";
    return 0;
}
