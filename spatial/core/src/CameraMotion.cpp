#include "spatial/CameraMotion.hpp"

#include <algorithm>
#include <cmath>

namespace spatial {

namespace {

[[nodiscard]] bool validDirection(int value) noexcept {
    return value >= -1 && value <= 1;
}

[[nodiscard]] Point normalizedDirection(int x, int y) noexcept {
    if (x == 0 && y == 0) {
        return {};
    }

    const double length = std::hypot(static_cast<double>(x), static_cast<double>(y));
    return {
        static_cast<double>(x) / length,
        static_cast<double>(y) / length,
    };
}

} // namespace

bool CameraMotion::nudge(int xDirection, int yDirection, TimePoint now) noexcept {
    if (!validDirection(xDirection) || !validDirection(yDirection) || (xDirection == 0 && yDirection == 0)) {
        return false;
    }

    const auto direction = normalizedDirection(xDirection, yDirection);

    if (!active_) {
        velocity_ = {
            direction.x * kInitialSpeed,
            direction.y * kInitialSpeed,
        };
        lastTick_ = now;
        active_ = true;
    }

    held_ = true;
    xDirection_ = xDirection;
    yDirection_ = yDirection;
    return true;
}

void CameraMotion::release() noexcept {
    held_ = false;
}

MotionFrame CameraMotion::tick(TimePoint now) noexcept {
    if (!active_) {
        return {};
    }

    auto elapsed = now - lastTick_;
    if (elapsed < Clock::duration::zero()) {
        elapsed = Clock::duration::zero();
    }

    elapsed = std::min(elapsed, std::chrono::duration_cast<Clock::duration>(kMaxFrameDelta));
    lastTick_ = now;

    const double dt = std::chrono::duration<double>(elapsed).count();

    Point target{};
    double rate = kDeceleration;

    if (held_) {
        const auto direction = normalizedDirection(xDirection_, yDirection_);
        target = {
            direction.x * kMaxSpeed,
            direction.y * kMaxSpeed,
        };
        rate = kAcceleration;
    }

    const double maxDelta = rate * dt;
    velocity_.x = approach(velocity_.x, target.x, maxDelta);
    velocity_.y = approach(velocity_.y, target.y, maxDelta);

    if (!held_
        && std::abs(velocity_.x) <= kStopVelocity
        && std::abs(velocity_.y) <= kStopVelocity) {
        stop();
        return {};
    }

    return {
        .delta = {
            velocity_.x * dt,
            velocity_.y * dt,
        },
        .velocity = velocity_,
        .active = true,
    };
}

void CameraMotion::stop() noexcept {
    active_ = false;
    held_ = false;
    xDirection_ = 0;
    yDirection_ = 0;
    velocity_ = {};
    lastTick_ = {};
}

bool CameraMotion::active() const noexcept {
    return active_;
}

bool CameraMotion::held() const noexcept {
    return held_;
}

Point CameraMotion::velocity() const noexcept {
    return velocity_;
}

double CameraMotion::approach(double value, double target, double maxDelta) noexcept {
    if (value < target) {
        return std::min(value + maxDelta, target);
    }

    if (value > target) {
        return std::max(value - maxDelta, target);
    }

    return value;
}

} // namespace spatial
