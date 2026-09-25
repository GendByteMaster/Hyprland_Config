#pragma once

#include "spatial/Geometry.hpp"

#include <chrono>

namespace spatial {

struct MotionFrame {
    Point delta{};
    Point velocity{};
    bool active = false;
};

class CameraMotion {
public:
    using Clock = std::chrono::steady_clock;
    using TimePoint = Clock::time_point;

    static constexpr double kInitialSpeed = 240.0;
    static constexpr double kMaxSpeed = 1600.0;
    static constexpr double kAcceleration = 4200.0;
    static constexpr double kDeceleration = 6000.0;
    static constexpr double kStopVelocity = 4.0;

    static constexpr auto kInputGrace = std::chrono::milliseconds(110);
    static constexpr auto kMaxFrameDelta = std::chrono::milliseconds(50);

    [[nodiscard]] bool nudge(int xDirection, int yDirection, TimePoint now) noexcept;
    [[nodiscard]] MotionFrame tick(TimePoint now) noexcept;

    void stop() noexcept;

    [[nodiscard]] bool active() const noexcept;
    [[nodiscard]] Point velocity() const noexcept;

private:
    [[nodiscard]] static double approach(double value, double target, double maxDelta) noexcept;

    bool active_ = false;
    int xDirection_ = 0;
    int yDirection_ = 0;
    Point velocity_{};
    TimePoint lastInput_{};
    TimePoint lastTick_{};
};

} // namespace spatial
