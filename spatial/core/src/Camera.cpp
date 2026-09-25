#include "spatial/Camera.hpp"

#include <cmath>

namespace spatial {

Point Camera::position() const noexcept {
    return position_;
}

double Camera::zoom() const noexcept {
    return zoom_;
}

bool Camera::validCoordinate(double value) noexcept {
    return std::isfinite(value) && value >= kMinCoordinate && value <= kMaxCoordinate;
}

bool Camera::pan(double dx, double dy) noexcept {
    if (!std::isfinite(dx) || !std::isfinite(dy)) {
        return false;
    }

    const Point candidate{position_.x + dx, position_.y + dy};
    if (!validCoordinate(candidate.x) || !validCoordinate(candidate.y)) {
        return false;
    }

    position_ = candidate;
    return true;
}

bool Camera::setPosition(Point value) noexcept {
    if (!validCoordinate(value.x) || !validCoordinate(value.y)) {
        return false;
    }

    position_ = value;
    return true;
}

bool Camera::setZoom(double value) noexcept {
    if (!std::isfinite(value) || value != 1.0) {
        return false;
    }

    zoom_ = value;
    return true;
}

Point Camera::deskToWorld(Point desk) const noexcept {
    return {
        position_.x + desk.x / zoom_,
        position_.y + desk.y / zoom_,
    };
}

Point Camera::worldToDesk(Point world) const noexcept {
    return {
        (world.x - position_.x) * zoom_,
        (world.y - position_.y) * zoom_,
    };
}

} // namespace spatial
